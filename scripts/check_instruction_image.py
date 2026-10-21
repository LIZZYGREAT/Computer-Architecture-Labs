#!/usr/bin/env python3
"""Check that a course COE image and XSim MIF contain the same 32-bit words."""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from pathlib import Path


def _radix_from_header(text: str) -> int | None:
    match = re.search(r"memory_initialization_radix\s*=\s*(\d+)\s*;", text, re.I)
    return int(match.group(1)) if match else None


def parse_image(path: Path) -> list[int]:
    text = path.read_text(encoding="utf-8-sig")
    radix = _radix_from_header(text)
    vector = re.search(r"memory_initialization_vector\s*=\s*(.*)", text, re.I | re.S)
    if vector:
        payload = vector.group(1)
    else:
        payload_lines = []
        for line in text.splitlines():
            line = re.split(r"//|#|--", line, maxsplit=1)[0].strip()
            if not line or line.lower().startswith("memory_initialization_radix"):
                continue
            if line.startswith("@"):  # Address directives are not emitted by the course converter.
                raise ValueError(f"{path}: unsupported address directive: {line}")
            payload_lines.append(line)
        payload = "\n".join(payload_lines)

    payload = re.sub(r"//[^\r\n]*|#[^\r\n]*|--[^\r\n]*", " ", payload)
    tokens = [token for token in re.split(r"[\s,;]+", payload) if token]
    if not tokens:
        raise ValueError(f"{path}: no memory words found")

    words: list[int] = []
    for index, token in enumerate(tokens):
        token = token.removeprefix("0x").removeprefix("0X")
        token_radix = radix
        if token_radix is None:
            token_radix = 2 if len(token) == 32 and set(token) <= {"0", "1"} else 16
        try:
            value = int(token, token_radix)
        except ValueError as error:
            raise ValueError(f"{path}: invalid word {index}: {token!r}") from error
        if value < 0 or value > 0xFFFFFFFF:
            raise ValueError(f"{path}: word {index} exceeds 32 bits: {token!r}")
        words.append(value)
    return words


def parse_depth(path: Path) -> int:
    text = path.read_text(encoding="utf-8-sig")
    match = re.search(
        r'"Write_Depth_A"\s*:\s*\[\s*\{\s*"value"\s*:\s*"(\d+)"', text
    )
    if not match:
        match = re.search(r'PARAM_VALUE\.Write_Depth_A">(\d+)</', text)
    if not match:
        raise ValueError(f"{path}: could not read Write_Depth_A from inst_ram.xci")
    return int(match.group(1))


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def words_sha256(words: list[int]) -> str:
    raw = b"".join(word.to_bytes(4, byteorder="big") for word in words)
    return hashlib.sha256(raw).hexdigest().upper()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--coe", required=True, type=Path)
    parser.add_argument("--mif", required=True, type=Path)
    parser.add_argument("--xci", required=True, type=Path)
    args = parser.parse_args()

    for name, path in (("COE", args.coe), ("MIF", args.mif), ("XCI", args.xci)):
        if not path.is_file() or path.stat().st_size == 0:
            print(f"IMAGE_ERROR: {name} file is missing or empty: {path}", file=sys.stderr)
            return 2

    try:
        coe_words = parse_image(args.coe)
        mif_words = parse_image(args.mif)
        depth = parse_depth(args.xci)
    except (OSError, UnicodeError, ValueError) as error:
        print(f"IMAGE_ERROR: {error}", file=sys.stderr)
        return 2

    print(f"COE={args.coe.absolute()}")
    print(f"COE_SHA256={file_sha256(args.coe)}")
    print(f"MIF={args.mif.absolute()}")
    print(f"MIF_SHA256={file_sha256(args.mif)}")
    print(f"XCI={args.xci.absolute()}")
    print(f"INST_RAM_DEPTH={depth}")
    print(f"COE_WORDS={len(coe_words)}")
    print(f"MIF_WORDS={len(mif_words)}")
    print(f"COE_WORDS_SHA256={words_sha256(coe_words)}")
    print(f"MIF_WORDS_SHA256={words_sha256(mif_words)}")

    if len(coe_words) > depth or len(mif_words) > depth:
        print("IMAGE_ERROR: instruction image exceeds the inst_ram depth", file=sys.stderr)
        return 1
    if coe_words != mif_words:
        limit = min(len(coe_words), len(mif_words))
        mismatch = next((i for i in range(limit) if coe_words[i] != mif_words[i]), limit)
        coe_word = f"0x{coe_words[mismatch]:08X}" if mismatch < len(coe_words) else "<EOF>"
        mif_word = f"0x{mif_words[mismatch]:08X}" if mismatch < len(mif_words) else "<EOF>"
        print(f"IMAGE_ERROR: COE/MIF mismatch at word {mismatch}: COE={coe_word}, MIF={mif_word}", file=sys.stderr)
        return 1

    print("IMAGE_MATCH=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
