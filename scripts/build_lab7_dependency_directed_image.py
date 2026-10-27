#!/usr/bin/env python3
"""Build a compact Lab7 image for load-use and unaligned-memory boundaries."""

from __future__ import annotations

import argparse
from pathlib import Path


BASE_PC = 0xBFC00000
END_WORD = 64
DATA_BASE = 0x800D0000


def i_type(op: int, rs: int, rt: int, imm: int) -> int:
    return (op << 26) | (rs << 21) | (rt << 16) | (imm & 0xFFFF)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=Path(__file__).absolute().parents[1]
        / "results"
        / "lab6_lab7"
        / "directed"
        / "dependency-boundaries"
        / "image",
    )
    args = parser.parse_args()
    out_dir: Path = args.out_dir.absolute()
    out_dir.mkdir(parents=True, exist_ok=True)

    entries: list[tuple[int, str]] = []
    labels: dict[str, int] = {}
    branch_fixups: list[tuple[int, int, str]] = []

    def emit(word: int, source: str) -> int:
        entries.append((word, source))
        return len(entries) - 1

    def label(name: str) -> None:
        if name in labels:
            raise ValueError(f"duplicate label: {name}")
        labels[name] = len(entries)

    def i(name: str, op: int, rt: int, rs: int, imm: int) -> None:
        emit(i_type(op, rs, rt, imm), f"{name} r{rt}, {imm}(r{rs})")

    def addiu(rt: int, rs: int, imm: int) -> None:
        emit(i_type(0x09, rs, rt, imm), f"addiu r{rt}, r{rs}, {imm}")

    def lui(rt: int, imm: int) -> None:
        emit(i_type(0x0F, 0, rt, imm), f"lui r{rt}, 0x{imm:04x}")

    def ori(rt: int, rs: int, imm: int) -> None:
        emit(i_type(0x0D, rs, rt, imm), f"ori r{rt}, r{rs}, 0x{imm:04x}")

    def branch_regimm(rt: int, rs: int, target: str) -> None:
        index = emit(0, f"bltz r{rs}, {target}")
        branch_fixups.append((index, rt, target))

    def nop() -> None:
        emit(0, "nop")

    # Byte/halfword writes are read back immediately with both signed and
    # unsigned loads. Each partial store receives its data from the prior LW.
    lui(10, 0x800D)
    lui(1, 0x89AB)
    ori(1, 1, 0xCDEF)
    i("sw", 0x2B, 1, 10, 0)
    i("lw", 0x23, 2, 10, 0)
    i("sb", 0x28, 2, 10, 4)
    i("lb", 0x20, 3, 10, 4)
    i("lbu", 0x24, 4, 10, 4)
    i("lw", 0x23, 2, 10, 0)
    i("sh", 0x29, 2, 10, 6)
    i("lh", 0x21, 5, 10, 6)
    i("lhu", 0x25, 6, 10, 6)

    # Exercise load-to-SWL/SWR dependencies at offsets 0 and 3, then inspect
    # the merged word through a normal LW.
    i("lw", 0x23, 2, 10, 0)
    i("swl", 0x2A, 2, 10, 8)
    i("lw", 0x23, 2, 10, 0)
    i("swr", 0x2E, 2, 10, 11)
    i("lw", 0x23, 8, 10, 8)

    # Seed adjacent words, then make LWL/LWR consecutive on the same target.
    lui(1, 0x4433)
    ori(1, 1, 0x2211)
    i("sw", 0x2B, 1, 10, 16)
    lui(1, 0x8877)
    ori(1, 1, 0x6655)
    i("sw", 0x2B, 1, 10, 20)
    i("lw", 0x23, 9, 10, 16)
    i("lwl", 0x22, 9, 10, 20)
    i("lwr", 0x26, 9, 10, 17)
    i("sw", 0x2B, 9, 10, 24)
    i("lw", 0x23, 11, 10, 24)

    # A just-loaded negative value must drive a taken signed branch. The delay
    # slot retires, the fall-through marker must not, and the target must.
    lui(1, 0xFFFF)
    ori(1, 1, 0xFFFF)
    i("sw", 0x2B, 1, 10, 28)
    i("lw", 0x23, 12, 10, 28)
    branch_regimm(0, 12, "branch_target")
    addiu(13, 0, 0x11)  # architectural delay slot
    addiu(14, 0, 0xEE)  # skipped when BLTZ is taken
    label("branch_target")
    addiu(15, 0, 0x33)

    if len(entries) > END_WORD:
        raise RuntimeError(f"directed program exceeds END_PC index {END_WORD}")
    while len(entries) < END_WORD:
        nop()
    emit(0, "nop ; END_PC sentinel at word 64")

    words = [word for word, _ in entries]
    for index, rt, target in branch_fixups:
        if target not in labels:
            raise ValueError(f"unknown branch target: {target}")
        offset = labels[target] - (index + 1)
        words[index] = i_type(0x01, 12, rt, offset)
        entries[index] = (words[index], f"bltz r12, {target} (offset {offset})")

    mif_path = out_dir / "lab7_dependency_boundaries.mif"
    coe_path = out_dir / "lab7_dependency_boundaries.coe"
    listing_path = out_dir / "lab7_dependency_boundaries_program.txt"
    mif_path.write_text("".join(f"{word:032b}\n" for word in words), encoding="ascii")
    coe_path.write_text(
        "memory_initialization_radix = 16;\n"
        "memory_initialization_vector =\n"
        + "\n".join(f"{word:08x}" for word in words[:-1])
        + f"\n{words[-1]:08x};\n",
        encoding="ascii",
    )
    listing = [
        "# Lab7 directed dependency test; compare with an independent CPU132 trace.",
        "# Expected: r3=ffffffef, r4=000000ef, r5=ffffcdef, r6=0000cdef.",
        "# Expected: r8=ef000089, r9/r11=55443322, r12=ffffffff.",
        "# Expected: r13=00000011, r14 is not written, r15=00000033.",
        "# Expected final memory: [0]=89abcdef [4]=cdef00ef [8]=ef000089.",
        "# Expected final memory: [16]=44332211 [20]=88776655 [24]=55443322 [28]=ffffffff.",
        "# Store bus addresses/masks/data are checked by DEPENDENCY_DIRECTED testbench mode.",
        "# Word index 64 is the shared END_PC sentinel at 0xbfc00100.",
    ]
    listing.extend(
        f"{index:02d}  0x{BASE_PC + index * 4:08x}  {word:08x}  {source}"
        for index, (word, source) in enumerate(entries)
    )
    listing_path.write_text("\n".join(listing) + "\n", encoding="ascii")
    print(f"WORDS={len(words)}")
    print(f"DATA_BASE=0x{DATA_BASE:08x}")
    print(f"COE={coe_path}")
    print(f"MIF={mif_path}")
    print(f"ASSEMBLY_LISTING={listing_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
