"""Generate the small, reproducible Lab19 software TLBWI image."""

from pathlib import Path


def lui(rt: int, immediate: int) -> int:
    return (0x0F << 26) | (rt << 16) | (immediate & 0xFFFF)


def ori(rs: int, rt: int, immediate: int) -> int:
    return (0x0D << 26) | (rs << 21) | (rt << 16) | (immediate & 0xFFFF)


def addiu(rs: int, rt: int, immediate: int) -> int:
    return (0x09 << 26) | (rs << 21) | (rt << 16) | (immediate & 0xFFFF)


def mtc0(rt: int, rd: int) -> int:
    return (0x10 << 26) | (0x04 << 21) | (rt << 16) | (rd << 11)


def jr(rs: int) -> int:
    return (rs << 21) | 0x08


def beq(rs: int, rt: int, offset: int) -> int:
    return (0x04 << 26) | (rs << 21) | (rt << 16) | (offset & 0xFFFF)


def image_words() -> list[int]:
    # Boot from the CPU's BFC00000 reset vector (direct-mapped to AXI RAM).
    # The software installs VA 00400000 -> PFN 00000, both pages valid,
    # dirty, and cacheable, then jumps to VA 00400100.
    words = [
        lui(8, 0x0040),  # lui   t0, 0x0040       ; EntryHi = 00400000
        mtc0(8, 10),     # mtc0  t0, EntryHi
        addiu(0, 9, 0x001E),  # addiu t1, zero, 0x1e ; C=3, D=1, V=1
        mtc0(9, 2),      # mtc0  t1, EntryLo0
        mtc0(9, 3),      # mtc0  t1, EntryLo1
        mtc0(0, 0),      # mtc0  zero, Index
        0x42000002,      # tlbwi
        lui(12, 0x0040), # lui   t4, 0x0040
        ori(12, 12, 0x0100),  # ori t4, t4, 0x0100
        jr(12),          # jr    t4
        0x00000000,      # delay-slot nop
    ]

    # AXI RAM indexes this image by byte address. Word 64 is at PA 0x100,
    # which is the target page's offset after the real TLB translation.
    words.extend([0] * (64 - len(words)))
    words.extend(
        [
            addiu(0, 23, 0x0019),  # addiu s7, zero, 0x19; checked at WB
            beq(0, 0, -1),         # beq zero, zero, .    ; stop on target page
            0x00000000,            # delay-slot nop
            0x00000000,
            0x00000000,
            0x00000000,
            0x00000000,
            0x00000000,
        ]
    )
    return words


def render_coe(words: list[int]) -> str:
    values = ",\n".join(f"{word:08x}" for word in words)
    return (
        "memory_initialization_radix = 16;\n"
        "memory_initialization_vector =\n"
        f"{values};\n"
    )


def main() -> None:
    output = Path(__file__).resolve().parents[2] / "lab19" / "cpu_cache" / "testbench" / "tlbwi_e2e.coe"
    output.write_bytes(render_coe(image_words()).encode("ascii"))
    print(f"WROTE={output}")
    print(f"WORDS={len(image_words())}")


if __name__ == "__main__":
    main()
