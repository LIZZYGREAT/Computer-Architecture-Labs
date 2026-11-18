#!/usr/bin/env python3
"""Rebase the prebuilt Lab19 benchmark data pointers into the KSEG0 alias.

The committed Dhrystone/CoreMark ELF and images are course-provided builds
linked at 0xbfc00000.  Their startup code already loads SP and GP from those
symbols.  Replacing only the upper 16-bit immediates of those two LUI
instructions is equivalent to the source-level `subu sp/gp, 0x20000000`
in lab19/perf_func/start.S, while preserving the low offsets and the linked
GP-relative relocations.  KSEG0 (0x9fc...) and KSEG1 (0xbfc...) translate to
the same physical address; this makes stack/global accesses cacheable without
changing the benchmark's memory layout or its software workload.

This script is deliberately exact-match and one-shot: it refuses images that
do not match the original committed startup words.  Rebuilds from start.S
already perform the runtime rebasing and should not be patched again.
"""

from __future__ import annotations

import argparse
import re
import struct
from pathlib import Path


PATCHES = {
    "dhrystone": {
        0x30: (0x3C1DBFC0, 0x3C1D9FC0),  # lui sp, _stack high half
        0x38: (0x3C1CBFC1, 0x3C1C9FC1),  # lui gp, _gp high half
    },
    "coremark": {
        0x30: (0x3C1DBFC1, 0x3C1D9FC1),
        0x38: (0x3C1CBFC1, 0x3C1C9FC1),
    },
}


def patch_word(data: bytearray, offset: int, old: int, new: int, label: str) -> None:
    actual = struct.unpack_from("<I", data, offset)[0]
    if actual != old:
        raise ValueError(f"{label}: expected 0x{old:08x} at 0x{offset:x}, got 0x{actual:08x}")
    struct.pack_into("<I", data, offset, new)


def replace_unique(data: bytearray, old: int, new: int, label: str) -> None:
    old_bytes = struct.pack("<I", old)
    offsets = [match.start() for match in re.finditer(re.escape(old_bytes), data)]
    if len(offsets) != 1:
        raise ValueError(f"{label}: expected one ELF occurrence of 0x{old:08x}, found {len(offsets)}")
    struct.pack_into("<I", data, offsets[0], new)


def memory_file_contents(image: bytes) -> tuple[str, str]:
    if len(image) % 4:
        raise ValueError("image byte length is not a multiple of four")
    words = [struct.unpack_from("<I", image, offset)[0] for offset in range(0, len(image), 4)]
    coe = "memory_initialization_radix = 16;\nmemory_initialization_vector =\n"
    coe += "\n".join(f"{word:08x}" for word in words) + "\n"
    mif = "\n".join(f"{word:032b}" for word in words) + "\n"
    return coe, mif


def patch_disassembly(text: str, replacements: dict[int, int], path: Path) -> str:
    for old, new in replacements.items():
        old_hex = f"{old:08x}"
        new_hex = f"{new:08x}"
        if text.count(old_hex) != 1:
            raise ValueError(f"{path}: expected one disassembly occurrence of {old_hex}")
        text = text.replace(old_hex, new_hex, 1)
        old_imm = f"0x{old & 0xffff:x}"
        new_imm = f"0x{new & 0xffff:x}"
        # The instruction line is the only line that has this exact LUI immediate.
        register = "sp" if old & 0xffff0000 == 0x3C1D0000 else "gp"
        old_asm = f"lui\t{register},{old_imm}"
        new_asm = f"lui\t{register},{new_imm}"
        if text.count(old_asm) != 1:
            raise ValueError(f"{path}: expected one matching assembly form {old_asm!r}")
        text = text.replace(old_asm, new_asm, 1)
    return text


def prepare(root: Path) -> None:
    for suite, offsets in PATCHES.items():
        directory = root / "lab19" / "perf_func" / "obj" / suite
        binary_path = directory / "inst_data.bin"
        elf_path = directory / "main.elf"
        disassembly_path = directory / "test.s"
        binary = bytearray(binary_path.read_bytes())
        elf = bytearray(elf_path.read_bytes())
        disassembly_replacements: dict[int, int] = {}
        for offset, (old, new) in offsets.items():
            patch_word(binary, offset, old, new, str(binary_path))
            replace_unique(elf, old, new, str(elf_path))
            disassembly_replacements[old] = new
        disassembly = patch_disassembly(
            disassembly_path.read_text(encoding="utf-8"), disassembly_replacements, disassembly_path
        )
        coe, mif = memory_file_contents(binary)
        binary_path.write_bytes(binary)
        elf_path.write_bytes(elf)
        with disassembly_path.open("w", encoding="utf-8", newline="") as output:
            output.write(disassembly)
        (directory / "axi_ram.coe").write_text(coe, encoding="ascii")
        (directory / "axi_ram.mif").write_text(mif, encoding="ascii")
        print(f"PREPARED={suite} bytes={len(binary)}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo_root", nargs="?", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    prepare(args.repo_root.resolve())


if __name__ == "__main__":
    main()
