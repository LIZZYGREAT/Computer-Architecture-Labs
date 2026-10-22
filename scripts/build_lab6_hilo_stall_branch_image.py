#!/usr/bin/env python3
"""Build a compact Lab6 image for DIV backpressure and branch delay-slot checks."""

from __future__ import annotations

import argparse
from pathlib import Path


def i_type(op: int, rs: int, rt: int, imm: int) -> int:
    return (op << 26) | (rs << 21) | (rt << 16) | (imm & 0xFFFF)


def r_type(rs: int, rt: int, rd: int, shamt: int, funct: int) -> int:
    return (rs << 21) | (rt << 16) | (rd << 11) | (shamt << 6) | funct


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=Path(__file__).absolute().parents[1]
        / "results"
        / "lab6_lab7"
        / "directed"
        / "hilo-stall-branch"
        / "image",
    )
    args = parser.parse_args()
    out_dir: Path = args.out_dir.absolute()
    out_dir.mkdir(parents=True, exist_ok=True)

    entries: list[tuple[int, str]] = [
        (i_type(0x09, 0, 1, -23), "addiu r1, r0, -23"),
        (i_type(0x09, 0, 2, 5), "addiu r2, r0, 5"),
        (r_type(1, 2, 0, 0, 0x1A), "div r1, r2 ; quotient=-4, remainder=-3"),
        (i_type(0x04, 0, 0, 2), "beq r0, r0, target ; held behind DIV in EX"),
        (i_type(0x09, 0, 3, 0x55), "addiu r3, r0, 0x55 ; branch delay slot"),
        (i_type(0x09, 0, 4, 0x1234), "addiu r4, r0, 0x1234 ; must be skipped"),
        (r_type(0, 0, 5, 0, 0x12), "mflo r5 ; expect fffffffc"),
        (r_type(0, 0, 6, 0, 0x10), "mfhi r6 ; expect fffffffd"),
        (i_type(0x09, 0, 7, 0x66), "addiu r7, r0, 0x66 ; branch target marker"),
    ]
    if len(entries) > 64:
        raise RuntimeError("directed image exceeds END_PC word index 64")
    entries.extend((0, "nop") for _ in range(65 - len(entries)))

    mif_path = out_dir / "lab6_hilo_stall_branch.mif"
    coe_path = out_dir / "lab6_hilo_stall_branch.coe"
    asm_path = out_dir / "lab6_hilo_stall_branch_program.txt"
    mif_path.write_text("".join(f"{word:032b}\n" for word, _ in entries), encoding="ascii")
    coe_path.write_text(
        "memory_initialization_radix = 16;\n"
        "memory_initialization_vector =\n"
        + "\n".join(f"{word:08x}" for word, _ in entries[:-1])
        + f"\n{entries[-1][0]:08x};\n",
        encoding="ascii",
    )
    listing = [
        "# Lab6 directed image for long DIV backpressure and held ID branch testing.",
        "# The branch's delay slot must retire, while its fall-through instruction must not.",
        "# Word index 64 is the testbench END_PC sentinel at 0xbfc00100.",
    ]
    listing.extend(
        f"{index:02d}  0x{0xBFC00000 + index * 4:08x}  {word:08x}  {source}"
        for index, (word, source) in enumerate(entries)
    )
    asm_path.write_text("\n".join(listing) + "\n", encoding="ascii")
    print(f"WORDS={len(entries)}")
    print(f"COE={coe_path}")
    print(f"MIF={mif_path}")
    print(f"ASSEMBLY_LISTING={asm_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
