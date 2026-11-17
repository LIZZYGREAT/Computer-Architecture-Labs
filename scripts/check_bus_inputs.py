#!/usr/bin/env python3
"""Capture a provenance-focused Lab10/Lab11 input baseline."""

from __future__ import annotations

import argparse
import csv
import hashlib
import re
import subprocess
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def parse_coe(path: Path) -> list[int]:
    text = path.read_text(encoding="ascii", errors="strict")
    radix_match = re.search(r"memory_initialization_radix\s*=\s*(\d+)\s*;", text, re.I)
    vector_match = re.search(r"memory_initialization_vector\s*=\s*(.*)\Z", text, re.I | re.S)
    if not radix_match or not vector_match:
        raise ValueError(f"COE header/vector not recognized: {path}")
    radix = int(radix_match.group(1))
    if radix not in (2, 10, 16):
        raise ValueError(f"unsupported COE radix {radix}: {path}")
    tokens = [token for token in re.split(r"[\s,;]+", vector_match.group(1).strip()) if token]
    return [int(token, radix) for token in tokens]


def parse_mif(path: Path) -> list[int]:
    values: list[int] = []
    for line_number, raw in enumerate(path.read_text(encoding="ascii", errors="strict").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("--") or line.startswith("#"):
            continue
        if ":" in line:
            _, line = line.split(":", 1)
        line = line.rstrip(";,").strip()
        if not line:
            continue
        if re.fullmatch(r"[01]{32}", line):
            values.append(int(line, 2))
        elif re.fullmatch(r"[0-9a-fA-F]{8}", line):
            values.append(int(line, 16))
        else:
            raise ValueError(f"unrecognized MIF word at {path}:{line_number}: {line[:80]}")
    return values


def file_info(root: Path, relative: str) -> tuple[str, str]:
    path = root / relative
    return (relative, sha256(path) if path.is_file() else "MISSING")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--lab-root", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--vivado-version", default="NOT_RUN")
    parser.add_argument("--ip-status", default="NOT_RUN")
    args = parser.parse_args()

    repo = args.repo_root.resolve()
    lab = args.lab_root.resolve()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    relative_lab = lab.relative_to(repo).as_posix()
    commit = subprocess.run(["git", "-C", str(repo), "rev-parse", "HEAD"], check=True,
                            capture_output=True, text=True).stdout.strip()
    status = subprocess.run(["git", "-C", str(repo), "status", "--porcelain=v1", "-uall"], check=True,
                            capture_output=True).stdout
    diff = subprocess.run(["git", "-C", str(repo), "--no-pager", "diff", "--no-textconv", "--binary", "HEAD", "--"], check=True,
                          capture_output=True).stdout
    diff_sha = hashlib.sha256(diff).hexdigest() if diff else "NONE"

    image = f"{relative_lab}/lab9/func_lab9/obj/inst_ram"
    coe = repo / f"{image}.coe"
    mif = repo / f"{image}.mif"
    trace10 = repo / f"{relative_lab}/lab10/CPU_CDE_SRAM/cpu132_gettrace/golden_trace.txt"
    trace11 = repo / f"{relative_lab}/lab11/CPU_CDE_AXI/cpu132_gettrace/golden_trace.txt"
    coe_words: list[int] = []
    mif_words: list[int] = []
    try:
        coe_words = parse_coe(coe)
        mif_words = parse_mif(mif)
        image_match = coe_words == mif_words
        image_detail = (f"COE_WORDS={len(coe_words)}\nMIF_WORDS={len(mif_words)}\n"
                        f"COE_MIF_CONTENT_MATCH={'true' if image_match else 'false'}\n"
                        f"COE_FIRST_WORDS={' '.join(f'{word:08x}' for word in coe_words[:8])}\n"
                        f"MIF_FIRST_WORDS={' '.join(f'{word:08x}' for word in mif_words[:8])}\n")
    except Exception as exc:  # preserve exact failure as baseline evidence
        image_match = False
        image_detail = f"COE_MIF_CONTENT_MATCH=NOT_VERIFIED\nCOE_MIF_ERROR={type(exc).__name__}: {exc}\n"
    (output / "image-content-check.txt").write_text(image_detail, encoding="utf-8")

    cases = [
        ("lab10", "lab10/CPU_CDE_SRAM/mycpu_sram_verify/run_vivado/mycpu_prj1/mycpu.xpr",
         "lab10/CPU_CDE_SRAM/soft/func_lab9/obj/inst_ram.coe",
         "lab10/CPU_CDE_SRAM/soft/func_lab9/obj/inst_ram.mif", trace10,
         "soc_sram_lite_top", "tb_top"),
        ("lab11", "lab11/CPU_CDE_AXI/mycpu_axi_verify/run_vivado/mycpu_prj1/mycpu.xpr",
         "lab11/CPU_CDE_AXI/soft/func_lab9/obj/inst_ram.coe",
         "lab11/CPU_CDE_AXI/soft/func_lab9/obj/inst_ram.mif", trace11,
         "soc_axi_lite_top", "tb_top"),
    ]
    fields = ["case", "source_commit", "source_dirty", "source_diff_sha256", "xpr",
              "coe_path", "coe_sha256", "mif_path", "mif_sha256", "trace_path",
              "trace_sha256", "top_module", "sim_top", "vivado_version", "ip_status",
              "preflight_status", "image_match", "trace_to_image_status"]
    with (output / "input_manifest.csv").open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for case, xpr, coe_rel, mif_rel, trace, top, sim_top in cases:
            source_prefix = f"{relative_lab}/"
            resolved_coe = (lab / coe_rel) if (lab / coe_rel).is_file() else coe
            resolved_mif = (lab / mif_rel) if (lab / mif_rel).is_file() else mif
            trace_hash = sha256(trace) if trace.is_file() else "MISSING"
            writer.writerow({
                "case": case,
                "source_commit": commit,
                "source_dirty": str(bool(status)).lower(),
                "source_diff_sha256": diff_sha,
                "xpr": f"{source_prefix}{xpr}",
                "coe_path": resolved_coe.relative_to(repo).as_posix(),
                "coe_sha256": sha256(resolved_coe) if resolved_coe.is_file() else "MISSING",
                "mif_path": resolved_mif.relative_to(repo).as_posix(),
                "mif_sha256": sha256(resolved_mif) if resolved_mif.is_file() else "MISSING",
                "trace_path": trace.relative_to(repo).as_posix(),
                "trace_sha256": trace_hash,
                "top_module": top,
                "sim_top": sim_top,
                "vivado_version": args.vivado_version,
                "ip_status": args.ip_status,
                "preflight_status": "INCOMPLETE",
                "image_match": str(image_match).upper(),
                "trace_to_image_status": "UNVERIFIED",
            })

    source_rows: list[dict[str, str]] = []
    for case, project, soc, wrappers, ips, testbench, trace in [
        ("lab10", "lab10/CPU_CDE_SRAM/mycpu_sram_verify/run_vivado/mycpu_prj1/mycpu.xpr",
         ["lab10/CPU_CDE_SRAM/mycpu_sram_verify/rtl/soc_sram_lite_top.v"],
         ["lab10/CPU_CDE_SRAM/mycpu_sram_verify/rtl/BRIDGE/bridge_1x2.v",
          "lab10/CPU_CDE_SRAM/mycpu_sram_verify/rtl/ram_wrap/sram_wrap.v",
          "lab10/CPU_CDE_SRAM/mycpu_sram_verify/rtl/CONFREG/confreg.v"],
         ["lab10/CPU_CDE_SRAM/mycpu_sram_verify/rtl/xilinx_ip/inst_ram/inst_ram.xci",
          "lab10/CPU_CDE_SRAM/mycpu_sram_verify/rtl/xilinx_ip/data_ram/data_ram.xci",
          "lab10/CPU_CDE_SRAM/mycpu_sram_verify/rtl/xilinx_ip/clk_pll/clk_pll.xci"],
         "lab10/CPU_CDE_SRAM/mycpu_sram_verify/testbench/mycpu_tb.v",
         "lab10/CPU_CDE_SRAM/cpu132_gettrace/golden_trace.txt"),
        ("lab11", "lab11/CPU_CDE_AXI/mycpu_axi_verify/run_vivado/mycpu_prj1/mycpu.xpr",
         ["lab11/CPU_CDE_AXI/mycpu_axi_verify/rtl/soc_axi_lite_top.v"],
         ["lab11/CPU_CDE_AXI/mycpu_axi_verify/rtl/axi_wrap/axi_wrap.v",
          "lab11/CPU_CDE_AXI/mycpu_axi_verify/rtl/ram_wrap/axi_wrap_ram.v",
          "lab11/CPU_CDE_AXI/mycpu_axi_verify/rtl/CONFREG/confreg.v"],
         ["lab11/CPU_CDE_AXI/mycpu_axi_verify/rtl/xilinx_ip/axi_ram/axi_ram.xci",
          "lab11/CPU_CDE_AXI/mycpu_axi_verify/rtl/xilinx_ip/axi_crossbar_1x2/axi_crossbar_1x2.xci",
          "lab11/CPU_CDE_AXI/mycpu_axi_verify/rtl/xilinx_ip/clk_pll/clk_pll.xci"],
         "lab11/CPU_CDE_AXI/mycpu_axi_verify/testbench/mycpu_tb.v",
         "lab11/CPU_CDE_AXI/cpu132_gettrace/golden_trace.txt"),
    ]:
        entries = [("project", project), ("testbench", testbench), ("reference_trace", trace)]
        entries += [("soc", path) for path in soc]
        entries += [("wrapper", path) for path in wrappers]
        entries += [("ip_configuration", path) for path in ips]
        entries += [("instruction_coe_source", "lab9/func_lab9/obj/inst_ram.coe"),
                    ("instruction_mif_source", "lab9/func_lab9/obj/inst_ram.mif")]
        for role, relative in entries:
            source = lab / relative
            source_rows.append({"case": case, "role": role, "path": f"{relative_lab}/{relative}",
                                "exists": str(source.is_file()).lower(),
                                "sha256": sha256(source) if source.is_file() else "MISSING"})
    source_rows.extend(
        {"case": "shared", "role": "baseline_cpu_source", "path": f"{relative_lab}/lab3/CPU_CDE/mycpu_verify/rtl/myCPU/{file_name}",
         "exists": str((lab / "lab3/CPU_CDE/mycpu_verify/rtl/myCPU" / file_name).is_file()).lower(),
         "sha256": sha256(lab / "lab3/CPU_CDE/mycpu_verify/rtl/myCPU" / file_name)
         if (lab / "lab3/CPU_CDE/mycpu_verify/rtl/myCPU" / file_name).is_file() else "MISSING"}
        for file_name in sorted(path.name for path in (lab / "lab3/CPU_CDE/mycpu_verify/rtl/myCPU").glob("*"))
        if (lab / "lab3/CPU_CDE/mycpu_verify/rtl/myCPU" / file_name).is_file()
    )
    with (output / "source-manifest.csv").open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=["case", "role", "path", "exists", "sha256"])
        writer.writeheader()
        writer.writerows(source_rows)

    summary = [
        f"SOURCE_COMMIT={commit}",
        f"SOURCE_DIRTY={str(bool(status)).lower()}",
        f"SOURCE_DIFF_SHA256={diff_sha}",
        f"SOURCE_DIFF_BYTES={len(diff)}",
        f"STATUS_LINES={len(status.decode('utf-8', errors='replace').splitlines())}",
        f"VIVADO_VERSION={args.vivado_version}",
        f"IP_STATUS={args.ip_status}",
        f"COE_MIF_CONTENT_MATCH={str(image_match).upper()}",
        f"GOLDEN_TRACE_FILES_IDENTICAL={str(trace10.is_file() and trace11.is_file() and sha256(trace10) == sha256(trace11)).upper()}",
        "GOLDEN_TRACE_TO_CURRENT_IMAGE=UNVERIFIED",
        "RTL_COPY_STATUS=NOT_STARTED",
        "SIMULATION_STATUS=NOT_RUN",
        "OVERALL_STATUS=INCOMPLETE",
    ]
    (output / "preflight.txt").write_text("\n".join(summary) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
