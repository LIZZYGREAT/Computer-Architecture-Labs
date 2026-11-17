#!/usr/bin/env python3
"""Capture a provenance-focused Lab10/Lab11 input baseline."""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import json
import re
import subprocess
from pathlib import Path

from source_provenance import parse_xpr


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


def scan_case(repo: Path, case_name: str, settings: dict[str, object], *,
              trace_override: Path | None = None, mif_override: Path | None = None,
              coe_override: Path | None = None, inst_override: bool = False) -> tuple[dict[str, str], list[dict[str, str]], list[str]]:
    """Scan configured inputs without assigning a Vivado or simulation result."""
    root = repo.resolve()
    paths = {
        "project_xpr": root / str(settings["BaseSocXpr"]),
        "instruction_coe": (coe_override or root / str(settings["InstructionCoe"])).resolve(),
        "instruction_mif": (mif_override or root / str(settings["InstructionMif"])).resolve(),
        "reference_trace": (trace_override or root / str(settings["ReferenceTrace"])).resolve(),
        "unit_testbench": root / str(settings["DirectedTestbench"]),
        "soc_creator": root / str(settings["SocCreator"]),
        "soc_runner": root / str(settings["SocRunner"]),
        "input_checker": root / "scripts/check_bus_inputs.py",
        "source_provenance": root / "scripts/source_provenance.py",
        "source_capture": root / "scripts/capture_bus_source_manifest.py",
        "project_preflight": root / "scripts/check_bus_project.tcl",
        "run_wrapper": root / "scripts/verify_bus.ps1",
    }
    if settings.get("UnitCreator"):
        paths["unit_creator"] = root / str(settings["UnitCreator"])
    paths["unit_runner"] = root / str(settings["UnitRunner"])
    if str(settings.get("UnitRunner", "")).endswith("run_lab11_axi3_directed.tcl"):
        paths["unit_project_creator"] = root / "scripts/create_bus_unit_xpr.py"

    issues: list[str] = []
    rows: list[dict[str, str]] = []

    def add(role: str, path: Path, basis: str, declared: bool = False) -> None:
        exists = path.is_file()
        relative = path.resolve(strict=False).relative_to(root).as_posix() if path.resolve(strict=False).is_relative_to(root) else path.resolve(strict=False).as_posix()
        rows.append({
            "case": case_name, "role": role, "path": relative,
            "exists": str(exists).lower(), "sha256": sha256(path) if exists else "MISSING",
            "source_basis": basis, "declared_in_base_xpr": str(declared).lower(),
        })
        if not exists:
            issues.append(f"{case_name}: missing {role}: {relative}")

    for role, path in paths.items():
        add(role, path, "INPUT_SCAN")
    cpu_source_dir = root / str(settings["CpuSourceDir"])
    if not cpu_source_dir.is_dir():
        issues.append(f"{case_name}: missing CPU source directory: {cpu_source_dir}")
    else:
        for candidate in sorted(cpu_source_dir.iterdir(), key=lambda item: item.name.lower()):
            if candidate.is_file() and candidate.suffix.lower() in {".v", ".sv", ".vh", ".h", ".inc"}:
                add("candidate_only", candidate, "CPU_SOURCE_CANDIDATE")

    xpr = paths["project_xpr"]
    if xpr.is_file():
        try:
            for entry in parse_xpr(xpr)["entries"]:
                path = Path(entry["path"]).resolve(strict=False)
                add("declared_in_base_xpr_candidate", path, f"BASE_XPR_{str(entry['fileset']).upper()}", True)
        except (OSError, ValueError) as exc:
            issues.append(f"{case_name}: cannot parse base XPR: {type(exc).__name__}: {exc}")
    declared_paths = {row["path"].casefold() for row in rows if row["declared_in_base_xpr"] == "true"}
    rows = [row for row in rows if not (
        row["role"] == "candidate_only" and row["path"].casefold() in declared_paths
    )]

    image_match = "NOT_VERIFIED"
    if paths["instruction_coe"].is_file() and paths["instruction_mif"].is_file():
        try:
            coe_words = parse_coe(paths["instruction_coe"])
            mif_words = parse_mif(paths["instruction_mif"])
            if inst_override:
                image_match = "NOT_APPLICABLE_OVERRIDE"
            else:
                image_match = str(coe_words == mif_words).upper()
                if coe_words != mif_words:
                    issues.append(f"{case_name}: instruction COE/MIF content differs")
        except (OSError, ValueError) as exc:
            image_match = "FAIL"
            issues.append(f"{case_name}: cannot parse instruction image: {type(exc).__name__}: {exc}")

    input_row = {
        "case": case_name,
        "xpr": paths["project_xpr"].resolve().relative_to(root).as_posix(),
        "coe_path": paths["instruction_coe"].resolve().relative_to(root).as_posix() if paths["instruction_coe"].resolve().is_relative_to(root) else paths["instruction_coe"].as_posix(),
        "coe_sha256": sha256(paths["instruction_coe"]) if paths["instruction_coe"].is_file() else "MISSING",
        "mif_path": paths["instruction_mif"].resolve().relative_to(root).as_posix() if paths["instruction_mif"].resolve().is_relative_to(root) else paths["instruction_mif"].as_posix(),
        "mif_sha256": sha256(paths["instruction_mif"]) if paths["instruction_mif"].is_file() else "MISSING",
        "trace_path": paths["reference_trace"].resolve().relative_to(root).as_posix() if paths["reference_trace"].resolve().is_relative_to(root) else paths["reference_trace"].as_posix(),
        "trace_sha256": sha256(paths["reference_trace"]) if paths["reference_trace"].is_file() else "MISSING",
        "image_match": image_match,
        "input_scan_status": "FAIL" if issues else "PASS",
    }
    return input_row, rows, issues


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--lab-root", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--case", choices=("lab10", "lab11"))
    parser.add_argument("--suite", choices=("directed", "full"), default="full")
    parser.add_argument("--run-id", default="input-scan")
    parser.add_argument("--coe", type=Path)
    parser.add_argument("--mif", type=Path)
    parser.add_argument("--trace", type=Path)
    parser.add_argument("--inst-override", action="store_true")
    parser.add_argument("--vivado-version", default="NOT_RUN")
    parser.add_argument("--ip-status", default="NOT_RUN")
    args = parser.parse_args()

    repo = args.repo_root.resolve()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    commit = subprocess.run(["git", "-C", str(repo), "rev-parse", "HEAD"], check=True,
                            capture_output=True, text=True).stdout.strip()
    status = subprocess.run(["git", "-C", str(repo), "status", "--porcelain=v1", "-uall"], check=True,
                            capture_output=True).stdout
    diff = subprocess.run(["git", "-C", str(repo), "--no-pager", "diff", "--no-textconv", "--binary", "HEAD", "--"], check=True,
                          capture_output=True).stdout
    diff_sha = hashlib.sha256(diff).hexdigest() if diff else "NONE"
    cases = json.loads((repo / "scripts/cases_bus.json").read_text(encoding="utf-8"))
    selected_cases = [args.case] if args.case else ["lab10", "lab11"]
    input_rows: list[dict[str, str]] = []
    scan_rows: list[dict[str, str]] = []
    issues: list[str] = []
    image_details: list[str] = []
    for case_name in selected_cases:
        settings = cases[case_name]
        trace_override = args.trace if case_name == args.case and args.trace else None
        mif_override = args.mif if case_name == args.case and args.mif else None
        coe_override = args.coe if case_name == args.case and args.coe else None
        row, found_rows, case_issues = scan_case(
            repo, case_name, settings, trace_override=trace_override,
            mif_override=mif_override, coe_override=coe_override,
            inst_override=args.inst_override and case_name == args.case,
        )
        input_rows.append(row)
        scan_rows.extend(found_rows)
        issues.extend(case_issues)
        image_details.extend([
            f"CASE={case_name}", f"COE_MIF_CONTENT_MATCH={row['image_match']}",
            f"COE_SHA256={row['coe_sha256']}", f"MIF_SHA256={row['mif_sha256']}",
        ])

    input_fields = ["case", "source_commit", "source_dirty", "source_diff_sha256", "xpr",
                    "coe_path", "coe_sha256", "mif_path", "mif_sha256", "trace_path",
                    "trace_sha256", "top_module", "sim_top", "vivado_version", "ip_status",
                    "preflight_status", "image_match", "trace_to_image_status", "input_scan_status"]
    top_names = {"lab10": "soc_sram_lite_top", "lab11": "soc_axi_lite_top"}
    for row in input_rows:
        case_name = row["case"]
        row.update({
            "source_commit": commit,
            "source_dirty": str(bool(status)).lower(),
            "source_diff_sha256": diff_sha,
            "top_module": top_names[case_name], "sim_top": "tb_top",
            "vivado_version": args.vivado_version, "ip_status": args.ip_status,
            "preflight_status": "NOT_RUN", "trace_to_image_status": "UNVERIFIED",
        })
    with (output / "input_manifest.csv").open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=input_fields)
        writer.writeheader()
        writer.writerows(input_rows)
    with (output / "input-scan-manifest.csv").open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=["case", "role", "path", "exists", "sha256",
                                                     "source_basis", "declared_in_base_xpr"])
        writer.writeheader()
        writer.writerows(scan_rows)
    (output / "image-content-check.txt").write_text("\n".join(image_details) + "\n", encoding="utf-8")
    scan_status = "FAIL" if issues else "PASS"
    timestamp = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    summary = [
        "STAGE=INPUT_SCAN", f"RUN_ID={args.run_id}",
        f"CASE={args.case or 'all'}", f"SUITE={args.suite}",
        f"INPUT_SCAN_STATUS={scan_status}", f"SCAN_TIMESTAMP_UTC={timestamp}",
        "SIMULATION_NOT_STARTED=true", f"SOURCE_COMMIT={commit}",
        f"SOURCE_DIRTY={str(bool(status)).lower()}", f"SOURCE_DIFF_SHA256={diff_sha}",
        f"SOURCE_DIFF_BYTES={len(diff)}",
        f"STATUS_LINES={len(status.decode('utf-8', errors='replace').splitlines())}",
    ]
    summary.extend(f"CASE_INPUT_SCAN={row['case']}:{row['input_scan_status']}" for row in input_rows)
    summary.extend(f"INPUT_SCAN_ERROR={issue}" for issue in issues)
    (output / "input-scan.txt").write_text("\n".join(summary) + "\n", encoding="utf-8")
    print(f"INPUT_SCAN_STATUS={scan_status}")
    print(f"INPUT_SCAN={output / 'input-scan.txt'}")
    return 0 if scan_status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
