#!/usr/bin/env python3
"""Build provenance CSVs and per-run Vivado Wave configurations for Lab10/11."""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

from check_bus_inputs import parse_mif


EVIDENCE_FIELDS = [
    "case", "run_id", "suite", "source_commit", "source_dirty", "source_diff_sha256",
    "build_status", "functional_status", "protocol_status", "overall_status",
    "expected_points", "actual_points", "trace_compare_status", "trace_records",
    "project_xpr", "rtl_manifest", "inst_mif", "inst_mif_sha256", "inst_coe",
    "inst_coe_sha256", "reference_trace", "reference_sha256", "vivado_version",
    "wdb_file", "wdb_sha256", "wcfg_files", "wcfg_validation", "sim_log",
    "completed_utc", "notes",
]
TRANSACTION_FIELDS = [
    "case", "run_id", "inst_req_accept", "inst_data_complete", "load_req_accept",
    "load_data_complete", "store_req_accept", "store_data_complete", "ar_handshakes",
    "r_handshakes", "aw_handshakes", "w_handshakes", "b_handshakes",
    "stale_fetch_drops", "duplicate_store_count", "protocol_assertions_failed",
    "deadlock_watchdogs", "summary_status",
]
WAVE_FIELDS = [
    "case", "run_id", "figure_id", "png_filename", "wdb_file", "wdb_sha256",
    "wcfg_file", "wcfg_validation", "inst_mif", "inst_mif_sha256", "reference_trace",
    "reference_sha256", "topic", "target_instruction", "target_pc", "search_signal",
    "search_value", "search_context", "required_signals", "expected", "expected_source",
    "observed", "time_start_ns", "time_end_ns", "proof_status", "remarks",
]
WAVE_VALIDATION_FIELDS = [
    "case", "run_id", "wdb_file", "wdb_sha256", "wcfg_file", "wcfg_sha256",
    "db_ref_matches", "db_opens", "config_opens", "signals_expected", "signals_found",
    "clock_toggles", "pc_valid", "target_event_found", "simtcl_missing_scope",
    "validation_status", "validation_log",
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def read_kv(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.is_file():
        return values
    for raw in path.read_text(encoding="utf-8-sig", errors="replace").splitlines():
        if "=" in raw:
            key, value = raw.split("=", 1)
            values[key.strip()] = value.strip()
    return values


def csv_rows(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        return []
    with path.open("r", newline="", encoding="utf-8-sig", errors="replace") as stream:
        return list(csv.DictReader(stream))


def write_csv(path: Path, fields: list[str], rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8-sig") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def repo_path(root: Path, raw: str | Path | None) -> str:
    if not raw:
        return ""
    text = str(raw).strip().strip('"')
    if not text:
        return ""
    candidate = Path(text)
    if not candidate.is_absolute():
        candidate = root / candidate
    try:
        return candidate.resolve().relative_to(root.resolve()).as_posix()
    except (OSError, ValueError):
        return text.replace("\\", "/")


def find_runs(root: Path, result_root: Path) -> list[tuple[str, Path, dict[str, str]]]:
    candidates: set[Path] = set()
    for parent in (result_root, result_root / "lab10", result_root / "lab11"):
        if parent.is_dir():
            for child in parent.iterdir():
                if child.is_dir() and (child / "result.txt").is_file():
                    candidates.add(child.resolve())
    runs: list[tuple[str, Path, dict[str, str]]] = []
    for directory in sorted(candidates, key=lambda path: str(path).lower()):
        info = read_kv(directory / "result.txt")
        case = info.get("CASE", "")
        if case not in {"lab10", "lab11"}:
            case = directory.parent.name if directory.parent.name in {"lab10", "lab11"} else ""
        if case not in {"lab10", "lab11"}:
            name = directory.name.lower()
            case = "lab10" if "lab10" in name else ("lab11" if "lab11" in name else "")
        if case:
            runs.append((case, directory, info))
    return runs


def run_manifest(case: str, run_dir: Path) -> tuple[dict[str, str], dict[str, str]]:
    input_rows = csv_rows(run_dir / "input_manifest.csv") or csv_rows(run_dir / "input-manifest.csv")
    input_row = next((row for row in input_rows if row.get("case") == case), {})
    return input_row, read_kv(run_dir / "preflight.txt")


def find_wave_db(run_dir: Path, info: dict[str, str]) -> Path | None:
    raw = info.get("WAVEFORM_FILE", "")
    if raw:
        candidate = Path(raw)
        if not candidate.is_absolute():
            candidate = run_dir / candidate
        if candidate.is_file() and candidate.stat().st_size:
            return candidate.resolve()
    candidate = run_dir / "wave-full.wdb"
    if candidate.is_file() and candidate.stat().st_size:
        return candidate.resolve()
    return None


def find_trace(root: Path, case: str, info: dict[str, str], cfg: dict[str, dict]) -> Path:
    raw = info.get("TRACE_FILE") or info.get("REFERENCE_TRACE") or cfg[case]["ReferenceTrace"]
    path = Path(raw)
    return path if path.is_absolute() else root / path


def find_mif(root: Path, case: str, info: dict[str, str], cfg: dict[str, dict]) -> Path:
    raw = info.get("INST_MIF") or cfg[case]["InstructionMif"]
    path = Path(raw)
    return path if path.is_absolute() else root / path


def anchor_lines(sim_log: Path) -> dict[str, dict[str, str]]:
    result: dict[str, dict[str, str]] = {}
    if not sim_log.is_file():
        return result
    for line in sim_log.read_text(encoding="utf-8", errors="replace").splitlines():
        match = re.search(r"BUS_ANCHOR\s+event=([a-z_]+)(?:\s+channel=([A-Z]+))?\s+(.+)", line)
        if not match:
            continue
        event = match.group(1)
        fields = dict(re.findall(r"([a-z_]+)=([^\s]+)", match.group(3)))
        if match.group(2):
            fields["channel"] = match.group(2)
        fields["raw"] = line
        result.setdefault(event if event != "backpressure" else f"backpressure_{fields.get('channel', '').lower()}", fields)
    return result


def parse_metrics(sim_log: Path) -> dict[str, str]:
    if not sim_log.is_file():
        return {}
    text = sim_log.read_text(encoding="utf-8", errors="replace")
    match = re.search(r"BUS_METRICS\s+([^\r\n]+)", text)
    if not match:
        return {}
    return dict(re.findall(r"([a-z_]+)=(\d+)", match.group(1)))


def pc_from_anchor(anchors: dict[str, dict[str, str]], event: str, key: str = "pc") -> str:
    if event not in anchors:
        return ""
    value = anchors[event].get(key, "")
    if re.fullmatch(r"[0-9a-fA-F]{8}", value):
        return f"0x{value.lower()}"
    return ""


def instruction_name(word: int) -> str:
    op = (word >> 26) & 0x3F
    funct = word & 0x3F
    if op in {0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26}:
        return {0x20: "LB", 0x21: "LH", 0x22: "LWL", 0x23: "LW", 0x24: "LBU", 0x25: "LHU", 0x26: "LWR"}[op]
    if op in {0x28, 0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E}:
        return {0x28: "SB", 0x29: "SH", 0x2A: "SWL", 0x2B: "SW", 0x2C: "SDL", 0x2D: "SDR", 0x2E: "SWR"}[op]
    if op == 0x00:
        return {0x08: "JR", 0x09: "JALR", 0x0C: "SYSCALL", 0x0D: "BREAK"}.get(funct, "R-TYPE")
    if op == 0x01:
        return "REGIMM"
    if op in {0x02, 0x03}:
        return "J" if op == 2 else "JAL"
    if op in {0x04, 0x05, 0x06, 0x07}:
        return {0x04: "BEQ", 0x05: "BNE", 0x06: "BLEZ", 0x07: "BGTZ"}[op]
    return f"OP_{op:02X}"


def decode_pc(pc_text: str, base: int, words: list[int]) -> tuple[str, int | None]:
    try:
        pc = int(pc_text, 16)
    except ValueError:
        return "", None
    index = (pc - base) // 4
    if pc < base or (pc - base) % 4 or index >= len(words):
        return "", None
    word = words[index]
    return instruction_name(word), word


def mips_context(root: Path, case: str, run_dir: Path, info: dict[str, str], cfg: dict[str, dict]):
    trace = find_trace(root, case, info, cfg)
    mif = find_mif(root, case, info, cfg)
    trace_pcs: list[int] = []
    if trace.is_file():
        for line in trace.read_text(encoding="ascii", errors="replace").splitlines():
            columns = line.split()
            if len(columns) >= 4:
                try:
                    trace_pcs.append(int(columns[1], 16))
                except ValueError:
                    continue
    words = parse_mif(mif) if mif.is_file() else []
    base = trace_pcs[0] if trace_pcs else 0xBFC00000
    return trace, mif, trace_pcs, base, words


def theme_rows(case: str) -> list[dict[str, object]]:
    if case == "lab10":
        themes = [
            {"figure": "L10-01", "file": "01_inst_request", "topic": "类 AXI 取指", "event": "fetch", "signal": "soc_lite/cpu/if_stage/request_pc[31:0]", "context": "指令请求在 inst_sram_req && inst_sram_addr_ok 接受；随后 data_ok 返回指令并进入 IF 响应缓冲。", "expected": "取指地址与 request_pc 一致；data_ok 后响应有效。", "expected_source": "Lab10 IF/SRAM 接口语义及本次 full-run BUS_ANCHOR。", "signals": ["tb_top/clk~bin", "soc_clk~bin", "soc_lite/cpu/if_stage/request_pc[31:0]~hex", "soc_lite/cpu_inst_req~bin", "soc_lite/cpu_inst_addr[31:0]~hex", "soc_lite/cpu_inst_addr_ok~bin", "soc_lite/cpu_inst_data_ok~bin", "soc_lite/cpu_inst_rdata[31:0]~hex", "soc_lite/cpu/fs_to_ds_valid~bin", "soc_lite/cpu/ds_allowin~bin", "tb_top/debug_wb_pc[31:0]~hex"]},
            {"figure": "L10-02", "file": "02_load_wait", "topic": "Load 与流水线等待", "event": "load", "signal": "soc_lite/cpu/mem_stage/ms_pc[31:0]", "context": "本次首个已接受 Load：CPU data req/address/addr_ok 后等待 data_ok；响应数据再进入写回阶段。", "expected": "data_ok 前 MEM 持有该 Load；响应后完成写回。", "expected_source": "Lab10 MEM 接口语义及本次 full-run BUS_ANCHOR。", "signals": ["tb_top/clk~bin", "soc_lite/cpu/mem_stage/ms_pc[31:0]~hex", "soc_lite/cpu/mem_stage/ms_valid~bin", "soc_lite/cpu/mem_stage/ms_allowin~bin", "soc_lite/cpu_data_req~bin", "soc_lite/cpu_data_addr[31:0]~hex", "soc_lite/cpu_data_addr_ok~bin", "soc_lite/cpu_data_data_ok~bin", "soc_lite/cpu_data_rdata[31:0]~hex", "tb_top/debug_wb_pc[31:0]~hex", "tb_top/debug_wb_rf_wen[3:0]~bin", "tb_top/debug_wb_rf_wdata[31:0]~hex"]},
            {"figure": "L10-03", "file": "03_store_write", "topic": "Store 与字节写掩码", "event": "store", "signal": "soc_lite/cpu/mem_stage/ms_pc[31:0]", "context": "本次首个已接受 Store：比较 CPU 写掩码、地址/数据、桥接后的 RAM 写掩码与完成响应。", "expected": "wstrb 对应 Store 大小和地址低位；事务仅接受并完成一次。", "expected_source": "Lab10 MEM/bridge 接口语义及本次 full-run BUS_ANCHOR。", "signals": ["tb_top/clk~bin", "soc_lite/cpu/mem_stage/ms_pc[31:0]~hex", "soc_lite/cpu_data_req~bin", "soc_lite/cpu_data_wr~bin", "soc_lite/cpu_data_size[1:0]~bin", "soc_lite/cpu_data_addr[31:0]~hex", "soc_lite/cpu_data_wstrb[3:0]~bin", "soc_lite/cpu_data_wdata[31:0]~hex", "soc_lite/cpu_data_addr_ok~bin", "soc_lite/cpu_data_data_ok~bin", "soc_lite/data_sram_wstrb[3:0]~bin", "soc_lite/data_ram_wen[3:0]~bin", "soc_lite/data_ram_addr[31:0]~hex"]},
            {"figure": "L10-04", "file": "04_redirect_stale", "topic": "异常重定向与旧取指响应", "event": "stale_drop", "signal": "soc_lite/cpu/if_stage/restart_pc[31:0]", "context": "本次 full-run 的异常/ERET 重定向与旧路径取指响应；restart_pc 保存重定向目标，stale_response 响应被丢弃。", "expected": "过时指令不进入 decode；下一条请求从 restart_pc 开始。", "expected_source": "Lab10 IF_stage 状态机与本次 full-run BUS_ANCHOR。", "signals": ["tb_top/clk~bin", "soc_lite/cpu/trap_commit~bin", "soc_lite/cpu/eret_commit~bin", "soc_lite/cpu/if_stage/redirect_pc[31:0]~hex", "soc_lite/cpu/if_stage/request_pc[31:0]~hex", "soc_lite/cpu/if_stage/restart_pc[31:0]~hex", "soc_lite/cpu/if_stage/stale_response~bin", "soc_lite/cpu/if_stage/response_valid~bin", "soc_lite/cpu_inst_req~bin", "soc_lite/cpu_inst_addr_ok~bin", "soc_lite/cpu_inst_data_ok~bin", "soc_lite/cpu/fs_to_ds_valid~bin"]},
        ]
        for theme in themes:
            theme["signals"] = ["tb_top/clk~bin" if signal == "clk~bin" else signal
                                for signal in theme["signals"]]
        return themes
    themes = [
        {"figure": "L11-01", "file": "01_axi_read", "topic": "AXI3 单拍读事务", "event": "ar", "signal": "soc_lite/cpu_araddr[31:0]", "context": "本次 full-run 首个 AR 握手地址；随后以同一读事务的 RVALID && RREADY 完成返回。", "expected": "ARLEN=0；读响应 RID/RRESP/RLAST 与单拍事务相符。", "expected_source": "AXI3 adapter 参数与本次 full-run BUS_ANCHOR/握手监视。", "signals": ["tb_top/clk~bin", "soc_lite/cpu_arvalid~bin", "soc_lite/cpu_arready~bin", "soc_lite/cpu_araddr[31:0]~hex", "soc_lite/cpu_arid[3:0]~hex", "soc_lite/cpu_arlen[7:0]~hex", "soc_lite/cpu_rvalid~bin", "soc_lite/cpu_rready~bin", "soc_lite/cpu_rdata[31:0]~hex", "soc_lite/cpu_rid[3:0]~hex", "soc_lite/cpu_rlast~bin", "soc_lite/cpu_rresp[1:0]~bin"]},
        {"figure": "L11-02", "file": "02_read_arbitration", "topic": "IF/Load 共用读通道仲裁", "event": "load", "signal": "soc_lite/cpu/mem_stage/ms_pc[31:0]", "context": "首个实际 Load 的 CPU MEM PC 对应 adapter rd_owner_data=1；对照 IF owner、AR ID 和 R 响应归属。", "expected": "IF=ID 0、Load=ID 1；响应按锁存 owner 返回正确 CPU 请求端。", "expected_source": "Lab11 axi3_cpu_bus.v ID/owner 设计与本次 full-run BUS_ANCHOR。", "signals": ["clk~bin", "soc_lite/cpu/if_stage/request_pc[31:0]~hex", "soc_lite/cpu/mem_stage/ms_pc[31:0]~hex", "soc_lite/cpu/axi3_cpu_bus/rd_owner_data~bin", "soc_lite/cpu/axi3_cpu_bus/rd_state[1:0]~bin", "soc_lite/cpu/axi3_cpu_bus/rd_claim_inst~bin", "soc_lite/cpu/axi3_cpu_bus/rd_claim_data~bin", "soc_lite/cpu_arvalid~bin", "soc_lite/cpu_arready~bin", "soc_lite/cpu_araddr[31:0]~hex", "soc_lite/cpu_arid[3:0]~hex", "soc_lite/cpu_rvalid~bin", "soc_lite/cpu_rready~bin", "soc_lite/cpu_rid[3:0]~hex", "soc_lite/cpu_inst_data_ok~bin", "soc_lite/cpu_data_data_ok~bin"]},
        {"figure": "L11-03", "file": "03_axi_write", "topic": "AXI3 写事务 AW/W/B", "event": "store", "signal": "soc_lite/cpu/mem_stage/ms_pc[31:0]", "context": "本次首个已接受 Store；对照 AW 与 W 独立握手，最后 B 响应后 MEM 完成。", "expected": "AW 与 W 可分拍；WID 对应 AWID；WLAST=1；B 响应后事务完成。", "expected_source": "Lab11 AXI3 adapter 与本次 full-run BUS_ANCHOR/握手监视。", "signals": ["clk~bin", "soc_lite/cpu/mem_stage/ms_pc[31:0]~hex", "soc_lite/cpu_awvalid~bin", "soc_lite/cpu_awready~bin", "soc_lite/cpu_awaddr[31:0]~hex", "soc_lite/cpu_awid[3:0]~hex", "soc_lite/cpu_wvalid~bin", "soc_lite/cpu_wready~bin", "soc_lite/cpu_wdata[31:0]~hex", "soc_lite/cpu_wstrb[3:0]~bin", "soc_lite/cpu_wlast~bin", "soc_lite/cpu_bvalid~bin", "soc_lite/cpu_bready~bin", "soc_lite/cpu_bid[3:0]~hex", "soc_lite/cpu_bresp[1:0]~bin", "soc_lite/cpu_data_data_ok~bin"]},
        {"figure": "L11-04", "file": "04_axi_backpressure", "topic": "AXI3 READY 反压", "event": "backpressure", "signal": "", "context": "定位本次 full-run 首个 VALID=1、READY=0 的真实 AXI 通道事件，检查 VALID 与 payload 稳定至握手。", "expected": "READY=0 时 VALID 保持且 payload 不变；READY 恢复后单次握手。", "expected_source": "AXI VALID/READY 规则及本次 full-run BUS_ANCHOR。", "signals": ["clk~bin", "soc_lite/cpu_arvalid~bin", "soc_lite/cpu_arready~bin", "soc_lite/cpu_araddr[31:0]~hex", "soc_lite/cpu_rvalid~bin", "soc_lite/cpu_rready~bin", "soc_lite/cpu_rdata[31:0]~hex", "soc_lite/cpu_awvalid~bin", "soc_lite/cpu_awready~bin", "soc_lite/cpu_awaddr[31:0]~hex", "soc_lite/cpu_wvalid~bin", "soc_lite/cpu_wready~bin", "soc_lite/cpu_wdata[31:0]~hex", "soc_lite/cpu_wstrb[3:0]~bin", "soc_lite/cpu_bvalid~bin", "soc_lite/cpu_bready~bin"]},
        {"figure": "L11-05", "file": "05_redirect_stale", "topic": "异常期间未完成读与旧响应丢弃", "event": "stale_drop", "signal": "soc_lite/cpu/if_stage/restart_pc[31:0]", "context": "异常/ERET 重定向期间已接受的旧 IF 读继续排空；stale_response 丢弃旧响应并转向 restart_pc。", "expected": "旧读响应不送入 decode；新请求使用异常/ERET 目标 PC。", "expected_source": "Lab11 IF_stage 状态机与本次 full-run BUS_ANCHOR。", "signals": ["clk~bin", "soc_lite/cpu/trap_commit~bin", "soc_lite/cpu/eret_commit~bin", "soc_lite/cpu/if_stage/request_pc[31:0]~hex", "soc_lite/cpu/if_stage/restart_pc[31:0]~hex", "soc_lite/cpu/if_stage/stale_response~bin", "soc_lite/cpu/if_stage/response_valid~bin", "soc_lite/cpu_arvalid~bin", "soc_lite/cpu_arready~bin", "soc_lite/cpu_araddr[31:0]~hex", "soc_lite/cpu_arid[3:0]~hex", "soc_lite/cpu_rvalid~bin", "soc_lite/cpu_rready~bin", "soc_lite/cpu_rid[3:0]~hex", "soc_lite/cpu_inst_data_ok~bin", "debug_wb_pc[31:0]~hex"]},
    ]
    for theme in themes:
        theme["signals"] = ["tb_top/clk~bin" if signal == "clk~bin" else signal
                            for signal in theme["signals"]]
        theme["signal"] = str(theme.get("signal", "")).replace("soc_lite/cpu/", "soc_lite/u_cpu/")
        mapped_signals = []
        for signal in theme["signals"]:
            signal = signal.replace("soc_lite/cpu/", "soc_lite/u_cpu/")
            signal = signal.replace("soc_lite/cpu_inst_data_ok", "soc_lite/u_cpu/inst_sram_data_ok")
            signal = signal.replace("soc_lite/cpu_data_data_ok", "soc_lite/u_cpu/data_sram_data_ok")
            signal = signal.replace("debug_wb_pc", "tb_top/debug_wb_pc")
            mapped_signals.append(signal)
        theme["signals"] = mapped_signals
    return themes


def run_vivado(vivado: Path, root: Path, source_tcl: Path, args: list[str], log: Path) -> tuple[int, str]:
    journal = log.with_suffix(".jou")
    command = [os.environ.get("COMSPEC", "cmd.exe"), "/d", "/c", "call", str(vivado),
               "-mode", "batch", "-source", str(source_tcl), "-log", str(log),
               "-journal", str(journal), "-tclargs", *args]
    proc = subprocess.run(command, cwd=root, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, encoding="utf-8", errors="replace")
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_text(proc.stdout, encoding="utf-8")
    return proc.returncode, proc.stdout


def parse_wcfg_signals(path: Path) -> list[str]:
    if not path.is_file():
        return []
    text = path.read_text(encoding="utf-8", errors="replace")
    return re.findall(r'<wvobject fp_name="([^"]+)" type="[^"]+"', text)


def normalize_signal_path(path: str) -> str:
    """Vivado's WDB object names omit packed-vector width selectors."""
    return re.sub(r"\[\d+:\d+\]$", "", path.replace("\\", "/"))


def run_wcfgs(fig_dir: Path, run_id: str) -> list[Path]:
    if not fig_dir.is_dir():
        return []
    pattern = re.compile(rf".*__{re.escape(run_id)}(?:-v(\d+))?\.wcfg$")
    candidates: list[tuple[int, Path]] = []
    for path in fig_dir.glob("*.wcfg"):
        match = pattern.fullmatch(path.name)
        if match:
            candidates.append((int(match.group(1) or "1"), path))
    if not candidates:
        return []
    latest = max(version for version, _ in candidates)
    return sorted(path for version, path in candidates if version == latest)


def get_pc_event(case: str, theme: dict[str, object], anchors: dict[str, dict[str, str]]) -> tuple[str, str, str]:
    event = str(theme["event"])
    if event == "backpressure":
        selected = next((key for key in anchors if key.startswith("backpressure_")), "")
        if not selected:
            return "", "", ""
        info = anchors[selected]
        channel = info.get("channel", "")
        mapping = {"ar": "soc_lite/cpu_arvalid", "r": "soc_lite/cpu_rvalid",
                   "aw": "soc_lite/cpu_awvalid", "w": "soc_lite/cpu_wvalid",
                   "b": "soc_lite/cpu_bvalid"}
        return mapping.get(channel.lower(), ""), "1", info.get("raw", "")
    anchor = anchors.get(event, {})
    key = "target" if event in {"redirect", "stale_drop"} else ("addr" if event == "ar" else "pc")
    value = anchor.get(key, "")
    if re.fullmatch(r"[0-9a-fA-F]{8}", value):
        value = f"0x{value.lower()}"
    suffix = str(theme.get("signal", ""))
    context = anchor.get("raw", "")
    if event == "stale_drop" and not anchor:
        redirect = anchors.get("redirect", {})
        value = redirect.get("target", "")
        if re.fullmatch(r"[0-9a-fA-F]{8}", value):
            value = f"0x{value.lower()}"
        context = redirect.get("raw", "")
        cpu_scope = "soc_lite/u_cpu" if case == "lab11" else "soc_lite/cpu"
        suffix = f"{cpu_scope}/if_stage/redirect_pc[31:0]"
    if event == "ar":
        suffix = "soc_lite/cpu_araddr[31:0]"
    return suffix, value, context


def make_wcfgs(root: Path, case: str, run_dir: Path, info: dict[str, str],
               vivado: Path | None, attempt: int) -> tuple[list[dict], list[dict], dict[str, dict[str, str]]]:
    wdb = find_wave_db(run_dir, info)
    sim_log = run_dir / "simulate.log"
    anchors = anchor_lines(sim_log)
    if not wdb:
        return [], [], anchors
    themes = theme_rows(case)
    fig_dir = root / "report" / "lab10-11" / "figures" / case
    fig_dir.mkdir(parents=True, exist_ok=True)
    attempt_tag = "" if attempt == 1 else f"-v{attempt}"
    validation_dir = run_dir / ("wave-validation" if attempt == 1 else f"wave-validation-v{attempt}")
    validation_dir.mkdir(exist_ok=True)
    wdb_rel = repo_path(root, wdb)
    wdb_hash = sha256(wdb)
    validation_rows: list[dict] = []
    expected_cfgs: list[Path] = []
    validation_log = validation_dir / "validation.log"
    db_code = 2
    db_text = "Vivado unavailable"
    if vivado:
        db_code, db_text = run_vivado(vivado, root, root / "scripts" / "validate_wave_db.tcl",
                                      [str(wdb)], validation_log)
    db_opens = "true" if db_code == 0 and "WDB_VALID=" in db_text else "false"
    missing_scope = "true" if "Simtcl 6-55" in db_text else "false"
    for theme in themes:
        run_id = info.get("RUN_ID", run_dir.name)
        wcfg = fig_dir / f"{theme['file']}__{run_id}{attempt_tag}.wcfg"
        expected_cfgs.append(wcfg)
        if not wcfg.exists():
            if vivado:
                create_log = validation_dir / f"{theme['figure']}-create.log"
                specs = [f"{normalize_signal_path(str(signal).rsplit('~', 1)[0])}~{str(signal).rsplit('~', 1)[1]}"
                         for signal in theme["signals"]]
                code, _ = run_vivado(vivado, root, root / "scripts" / "create_wave_config_from_wdb.tcl",
                                     [str(wdb), str(wcfg), *specs], create_log)
                if code != 0:
                    # Preserve the failed attempt log; never create or overwrite a placeholder WCFG.
                    pass
        signal_paths = parse_wcfg_signals(wcfg)
        config_log = validation_dir / f"{theme['figure']}-validate.log"
        config_code = 2
        config_text = "Vivado unavailable"
        if vivado and wcfg.is_file():
            config_code, config_text = run_vivado(
                vivado, root, root / "scripts" / "validate_wave_configs.tcl",
                [str(wdb), str(wcfg)], config_log)
        db_ref_ok = "true" if wcfg.is_file() and str(wdb).replace("\\", "/") in wcfg.read_text(encoding="utf-8", errors="replace").replace("\\", "/") else "false"
        config_opens = "true" if config_code == 0 and "WAVE_CONFIG_VALIDATION_COMPLETE=1" in config_text else "false"
        target_suffix, target_value, anchor = get_pc_event(case, theme, anchors)
        selected_signal = ""
        for path in signal_paths:
            normalized = path.replace("\\", "/")
            suffix = normalize_signal_path(target_suffix) if target_suffix else ""
            if suffix and (normalize_signal_path(normalized).endswith("/" + suffix) or
                           normalize_signal_path(normalized).endswith(suffix)):
                selected_signal = normalized
                break
        if theme["event"] == "backpressure" and target_suffix:
            selected_signal = next((path.replace("\\", "/") for path in signal_paths
                                    if normalize_signal_path(path).endswith("/" + normalize_signal_path(target_suffix))), "")
        target_found = "true" if anchor and selected_signal and target_value else "false"
        completed = bool(read_kv(run_dir / "result.txt").get("TEST_END_SEEN", "").lower() == "true")
        metrics = parse_metrics(sim_log)
        cycles = metrics.get("pipeline_cycles", "")
        if not cycles:
            # The testbench clock is explicitly counted in BUS_METRICS where available.
            cycles = ""
        has_tb_clock = any(normalize_signal_path(path).endswith("/tb_top/clk") for path in signal_paths)
        clock_toggles = "true" if db_opens == "true" and has_tb_clock and completed else "false"
        pc_valid = "true" if target_found == "true" and selected_signal else "false"
        validation_status = "PASS" if (db_opens == "true" and config_opens == "true" and
                                         db_ref_ok == "true" and len(signal_paths) == len(theme["signals"]) and
                                         clock_toggles == "true" and pc_valid == "true" and
                                         target_found == "true" and missing_scope == "false") else "INCOMPLETE"
        validation_rows.append({
            "case": case, "run_id": run_id, "wdb_file": wdb_rel, "wdb_sha256": wdb_hash,
            "wcfg_file": repo_path(root, wcfg) if wcfg.is_file() else "",
            "wcfg_sha256": sha256(wcfg) if wcfg.is_file() else "",
            "db_ref_matches": db_ref_ok, "db_opens": db_opens, "config_opens": config_opens,
            "signals_expected": len(theme["signals"]), "signals_found": len(signal_paths),
            "clock_toggles": clock_toggles, "pc_valid": pc_valid,
            "target_event_found": target_found, "simtcl_missing_scope": missing_scope,
            "validation_status": validation_status,
            "validation_log": repo_path(root, config_log if config_log.is_file() else validation_log),
        })
    return [], validation_rows, anchors


def build_evidence_rows(root: Path, runs, cfg: dict[str, dict]) -> list[dict]:
    rows: list[dict] = []
    for case, run_dir, info in runs:
        input_row, baseline = run_manifest(case, run_dir)
        result_status = info.get("STATUS", "INCOMPLETE")
        trace = find_trace(root, case, info, cfg)
        mif = find_mif(root, case, info, cfg)
        coe_raw = info.get("INST_COE", cfg[case]["InstructionCoe"])
        coe = Path(coe_raw)
        if not coe.is_absolute():
            coe = root / coe
        wdb = find_wave_db(run_dir, info)
        case_fig_dir = root / "report" / "lab10-11" / "figures" / case
        run_id = info.get("RUN_ID", run_dir.name)
        configs = run_wcfgs(case_fig_dir, run_id)
        trace_records = info.get("TRACE_RECORDS_COMPARED") or info.get("TRACE_RECORDS", "")
        sim_log = run_dir / "simulate.log"
        run_source = run_dir / "source-manifest.csv"
        xpr = info.get("PROJECT_XPR", cfg[case].get("ProjectXpr", ""))
        if not xpr:
            xpr = cfg[case].get("ProjectXpr", "")
        selected_wcfgs = {repo_path(root, path) for path in configs}
        wcfg_statuses = [row.get("validation_status", "")
                         for row in csv_rows(root / "report/lab10-11/data/waveform_validation.csv")
                         if row.get("run_id") == run_id and row.get("wcfg_file") in selected_wcfgs]
        waveform_validation = "PASS" if len(wcfg_statuses) == len(theme_rows(case)) and all(
            value == "PASS" for value in wcfg_statuses) else ("INCOMPLETE" if wdb else "NOT_RUN")
        notes = info.get("ERROR_REASON", "")
        if not notes and result_status == "PASS" and not wdb:
            notes = "Functional run passed; WDB not captured for this run."
        rows.append({
            "case": case, "run_id": run_id, "suite": info.get("SUITE", ""),
            "source_commit": info.get("SOURCE_COMMIT", input_row.get("source_commit", baseline.get("SOURCE_COMMIT", ""))),
            "source_dirty": info.get("SOURCE_DIRTY", input_row.get("source_dirty", baseline.get("SOURCE_DIRTY", ""))),
            "source_diff_sha256": info.get("SOURCE_DIFF_SHA256", input_row.get("source_diff_sha256", baseline.get("SOURCE_DIFF_SHA256", ""))),
            "build_status": "PASS" if result_status == "PASS" and info.get("SIM_EXIT_CODE", "0") == "0" else result_status,
            "functional_status": info.get("FUNCTIONAL_STATUS", result_status),
            "protocol_status": info.get("PROTOCOL_STATUS", "NOT_RECORDED"),
            "overall_status": result_status,
            "expected_points": info.get("EXPECTED_FUNCTIONAL_POINTS", str(cfg[case]["ExpectedFunctionalPoints"])),
            "actual_points": info.get("ACTUAL_FUNCTIONAL_POINTS", info.get("FUNCTIONAL_POINTS", "")),
            "trace_compare_status": info.get("TRACE_COMPARE_STATUS", "PASS" if info.get("TRACE_RECORDS") else "NOT_RUN"),
            "trace_records": trace_records,
            "project_xpr": repo_path(root, xpr), "rtl_manifest": repo_path(root, run_source) if run_source.is_file() else "",
            "inst_mif": repo_path(root, mif), "inst_mif_sha256": sha256(mif) if mif.is_file() else "",
            "inst_coe": repo_path(root, coe), "inst_coe_sha256": sha256(coe) if coe.is_file() else "",
            "reference_trace": repo_path(root, trace), "reference_sha256": sha256(trace) if trace.is_file() else "",
            "vivado_version": info.get("VIVADO_VERSION", (run_dir / "vivado-version.txt").read_text(encoding="utf-8", errors="replace").splitlines()[0] if (run_dir / "vivado-version.txt").is_file() else ""),
            "wdb_file": repo_path(root, wdb) if wdb else "", "wdb_sha256": sha256(wdb) if wdb else "",
            "wcfg_files": ";".join(repo_path(root, path) for path in configs),
            "wcfg_validation": waveform_validation, "sim_log": repo_path(root, sim_log) if sim_log.is_file() else "",
            "completed_utc": dt.datetime.fromtimestamp((run_dir / "result.txt").stat().st_mtime, dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
            "notes": notes,
        })
    return rows


def build_transaction_rows(runs) -> list[dict]:
    rows: list[dict] = []
    metrics_by_result = {
        "inst_req_accept": "INSTRUCTION_REQUESTS_ACCEPTED", "inst_data_complete": "INSTRUCTION_RESPONSES_CONSUMED",
        "load_req_accept": "DATA_READ_REQUESTS_ACCEPTED", "load_data_complete": "DATA_READ_RESPONSES_CONSUMED",
        "store_req_accept": "DATA_WRITE_REQUESTS_ACCEPTED", "store_data_complete": "DATA_WRITE_COMPLETIONS",
        "ar_handshakes": "AR_HANDSHAKES", "r_handshakes": "R_HANDSHAKES",
        "aw_handshakes": "AW_HANDSHAKES", "w_handshakes": "W_HANDSHAKES", "b_handshakes": "B_HANDSHAKES",
        "stale_fetch_drops": "STALE_FETCH_RESPONSES_DROPPED",
    }
    for case, run_dir, info in runs:
        metrics = parse_metrics(run_dir / "simulate.log")
        record: dict[str, object] = {"case": case, "run_id": info.get("RUN_ID", run_dir.name)}
        for name, result_key in metrics_by_result.items():
            record[name] = metrics.get(name, info.get(result_key, ""))
        record["duplicate_store_count"] = info.get("DUPLICATE_STORE_COUNT", "")
        record["protocol_assertions_failed"] = info.get("PROTOCOL_ASSERTS_FAIL", "")
        record["deadlock_watchdogs"] = info.get("DEADLOCK_WATCHDOGS", "")
        if info.get("STATUS") != "PASS":
            record["summary_status"] = info.get("STATUS", "INCOMPLETE")
        elif metrics:
            pairs = (("load_req_accept", "load_data_complete"), ("store_req_accept", "store_data_complete"))
            record["summary_status"] = "PASS" if all(metrics.get(left) == metrics.get(right) for left, right in pairs) else "MISMATCH"
        else:
            record["summary_status"] = "NOT_INSTRUMENTED"
        rows.append(record)
    return rows


def write_outputs(root: Path, runs, cfg: dict[str, dict], vivado: Path | None,
                  target_case: str | None, target_run: str | None, attempt: int) -> None:
    data_dir = root / "report" / "lab10-11" / "data"
    data_dir.mkdir(parents=True, exist_ok=True)
    validation_rows: list[dict] = []
    wave_rows: list[dict] = []
    if target_case and target_run:
        selected = [(case, path, info) for case, path, info in runs
                    if case == target_case and info.get("RUN_ID", path.name) == target_run]
        if not selected:
            raise ValueError(f"run not found: {target_case}/{target_run}")
        for case, run_dir, info in selected:
            made_wave_rows, made_validation_rows, anchors = make_wcfgs(root, case, run_dir, info, vivado, attempt)
            # Filled below after paths and run inputs are resolved.
            wave_rows.extend(make_wave_rows_for_run(root, case, run_dir, info, cfg, anchors,
                                                    made_validation_rows, attempt))
            validation_rows.extend(made_validation_rows)
            print(f"WDB={find_wave_db(run_dir, info) or ''}")
            print(f"ANCHORS={json.dumps(anchors, ensure_ascii=False, sort_keys=True)}")
    existing_wave_validation = csv_rows(data_dir / "waveform_validation.csv")
    if validation_rows:
        validation_index = {(row["run_id"], row["wcfg_file"]): row for row in existing_wave_validation}
        for row in validation_rows:
            validation_index[(row["run_id"], row["wcfg_file"])] = row
        existing_wave_validation = list(validation_index.values())
        write_csv(data_dir / "waveform_validation.csv", WAVE_VALIDATION_FIELDS, existing_wave_validation)
    elif not (data_dir / "waveform_validation.csv").exists():
        write_csv(data_dir / "waveform_validation.csv", WAVE_VALIDATION_FIELDS, [])
    if wave_rows:
        existing_wave = csv_rows(data_dir / "wave-capture-log.csv")
        wave_index = {(row["case"], row["run_id"], row["figure_id"]): row for row in existing_wave}
        for row in wave_rows:
            wave_index[(row["case"], row["run_id"], row["figure_id"])] = row
        write_csv(data_dir / "wave-capture-log.csv", WAVE_FIELDS, list(wave_index.values()))
    elif not (data_dir / "wave-capture-log.csv").exists():
        write_csv(data_dir / "wave-capture-log.csv", WAVE_FIELDS, [])
    write_csv(data_dir / "evidence_index.csv", EVIDENCE_FIELDS, build_evidence_rows(root, runs, cfg))
    write_csv(data_dir / "transaction-summary.csv", TRANSACTION_FIELDS, build_transaction_rows(runs))
    print(f"EVIDENCE_INDEX={data_dir / 'evidence_index.csv'}")
    print(f"TRANSACTION_SUMMARY={data_dir / 'transaction-summary.csv'}")
    print(f"WAVE_CAPTURE_LOG={data_dir / 'wave-capture-log.csv'}")
    print(f"WAVEFORM_VALIDATION={data_dir / 'waveform_validation.csv'}")


def make_wave_rows_for_run(root: Path, case: str, run_dir: Path, info: dict[str, str],
                           cfg: dict[str, dict], anchors: dict[str, dict[str, str]],
                           validation_rows: list[dict], attempt: int) -> list[dict]:
    wdb = find_wave_db(run_dir, info)
    if not wdb:
        return []
    trace, mif, trace_pcs, base, words = mips_context(root, case, run_dir, info, cfg)
    run_id = info.get("RUN_ID", run_dir.name)
    wdb_hash = sha256(wdb)
    themes = theme_rows(case)
    rows: list[dict] = []
    for theme, validation in zip(themes, validation_rows):
        target_signal_suffix, search_value, raw_anchor = get_pc_event(case, theme, anchors)
        target_pc = ""
        if theme["event"] in {"fetch", "load", "store"}:
            target_pc = pc_from_anchor(anchors, str(theme["event"]))
        elif theme["event"] == "stale_drop":
            target_pc = pc_from_anchor(anchors, "stale_drop", "target") or pc_from_anchor(anchors, "redirect", "target")
        if target_pc:
            inst_name, word = decode_pc(target_pc, base, words)
            target_instruction = inst_name
        else:
            word = None
            target_instruction = ""
        if theme["event"] == "ar":
            target_pc = pc_from_anchor(anchors, "fetch")
            target_instruction, word = decode_pc(target_pc, base, words) if target_pc else ("", None)
        if theme["event"] == "backpressure":
            target_pc = ""
            selected_anchor = next((value for key, value in anchors.items() if key.startswith("backpressure_")), {})
            # search_signal is the channel VALID wire; the channel payload and
            # transaction ID remain available in search_context from BUS_ANCHOR.
            search_value = "1"
            target_instruction = ""
            channel = selected_anchor.get("channel", "")
            if channel:
                target_signal_suffix = {"AR": "soc_lite/cpu_arvalid", "R": "soc_lite/cpu_rvalid",
                                        "AW": "soc_lite/cpu_awvalid", "W": "soc_lite/cpu_wvalid",
                                        "B": "soc_lite/cpu_bvalid"}.get(channel, "")
        attempt_tag = "" if attempt == 1 else f"-v{attempt}"
        wcfg = root / "report" / "lab10-11" / "figures" / case / f"{theme['file']}__{run_id}{attempt_tag}.wcfg"
        signals = parse_wcfg_signals(wcfg)
        search_signal = next((path.replace("\\", "/") for path in signals
                              if target_signal_suffix and normalize_signal_path(path).endswith(
                                  normalize_signal_path(target_signal_suffix))), "")
        validation_status = validation.get("validation_status", "NOT_RUN")
        event_found = validation.get("target_event_found") == "true"
        proof_status = "PENDING_CAPTURE" if validation_status == "PASS" and event_found else "PENDING_CAPTURE"
        expected = str(theme["expected"])
        if word is not None and theme["event"] == "fetch":
            expected = f"instruction=0x{word:08x}"
        rows.append({
            "case": case, "run_id": run_id, "figure_id": theme["figure"],
            "png_filename": f"{theme['figure']}.png", "wdb_file": repo_path(root, wdb),
            "wdb_sha256": wdb_hash, "wcfg_file": repo_path(root, wcfg) if wcfg.is_file() else "",
            "wcfg_validation": validation_status, "inst_mif": repo_path(root, mif),
            "inst_mif_sha256": sha256(mif) if mif.is_file() else "",
            "reference_trace": repo_path(root, trace), "reference_sha256": sha256(trace) if trace.is_file() else "",
            "topic": theme["topic"], "target_instruction": target_instruction,
            "target_pc": target_pc, "search_signal": search_signal, "search_value": search_value,
            "search_context": f"{theme['context']}\n同次运行监视记录：{raw_anchor}" if raw_anchor else theme["context"],
            "required_signals": ";".join(path.replace("\\", "/") for path in signals),
            "expected": expected, "expected_source": theme["expected_source"], "observed": "",
            "time_start_ns": "", "time_end_ns": "", "proof_status": proof_status,
            "remarks": "需用户从对应 WDB/WCFG 截图；observed 与时间窗仅在 Wave 中实读后填写。" if validation_status == "PASS" else "WDB/WCFG 校验未完成；此行不能作为已可截图证据。",
        })
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--case", choices=("lab10", "lab11"))
    parser.add_argument("--run-id")
    parser.add_argument("--vivado-bin", type=Path)
    parser.add_argument("--attempt", type=int, default=1,
                        help="evidence creation attempt; later attempts use versioned paths and never overwrite files")
    args = parser.parse_args()
    root = args.repo_root.resolve()
    cfg = json.loads((root / "scripts" / "cases_bus.json").read_text(encoding="utf-8"))
    result_root = root / "results" / "lab10_lab11"
    runs = find_runs(root, result_root)
    if args.case and args.run_id is None:
        raise SystemExit("--run-id is required together with --case")
    if args.run_id and not args.case:
        raise SystemExit("--case is required together with --run-id")
    if args.attempt < 1:
        raise SystemExit("--attempt must be >= 1")
    vivado = args.vivado_bin.resolve() if args.vivado_bin else None
    if vivado and vivado.is_dir():
        vivado = vivado / "vivado.bat"
    if vivado and not vivado.is_file():
        raise SystemExit(f"Vivado executable not found: {vivado}")
    write_outputs(root, runs, cfg, vivado, args.case, args.run_id, args.attempt)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
