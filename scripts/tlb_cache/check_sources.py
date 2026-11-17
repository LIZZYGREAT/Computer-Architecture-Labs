#!/usr/bin/env python3
"""Capture the Lab13–Lab19 baseline source and program-input inventory.

This inventory describes candidate inputs only. It does not claim that a file
was active in an elaborated design; final runs must also retain Vivado's source
set/compile-order evidence.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import subprocess
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Tuple


SOURCE_SUFFIXES = {".v", ".sv", ".vh", ".svh", ".S", ".s", ".c", ".h", ".xpr", ".xci", ".xdc"}
INPUT_SUFFIXES = {".mif", ".coe", ".elf", ".bin"}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def _add_existing_files(
    root: Path,
    candidates: Dict[str, str],
    directory: str,
    suffixes: Iterable[str],
    role: str,
) -> None:
    base = root / directory
    if not base.is_dir():
        return
    normalized_suffixes = {suffix.lower() for suffix in suffixes}
    for path in sorted(base.rglob("*")):
        if path.is_file() and path.suffix.lower() in normalized_suffixes:
            candidates[path.relative_to(root).as_posix()] = role


def collect_candidates(root: Path) -> Tuple[Dict[str, str], List[Tuple[str, str]]]:
    candidates: Dict[str, str] = {}
    required = [
        ("lab13/tlb_verify/rtl/tlb_top.v", "official_wrapper"),
        ("lab13/tlb_verify/testbench/testbench.v", "official_testbench"),
        ("lab13/tlb_verify/run_vivado/tlb_verify/tlb_verify.xpr", "official_project"),
        ("lab13/tlb_verify/rtl/xilinx_ip/clk_pll.xci", "legacy_ip"),
        ("lab16/cache_verify/rtl/cache_top.v", "official_wrapper"),
        ("lab16/cache_verify/testbench/testbench.v", "official_testbench"),
        ("lab16/cache_verify/run_vivado/cache_verify/cache_verify.xpr", "official_project"),
        ("lab16/cache_verify/rtl/xilinx_ip/clk_pll.xci", "legacy_ip"),
        ("lab14/tlb_func/obj/inst_ram.mif", "lab14_image"),
        ("lab14/tlb_func/obj/inst_ram.coe", "lab14_image"),
        ("lab17/func_all94/obj/inst_ram.mif", "lab17_image"),
        ("lab17/func_all94/obj/inst_ram.coe", "lab17_image"),
        ("lab19/perf_func/obj/dhrystone/axi_ram.mif", "dhrystone_image"),
        ("lab19/perf_func/obj/coremark/axi_ram.mif", "coremark_image"),
        ("lab19/perf_func/include/asm/r4kcache.h", "cache_abi_header"),
    ]
    missing_required: List[Tuple[str, str]] = []
    for relative, role in required:
        if (root / relative).is_file():
            candidates[relative] = role
        else:
            missing_required.append((relative, role))

    for directory in (
        "lab13/tlb_verify/rtl",
        "lab13/tlb_verify/testbench",
        "lab13/tlb_verify/run_vivado/tlb_verify",
        "lab16/cache_verify/rtl",
        "lab16/cache_verify/testbench",
        "lab16/cache_verify/run_vivado/cache_verify",
        "lab14/tlb_func/rtl",
        "lab14/tlb_func/inst",
        "lab14/tlb_func/include",
        "lab17/func_all94",
        "lab19/cache_func",
        "lab19/perf_func/include",
    ):
        _add_existing_files(root, candidates, directory, SOURCE_SUFFIXES, "source_candidate")

    for directory in (
        "lab14/tlb_func/obj",
        "lab17/func_all94/obj",
        "lab19/cache_func/obj",
        "lab19/perf_func/obj/dhrystone",
        "lab19/perf_func/obj/coremark",
    ):
        _add_existing_files(root, candidates, directory, INPUT_SUFFIXES, "program_input")

    # The absence of these two modules is the known implementation gap at S0.
    expected_gaps = [
        (relative, role)
        for relative, role in (
            ("lab13/tlb_verify/rtl/tlb.v", "required_lab13_module"),
            ("lab16/cache_verify/rtl/cache.v", "required_lab16_module"),
        )
        if not (root / relative).is_file()
    ]
    return candidates, missing_required + expected_gaps


def git_value(root: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(root), *args],
        check=False,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip() if result.returncode == 0 else "UNAVAILABLE"


def write_csv(path: Path, rows: Sequence[dict], fields: Sequence[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def build_inventory(root: Path, run_dir: Path) -> int:
    candidates, gaps = collect_candidates(root)
    source_rows: List[dict] = []
    input_rows: List[dict] = []
    for relative, role in sorted(candidates.items()):
        path = root / relative
        row = {
            "path": relative,
            "role": role,
            "size_bytes": path.stat().st_size,
            "sha256": sha256_file(path),
        }
        target = input_rows if path.suffix.lower() in INPUT_SUFFIXES else source_rows
        target.append(row)

    gap_rows = [
        {
            "path": relative,
            "role": role,
            "status": "EXPECTED_MISSING_MODULE" if relative.endswith(("/tlb.v", "/cache.v")) else "MISSING_REQUIRED_INPUT",
        }
        for relative, role in gaps
    ]
    write_csv(run_dir / "source-candidate-manifest.csv", source_rows, ["path", "role", "size_bytes", "sha256"])
    write_csv(run_dir / "input_manifest.csv", input_rows, ["path", "role", "size_bytes", "sha256"])
    write_csv(run_dir / "gap-audit.csv", gap_rows, ["path", "role", "status"])

    branch = git_value(root, "branch", "--show-current")
    head = git_value(root, "rev-parse", "HEAD")
    status = git_value(root, "status", "--porcelain")
    lab14_tests = sorted((root / "lab14/tlb_func/inst").glob("n*.S"))
    lab19_tests = sorted((root / "lab19/cache_func/inst").glob("n*.S"))
    summary = [
        "CASE=S0_BASELINE",
        f"BRANCH={branch}",
        f"HEAD={head}",
        f"WORKTREE_CLEAN={str(not status).lower()}",
        f"SOURCE_CANDIDATE_COUNT={len(source_rows)}",
        f"PROGRAM_INPUT_COUNT={len(input_rows)}",
        f"LAB14_TEST_PROGRAM_COUNT={len(lab14_tests)}",
        f"LAB19_CACHE_TEST_PROGRAM_COUNT={len(lab19_tests)}",
        f"MISSING_REQUIRED_INPUT_COUNT={sum(row['status'] == 'MISSING_REQUIRED_INPUT' for row in gap_rows)}",
        f"EXPECTED_IMPLEMENTATION_GAP_COUNT={sum(row['status'] == 'EXPECTED_MISSING_MODULE' for row in gap_rows)}",
        "NOTE=Candidate inventory only; active files must be proven from the actual Vivado source set and compile order.",
    ]
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "baseline-summary.txt").write_text("\n".join(summary) + "\n", encoding="utf-8")
    return 1 if any(row["status"] == "MISSING_REQUIRED_INPUT" for row in gap_rows) else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--run-dir", type=Path, required=True)
    args = parser.parse_args()
    return build_inventory(args.repo_root.resolve(), args.run_dir.resolve())


if __name__ == "__main__":
    raise SystemExit(main())
