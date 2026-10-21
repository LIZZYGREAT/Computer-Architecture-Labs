#!/usr/bin/env python3
"""Build a small MIPS-I hazard program as COE/MIF without a cross toolchain."""

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
        default=Path(__file__).absolute().parents[2]
        / "lab"
        / "results"
        / "lab3_lab4"
        / "hazard-directed"
        / "image",
    )
    args = parser.parse_args()
    out_dir: Path = args.out_dir.absolute()
    out_dir.mkdir(parents=True, exist_ok=True)

    # Entries are either assembled words or branch fixups. Labels are word indices.
    entries: list[tuple[int, str]] = []
    labels: dict[str, int] = {}
    branches: list[tuple[int, int, int, str]] = []

    def emit(word: int, source: str) -> None:
        entries.append((word, source))

    def label(name: str) -> None:
        labels[name] = len(entries)

    def addiu(rt: int, rs: int, imm: int) -> None:
        emit(i_type(0x09, rs, rt, imm), f"addiu r{rt}, r{rs}, {imm}")

    def lui(rt: int, imm: int) -> None:
        emit(i_type(0x0F, 0, rt, imm), f"lui r{rt}, 0x{imm:04x}")

    def addu(rd: int, rs: int, rt: int) -> None:
        emit(r_type(rs, rt, rd, 0, 0x21), f"addu r{rd}, r{rs}, r{rt}")

    def lw(rt: int, rs: int, imm: int) -> None:
        emit(i_type(0x23, rs, rt, imm), f"lw r{rt}, {imm}(r{rs})")

    def sw(rt: int, rs: int, imm: int) -> None:
        emit(i_type(0x2B, rs, rt, imm), f"sw r{rt}, {imm}(r{rs})")

    def beq(rs: int, rt: int, destination: str) -> None:
        index = len(entries)
        entries.append((0, f"beq r{rs}, r{rt}, {destination}"))
        branches.append((index, rs, rt, destination))

    def jr(rs: int) -> None:
        emit(r_type(rs, 0, 0, 0, 0x08), f"jr r{rs}")

    # EX forwarding, MEM/WB forwarding, and youngest-writer priority.
    addiu(1, 0, 5)
    addiu(2, 1, 3)
    addiu(3, 0, 1)
    addu(4, 2, 1)
    addiu(5, 0, 1)
    addiu(5, 0, 2)
    addu(6, 5, 0)

    # Immediate ALU-to-store base/data forwarding, load-use, and load-to-store.
    lui(10, 0x800D)
    addiu(8, 0, 0x55)
    sw(8, 10, 0)
    lw(9, 10, 0)
    addu(11, 9, 8)
    lw(12, 10, 0)
    sw(12, 10, 4)
    lw(22, 10, 4)

    # ALU-to-branch (not taken), with a visible delay-slot write.
    addiu(13, 0, 1)
    beq(13, 1, "after_not_taken")
    addiu(14, 0, 7)  # delay slot
    addiu(14, 0, 99)  # executes only when the branch is not taken
    label("after_not_taken")

    # Load-to-branch (taken), with one visible delay-slot write.
    lw(15, 10, 0)
    beq(15, 8, "after_taken")
    addiu(16, 0, 2)  # delay slot
    addiu(16, 0, 99)  # skipped by the taken branch
    label("after_taken")
    addiu(17, 0, 3)

    # The newest value of r20 must drive JR while an older r20 write is in MEM.
    target_index = len(entries) + 6
    lui(20, 0xBFC0)
    addiu(20, 20, target_index * 4)
    jr(20)
    addiu(18, 0, 4)  # JR delay slot
    addiu(18, 0, 99)  # skipped by JR
    addiu(18, 0, 88)  # skipped by JR
    label("jr_target")
    if labels["jr_target"] != target_index:
        raise RuntimeError("JR target layout changed unexpectedly")
    addiu(19, 0, 5)

    # Attempted $zero write followed by a real read. The following writeback
    # is checked against the independent CPU132 trace, and the testbench also
    # asserts that the WB interface never enables destination register zero.
    addiu(0, 0, 5)
    addu(21, 0, 1)

    words: list[int] = []
    sources: list[str] = []
    for index, (word, source) in enumerate(entries):
        words.append(word)
        sources.append(source)

    for index, rs, rt, destination in branches:
        offset = labels[destination] - (index + 1)
        if not -32768 <= offset <= 32767:
            raise RuntimeError(f"branch target out of range: {destination}")
        words[index] = i_type(0x04, rs, rt, offset)
        sources[index] += f" (offset {offset})"

    # The supplied testbench terminates when WB reaches PC 0xbfc00100 (word 64).
    # Padding NOPs are sll $zero,$zero,0 and therefore appear in EX's
    # zero-destination write-attempt counter; they are not dedicated tests.
    if len(words) > 64:
        raise RuntimeError("directed program exceeds the testbench END_PC")
    words.extend([0] * (65 - len(words)))
    sources.extend(["nop"] * (65 - len(sources)))

    mif_path = out_dir / "hazard_inst_ram.mif"
    coe_path = out_dir / "hazard_inst_ram.coe"
    asm_path = out_dir / "hazard_program.txt"
    mif_path.write_text("".join(f"{word:032b}\n" for word in words), encoding="ascii")
    coe_path.write_text(
        "memory_initialization_radix = 16;\n"
        "memory_initialization_vector =\n"
        + "\n".join(f"{word:08x}" for word in words[:-1])
        + f"\n{words[-1]:08x};\n",
        encoding="ascii",
    )
    asm_lines = [
        "# MIPS-I directed hazard image; expected behavior is checked by cpu132_gettrace.",
        "# Word index 64 is the shared END_PC sentinel at 0xbfc00100.",
    ]
    for index, (word, source) in enumerate(zip(words, sources)):
        asm_lines.append(f"{index:02d}  0x{0xBFC00000 + index * 4:08x}  {word:08x}  {source}")
    asm_path.write_text("\n".join(asm_lines) + "\n", encoding="ascii")
    print(f"WORDS={len(words)}")
    print(f"COE={coe_path}")
    print(f"MIF={mif_path}")
    print(f"ASSEMBLY_LISTING={asm_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
