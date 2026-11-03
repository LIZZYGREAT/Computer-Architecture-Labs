"""Build report figures from the committed Lab6/Lab7 verification summaries."""

from __future__ import annotations

import csv
import hashlib
from pathlib import Path
import re

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.colors import ListedColormap
from matplotlib.patches import Patch
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch
from matplotlib.path import Path as MplPath


REPORT_ROOT = Path(__file__).resolve().parents[1]
LAB_ROOT = REPORT_ROOT.parents[1]
FIGURES = REPORT_ROOT / "figures"
DATA = REPORT_ROOT / "data"
RESULTS = LAB_ROOT / "results" / "lab6_lab7"
LEGACY_RESULTS = LAB_ROOT / "results" / "lab3_lab4"

NAVY = "#17324D"
BLUE = "#3B78A5"
TEAL = "#42A596"
GOLD = "#E6A64C"
RED = "#C65353"
PALE = "#F2F6F8"
INK = "#203040"
MUTED = "#617486"

LAB6_RESULT = LAB_ROOT / "results" / "wave_recapture" / "lab6-20261102T054949Z" / "result.txt"
LAB7_RESULT = LAB_ROOT / "results" / "wave_recapture" / "lab7-20261102T055526Z" / "result.txt"
ALU_DIRECTED_RESULT = LEGACY_RESULTS / "lab3-20261028T132600Z" / "result.txt"
DIV_DIRECTED_RESULT = LAB_ROOT / "results" / "wave_recapture" / "lab6-20261102T060138Z" / "result.txt"
EXTENDED_DIRECTED_RESULT = RESULTS / "lab7-20261026T170957Z" / "result.txt"
HILO_UNIT_RESULT = RESULTS / "hilo-unit-20261027T032000Z" / "result.txt"
ALU_IMAGE = RESULTS / "directed" / "alu" / "image" / "lab6_alu_directed_program.txt"
DIV_IMAGE = RESULTS / "directed" / "hilo-stall-branch" / "image" / "lab6_hilo_stall_branch_program.txt"
EXTENDED_IMAGE = RESULTS / "directed" / "extended-forwarding" / "image" / "lab7_extended_forwarding_program.txt"

TRACE_RE = re.compile(
    r"^\s*(\d+)\s+([0-9a-fA-F]{8})\s+([0-9a-fA-F]{2})\s+([0-9a-fA-F]{8})\s*$"
)


def parse_result(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            data[key.strip()] = value.strip()
    return data


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def parse_trace(path: Path) -> list[dict[str, int | str]]:
    records: list[dict[str, int | str]] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        match = TRACE_RE.match(line)
        if not match:
            raise ValueError(f"Unrecognized trace row {path}:{line_number}: {line!r}")
        sequence, pc, destination, value = match.groups()
        records.append({
            "trace_index": len(records) + 1,
            "reference_sequence": int(sequence),
            "pc": pc.upper(),
            "destination_register": int(destination, 16),
            "write_data": value.upper(),
        })
    return records


def verified_result(path: Path, expected_case: str | None = None) -> dict[str, str]:
    result = parse_result(path)
    for key in ("STATUS", "TRACE_OPENED", "TEST_END", "PASS_MARKER", "SIM_IMAGE_MATCHES_SOURCE"):
        if result.get(key) not in ("PASS", "True"):
            raise RuntimeError(f"{path} does not contain required PASS evidence: {key}={result.get(key)}")
    if expected_case and result.get("CASE") != expected_case:
        raise RuntimeError(f"Expected CASE={expected_case} in {path}, found {result.get('CASE')}")

    trace_path = Path(result["TRACE_FILE"])
    if not trace_path.is_file():
        raise FileNotFoundError(f"Trace referenced by {path} is missing: {trace_path}")
    trace_hash = sha256(trace_path)
    if trace_hash != result.get("TRACE_SHA256", "").upper():
        raise RuntimeError(f"Trace hash does not match result.txt: {trace_path}")

    result["_RESULT_PATH"] = str(path)
    result["_TRACE_PATH"] = str(trace_path)
    result["_TRACE_RECORDS"] = str(len(parse_trace(trace_path)))
    if result.get("WAVEFORM_CAPTURED") == "True":
        waveform_path = Path(result["WAVEFORM_FILE"])
        if not waveform_path.is_file():
            raise FileNotFoundError(f"WDB referenced by {path} is missing: {waveform_path}")
        waveform_hash = sha256(waveform_path)
        if waveform_hash != result.get("WAVEFORM_SHA256", "").upper():
            raise RuntimeError(f"WDB hash does not match result.txt: {waveform_path}")
        simulate_log = path.parent / "xsim-simulate-stage.log"
        if not simulate_log.is_file():
            raise FileNotFoundError(f"WDB capture log referenced by {path} is missing: {simulate_log}")
        simulate_text = simulate_log.read_text(encoding="utf-8-sig", errors="replace")
        if "No matching HDL object or HDL scope found" in simulate_text:
            raise RuntimeError(f"WDB capture did not match an HDL scope: {simulate_log}")
        result["_WDB_PATH"] = str(waveform_path)
    else:
        result["_WDB_PATH"] = ""
    return result


def write_csv(path: Path, rows: list[dict[str, object]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8-sig") as stream:
        writer = csv.DictWriter(stream, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def write_trace_csv(
    path: Path,
    records: list[dict[str, int | str]],
    run_id: str,
    evidence_note: str,
    program: dict[str, dict[str, str]] | None = None,
) -> None:
    program = program or {}
    rows = [
        {
            "run_id": run_id,
            "trace_index": row["trace_index"],
            "reference_sequence": row["reference_sequence"],
            "pc": row["pc"],
            "instruction": program.get(str(row["pc"]), {}).get("instruction", ""),
            "destination_register": row["destination_register"],
            "write_data": row["write_data"],
            "evidence_note": evidence_note,
        }
        for row in records
    ]
    write_csv(
        path,
        rows,
        ["run_id", "trace_index", "reference_sequence", "pc", "instruction", "destination_register", "write_data", "evidence_note"],
    )


def row_at_pc(records: list[dict[str, int | str]], pc: str) -> dict[str, int | str]:
    matches = [row for row in records if row["pc"] == pc.upper()]
    if len(matches) != 1:
        raise RuntimeError(f"Expected one retirement record for PC {pc}, found {len(matches)}")
    return matches[0]


def parse_program_image(path: Path) -> dict[str, dict[str, str]]:
    image_row = re.compile(r"^\s*\d+\s+0x([0-9a-fA-F]{8})\s+[0-9a-fA-F]{8}\s+(.+?)\s*$")
    program: dict[str, dict[str, str]] = {}
    for line_number, line in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
        match = image_row.match(line)
        if not match:
            continue
        pc, text = match.groups()
        instruction, separator, note = text.partition(";")
        program[pc.upper()] = {
            "instruction": instruction.strip(),
            "source_note": note.strip() if separator else "",
        }
    if not program:
        raise RuntimeError(f"No instruction rows found in directed image: {path}")
    return program


def trace_record_or_none(records: list[dict[str, int | str]], pc: str) -> dict[str, int | str] | None:
    matches = [row for row in records if row["pc"] == pc.upper()]
    if len(matches) > 1:
        raise RuntimeError(f"Expected at most one retirement record for PC {pc}, found {len(matches)}")
    return matches[0] if matches else None


def make_event_rows(
    run_id: str,
    records: list[dict[str, int | str]],
    program: dict[str, dict[str, str]],
    specs: list[tuple[str, str]],
) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for pc, event in specs:
        record = trace_record_or_none(records, pc)
        instruction = program.get(pc.upper(), {}).get("instruction", "")
        rows.append({
            "run_id": run_id,
            "pc": pc.upper(),
            "instruction": instruction,
            "event": event,
            "trace_index": record["trace_index"] if record else "",
            "destination_register": record["destination_register"] if record else "",
            "reference_write_data": record["write_data"] if record else "",
            "gpr_write_in_trace": bool(record),
            "evidence_note": "CPU132 reference trace; DUT run reports full trace match",
        })
    return rows


def collect_report_data() -> dict[str, object]:
    lab6 = verified_result(LAB6_RESULT, "lab6")
    lab7 = verified_result(LAB7_RESULT, "lab7")
    alu = verified_result(ALU_DIRECTED_RESULT, "lab3")
    div = verified_result(DIV_DIRECTED_RESULT, "lab6")
    extended = verified_result(EXTENDED_DIRECTED_RESULT, "lab7")
    hilo_unit = parse_result(HILO_UNIT_RESULT)

    for result, label in ((lab6, "Lab6"), (lab7, "Lab7")):
        if result["FUNCTIONAL_POINT_PASSES"] != result["EXPECTED_FUNCTIONAL_POINTS"]:
            raise RuntimeError(f"{label} cumulative verification is not complete")
    if any(hilo_unit.get(key) != "HILO_UNIT_TB_PASS" for key in ("PASS_MARKER",)):
        raise RuntimeError("HI/LO unit result is missing its PASS marker")

    results = {"lab6": lab6, "lab7": lab7, "alu": alu, "div": div, "extended": extended}
    traces: dict[str, list[dict[str, int | str]]] = {}
    programs = {
        "alu": parse_program_image(ALU_IMAGE),
        "div": parse_program_image(DIV_IMAGE),
        "extended": parse_program_image(EXTENDED_IMAGE),
    }
    summary_rows: list[dict[str, object]] = []
    for label, result in results.items():
        trace_path = Path(result["_TRACE_PATH"])
        records = parse_trace(trace_path)
        traces[label] = records
        write_trace_csv(
            DATA / f"{label}_reference_trace.csv",
            records,
            result["RUN_ID"],
            "CPU132 reference retirement trace; DUT result reports full trace match",
            programs.get(label),
        )
        cycles = int(result.get("PIPELINE_CYCLES", "0"))
        stalls = int(result.get("PIPELINE_STALL_CYCLES", "0"))
        summary_rows.append({
            "run_id": result["RUN_ID"],
            "case": result["CASE"],
            "status": result["STATUS"],
            "functional_points_passed": result.get("FUNCTIONAL_POINT_PASSES", "0"),
            "functional_points_expected": result.get("EXPECTED_FUNCTIONAL_POINTS", "0"),
            "pipeline_cycles": cycles,
            "stall_cycles": stalls,
            "stall_percent_of_cycles": f"{(100 * stalls / cycles) if cycles else 0:.4f}",
            "forward_ex_uses": result.get("FORWARD_EX_USES", "0"),
            "forward_mem_uses": result.get("FORWARD_MEM_USES", "0"),
            "forward_wb_uses": result.get("FORWARD_WB_USES", "0"),
            "new_store_base_forwards": result.get("HAZARD_NEW_STORE_BASE_FORWARDS", "0"),
            "new_store_data_forwards": result.get("HAZARD_NEW_STORE_DATA_FORWARDS", "0"),
            "new_branch_forwards": result.get("HAZARD_NEW_BRANCH_FORWARDS", "0"),
            "jalr_forwards": result.get("HAZARD_JALR_FORWARDS", "0"),
            "trace_records": len(records),
            "trace_sha256": result["TRACE_SHA256"],
            "trace_file": str(Path(result["_TRACE_PATH"]).relative_to(LAB_ROOT)),
            "waveform_captured": result["WAVEFORM_CAPTURED"],
            "waveform_sha256": result.get("WAVEFORM_SHA256", ""),
            "waveform_file": str(Path(result["_WDB_PATH"]).relative_to(LAB_ROOT)) if result["_WDB_PATH"] else "",
        })

    write_csv(
        DATA / "verification_summary.csv",
        summary_rows,
        list(summary_rows[0].keys()),
    )
    hilo_row = {
        "run_id": "hilo-unit-20261027T032000Z",
        "mult_accepts": hilo_unit["MULT_ACCEPTS"],
        "div_accepts": hilo_unit["DIV_ACCEPTS"],
        "total_accepts": int(hilo_unit["MULT_ACCEPTS"]) + int(hilo_unit["DIV_ACCEPTS"]),
        "completion_commits": hilo_unit["COMPLETION_COMMITS"],
        "reset_cancelled_inflight": int(hilo_unit["MULT_ACCEPTS"]) + int(hilo_unit["DIV_ACCEPTS"]) - int(hilo_unit["COMPLETION_COMMITS"]),
        "pass_marker": hilo_unit["PASS_MARKER"],
    }
    write_csv(DATA / "hilo_unit_summary.csv", [hilo_row], list(hilo_row.keys()))

    alu_events = make_event_rows(alu["RUN_ID"], traces["alu"], programs["alu"], [
        ("BFC0002C", "zero-extended immediate / ANDI"),
        ("BFC00030", "zero-extended immediate / ORI"),
        ("BFC00034", "zero-extended immediate / XORI"),
        ("BFC00044", "variable shift, amount low 5 bits = 5 / SLLV"),
        ("BFC00048", "variable shift, amount low 5 bits = 5 / SRLV"),
        ("BFC0004C", "variable shift, amount low 5 bits = 5 / SRAV"),
        ("BFC00054", "EX forwarding"),
        ("BFC00060", "MEM forwarding"),
        ("BFC00070", "WB forwarding"),
        ("BFC0008C", "load-use result after one stall"),
        ("BFC00094", "variable shift, amount low 5 bits = 31 / SLLV"),
        ("BFC00098", "variable shift, amount low 5 bits = 31 / SRLV"),
        ("BFC0009C", "variable shift, amount low 5 bits = 31 / SRAV"),
    ])
    write_csv(DATA / "alu_key_events.csv", alu_events, list(alu_events[0].keys()))

    div_events = make_event_rows(div["RUN_ID"], traces["div"], programs["div"], [
        ("BFC00000", "input dividend setup"),
        ("BFC00004", "input divisor setup"),
        ("BFC00008", "multi-cycle signed DIV; no GPR write"),
        ("BFC0000C", "taken BEQ waits in ID; no GPR write"),
        ("BFC00010", "branch delay slot retires"),
        ("BFC00014", "taken-branch fall-through must be skipped"),
        ("BFC00018", "MFLO quotient readback"),
        ("BFC0001C", "MFHI remainder readback"),
        ("BFC00020", "branch target marker"),
    ])
    write_csv(DATA / "div_branch_events.csv", div_events, list(div_events[0].keys()))

    extended_events = make_event_rows(extended["RUN_ID"], traces["extended"], programs["extended"], [
        ("BFC00068", "branch source setup"),
        ("BFC0006C", "taken conditional branch"),
        ("BFC00070", "conditional branch delay slot"),
        ("BFC00074", "conditional branch fall-through must be skipped"),
        ("BFC00078", "conditional branch target"),
        ("BFC000E0", "JALR target setup"),
        ("BFC000E4", "JALR link value PC+8"),
        ("BFC000E8", "JALR delay slot"),
        ("BFC000EC", "JALR fall-through must be skipped"),
        ("BFC000F0", "JALR target"),
    ])
    write_csv(DATA / "extended_control_events.csv", extended_events, list(extended_events[0].keys()))

    manifest = [
        {"artifact": "alu_key_values.png", "run_id": alu["RUN_ID"], "data_file": "data/alu_key_events.csv", "source": "reference retirement trace matched by DUT PASS result"},
        {"artifact": "div_branch_retirement.png", "run_id": div["RUN_ID"], "data_file": "data/div_branch_events.csv", "source": "reference trace matched by DUT PASS result; retirement order only; directed timing WDB available separately"},
        {"artifact": "extended_branch_retirement.png", "run_id": extended["RUN_ID"], "data_file": "data/extended_control_events.csv", "source": "reference trace matched by DUT PASS result; retirement order only; full Lab7 timing WDB available separately"},
        {"artifact": "jalr_retirement.png", "run_id": extended["RUN_ID"], "data_file": "data/extended_control_events.csv", "source": "reference trace matched by DUT PASS result; retirement order only; full Lab7 timing WDB available separately"},
        {"artifact": "cumulative_metrics.png", "run_id": f"{lab6['RUN_ID']} / {lab7['RUN_ID']}", "data_file": "data/verification_summary.csv", "source": "cumulative result.txt fields; Lab6 and Lab7 program lengths differ"},
        {"artifact": "hilo_unit_counts.png", "run_id": hilo_row["run_id"], "data_file": "data/hilo_unit_summary.csv", "source": "HI/LO unit test result.txt"},
    ]
    write_csv(DATA / "evidence_index.csv", manifest, list(manifest[0].keys()))
    return {"results": results, "traces": traces, "programs": programs, "summary_rows": summary_rows, "hilo_row": hilo_row}


def box(ax, xy, width, height, title, subtitle="", color=BLUE, fill=PALE,
        title_size=12, subtitle_size=9, lw=1.5):
    x, y = xy
    patch = FancyBboxPatch(
        (x, y), width, height,
        boxstyle="round,pad=0.04,rounding_size=0.08",
        linewidth=lw, edgecolor=color, facecolor=fill,
    )
    ax.add_patch(patch)
    ax.text(x + width / 2, y + height * 0.63, title,
            ha="center", va="center", color=INK,
            fontsize=title_size, fontweight="bold")
    if subtitle:
        ax.text(x + width / 2, y + height * 0.28, subtitle,
                ha="center", va="center", color=MUTED,
                fontsize=subtitle_size, linespacing=1.25)
    return patch


def arrow(ax, start, end, color=MUTED, lw=1.7, style="-|>",
          connection="arc3,rad=0", linestyle="solid", mutation=13):
    p = FancyArrowPatch(
        start, end, arrowstyle=style, mutation_scale=mutation,
        connectionstyle=connection, linewidth=lw, color=color,
        linestyle=linestyle, shrinkA=3, shrinkB=3,
    )
    ax.add_patch(p)
    return p


def save(fig, name: str) -> None:
    FIGURES.mkdir(parents=True, exist_ok=True)
    fig.savefig(FIGURES / name, dpi=220, bbox_inches="tight", facecolor="white")
    plt.close(fig)


def draw_pipeline() -> None:
    fig, ax = plt.subplots(figsize=(13.0, 5.4))
    ax.set_xlim(0, 13)
    ax.set_ylim(-0.1, 5.2)
    ax.axis("off")
    ax.text(6.5, 4.92, "Five-stage CPU and Lab6/Lab7 control points",
            ha="center", va="center", fontsize=16, color=NAVY, fontweight="bold")

    xs = [0.35, 2.85, 5.35, 7.85, 10.35]
    w, h, y = 2.0, 0.82, 3.15
    labels = [
        ("IF", "PC / instruction ROM", BLUE),
        ("ID", "decode / RAW / redirect", TEAL),
        ("EX", "ALU / mult / div", GOLD),
        ("MEM", "sync RAM / byte lanes", BLUE),
        ("WB", "GPR / HI-LO commit", TEAL),
    ]
    for i, (title, subtitle, color) in enumerate(labels):
        box(ax, (xs[i], y), w, h, title, subtitle, color=color,
            fill="#F4F8FA", title_size=14, subtitle_size=8.7)
        if i < len(xs) - 1:
            arrow(ax, (xs[i] + w + 0.08, y + h / 2),
                  (xs[i + 1] - 0.08, y + h / 2), color=NAVY, lw=1.8)

    # Keep the control-point notes directly beneath their owning stage. The
    # vertical links make the correspondence clear without crossing labels.
    notes = [
        ("IF control", "sync instruction\nROM", BLUE, "#F4F8FA"),
        ("Operand / branch", "RAW check\nEX > MEM > WB > RF", TEAL, "#E9F5F2"),
        ("EX control", "HI/LO busy/done\nbackpressure", GOLD, "#FFF5E6"),
        ("MEM control", "byte lanes / merge\nsign / zero extend", BLUE, "#F4F8FA"),
        ("WB control", "valid commit\nzero write checked", TEAL, "#E9F5F2"),
    ]
    for i, (title, subtitle, color, fill) in enumerate(notes):
        box(ax, (xs[i], 0.66), w, 1.28, title, subtitle,
            color=color, fill=fill, title_size=9.7, subtitle_size=7.6)
        arrow(ax, (xs[i] + w / 2, 1.96), (xs[i] + w / 2, y - 0.04),
              color=color, lw=1.25, mutation=10)
    save(fig, "cpu_pipeline.png")


def draw_hilo_fsm() -> None:
    fig, ax = plt.subplots(figsize=(10.6, 5.7))
    ax.set_xlim(0, 10.6)
    ax.set_ylim(0, 6.0)
    ax.axis("off")
    ax.text(5.3, 5.62, "HI/LO operation handshake", ha="center", va="center",
            fontsize=16, color=NAVY, fontweight="bold")

    states = {
        "idle": (0.65, 2.55, 2.0, 1.05, "IDLE", "accept one request", TEAL, "#E9F5F2"),
        "mult": (4.05, 4.0, 2.25, 1.05, "MULT_WAIT", "pipelined product", GOLD, "#FFF5E6"),
        "div": (4.05, 1.15, 2.25, 1.05, "DIV_WAIT", "divider valid", GOLD, "#FFF5E6"),
        "done": (7.75, 2.55, 2.1, 1.05, "DONE", "hold until consume", BLUE, "#EAF2F8"),
    }
    coords = {}
    for key, (x, y, w, h, title, subtitle, color, fill) in states.items():
        box(ax, (x, y), w, h, title, subtitle, color, fill,
            title_size=12, subtitle_size=8.2)
        coords[key] = (x, y, w, h)

    arrow(ax, (2.68, 3.42), (4.00, 4.30), TEAL, connection="arc3,rad=0.05")
    ax.text(3.22, 4.13, "start & MULT/MULTU", fontsize=8.3, color=INK,
            ha="center", va="center", rotation=25)
    arrow(ax, (2.68, 2.75), (4.00, 1.95), TEAL, connection="arc3,rad=-0.05")
    ax.text(3.24, 2.02, "start & DIV/DIVU", fontsize=8.3, color=INK,
            ha="center", va="center", rotation=-22)
    arrow(ax, (6.35, 4.42), (7.70, 3.34), GOLD, connection="arc3,rad=-0.05")
    ax.text(7.16, 4.03, "result captured", fontsize=8.3, color=INK,
            ha="center", va="center", rotation=-26)
    arrow(ax, (6.35, 1.72), (7.70, 2.80), GOLD, connection="arc3,rad=0.05")
    ax.text(7.10, 2.05, "valid result", fontsize=8.3, color=INK,
            ha="center", va="center", rotation=26)
    # Route DONE -> IDLE below the divider node so the return path does not
    # obscure the DIV_WAIT label.
    consume_path = MplPath(
        [(8.80, 2.52), (8.80, 0.72), (1.65, 0.72), (1.65, 2.52)],
        [MplPath.MOVETO, MplPath.LINETO, MplPath.LINETO, MplPath.LINETO],
    )
    ax.add_patch(FancyArrowPatch(
        path=consume_path, arrowstyle="-|>", mutation_scale=13,
        linewidth=1.7, color=BLUE,
    ))
    ax.text(5.25, 0.30, "consume_done returns to IDLE; reset clears state and cancels an in-flight divide",
            ha="center", va="center", fontsize=8.4, color=BLUE)
    ax.text(5.30, 3.04, "HI = high product / remainder\nLO = low product / quotient",
            ha="center", va="center", fontsize=8.5, color=NAVY,
            bbox=dict(boxstyle="round,pad=0.35", facecolor="white", edgecolor="#D5DEE5"))
    save(fig, "hilo_handshake.png")


def draw_branch_case() -> None:
    fig, ax = plt.subplots(figsize=(12.4, 5.0))
    ax.set_xlim(0, 12.4)
    ax.set_ylim(0, 5.3)
    ax.axis("off")
    ax.text(6.2, 4.95, "Directed case: branch immediately after a multi-cycle DIV",
            ha="center", va="center", fontsize=15, color=NAVY, fontweight="bold")

    items = [
        (0.35, "0x08", "DIV r1,r2", "-23 / 5", GOLD, "#FFF5E6"),
        (2.75, "0x0C", "BEQ r0,r0", "taken", TEAL, "#E9F5F2"),
        (5.15, "0x10", "delay slot", "r3 = 0x55", BLUE, "#EAF2F8"),
        (7.55, "0x14", "fall-through", "r4 = 0x1234", RED, "#FBECEC"),
        (9.95, "0x18", "target / MFLO", "r5 = -4", TEAL, "#E9F5F2"),
    ]
    nodes = []
    for x, pc, op, desc, color, fill in items:
        nodes.append(box(ax, (x, 2.45), 2.05, 1.14,
                         f"{pc}  {op}", desc, color, fill,
                         title_size=9.3, subtitle_size=8.5))
    for i in range(2):
        arrow(ax, (items[i][0] + 2.08, 3.02), (items[i + 1][0] - 0.06, 3.02), MUTED)
    # The taken branch keeps the delay slot and then bypasses fall-through.
    branch_path = MplPath(
        [(6.17, 2.42), (6.17, 1.72), (10.98, 1.72), (10.98, 2.42)],
        [MplPath.MOVETO, MplPath.LINETO, MplPath.LINETO, MplPath.LINETO],
    )
    ax.add_patch(FancyArrowPatch(
        path=branch_path, arrowstyle="-|>", mutation_scale=13,
        linewidth=2.0, color=TEAL,
    ))
    ax.text(8.55, 1.45, "taken branch redirects after the delay slot", fontsize=8.7,
            color=TEAL, ha="center")
    ax.text(8.58, 2.05, "must not retire", fontsize=8.2, color=RED, ha="center")

    box(ax, (1.05, 0.35), 2.55, 0.72, "HI / remainder", "r6 = -3", BLUE, "#EAF2F8", 9.5, 8)
    box(ax, (4.28, 0.35), 2.55, 0.72, "MFLO / quotient", "r5 = -4", BLUE, "#EAF2F8", 9.5, 8)
    box(ax, (7.52, 0.35), 3.2, 0.72, "branch target marker", "r7 = 0x66", TEAL, "#E9F5F2", 9.5, 8)
    ax.text(6.2, 0.05,
            "Observed trace: r3, r5, r6 and r7 are written; no r4 write appears.",
            ha="center", va="center", fontsize=8.8, color=INK)
    save(fig, "div_branch_delay_slot.png")


def draw_verification_summary() -> None:
    lab6 = parse_result(LAB6_RESULT)
    lab7 = parse_result(LAB7_RESULT)
    rows = [
        ("Lab6", int(lab6["FUNCTIONAL_POINT_PASSES"]),
         int(lab6["EXPECTED_FUNCTIONAL_POINTS"]), BLUE),
        ("Lab7", int(lab7["FUNCTIONAL_POINT_PASSES"]),
         int(lab7["EXPECTED_FUNCTIONAL_POINTS"]), TEAL),
    ]
    for name, passed, expected, _ in rows:
        if passed != expected:
            raise RuntimeError(f"{name} is not a full PASS: {passed}/{expected}")
    fig, ax = plt.subplots(figsize=(10.4, 3.4))
    ax.set_xlim(0, 106)
    ax.set_ylim(-0.8, 1.8)
    ax.set_yticks([1, 0], ["Lab6 cumulative suite", "Lab7 cumulative suite"])
    ax.set_xticks([0, 20, 40, 60, 80, 100], ["0", "20", "40", "60", "80", "100%"])
    ax.set_xlabel("Functional points passed")
    ax.grid(axis="x", color="#D9E1E7", linewidth=0.8)
    ax.set_axisbelow(True)
    for y, (name, passed, expected, color) in zip([1, 0], rows):
        ax.barh(y, 100, height=0.48, color="#E8EDF1", edgecolor="none")
        ax.barh(y, 100 * passed / expected, height=0.48,
                color=color, edgecolor="none")
        ax.text(50, y, f"{passed} / {expected}", color="white",
                ha="center", va="center", fontsize=12, fontweight="bold")
    ax.spines[["top", "right", "left"]].set_visible(False)
    ax.spines["bottom"].set_color("#AAB8C2")
    ax.tick_params(axis="y", length=0, labelcolor=INK, labelsize=10)
    ax.tick_params(axis="x", colors=MUTED, labelsize=8)
    ax.xaxis.label.set_color(MUTED)
    ax.xaxis.label.set_size(9)
    ax.set_title("Cumulative functional-point acceptance", color=NAVY,
                 fontsize=14, fontweight="bold", pad=14)
    fig.tight_layout()
    save(fig, "functional_coverage.png")


def draw_alu_key_values(data: dict[str, object]) -> None:
    records = data["traces"]["alu"]
    program = data["programs"]["alu"]
    selected = [
        ("BFC0002C", "zero-extended immediate / ANDI"),
        ("BFC00030", "zero-extended immediate / ORI"),
        ("BFC00034", "zero-extended immediate / XORI"),
        ("BFC00044", "variable shift amount 5 / SLLV"),
        ("BFC00048", "variable shift amount 5 / SRLV"),
        ("BFC0004C", "variable shift amount 5 / SRAV"),
        ("BFC00054", "EX forwarding"),
        ("BFC00060", "MEM forwarding"),
        ("BFC00070", "WB forwarding"),
        ("BFC0008C", "load-use result"),
        ("BFC00094", "variable shift amount 31 / SLLV"),
        ("BFC00098", "variable shift amount 31 / SRLV"),
        ("BFC0009C", "variable shift amount 31 / SRAV"),
    ]
    chosen = [(row_at_pc(records, pc), category) for pc, category in selected]
    bit_values = np.asarray([
        [(int(row["write_data"], 16) >> bit) & 1 for bit in range(31, -1, -1)]
        for row, _ in chosen
    ], dtype=np.uint8)
    labels = []
    for row, category in chosen:
        instruction = program.get(str(row["pc"]), {}).get("instruction", "")
        labels.append(
            f"{str(row['pc'])[-4:]}  {instruction}  [{category}]\n"
            f"r{row['destination_register']} = {row['write_data']}"
        )

    fig, ax = plt.subplots(figsize=(14.2, 7.4))
    ax.imshow(bit_values, cmap=ListedColormap(["#E7EEF2", TEAL]),
              interpolation="nearest", aspect="auto", vmin=0, vmax=1)
    ax.set_yticks(np.arange(len(labels)), labels)
    ax.set_xticks(np.arange(32), [str(bit) for bit in range(31, -1, -1)])
    ax.set_xlabel("32-bit reference write data (bit index)", color=MUTED, labelpad=8)
    ax.set_ylabel("Retirement PC, instruction and matched destination value", color=MUTED)
    ax.set_title("ALU directed case: reference writeback bit patterns",
                 color=NAVY, fontsize=14, fontweight="bold", pad=12)
    ax.set_xticks(np.arange(-0.5, 32, 1), minor=True)
    ax.set_yticks(np.arange(-0.5, len(labels), 1), minor=True)
    ax.grid(which="minor", color="white", linewidth=0.7)
    ax.tick_params(which="minor", bottom=False, left=False)
    ax.tick_params(axis="x", colors=MUTED, labelsize=7, length=0, pad=4)
    ax.tick_params(axis="y", colors=INK, labelsize=7.5, length=0, pad=6)
    ax.text(0.5, -0.13,
            "Data source: CPU132 reference retirement trace; this run reports a full DUT trace match. "
            "This figure summarizes values and does not encode cycle timing.",
            transform=ax.transAxes, ha="center", va="top", color=MUTED, fontsize=8)
    fig.tight_layout(rect=(0, 0.02, 1, 1))
    save(fig, "alu_key_values.png")


def draw_div_branch_retirement(data: dict[str, object]) -> None:
    records = data["traces"]["div"]
    run_id = data["results"]["div"]["RUN_ID"]
    selected_pcs = ["BFC00000", "BFC00004", "BFC00010", "BFC00018", "BFC0001C", "BFC00020"]
    selected = [row_at_pc(records, pc) for pc in selected_pcs]
    colors = [BLUE, BLUE, TEAL, GOLD, GOLD, TEAL]
    fig, ax = plt.subplots(figsize=(12.0, 3.7))
    x_values = np.arange(1, len(selected) + 1)
    ax.plot(x_values, np.full(len(x_values), 0.58), color="#B8C6CF", linewidth=1.6, zorder=1)
    for x, row, color in zip(x_values, selected, colors):
        ax.scatter([x], [0.58], s=95, color=color, edgecolor="white", linewidth=1.1, zorder=2)
        ax.annotate(
            f"{str(row['pc'])[-4:]}\nr{row['destination_register']} = {row['write_data']}",
            (x, 0.58), xytext=(0, 22), textcoords="offset points",
            ha="center", va="bottom", fontsize=8.5, color=INK,
        )
    ax.text(3.5, 0.12,
            "Fall-through PC BFC00014 (r4 = 00001234) is absent from the matched retirement trace.",
            ha="center", va="center", fontsize=9, color=RED,
            bbox=dict(boxstyle="round,pad=0.35", facecolor="#FBECEC", edgecolor="#E8B9B9"))
    ax.set_xlim(0.45, len(selected) + 0.55)
    ax.set_ylim(-0.12, 1.42)
    ax.set_xticks(x_values, [str(row["trace_index"]) for row in selected])
    ax.set_xlabel("Reference retirement record index", color=MUTED)
    ax.set_yticks([])
    ax.grid(axis="x", color="#E2E8EC", linewidth=0.8)
    ax.set_axisbelow(True)
    ax.spines[["top", "right", "left"]].set_visible(False)
    ax.spines["bottom"].set_color("#AAB8C2")
    ax.tick_params(axis="x", colors=MUTED, labelsize=8, length=0)
    ax.set_title("DIV stall / branch delay slot: observed reference writebacks",
                 color=NAVY, fontsize=14, fontweight="bold", pad=14)
    ax.text(0.5, -0.25,
            f"Run {run_id}; DUT status PASS and full reference trace match. "
            "The plot shows retirement order, not a time-scaled waveform.",
            transform=ax.transAxes, ha="center", va="top", color=MUTED, fontsize=8)
    fig.tight_layout(rect=(0, 0.09, 1, 1))
    save(fig, "div_branch_retirement.png")


def draw_extended_control_retirement(data: dict[str, object]) -> None:
    records = data["traces"]["extended"]
    run_id = data["results"]["extended"]["RUN_ID"]

    def draw_sequence(selected_pcs: list[str], title: str, filename: str,
                      skipped_note: str, colors: list[str]) -> None:
        selected = [row_at_pc(records, pc) for pc in selected_pcs]
        x_values = np.arange(1, len(selected) + 1)
        fig, ax = plt.subplots(figsize=(10.8, 3.8))
        ax.plot(x_values, np.full(len(x_values), 0.61), color="#B8C6CF", linewidth=1.6, zorder=1)
        for x, row, color in zip(x_values, selected, colors):
            ax.scatter([x], [0.61], s=94, color=color, edgecolor="white", linewidth=1.1, zorder=2)
            ax.annotate(
                f"PC {row['pc']}\nr{row['destination_register']} = {row['write_data']}",
                (x, 0.61), xytext=(0, 22), textcoords="offset points",
                ha="center", va="bottom", fontsize=8.2, color=INK,
            )
        ax.text((len(selected) + 1) / 2, 0.12, skipped_note, ha="center", va="center",
                fontsize=8.5, color=RED,
                bbox=dict(boxstyle="round,pad=0.3", facecolor="#FBECEC", edgecolor="#E8B9B9"))
        ax.set_xlim(0.4, len(selected) + 0.6)
        ax.set_ylim(-0.10, 1.45)
        ax.set_xticks(x_values, [str(row["trace_index"]) for row in selected])
        ax.set_xlabel("Reference retirement record index", color=MUTED)
        ax.set_yticks([])
        ax.grid(axis="x", color="#E2E8EC", linewidth=0.8)
        ax.set_axisbelow(True)
        ax.spines[["top", "right", "left"]].set_visible(False)
        ax.spines["bottom"].set_color("#AAB8C2")
        ax.tick_params(axis="x", colors=MUTED, labelsize=8, length=0)
        ax.set_title(title, color=NAVY, fontsize=13, fontweight="bold", pad=12)
        ax.text(0.5, -0.24,
                f"Run {run_id}; PASS trace match. Points summarize matched reference writeback records.",
                transform=ax.transAxes, ha="center", va="top", color=MUTED, fontsize=8)
        fig.tight_layout(rect=(0, 0.09, 1, 1))
        save(fig, filename)

    draw_sequence(
        ["BFC00068", "BFC00070", "BFC00078"],
        "Lab7 directed branch: source, delay-slot writeback and target",
        "extended_branch_retirement.png",
        "Fall-through PC BFC00074 is absent from the retirement trace.",
        [BLUE, TEAL, TEAL],
    )
    draw_sequence(
        ["BFC000E0", "BFC000E4", "BFC000E8", "BFC000F0"],
        "Lab7 directed JALR: target, PC+8 link, delay slot and destination",
        "jalr_retirement.png",
        "Fall-through PC BFC000EC is absent; the JALR link value is BFC000EC.",
        [BLUE, GOLD, TEAL, TEAL],
    )


def draw_cumulative_metrics(data: dict[str, object]) -> None:
    cumulative_run_ids = {data["results"]["lab6"]["RUN_ID"], data["results"]["lab7"]["RUN_ID"]}
    rows = [row for row in data["summary_rows"] if row["run_id"] in cumulative_run_ids]
    labels = ["Lab6", "Lab7"]
    colors = [BLUE, TEAL]
    cycles = [int(row["pipeline_cycles"]) for row in rows]
    stalls = [int(row["stall_cycles"]) for row in rows]
    forwarding = [
        [int(row["forward_ex_uses"]), int(row["forward_mem_uses"]), int(row["forward_wb_uses"])]
        for row in rows
    ]
    fig, axes = plt.subplots(1, 3, figsize=(14.0, 4.15), gridspec_kw={"width_ratios": [1.1, 0.85, 1.3]})
    for ax, values, title, xlabel, xmax in (
        (axes[0], cycles, "Simulated pipeline cycles", "Cycles", max(cycles) * 1.12),
        (axes[1], stalls, "Stall cycles", "Cycles", max(stalls) * 1.35),
    ):
        y = np.arange(2)
        bars = ax.barh(y, values, color=colors, height=0.48)
        ax.set_yticks(y, labels)
        ax.invert_yaxis()
        ax.set_xlim(0, xmax)
        ax.set_xlabel(xlabel, color=MUTED, fontsize=8)
        ax.set_title(title, color=NAVY, fontsize=10.5, fontweight="bold", pad=9)
        ax.grid(axis="x", color="#E2E8EC", linewidth=0.8)
        ax.set_axisbelow(True)
        ax.spines[["top", "right", "left"]].set_visible(False)
        ax.spines["bottom"].set_color("#AAB8C2")
        ax.tick_params(axis="y", length=0, labelsize=8, labelcolor=INK)
        ax.tick_params(axis="x", labelsize=7, colors=MUTED)
        for bar, value in zip(bars, values):
            ax.text(bar.get_width() + xmax * 0.018, bar.get_y() + bar.get_height() / 2,
                    f"{value:,}", ha="left", va="center", fontsize=8, color=INK)

    ax = axes[2]
    x = np.arange(3)
    width = 0.34
    bars6 = ax.bar(x - width / 2, forwarding[0], width, color=BLUE, label="Lab6")
    bars7 = ax.bar(x + width / 2, forwarding[1], width, color=TEAL, label="Lab7")
    ax.set_xticks(x, ["EX", "MEM", "WB"])
    ax.set_ylabel("Forwarding uses", color=MUTED, fontsize=8)
    ax.set_title("Forwarding activity", color=NAVY, fontsize=10.5, fontweight="bold", pad=9)
    ax.grid(axis="y", color="#E2E8EC", linewidth=0.8)
    ax.set_axisbelow(True)
    ax.spines[["top", "right", "left"]].set_visible(False)
    ax.spines["bottom"].set_color("#AAB8C2")
    ax.tick_params(axis="x", length=0, labelsize=8, labelcolor=INK)
    ax.tick_params(axis="y", labelsize=7, colors=MUTED)
    ax.legend(frameon=False, fontsize=7, loc="upper left")
    for bars in (bars6, bars7):
        for bar in bars:
            ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + max(max(forwarding[0]), max(forwarding[1])) * 0.018,
                    f"{int(bar.get_height()):,}", ha="center", va="bottom", fontsize=6.8, rotation=0)

    fig.suptitle("Cumulative Lab6/Lab7 verification counters", color=NAVY,
                 fontsize=14, fontweight="bold", y=1.02)
    fig.text(0.5, 0.005,
             "Functional points: Lab6 42/42; Lab7 68/68. Programs differ in length; cycle counts are not a performance comparison.",
             ha="center", va="bottom", fontsize=8, color=MUTED)
    fig.tight_layout(rect=(0, 0.055, 1, 0.96))
    save(fig, "cumulative_metrics.png")


def draw_hilo_unit_counts(data: dict[str, object]) -> None:
    row = data["hilo_row"]
    labels = ["MULT accepted", "DIV accepted", "Completion commits", "Reset-cancelled"]
    values = [int(row["mult_accepts"]), int(row["div_accepts"]),
              int(row["completion_commits"]), int(row["reset_cancelled_inflight"])]
    colors = [BLUE, TEAL, GOLD, RED]
    fig, ax = plt.subplots(figsize=(8.5, 3.6))
    bars = ax.bar(np.arange(len(labels)), values, color=colors, width=0.62)
    ax.set_xticks(np.arange(len(labels)), labels)
    ax.set_ylabel("Operations", color=MUTED)
    ax.set_ylim(0, max(values) + 1.5)
    ax.set_title("HI/LO unit testbench accounting", color=NAVY,
                 fontsize=14, fontweight="bold", pad=12)
    ax.grid(axis="y", color="#E2E8EC", linewidth=0.8)
    ax.set_axisbelow(True)
    ax.spines[["top", "right", "left"]].set_visible(False)
    ax.spines["bottom"].set_color("#AAB8C2")
    ax.tick_params(axis="x", colors=INK, labelsize=8, length=0)
    ax.tick_params(axis="y", colors=MUTED, labelsize=8)
    for bar, value in zip(bars, values):
        ax.text(bar.get_x() + bar.get_width() / 2, value + 0.12, str(value),
                ha="center", va="bottom", fontsize=10, fontweight="bold", color=INK)
    ax.text(0.5, -0.25,
            "7 requests were accepted; 6 completions were consumed and one in-flight divide was cancelled by reset.",
            transform=ax.transAxes, ha="center", va="top", fontsize=8, color=MUTED)
    fig.tight_layout(rect=(0, 0.1, 1, 1))
    save(fig, "hilo_unit_counts.png")


def main() -> None:
    plt.rcParams.update({
        "font.family": "DejaVu Sans",
        "font.size": 9,
        "axes.edgecolor": "#AAB8C2",
        "figure.facecolor": "white",
        "savefig.facecolor": "white",
    })
    data = collect_report_data()
    draw_pipeline()
    draw_hilo_fsm()
    draw_branch_case()
    draw_verification_summary()
    draw_alu_key_values(data)
    draw_div_branch_retirement(data)
    draw_extended_control_retirement(data)
    draw_cumulative_metrics(data)
    draw_hilo_unit_counts(data)
    print(f"Generated report figures in {FIGURES}")


if __name__ == "__main__":
    main()
