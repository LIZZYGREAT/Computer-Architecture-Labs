#!/usr/bin/env python3
"""Hash the Vivado project files actually selected for a Lab13–Lab19 run."""

from __future__ import annotations

import argparse
import csv
import hashlib
import subprocess
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Tuple


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def parse_active_sources(path: Path) -> List[Tuple[str, str]]:
    fields = {"PROJECT_XPR": "vivado_project", "SOURCE": "design_source", "SIM_SOURCE": "simulation_source"}
    found: List[Tuple[str, str]] = []
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        key, separator, value = line.partition("=")
        if separator and key in fields and value.strip():
            found.append((fields[key], value.strip()))
    return found


def _write_csv(path: Path, rows: Sequence[dict], fields: Sequence[str]) -> None:
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def _git(root: Path, *args: str) -> str:
    result = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True, check=False)
    return result.stdout.strip() if result.returncode == 0 else "UNAVAILABLE"


def capture_run_manifest(
    repo_root: Path,
    run_dir: Path,
    active_source_file: Path | None = None,
    input_files: Iterable[Path] = (),
    reference_files: Iterable[Path] = (),
) -> bool:
    active_source_file = active_source_file or (run_dir / "active-sources.txt")
    sources = parse_active_sources(active_source_file) if active_source_file.is_file() else []
    rows: List[dict] = []
    missing: List[str] = []
    seen = set()
    for role, raw_path in sources:
        path = Path(raw_path).resolve()
        key = str(path).lower()
        if key in seen:
            continue
        seen.add(key)
        try:
            relative = path.relative_to(repo_root).as_posix()
        except ValueError:
            relative = str(path).replace("\\", "/")
        if not path.is_file():
            missing.append(str(path))
            continue
        rows.append({
            "path": relative,
            "role": role,
            "size_bytes": path.stat().st_size,
            "sha256": sha256_file(path),
        })

    run_dir.mkdir(parents=True, exist_ok=True)
    _write_csv(run_dir / "source-manifest.csv", rows, ["path", "role", "size_bytes", "sha256"])

    input_rows: List[dict] = []
    tagged_inputs = [(raw_path, "program_image") for raw_path in input_files]
    tagged_inputs.extend((raw_path, "reference_trace") for raw_path in reference_files)
    for raw_path, input_role in tagged_inputs:
        path = raw_path if raw_path.is_absolute() else (repo_root / raw_path)
        path = path.resolve()
        if not path.is_file():
            missing.append(str(path))
            continue
        try:
            relative = path.relative_to(repo_root).as_posix()
        except ValueError:
            relative = str(path).replace("\\", "/")
        input_rows.append({
            "path": relative,
            "role": input_role,
            "size_bytes": path.stat().st_size,
            "sha256": sha256_file(path),
            "status": "RECORDED",
        })
    if not input_rows:
        input_rows.append({"path": "N/A", "role": "no_external_image", "size_bytes": "", "sha256": "", "status": "NOT_REQUIRED"})
    _write_csv(run_dir / "input_manifest.csv", input_rows, ["path", "role", "size_bytes", "sha256", "status"])

    branch = _git(repo_root, "branch", "--show-current")
    head = _git(repo_root, "rev-parse", "HEAD")
    status = _git(repo_root, "status", "--short")
    git_lines = [f"BRANCH={branch}", f"HEAD={head}", "WORKTREE_STATUS_BEGIN", status or "CLEAN", "WORKTREE_STATUS_END"]
    (run_dir / "git-head.txt").write_text("\n".join(git_lines) + "\n", encoding="utf-8")

    integrity_status = "PASS" if sources and not missing else "FAIL"
    integrity_lines = [
        f"SOURCE_INTEGRITY={integrity_status}",
        f"ACTIVE_PROJECT_FILE_COUNT={len(rows)}",
        f"MISSING_ACTIVE_FILE_COUNT={len(missing)}",
        f"ACTIVE_SOURCE_LIST={active_source_file.name}",
    ]
    integrity_lines.extend(f"MISSING={path}" for path in missing)
    (run_dir / "source-integrity.txt").write_text("\n".join(integrity_lines) + "\n", encoding="utf-8")

    result_path = run_dir / "result.txt"
    if result_path.is_file():
        existing = result_path.read_text(encoding="utf-8-sig")
        managed_keys = ("SOURCE_INTEGRITY=", "SOURCE_MANIFEST=", "INPUT_MANIFEST=", "GIT_HEAD=")
        base_lines = [line for line in existing.splitlines() if not line.startswith(managed_keys)]
        extra = [
            f"SOURCE_INTEGRITY={integrity_status}",
            f"SOURCE_MANIFEST=source-manifest.csv",
            f"INPUT_MANIFEST=input_manifest.csv",
            f"GIT_HEAD={head}",
        ]
        result_path.write_text("\n".join(base_lines + extra) + "\n", encoding="utf-8")
    return integrity_status == "PASS"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("--active-source-file", type=Path)
    parser.add_argument("--input-file", type=Path, action="append", default=[])
    parser.add_argument("--reference-file", type=Path, action="append", default=[])
    args = parser.parse_args()
    ok = capture_run_manifest(
        args.repo_root.resolve(),
        args.run_dir.resolve(),
        args.active_source_file,
        args.input_file,
        args.reference_file,
    )
    print(f"SOURCE_INTEGRITY={'PASS' if ok else 'FAIL'}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
