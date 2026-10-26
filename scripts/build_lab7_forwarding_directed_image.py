#!/usr/bin/env python3
"""Build a compact Lab7 instruction-forwarding image without a cross-toolchain."""

from __future__ import annotations

import argparse
from pathlib import Path


BASE_PC = 0xBFC00000
END_WORD = 64


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
        / "extended-forwarding"
        / "image",
    )
    args = parser.parse_args()
    out_dir: Path = args.out_dir.absolute()
    out_dir.mkdir(parents=True, exist_ok=True)

    entries: list[tuple[int, str]] = []
    labels: dict[str, int] = {}
    branch_fixups: list[tuple[int, int, int, int, str]] = []
    address_fixups: list[tuple[int, int, int, str]] = []

    def emit(word: int, source: str) -> int:
        entries.append((word, source))
        return len(entries) - 1

    def label(name: str) -> None:
        if name in labels:
            raise ValueError(f"duplicate label: {name}")
        labels[name] = len(entries)

    def addiu(rt: int, rs: int, imm: int, note: str = "") -> None:
        emit(i_type(0x09, rs, rt, imm), f"addiu r{rt}, r{rs}, {imm}{note}")

    def lui(rt: int, imm: int, note: str = "") -> None:
        emit(i_type(0x0F, 0, rt, imm), f"lui r{rt}, 0x{imm:04x}{note}")

    def ori(rt: int, rs: int, imm: int, fixup_label: str | None = None) -> None:
        index = emit(i_type(0x0D, rs, rt, imm), f"ori r{rt}, r{rs}, 0x{imm & 0xffff:04x}")
        if fixup_label is not None:
            address_fixups.append((index, rs, rt, fixup_label))

    def addu(rd: int, rs: int, rt: int, note: str = "") -> None:
        emit(r_type(rs, rt, rd, 0, 0x21), f"addu r{rd}, r{rs}, r{rt}{note}")

    def load(rt: int, rs: int, imm: int) -> None:
        emit(i_type(0x23, rs, rt, imm), f"lw r{rt}, {imm}(r{rs})")

    def store(name: str, op: int, rt: int, rs: int, imm: int) -> None:
        emit(i_type(op, rs, rt, imm), f"{name} r{rt}, {imm}(r{rs})")

    def branch(name: str, op: int, rs: int, rt: int, target: str) -> None:
        operands = f"r{rs}, {target}" if op == 0x01 else f"r{rs}, r{rt}, {target}"
        index = emit(0, f"{name} {operands}")
        branch_fixups.append((index, op, rs, rt, target))

    def jr(rs: int) -> None:
        emit(r_type(rs, 0, 0, 0, 0x08), f"jr r{rs}")

    def jalr(rd: int, rs: int) -> None:
        emit(r_type(rs, 0, rd, 0, 0x09), f"jalr r{rd}, r{rs}")

    def nop(note: str = "") -> None:
        emit(0, f"nop{note}")

    # EX/MEM/WB forwarding, youngest-writer priority, and a load-use wait.
    addiu(5, 0, 1)
    addiu(6, 5, 1, " ; EX forwarding")
    addiu(7, 0, 2)
    nop()
    addiu(8, 7, 1, " ; MEM forwarding")
    addiu(9, 0, 3)
    nop()
    nop()
    addiu(11, 9, 1, " ; WB forwarding")
    addiu(12, 0, 1)
    addiu(12, 0, 2)
    addu(13, 12, 0, " ; youngest writer wins")
    lui(14, 0x800D, " ; load-use test data base")
    load(15, 14, 0)
    addu(16, 15, 0, " ; one load-use wait")

    # Each added store family has a forwarded operand. SB/SH exercise the
    # address base; SWL/SWR exercise store data. The final SW preserves the
    # original Lab3/Lab4 store counters as a compatibility check.
    lui(10, 0x800D, " ; data RAM base")
    addiu(10, 10, 4)
    store("sb", 0x28, 6, 10, -4)
    addiu(10, 10, 4)
    store("sh", 0x29, 6, 10, -4)
    addiu(1, 0, 0x1234)
    store("swl", 0x2A, 1, 10, 0)
    addiu(1, 0, 0x5678)
    store("swr", 0x2E, 1, 10, 4)
    addiu(10, 10, 4)
    store("sw", 0x2B, 10, 10, -4)

    # All six added conditional branches consume a just-produced rs value.
    branch_cases = [
        ("bgez", 0x01, 1, 1),
        ("bgtz", 0x07, 0, 1),
        ("blez", 0x06, 0, 0),
        ("bltz", 0x01, 0, -1),
        ("bgezal", 0x01, 0x11, 1),
        ("bltzal", 0x01, 0x10, -1),
    ]
    for index, (name, op, rt, value) in enumerate(branch_cases):
        addiu(2, 0, value, f" ; {name} rs producer")
        branch(name, op, 2, rt, f"after_{name}")
        addiu(3, 0, 0x40 + index, " ; architectural delay slot")
        addiu(3, 0, 0x99, " ; skipped when branch is taken")
        label(f"after_{name}")

    # JR and JALR both use the immediately preceding ORI result as the target.
    lui(20, 0xBFC0)
    ori(20, 20, 0, "jalr_setup")
    jr(20)
    addiu(4, 0, 0x51, " ; JR delay slot")
    addiu(4, 0, 0x99, " ; skipped by JR")
    label("jalr_setup")

    lui(25, 0xBFC0)
    ori(25, 25, 0, "beq_setup")
    jalr(26, 25)
    addiu(4, 0, 0x61, " ; JALR delay slot")
    addiu(4, 0, 0x99, " ; skipped by JALR")
    label("beq_setup")

    addiu(2, 0, 1, " ; legacy BEQ rs producer")
    branch("beq", 0x04, 2, 2, "end")
    addiu(4, 0, 0x71, " ; BEQ delay slot")
    addiu(4, 0, 0x99, " ; skipped by BEQ")
    label("end")

    if len(entries) != END_WORD:
        raise RuntimeError(f"expected {END_WORD} test words before END_PC, got {len(entries)}")

    words = [word for word, _ in entries]
    for index, op, rs, rt, target in branch_fixups:
        if target not in labels:
            raise ValueError(f"unknown branch target: {target}")
        offset = labels[target] - (index + 1)
        if not -32768 <= offset <= 32767:
            raise RuntimeError(f"branch target out of range: {target}")
        words[index] = i_type(op, rs, rt, offset)
        entries[index] = (words[index], entries[index][1] + f" (offset {offset})")

    for index, rs, rt, target in address_fixups:
        if target not in labels:
            raise ValueError(f"unknown jump target: {target}")
        target_address = BASE_PC + labels[target] * 4
        words[index] = i_type(0x0D, rs, rt, target_address & 0xFFFF)
        entries[index] = (
            words[index],
            f"ori r{rt}, r{rs}, 0x{target_address & 0xffff:04x} "
            f"(target 0x{target_address:08x})",
        )

    # The shared testbench stops when WB reaches PC 0xbfc00100 (word 64).
    words.append(0)
    entries.append((0, "nop ; END_PC sentinel at word 64"))

    mif_path = out_dir / "lab7_extended_forwarding.mif"
    coe_path = out_dir / "lab7_extended_forwarding.coe"
    listing_path = out_dir / "lab7_extended_forwarding_program.txt"
    mif_path.write_text("".join(f"{word:032b}\n" for word in words), encoding="ascii")
    coe_path.write_text(
        "memory_initialization_radix = 16;\n"
        "memory_initialization_vector =\n"
        + "\n".join(f"{word:08x}" for word in words[:-1])
        + f"\n{words[-1]:08x};\n",
        encoding="ascii",
    )
    listing = [
        "# Lab7 forwarding directed image, checked against the independent CPU132 trace.",
        "# Includes sb/sh/swl/swr, bgez/bgtz/blez/bltz/bgezal/bltzal and jalr.",
        "# Each added store/branch/jalr family includes at least one forwarded source.",
        "# Word index 64 is the testbench END_PC sentinel at 0xbfc00100.",
    ]
    listing.extend(
        f"{index:02d}  0x{BASE_PC + index * 4:08x}  {word:08x}  {source}"
        for index, (word, source) in enumerate(entries)
    )
    listing_path.write_text("\n".join(listing) + "\n", encoding="ascii")
    print(f"WORDS={len(words)}")
    print(f"COE={coe_path}")
    print(f"MIF={mif_path}")
    print(f"ASSEMBLY_LISTING={listing_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
