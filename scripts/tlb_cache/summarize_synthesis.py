#!/usr/bin/env python3
"""Summarize an isolated Lab19 synthesis run and enforce its acceptance gates."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace") if path.is_file() else ""


def count_matches(pattern: str, text: str) -> int:
    return len(re.findall(pattern, text, flags=re.IGNORECASE | re.MULTILINE))


def resource_used(report: str, label: str) -> int | None:
    for line in report.splitlines():
        if label.lower() in line.lower():
            cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
            if len(cells) >= 3 and cells[0].lower() == label.lower():
                match = re.search(r"\d+", cells[1].replace(",", ""))
                if match:
                    return int(match.group())
    return None


def timing_metrics(report: str) -> dict[str, str]:
    values: dict[str, str] = {}
    summary = report.split("| Design Timing Summary", 1)
    if len(summary) != 2:
        return values
    for line in summary[1].splitlines():
        if not re.match(r"^\s*-?\d+\.\d+\s+", line):
            continue
        columns = line.split()
        if len(columns) >= 12:
            values.update(
                SETUP_WNS_NS=columns[0],
                SETUP_TNS_NS=columns[1],
                SETUP_FAILING_ENDPOINTS=columns[2],
                HOLD_WHS_NS=columns[4],
                HOLD_THS_NS=columns[5],
                HOLD_FAILING_ENDPOINTS=columns[6],
            )
            break
    for key, pattern in (
        ("UNCONSTRAINED_INPUTS", r"There are (\d+) input ports with no input delay specified"),
        ("UNCONSTRAINED_OUTPUTS", r"There are (\d+) ports with no output delay specified"),
    ):
        match = re.search(pattern, report, flags=re.IGNORECASE)
        if match:
            values[key] = match.group(1)
    return values


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--vivado-exit-code", type=int, required=True)
    args = parser.parse_args()
    run_dir = args.run_dir.resolve()
    repo_root = args.repo_root.resolve()

    log = read_text(run_dir / "vivado.log")
    run = read_text(run_dir / "synthesis-run.txt")
    synth_log = read_text(run_dir / "project/r3l19_synthesis.runs/synth_1/runme.log")
    timing = read_text(run_dir / "timing-summary.rpt")
    utilization = read_text(run_dir / "utilization.rpt")
    source_integrity = read_text(run_dir / "source-integrity.txt")

    warning_lines = [
        line for line in log.splitlines()
        if re.match(r"^\s*(?:CRITICAL WARNING|WARNING):", line, flags=re.IGNORECASE)
    ]
    synth_warning_lines = [
        line for line in synth_log.splitlines()
        if re.match(r"^\s*(?:CRITICAL WARNING|WARNING):", line, flags=re.IGNORECASE)
    ]
    vivado_error_lines = [
        line for line in log.splitlines()
        if re.match(r"^\s*ERROR:", line, flags=re.IGNORECASE)
    ]
    (run_dir / "warning-messages.txt").write_text(
        "\n".join(synth_warning_lines) + ("\n" if synth_warning_lines else ""), encoding="utf-8"
    )
    (run_dir / "vivado-error-messages.txt").write_text(
        "\n".join(vivado_error_lines) + ("\n" if vivado_error_lines else ""), encoding="utf-8"
    )

    synth_summary_match = re.search(
        r"(?m)^\s*\d+\s+Infos?,\s+(\d+)\s+Warnings,\s+(\d+)\s+Critical Warnings and\s+(\d+)\s+Errors encountered\.",
        synth_log,
    )
    warning_count = int(synth_summary_match.group(1)) if synth_summary_match else 0
    critical_count = int(synth_summary_match.group(2)) if synth_summary_match else 0
    error_count = int(synth_summary_match.group(3)) if synth_summary_match else 1
    categories = {
        "UNCONNECTED_OR_UNDRIVEN": r"unconnected|not connected|undriven|no driver",
        "WIDTH_OR_TRUNCATION": r"width mismatch|truncat|size mismatch|extended to|expects .* bits",
        "LATCH_OR_COMBINATIONAL_LOOP": r"inferred latch|latch inferred|combinational loop|loop detected",
        "CLOCK_OR_IP_MIGRATION": r"clock|period|clocking wizard|upgrade_ip|ip revision|ip version",
        "UNUSED_OR_TRIMMED": r"unused|trimmed|not used|unconnected",
    }
    category_counts = {
        name: sum(1 for line in synth_warning_lines if re.search(pattern, line, flags=re.IGNORECASE))
        for name, pattern in categories.items()
    }

    metrics = timing_metrics(timing)
    metric_rows = [
        ("SLICE_LUTS", "Slice LUTs*"),
        ("LUT_AS_MEMORY", "LUT as Memory"),
        ("SLICE_REGISTERS", "Slice Registers"),
        ("BRAM_TILES", "Block RAM Tile"),
        ("DSP", "DSPs"),
        ("IOB", "Bonded IOB"),
        ("PLLE2_ADV", "PLLE2_ADV"),
        ("BUFGCTRL", "BUFGCTRL"),
    ]
    for key, label in metric_rows:
        used = resource_used(utilization, label)
        if used is not None:
            metrics[key] = str(used)

    run_status_match = re.search(r"(?m)^SYNTH_STATUS=(.+)$", run)
    progress_match = re.search(r"(?m)^SYNTH_PROGRESS=(.+)$", run)
    synth_run_ok = bool(
        run_status_match
        and "complete" in run_status_match.group(1).lower()
        and progress_match
        and progress_match.group(1).strip() == "100%"
        and "synth_design completed successfully" in synth_log.lower()
        and synth_summary_match is not None
    )
    integrity_ok = "SOURCE_INTEGRITY=PASS" in source_integrity
    synth_status = "PASS" if synth_run_ok and args.vivado_exit_code == 0 else "FAIL"
    acceptance_status = "PASS" if (
        synth_status == "PASS" and integrity_ok and critical_count == 0 and error_count == 0
    ) else "FAIL"
    if acceptance_status == "PASS" and vivado_error_lines:
        acceptance_status = "PASS_WITH_TOOL_DIAGNOSTIC"

    try:
        setup_estimate = "PASS" if (
            float(metrics["SETUP_WNS_NS"]) >= 0
            and int(metrics["SETUP_FAILING_ENDPOINTS"]) == 0
        ) else "FAIL"
    except (KeyError, ValueError):
        setup_estimate = "UNAVAILABLE"
    try:
        hold_estimate = "PASS" if (
            float(metrics["HOLD_WHS_NS"]) >= 0
            and int(metrics["HOLD_FAILING_ENDPOINTS"]) == 0
        ) else "FAIL"
    except (KeyError, ValueError):
        hold_estimate = "UNAVAILABLE"
    external_io_status = "NOT_CONSTRAINED" if (
        metrics.get("UNCONSTRAINED_INPUTS", "0") != "0"
        or metrics.get("UNCONSTRAINED_OUTPUTS", "0") != "0"
    ) else "NO_MISSING_IO_DELAYS_REPORTED"
    # This run stops after synthesis, so no result from it can claim FPGA signoff.
    timing_status = "TIMING_NOT_CLOSED"

    baseline_path = repo_root / "results/lab13-lab19/lab19/lab19-synthesis-20261118-01/utilization.rpt"
    baseline = read_text(baseline_path)
    comparisons = []
    for key, label in (("SLICE_LUTS", "Slice LUTs*"), ("BRAM_TILES", "Block RAM Tile")):
        current_value = resource_used(utilization, label)
        baseline_value = resource_used(baseline, label)
        if current_value is not None and baseline_value:
            delta = (current_value - baseline_value) * 100.0 / baseline_value
            comparisons.append(f"{key}_BASELINE={baseline_value}")
            comparisons.append(f"{key}_DELTA_PCT={delta:+.2f}")

    summary = [
        f"STATUS={acceptance_status}",
        f"SYNTHESIS_STATUS={synth_status}",
        f"TIMING_STATUS={timing_status}",
        "PLACE_ROUTE_STATUS=NOT_RUN",
        "BOARD_XDC_STATUS=ABSENT",
        f"SYNTH_SETUP_ESTIMATE={setup_estimate}",
        f"SYNTH_HOLD_ESTIMATE={hold_estimate}",
        f"EXTERNAL_IO_TIMING={external_io_status}",
        f"VIVADO_EXIT_CODE={args.vivado_exit_code}",
        f"SOURCE_INTEGRITY={'PASS' if integrity_ok else 'FAIL'}",
        f"SYNTH_WARNINGS={warning_count}",
        f"SYNTH_CRITICAL_WARNINGS={critical_count}",
        f"SYNTH_ERRORS={error_count}",
        f"VIVADO_LOG_WARNING_LINES={len(warning_lines)}",
        f"VIVADO_LOG_ERROR_LINES={len(vivado_error_lines)}",
        f"VIVADO_COMMON_PATH_ERROR_LINES={sum('Common 17-1257' in line for line in vivado_error_lines)}",
    ]
    summary.extend(f"{key}={value}" for key, value in metrics.items())
    summary.extend(comparisons)
    summary.extend(
        [
            f"WARNING_CLASS_{name}={count}" for name, count in category_counts.items()
        ]
    )
    summary.extend(
        [
            f"WARNING_CLASS_{name}_REVIEW=See warning-messages.txt and vivado.log"
            for name, count in category_counts.items() if count
        ]
    )
    summary.append("IP_STATUS_REPORT=ip-status.rpt")
    summary.append("TIMING_REPORT=timing-summary.rpt")
    summary.append("CHECK_TIMING_REPORT=check-timing.rpt")
    summary.append("CLOCK_REPORT=clocks.rpt")
    summary.append("HIERARCHICAL_UTILIZATION_REPORT=utilization-hierarchical.rpt")
    (run_dir / "synthesis-summary.txt").write_text("\n".join(summary) + "\n", encoding="utf-8")

    result_path = run_dir / "result.txt"
    existing = read_text(result_path).splitlines()
    retained = [
        line for line in existing
        if not line.startswith((
            "STATUS=", "SYNTHESIS_STATUS=", "TIMING_STATUS=", "PLACE_ROUTE_STATUS=",
            "BOARD_XDC_STATUS=", "SYNTH_SETUP_ESTIMATE=", "SYNTH_HOLD_ESTIMATE=", "EXTERNAL_IO_TIMING=",
            "SYNTH_ERRORS=", "SYNTH_WARNINGS=", "SYNTH_CRITICAL_WARNINGS=",
            "VIVADO_LOG_WARNING_LINES=", "VIVADO_LOG_ERROR_LINES=", "VIVADO_COMMON_PATH_ERROR_LINES=",
            "SLICE_LUTS=", "LUT_AS_MEMORY=", "SLICE_REGISTERS=", "BRAM_TILES=",
            "DSP=", "IOB=", "PLLE2_ADV=", "BUFGCTRL=", "SETUP_WNS_NS=",
            "SETUP_TNS_NS=", "SETUP_FAILING_ENDPOINTS=", "HOLD_WHS_NS=",
            "HOLD_THS_NS=", "HOLD_FAILING_ENDPOINTS=", "UNCONSTRAINED_INPUTS=",
            "UNCONSTRAINED_OUTPUTS=", "EXTERNAL_IO_DELAYS=", "BASELINE_",
        ))
    ]
    result = [
        *retained,
        f"STATUS={acceptance_status}",
        f"SYNTHESIS_STATUS={synth_status}",
        f"TIMING_STATUS={timing_status}",
        "PLACE_ROUTE_STATUS=NOT_RUN",
        "BOARD_XDC_STATUS=ABSENT",
        f"SYNTH_SETUP_ESTIMATE={setup_estimate}",
        f"SYNTH_HOLD_ESTIMATE={hold_estimate}",
        f"EXTERNAL_IO_TIMING={external_io_status}",
        f"SYNTH_WARNINGS={warning_count}",
        f"SYNTH_CRITICAL_WARNINGS={critical_count}",
        f"SYNTH_ERRORS={error_count}",
        f"VIVADO_LOG_WARNING_LINES={len(warning_lines)}",
        f"VIVADO_LOG_ERROR_LINES={len(vivado_error_lines)}",
        f"VIVADO_COMMON_PATH_ERROR_LINES={sum('Common 17-1257' in line for line in vivado_error_lines)}",
        *(f"{key}={metrics[key]}" for key in (
            "SLICE_LUTS", "LUT_AS_MEMORY", "SLICE_REGISTERS", "BRAM_TILES", "DSP", "IOB", "PLLE2_ADV", "BUFGCTRL",
            "SETUP_WNS_NS", "SETUP_TNS_NS", "SETUP_FAILING_ENDPOINTS", "HOLD_WHS_NS", "HOLD_THS_NS", "HOLD_FAILING_ENDPOINTS",
            "UNCONSTRAINED_INPUTS", "UNCONSTRAINED_OUTPUTS",
        ) if key in metrics),
        *comparisons,
        f"EXTERNAL_IO_DELAYS={external_io_status}",
    ]
    result_path.write_text("\n".join(result) + "\n", encoding="utf-8")

    print(f"SYNTHESIS_STATUS={synth_status}")
    print(f"SYNTH_CRITICAL_WARNINGS={critical_count}")
    print(f"SYNTH_ERRORS={error_count}")
    print(f"TIMING_STATUS={timing_status}")
    print(f"STATUS={acceptance_status}")
    return 0 if acceptance_status.startswith("PASS") else 1


if __name__ == "__main__":
    raise SystemExit(main())
