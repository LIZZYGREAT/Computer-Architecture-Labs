"""Build auditable Lab8/Lab9 CSVs and a summary chart from final run records."""

from __future__ import annotations

import csv
import hashlib
from pathlib import Path
import re
import xml.etree.ElementTree as ET

import matplotlib.pyplot as plt
import numpy as np


REPORT_ROOT = Path(__file__).resolve().parents[1]
LAB_ROOT = Path(__file__).resolve().parents[3]
RESULTS = LAB_ROOT / "results"
DATA = REPORT_ROOT / "data"
WAVEFORMS = REPORT_ROOT / "figures" / "waveforms" / "final"

COURSE_RUNS = [
    ("lab3", "lab3-20261109T164953Z", "results/lab3_lab4"),
    ("lab4", "lab4-20261109T165423Z", "results/lab3_lab4"),
    ("lab6", "lab6-20261109T165828Z", "results/lab6_lab7"),
    ("lab7", "lab7-20261109T170251Z", "results/lab6_lab7"),
    ("lab8", "lab8-20261109T163413Z", "results/lab8_lab9"),
    ("lab9", "lab9-20261109T163846Z", "results/lab8_lab9"),
]

IRQ_RUNS = {
    2: "interrupt-ip2-20261110T",
    3: "interrupt-ip3-20261110T",
    4: "interrupt-ip4-20261110T",
    5: "interrupt-ip5-20261110T",
    6: "interrupt-ip6-20261110T",
    7: "interrupt-ip7-20261110T-retry",
}


def parse_key_values(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8-sig", errors="replace").splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()
    return values


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def rel(path: Path | None) -> str:
    return path.resolve().relative_to(LAB_ROOT.resolve()).as_posix() if path else ""


def require_file(path: Path, description: str) -> None:
    if not path.is_file() or path.stat().st_size == 0:
        raise FileNotFoundError(f"{description} is missing or empty: {path}")


def write_csv(path: Path, rows: list[dict[str, object]], fields: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8-sig") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, extrasaction="raise")
        writer.writeheader()
        writer.writerows(rows)


def load_course_runs() -> tuple[list[dict[str, object]], dict[str, dict[str, str]]]:
    evidence: list[dict[str, object]] = []
    parsed: dict[str, dict[str, str]] = {}
    for case, run_id, root_name in COURSE_RUNS:
        run_dir = LAB_ROOT / root_name / run_id
        result_path = run_dir / "result.txt"
        require_file(result_path, f"{case} result.txt")
        result = parse_key_values(result_path)
        if result.get("STATUS") != "PASS":
            raise RuntimeError(f"{run_id} is not PASS: {result.get('STATUS')}")
        if result.get("FUNCTIONAL_POINT_PASSES") != result.get("EXPECTED_FUNCTIONAL_POINTS"):
            raise RuntimeError(f"{run_id} did not reach its expected functional points")
        if result.get("TRACE_OPENED") != "True" or result.get("SIM_IMAGE_MATCHES_SOURCE") != "True":
            raise RuntimeError(f"{run_id} lacks matching image/trace evidence")

        trace_path = Path(result["TRACE_FILE"])
        mif_path = Path(result["INST_MIF"])
        require_file(trace_path, f"{case} reference trace")
        require_file(mif_path, f"{case} instruction MIF")
        trace_hash = sha256(trace_path)
        mif_hash = sha256(mif_path)
        if trace_hash != result.get("TRACE_SHA256", "").upper():
            raise RuntimeError(f"{run_id} trace SHA-256 does not match result.txt")
        if mif_hash != result.get("INST_MIF_SHA256", "").upper():
            raise RuntimeError(f"{run_id} MIF SHA-256 does not match result.txt")

        waveform_captured = result.get("WAVEFORM_CAPTURED") == "True"
        wdb_path: Path | None = None
        wdb_hash = ""
        if waveform_captured:
            wdb_path = Path(result["WAVEFORM_FILE"])
            require_file(wdb_path, f"{case} WDB")
            wdb_hash = sha256(wdb_path)
            if wdb_hash != result.get("WAVEFORM_SHA256", "").upper():
                raise RuntimeError(f"{run_id} WDB SHA-256 does not match result.txt")
            stage_log = run_dir / "xsim-simulate-stage.log"
            require_file(stage_log, f"{case} XSim stage log")
            stage_text = stage_log.read_text(encoding="utf-8-sig", errors="replace")
            if "No matching HDL object or HDL scope found" in stage_text:
                raise RuntimeError(f"{run_id} WDB capture scope is invalid")

        row = {
            "run_id": run_id,
            "case": case,
            "status": result["STATUS"],
            "pipeline_mode": result.get("PIPELINE_MODE", "forwarding"),
            "expected_points": result.get("EXPECTED_FUNCTIONAL_POINTS", ""),
            "passed_points": result.get("FUNCTIONAL_POINT_PASSES", ""),
            "pipeline_cycles": result.get("PIPELINE_CYCLES", ""),
            "stall_cycles": result.get("PIPELINE_STALL_CYCLES", ""),
            "trace_matched": "True",
            "inst_mif_path": rel(mif_path),
            "inst_mif_sha256": mif_hash,
            "reference_trace_path": rel(trace_path),
            "reference_trace_sha256": trace_hash,
            "waveform_captured": str(waveform_captured),
            "wdb_path": rel(wdb_path) if wdb_path else "",
            "wdb_sha256": wdb_hash,
            "result_path": rel(result_path),
            "assertions_pass": "",
            "notes": "Full reference GPR trace match; result.txt is the run record.",
        }
        evidence.append(row)
        parsed[case] = result
    return evidence, parsed


def load_directed_runs() -> list[dict[str, object]]:
    evidence: list[dict[str, object]] = []
    unit_runs = [
        ("cp0_reg_unit", "cp0-unit-20261109T141303Z", "CASE_NAME=cp0_reg_unit", 62, 2),
        ("hilo_cancel_unit", "hilo-cancel-20261109T150200Z", "HILO_UNIT_TB_PASS", "", ""),
    ]
    for case, run_id, pass_marker, assertions, traps in unit_runs:
        run_dir = RESULTS / "lab8_lab9" / run_id
        log_path = run_dir / "vivado.log"
        require_file(log_path, f"{case} log")
        text = log_path.read_text(encoding="utf-8-sig", errors="replace")
        if pass_marker not in text:
            raise RuntimeError(f"{case} PASS marker is missing")
        runtime_text = "\n".join(line for line in text.splitlines()
                                 if not line.lstrip().startswith("#"))
        if "Fatal:" in runtime_text or "_TB_FAIL" in runtime_text:
            raise RuntimeError(f"{case} log contains a fatal/failure marker")
        if case == "cp0_reg_unit" and "STATUS=PASS" not in text:
            raise RuntimeError("CP0 unit test lacks STATUS=PASS")
        evidence.append({
            "run_id": run_id,
            "case": case,
            "status": "PASS",
            "pipeline_mode": "module-level",
            "expected_points": "",
            "passed_points": "",
            "pipeline_cycles": "",
            "stall_cycles": "",
            "trace_matched": "",
            "inst_mif_path": "",
            "inst_mif_sha256": "",
            "reference_trace_path": "",
            "reference_trace_sha256": "",
            "waveform_captured": "False",
            "wdb_path": "",
            "wdb_sha256": "",
            "result_path": rel(log_path),
            "assertions_pass": assertions,
            "notes": f"TRAPS_OBSERVED={traps}" if traps != "" else "In-flight divide cancel; prior HI/LO preserved.",
        })

    for ip_bit, run_id in IRQ_RUNS.items():
        run_dir = RESULTS / "lab8_lab9" / run_id
        # Keep the canonical test record beside the exported WDB so the
        # generated project/build tree can be removed without losing evidence.
        log_path = run_dir / "simulate.log"
        wdb_path = run_dir / f"interrupt-ip{ip_bit}.wdb"
        require_file(log_path, f"IP{ip_bit} XSim log")
        require_file(wdb_path, f"IP{ip_bit} WDB")
        text = log_path.read_text(encoding="utf-8-sig", errors="replace")
        expected = {
            f"CASE_NAME=external_irq_ip{ip_bit}",
            "ASSERTIONS_PASS=10",
            "TRAPS_OBSERVED=1",
            "STATUS=PASS",
        }
        if not expected.issubset(set(text.splitlines())) or "INTERRUPT_TB_FAIL" in text or "Fatal:" in text:
            raise RuntimeError(f"IP{ip_bit} CPU-level test did not produce a clean PASS")
        evidence.append({
            "run_id": run_id,
            "case": f"external_irq_ip{ip_bit}",
            "status": "PASS",
            "pipeline_mode": "CPU-level directed test",
            "expected_points": "",
            "passed_points": "",
            "pipeline_cycles": "",
            "stall_cycles": "",
            "trace_matched": "not applicable (embedded directed ROM)",
            "inst_mif_path": "",
            "inst_mif_sha256": "",
            "reference_trace_path": "",
            "reference_trace_sha256": "",
            "waveform_captured": "True",
            "wdb_path": rel(wdb_path),
            "wdb_sha256": sha256(wdb_path),
            "result_path": rel(log_path),
            "assertions_pass": 10,
            "notes": "Masked, enabled, vector, request clear, ERET resume; resumed store once.",
        })
    return evidence


def verify_wave_config(wcfg: Path, wdb: Path) -> int:
    require_file(wcfg, "WCFG")
    require_file(wdb, "WDB")
    tree = ET.parse(wcfg)
    refs = [Path(ref.attrib["path"]).resolve() for ref in tree.findall(".//db_ref")]
    if wdb.resolve() not in refs:
        raise RuntimeError(f"{wcfg} does not reference {wdb}")
    size = tree.find(".//WVObjectSize")
    if size is None or "size" not in size.attrib:
        raise RuntimeError(f"{wcfg} has no WVObjectSize declaration")
    return int(size.attrib["size"])


def make_wave_rows(parsed: dict[str, dict[str, str]]) -> list[dict[str, object]]:
    lab8 = parsed["lab8"]
    lab9 = parsed["lab9"]
    lab8_wdb = Path(lab8["WAVEFORM_FILE"])
    lab9_wdb = Path(lab9["WAVEFORM_FILE"])
    lab8_mif = Path(lab8["INST_MIF"])
    lab9_mif = Path(lab9["INST_MIF"])
    lab8_trace = Path(lab8["TRACE_FILE"])
    lab9_trace = Path(lab9["TRACE_FILE"])
    irq_wdb = RESULTS / "lab8_lab9" / IRQ_RUNS[2] / "interrupt-ip2.wdb"

    specs = [
        {
            "image_name": "01_syscall.png", "run_id": lab8["RUN_ID"], "wdb": lab8_wdb,
            "wcfg": "01_syscall.wcfg", "mif": lab8_mif, "trace": lab8_trace,
            "instruction": "n69 first syscall", "pc": "0xBFC1DDFC", "signal": "ds_pc[31:0]",
            "context": "First syscall PC from the Lab8 ELF; the same run must show ExcCode 8 and the trap/ERET sequence.",
            "code": "8", "epc": "0xBFC1DDFC", "bd": "0", "badvaddr": "",
            "cause_ip": "", "side_effects": "No GPR write for syscall; handler returns through EPC.",
            "assertion": "Lab8 PASS 69/69; full reference trace match.",
        },
        {
            "image_name": "02_break.png", "run_id": lab9["RUN_ID"], "wdb": lab9_wdb,
            "wcfg": "02_break.wcfg", "mif": lab9_mif, "trace": lab9_trace,
            "instruction": "n70 break", "pc": "0xBFC864EC", "signal": "es_pc[31:0]",
            "context": "First break instruction in the final Lab9 image.", "code": "9", "epc": "0xBFC864EC",
            "bd": "0", "badvaddr": "", "cause_ip": "", "side_effects": "Break must not write a GPR.",
            "assertion": "Lab9 PASS 94/94; full reference trace match.",
        },
        {
            "image_name": "03_overflow.png", "run_id": lab9["RUN_ID"], "wdb": lab9_wdb,
            "wcfg": "03_overflow.wcfg", "mif": lab9_mif, "trace": lab9_trace,
            "instruction": "n71 signed add overflow", "pc": "0xBFC3BA4C", "signal": "es_pc[31:0]",
            "context": "First signed ADD overflow site in n71; compare ALU inputs/result and trap code.",
            "code": "12", "epc": "0xBFC3BA4C", "bd": "0", "badvaddr": "", "cause_ip": "",
            "side_effects": "Overflowing ADD must suppress its destination-register write.",
            "assertion": "Lab9 PASS 94/94; full reference trace match.",
        },
        {
            "image_name": "04_load_adel.png", "run_id": lab9["RUN_ID"], "wdb": lab9_wdb,
            "wcfg": "04_load_adel.wcfg", "mif": lab9_mif, "trace": lab9_trace,
            "instruction": "n74 misaligned LW", "pc": "0xBFC68E4C", "signal": "es_pc[31:0]",
            "context": "First misaligned LW in n74; BadVAddr is the original byte address.",
            "code": "4", "epc": "0xBFC68E4C", "bd": "0", "badvaddr": "0x800CFDE1",
            "cause_ip": "", "side_effects": "Misaligned load must not issue a RAM request or write its GPR.",
            "assertion": "Lab9 PASS 94/94; full reference trace match.",
        },
        {
            "image_name": "05_store_ades.png", "run_id": lab9["RUN_ID"], "wdb": lab9_wdb,
            "wcfg": "05_store_ades.wcfg", "mif": lab9_mif, "trace": lab9_trace,
            "instruction": "n77 misaligned SW", "pc": "0xBFC7E348", "signal": "es_pc[31:0]",
            "context": "First misaligned SW in n77; inspect original byte address and RAM write mask.",
            "code": "5", "epc": "0xBFC7E348", "bd": "0", "badvaddr": "0x800DF545",
            "cause_ip": "", "side_effects": "Faulting SW must have no data SRAM write enable.",
            "assertion": "Lab9 PASS 94/94; full reference trace match.",
        },
        {
            "image_name": "06_fetch_adel.png", "run_id": lab9["RUN_ID"], "wdb": lab9_wdb,
            "wcfg": "06_fetch_adel.wcfg", "mif": lab9_mif, "trace": lab9_trace,
            "instruction": "n79 unaligned instruction fetch", "pc": "", "signal": "bad_vaddr[31:0]",
            "context": "Search the exact BadVAddr written for TEST_FT_ADEL; correlate with fs_pc and AdEL code.",
            "code": "4", "epc": "", "bd": "0", "badvaddr": "0xB27F9789", "cause_ip": "",
            "side_effects": "Misaligned fetch must not turn the stale RAM response into a legal instruction.",
            "assertion": "Lab9 PASS 94/94; full reference trace match.",
        },
        {
            "image_name": "07_delay_slot.png", "run_id": lab9["RUN_ID"], "wdb": lab9_wdb,
            "wcfg": "07_delay_slot.wcfg", "mif": lab9_mif, "trace": lab9_trace,
            "instruction": "n83 syscall in branch delay slot", "pc": "0xBFC97F40", "signal": "epc[31:0]",
            "context": "Search the branch PC saved in EPC; the faulting syscall is its delay-slot instruction.",
            "code": "8", "epc": "0xBFC97F3C", "bd": "1", "badvaddr": "", "cause_ip": "",
            "side_effects": "Cause.BD must be set and EPC must name the branch, not the delay-slot PC.",
            "assertion": "Lab9 PASS 94/94; full reference trace match.",
        },
        {
            "image_name": "08_timer_irq.png", "run_id": lab9["RUN_ID"], "wdb": lab9_wdb,
            "wcfg": "08_timer_irq.wcfg", "mif": lab9_mif, "trace": lab9_trace,
            "instruction": "n81 timer interrupt loop", "pc": "0xBFC5FA8C", "signal": "epc[31:0]",
            "context": "Search the n81 polling-loop branch PC in EPC; inspect Count, Compare, TI/IP7, IM7 and ERET.",
            "code": "0", "epc": "0xBFC5FA8C", "bd": "0", "badvaddr": "", "cause_ip": "IP7",
            "side_effects": "Compare write clears TI; the handler returns without repeated entry.",
            "assertion": "Lab9 PASS 94/94; CP0 unit confirms TI and Compare-clear semantics.",
        },
        {
            "image_name": "09_software_irq.png", "run_id": lab9["RUN_ID"], "wdb": lab9_wdb,
            "wcfg": "09_software_irq.wcfg", "mif": lab9_mif, "trace": lab9_trace,
            "instruction": "n82 software interrupt loop", "pc": "0xBFC16C54", "signal": "epc[31:0]",
            "context": "Search the n82 polling-loop branch PC in EPC; inspect Cause software IP and Status mask.",
            "code": "0", "epc": "0xBFC16C54", "bd": "0", "badvaddr": "", "cause_ip": "IP0/IP1",
            "side_effects": "MTC0 Cause clears the software request; handler returns without repeated entry.",
            "assertion": "Lab9 PASS 94/94; CP0 unit confirms IP0/IP1 mask and clear behavior.",
        },
        {
            "image_name": "10_external_interrupt_ip2.png", "run_id": IRQ_RUNS[2], "wdb": irq_wdb,
            "wcfg": "10_external_interrupt_ip2.wcfg", "mif": None, "trace": None,
            "instruction": "CPU directed interrupted ADDIU", "pc": "0xBFC0001C", "signal": "trap_pc[31:0]",
            "context": "Standalone interrupt_tb ROM; IP2 is asserted at reset, remains masked, then is enabled and taken once.",
            "code": "0", "epc": "0xBFC0001C", "bd": "0", "badvaddr": "", "cause_ip": "IP2",
            "side_effects": "Interrupted ADDIU and trap-cycle younger store are suppressed; resumed store commits once after ERET.",
            "assertion": "CPU directed IP2 PASS; 10 assertions, 1 trap, 1 ERET, 1 store.",
        },
    ]

    rows: list[dict[str, object]] = []
    for spec in specs:
        wcfg = WAVEFORMS / str(spec["wcfg"])
        wdb = spec["wdb"]
        count = verify_wave_config(wcfg, wdb)
        expected_count = {
            "01_syscall.wcfg": 21, "02_break.wcfg": 21, "03_overflow.wcfg": 30,
            "04_load_adel.wcfg": 27, "05_store_ades.wcfg": 30, "06_fetch_adel.wcfg": 26,
            "07_delay_slot.wcfg": 25, "08_timer_irq.wcfg": 20, "09_software_irq.wcfg": 16,
            "10_external_interrupt_ip2.wcfg": 22,
        }[str(spec["wcfg"])]
        if count != expected_count:
            raise RuntimeError(f"Unexpected WCFG signal count for {wcfg}: {count} != {expected_count}")
        mif = spec["mif"]
        trace = spec["trace"]
        rows.append({
            "image_name": spec["image_name"],
            "run_id": spec["run_id"],
            "wdb_path": rel(wdb),
            "wdb_sha256": sha256(wdb),
            "wcfg_path": rel(wcfg),
            "wcfg_signal_count": count,
            "instruction_mif_path": rel(mif) if mif else "",
            "instruction_mif_sha256": sha256(mif) if mif else "",
            "reference_trace_path": rel(trace) if trace else "",
            "reference_trace_sha256": sha256(trace) if trace else "",
            "target_instruction": spec["instruction"],
            "target_pc": spec["pc"],
            "search_signal": spec["signal"],
            "search_value": spec["pc"] if spec["image_name"] != "06_fetch_adel.png" else spec["badvaddr"],
            "search_context": spec["context"],
            "expected_exc_code": spec["code"],
            "expected_epc": spec["epc"],
            "expected_bd": spec["bd"],
            "expected_badvaddr": spec["badvaddr"],
            "expected_cause_ip": spec["cause_ip"],
            "expected_side_effects": spec["side_effects"],
            "observed_time_window": "",
            "observed_values": "",
            "assertion_status": spec["assertion"],
            "capture_status": "WDB/WCFG pair opened in Vivado; PNG pending user capture.",
        })
    return rows


def draw_summary(rows: list[dict[str, object]]) -> None:
    labs = [str(row["case"]).upper() for row in rows]
    points = [100 * int(row["passed_points"]) / int(row["expected_points"]) for row in rows]
    point_labels = [f"{row['passed_points']}/{row['expected_points']}" for row in rows]
    cycles = [int(row["pipeline_cycles"]) for row in rows]
    stalls = [int(row["stall_cycles"]) for row in rows]
    colors = ["#3B78A5", "#42A596", "#4B93A8", "#60AFA0", "#D79C43", "#C56D5F"]
    y = np.arange(len(rows))

    plt.rcParams.update({
        "font.family": "DejaVu Sans",
        "font.size": 8,
        "axes.edgecolor": "#AAB8C2",
        "figure.facecolor": "white",
        "savefig.facecolor": "white",
    })
    fig, axes = plt.subplots(1, 3, figsize=(13.8, 4.7), sharey=True,
                             gridspec_kw={"width_ratios": [1.0, 1.4, 1.1]})

    panels = [
        (axes[0], points, "Functional points", "Pass rate (%)", 110),
        (axes[1], cycles, "Pipeline cycles", "Cycles", max(cycles) * 1.22),
        (axes[2], stalls, "Stall cycles", "Cycles", max(stalls) * 1.5 + 1),
    ]
    for panel_index, (ax, values, title, xlabel, xmax) in enumerate(panels):
        bars = ax.barh(y, values, color=colors, height=0.62)
        ax.set_title(title, color="#17324D", fontsize=10, fontweight="bold", pad=11)
        ax.set_xlabel(xlabel, color="#617486", labelpad=7)
        ax.set_xlim(0, xmax)
        ax.grid(axis="x", color="#E2E8EC", linewidth=0.8)
        ax.set_axisbelow(True)
        ax.spines[["top", "right", "left"]].set_visible(False)
        ax.spines["bottom"].set_color("#AAB8C2")
        ax.tick_params(axis="x", colors="#617486", labelsize=7, length=0)
        ax.tick_params(axis="y", length=0, labelsize=8, labelcolor="#203040")
        if panel_index == 0:
            ax.set_yticks(y, labs)
            ax.invert_yaxis()
        else:
            ax.set_yticks(y, [])
        for index, (bar, value) in enumerate(zip(bars, values)):
            label = point_labels[index] if panel_index == 0 else f"{int(value):,}"
            ax.text(bar.get_width() + xmax * 0.025, bar.get_y() + bar.get_height() / 2,
                    label, va="center", ha="left", color="#203040", fontsize=7.2)

    fig.suptitle("Final forwarding-mode course regressions", color="#17324D",
                 fontsize=13, fontweight="bold", y=0.98)
    fig.text(0.5, 0.015,
             "Source: final result.txt files and matching MIF/reference traces. Program lengths differ; cycle counts are not a speed comparison.",
             ha="center", va="bottom", color="#617486", fontsize=7.5)
    fig.tight_layout(rect=(0, 0.055, 1, 0.93), w_pad=1.4)
    output = REPORT_ROOT / "figures" / "regression_metrics.png"
    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=220, bbox_inches="tight")
    plt.close(fig)


def main() -> None:
    course_evidence, parsed = load_course_runs()
    directed_evidence = load_directed_runs()
    evidence_rows = course_evidence + directed_evidence
    evidence_fields = [
        "run_id", "case", "status", "pipeline_mode", "expected_points", "passed_points",
        "pipeline_cycles", "stall_cycles", "trace_matched", "inst_mif_path", "inst_mif_sha256",
        "reference_trace_path", "reference_trace_sha256", "waveform_captured", "wdb_path",
        "wdb_sha256", "result_path", "assertions_pass", "notes",
    ]
    write_csv(DATA / "evidence_index.csv", evidence_rows, evidence_fields)

    regression_rows = [
        {
            "run_id": row["run_id"], "case": row["case"], "expected_points": row["expected_points"],
            "passed_points": row["passed_points"], "pipeline_cycles": row["pipeline_cycles"],
            "stall_cycles": row["stall_cycles"], "trace_matched": row["trace_matched"],
            "inst_mif_sha256": row["inst_mif_sha256"],
            "reference_trace_sha256": row["reference_trace_sha256"],
            "result_path": row["result_path"],
        }
        for row in course_evidence
    ]
    write_csv(DATA / "regression-summary.csv", regression_rows, list(regression_rows[0].keys()))

    wave_rows = make_wave_rows(parsed)
    wave_fields = list(wave_rows[0].keys())
    write_csv(DATA / "wave-capture-log.csv", wave_rows, wave_fields)
    draw_summary(course_evidence)

    print(f"COURSE_RUNS_VALIDATED={len(course_evidence)}")
    print(f"DIRECTED_RUNS_VALIDATED={len(directed_evidence)}")
    print(f"WAVE_CAPTURE_ROWS={len(wave_rows)}")
    for path in (DATA / "evidence_index.csv", DATA / "regression-summary.csv",
                 DATA / "wave-capture-log.csv", REPORT_ROOT / "figures" / "regression_metrics.png"):
        print(f"OUTPUT={path}")


if __name__ == "__main__":
    main()
