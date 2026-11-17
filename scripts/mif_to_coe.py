#!/usr/bin/env python3
"""Convert the repository's 32-bit instruction MIF format to Xilinx COE."""

from __future__ import annotations

import argparse
from pathlib import Path

from check_bus_inputs import parse_mif


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    source = args.input.resolve()
    output = args.output.resolve()
    if not source.is_file():
        parser.error(f"instruction MIF is missing: {source}")
    if output.exists():
        parser.error(f"refusing to overwrite instruction COE: {output}")

    words = parse_mif(source)
    if not words:
        parser.error(f"instruction MIF contains no words: {source}")
    if any(word < 0 or word > 0xFFFF_FFFF for word in words):
        parser.error(f"instruction MIF contains a non-32-bit word: {source}")

    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x", encoding="ascii", newline="\n") as handle:
        handle.write("memory_initialization_radix=16;\n")
        handle.write("memory_initialization_vector=\n")
        for index, word in enumerate(words):
            handle.write(f"{word:08x}{';' if index + 1 == len(words) else ','}\n")
    print(f"INPUT_MIF={source}")
    print(f"OUTPUT_COE={output}")
    print(f"WORD_COUNT={len(words)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
