#!/usr/bin/env python3
"""Validate the external-interrupt VCD against its Vivado wave configuration."""

from __future__ import annotations

import argparse
import re
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path


def parse_vcd(path: Path) -> tuple[dict[str, str], dict[str, list[tuple[int, str]]], str]:
    text = path.read_text(encoding="ascii", errors="replace")
    timescale_match = re.search(r"\$timescale\s+([^\s]+)\s+\$end", text)
    if not timescale_match:
        raise ValueError("VCD has no readable $timescale")

    scopes: list[str] = []
    names_by_code: dict[str, str] = {}
    events: dict[str, list[tuple[int, str]]] = defaultdict(list)
    in_header = True
    timestamp_ps = 0

    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if in_header:
            fields = line.split()
            if line.startswith("$scope") and len(fields) >= 3:
                scopes.append(fields[2])
            elif line.startswith("$upscope") and scopes:
                scopes.pop()
            elif line.startswith("$var") and len(fields) >= 5:
                code, signal = fields[3], fields[4]
                names_by_code[code] = "/" + "/".join([*scopes, signal])
            elif line.startswith("$enddefinitions"):
                in_header = False
            continue

        if line.startswith("#"):
            timestamp_ps = int(line[1:])
            continue
        if line.startswith("$"):
            continue
        if line[0] in "01xXzZ" and len(line) > 1:
            value, code = line[0].lower(), line[1:]
        elif line[0] in "bB" and len(line.split()) >= 2:
            fields = line[1:].split()
            value, code = fields[0].lower(), fields[1]
        else:
            continue
        events[code].append((timestamp_ps, value))

    return names_by_code, events, timescale_match.group(1)


def integer(value: str | None) -> int | None:
    if value is None or any(char in value for char in "xz"):
        return None
    return int(value, 2)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("vcd", type=Path)
    parser.add_argument("wcfg", type=Path)
    args = parser.parse_args()

    names_by_code, events_by_code, timescale = parse_vcd(args.vcd)
    if timescale != "1ps":
        raise SystemExit(f"expected a 1ps VCD timescale, got {timescale}")
    code_by_name = {name: code for code, name in names_by_code.items()}

    config = ET.parse(args.wcfg).getroot()
    configured_paths = {node.attrib["fp_name"] for node in config.iter("wvobject")}
    vcd_paths = set(names_by_code.values())
    if configured_paths != vcd_paths:
        missing = sorted(configured_paths - vcd_paths)
        extra = sorted(vcd_paths - configured_paths)
        raise SystemExit(f"WCFG/VCD path mismatch; missing={missing}, extra={extra}")
    if len(configured_paths) != 22:
        raise SystemExit(f"expected 22 waveform paths, got {len(configured_paths)}")

    def signal_events(path: str) -> list[tuple[int, str]]:
        code = code_by_name.get(path)
        if code is None:
            raise SystemExit(f"missing VCD signal: {path}")
        return events_by_code[code]

    def value_at(path: str, time_ps: int) -> int | None:
        value: str | None = None
        for at_ps, update in signal_events(path):
            if at_ps > time_ps:
                break
            value = update
        return integer(value)

    def require(path: str, time_ps: int, expected: int) -> None:
        actual = value_at(path, time_ps)
        if actual != expected:
            raise SystemExit(
                f"{path} at {time_ps / 1000:g}ns: expected 0x{expected:X}, "
                f"got {None if actual is None else f'0x{actual:X}'}"
            )

    clock_path = "/interrupt_tb/clk"
    clock_events = signal_events(clock_path)
    clock_transitions = [time for time, _ in clock_events if time > 0]
    if len(clock_transitions) < 80 or any(
        later - earlier != 5000
        for earlier, later in zip(clock_transitions, clock_transitions[1:])
    ):
        raise SystemExit("clock does not contain the expected 5ns transitions")

    prefix = "/interrupt_tb/dut/"
    require(prefix + "cp0_reg/interrupt_pending", 175_000, 1)
    require(prefix + "trap_commit", 195_000, 1)
    require(prefix + "trap_pc", 195_000, 0xBFC0001C)
    require(prefix + "trap_code", 195_000, 0)
    require(prefix + "cp0_epc", 205_000, 0xBFC0001C)
    require(prefix + "cp0_reg/interrupt_pending", 205_000, 0)
    require(prefix + "eret_commit", 295_000, 1)
    require(prefix + "eret_commit", 305_000, 0)
    require(prefix + "cp0_reg/status_exl", 305_000, 0)
    require("/interrupt_tb/data_sram_wen", 325_000, 0xF)
    require("/interrupt_tb/data_sram_wen", 335_000, 0)

    trap_rises = sum(
        integer(value) == 1
        and (index == 0 or integer(signal_events(prefix + "trap_commit")[index - 1][1]) != 1)
        for index, (_, value) in enumerate(signal_events(prefix + "trap_commit"))
    )
    eret_rises = sum(
        integer(value) == 1
        and (index == 0 or integer(signal_events(prefix + "eret_commit")[index - 1][1]) != 1)
        for index, (_, value) in enumerate(signal_events(prefix + "eret_commit"))
    )
    if trap_rises != 1 or eret_rises != 1:
        raise SystemExit(f"expected one trap and one ERET, got {trap_rises} and {eret_rises}")

    store_events = signal_events("/interrupt_tb/data_sram_wen")
    store_pulses = 0
    previous_store = 0
    for _, value in store_events:
        current_store = integer(value)
        if current_store is not None and current_store != 0 and previous_store == 0:
            store_pulses += 1
        if current_store is not None:
            previous_store = current_store
    if store_pulses != 1:
        raise SystemExit(f"expected one resumed store pulse, got {store_pulses}")

    write_pc = signal_events("/interrupt_tb/debug_wb_pc")
    write_mask = signal_events("/interrupt_tb/debug_wb_rf_wen")
    sample_times = sorted({time for time, _ in write_pc + write_mask})
    for time_ps in sample_times:
        if value_at("/interrupt_tb/debug_wb_pc", time_ps) == 0xBFC0001C and value_at(
            "/interrupt_tb/debug_wb_rf_wen", time_ps
        ):
            raise SystemExit("interrupted instruction unexpectedly wrote a GPR")

    print(f"VCD_VALID={args.vcd}")
    print(f"WCFG_PATHS_MATCHED={len(configured_paths)}")
    print(f"CLOCK_TRANSITIONS={len(clock_transitions)}")
    print("IP2_EVENTS=PASS pending@175ns trap@195ns EPC@205ns ERET@295ns one_store@325ns")
    print("INTERRUPTED_GPR_WRITE=NONE")


if __name__ == "__main__":
    main()
