#!/usr/bin/env python3
"""Build a compact Lab6 ALU/forwarding image without a MIPS cross-toolchain."""

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
        / "alu"
        / "image",
    )
    args = parser.parse_args()
    out_dir: Path = args.out_dir.absolute()
    out_dir.mkdir(parents=True, exist_ok=True)

    entries: list[tuple[int, str]] = []

    def emit(word: int, source: str) -> None:
        entries.append((word, source))

    def addiu(rt: int, rs: int, imm: int, note: str = "") -> None:
        emit(i_type(0x09, rs, rt, imm), f"addiu r{rt}, r{rs}, 0x{imm & 0xffff:04x}{note}")

    def addi(rt: int, rs: int, imm: int, note: str = "") -> None:
        emit(i_type(0x08, rs, rt, imm), f"addi r{rt}, r{rs}, 0x{imm & 0xffff:04x}{note}")

    def lui(rt: int, imm: int, note: str = "") -> None:
        emit(i_type(0x0F, 0, rt, imm), f"lui r{rt}, 0x{imm & 0xffff:04x}{note}")

    def imm_op(op: int, name: str, rt: int, rs: int, imm: int, note: str) -> None:
        emit(i_type(op, rs, rt, imm), f"{name} r{rt}, r{rs}, 0x{imm & 0xffff:04x}{note}")

    def r_op(name: str, funct: int, rd: int, rs: int, rt: int, note: str = "") -> None:
        operands = f"r{rd}, r{rt}, r{rs}" if name in {"sllv", "srlv", "srav"} else f"r{rd}, r{rs}, r{rt}"
        emit(r_type(rs, rt, rd, 0, funct), f"{name} {operands}{note}")

    def nop() -> None:
        emit(0, "nop")

    lui(10, 0x800D, " ; data RAM base")
    addiu(1, 0, 0x8000, " ; expect ffff8000")
    addiu(2, 0, 0x7FFF, " ; expect 00007fff")
    r_op("add", 0x20, 3, 1, 2, " ; expect ffffffff")
    addi(4, 0, 0x8000, " ; sign extension: expect ffff8000")
    addi(5, 0, 0xFFFF, " ; sign extension: expect ffffffff")
    r_op("sub", 0x22, 6, 4, 2, " ; expect ffff0001")
    imm_op(0x0A, "slti", 7, 1, 0x7FFF, " ; signed less-than: expect 1")
    imm_op(0x0A, "slti", 8, 1, 0x8000, " ; equal signed operands: expect 0")
    imm_op(0x0B, "sltiu", 9, 1, 0x8000, " ; sign-extended unsigned compare: expect 0")
    imm_op(0x0B, "sltiu", 11, 0, 0x8000, " ; sign-extended unsigned compare: expect 1")
    imm_op(0x0C, "andi", 12, 5, 0x8000, " ; zero extension: expect 00008000")
    imm_op(0x0D, "ori", 13, 0, 0x8000, " ; zero extension: expect 00008000")
    imm_op(0x0E, "xori", 14, 5, 0xFFFF, " ; zero extension: expect ffff0000")

    lui(15, 0x8000, " ; expect 80000000")
    lui(16, 0x8000)
    addiu(16, 16, 0x0025, " ; shift amount 0x80000025, low five bits are 5")
    r_op("sllv", 0x04, 17, 16, 1, " ; expect fff00000")
    r_op("srlv", 0x06, 18, 16, 15, " ; expect 04000000")
    r_op("srav", 0x07, 19, 16, 15, " ; expect fc000000")

    # Exercise all three producer stages with the new ADD instruction.
    addiu(20, 0, 0x1234)
    r_op("add", 0x20, 21, 20, 20, " ; EX forwarding")
    addiu(22, 0, 0x0011)
    nop()
    r_op("add", 0x20, 23, 22, 22, " ; MEM forwarding")
    addiu(24, 0, 0x0012)
    nop()
    nop()
    r_op("add", 0x20, 25, 24, 24, " ; WB forwarding")

    # Exercise immediate-op source forwarding and an immediate load-use pair.
    addiu(26, 0, 1)
    addi(27, 26, 0x7FFF, " ; expect 00008000")
    imm_op(0x0D, "ori", 28, 0, 0xDEAD, " ; expect 0000dead")
    imm_op(0x0C, "andi", 29, 28, 0x8000, " ; expect 00008000")
    emit(i_type(0x2B, 10, 2, 0), "sw r2, 0(r10)")
    emit(i_type(0x23, 10, 30, 0), "lw r30, 0(r10)")
    addi(31, 30, 1, " ; load-use stall; expect 00008000")

    # Low-five-bit masking must ignore the high bits and retain bit 4.
    addiu(16, 0, 0x003F, " ; shift amount 63, low five bits are 31")
    r_op("sllv", 0x04, 17, 16, 2, " ; expect 80000000")
    r_op("srlv", 0x06, 18, 16, 15, " ; expect 00000001")
    r_op("srav", 0x07, 19, 16, 15, " ; expect ffffffff")

    if len(entries) > 64:
        raise RuntimeError("directed image exceeds END_PC word index 64")
    entries.extend([(0, "nop") for _ in range(65 - len(entries))])

    mif_path = out_dir / "lab6_alu_directed.mif"
    coe_path = out_dir / "lab6_alu_directed.coe"
    asm_path = out_dir / "lab6_alu_directed_program.txt"
    mif_path.write_text("".join(f"{word:032b}\n" for word, _ in entries), encoding="ascii")
    coe_path.write_text(
        "memory_initialization_radix = 16;\n"
        "memory_initialization_vector =\n"
        + "\n".join(f"{word:08x}" for word, _ in entries[:-1])
        + f"\n{entries[-1][0]:08x};\n",
        encoding="ascii",
    )
    listing = [
        "# Lab6 ALU, immediate extension, variable shifts and forwarding directed image.",
        "# CPU results are checked against the independent CPU132 reference trace.",
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
