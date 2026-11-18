#!/usr/bin/env python3
"""Write the authoritative run result after simulation and integrity checks."""

from __future__ import annotations

import argparse
import os
import tempfile
from pathlib import Path
from typing import Iterable


MANAGED_PREFIXES = (
    "STATUS=",
    "SIMULATION_STATUS=",
    "SOURCE_INTEGRITY=",
    "SOURCE_MANIFEST=",
    "INPUT_MANIFEST=",
    "GIT_HEAD=",
    "SIMULATOR_CPU_MS=",
    "VIVADO_EXIT_CODE=",
    "VIVADO_PROCESS_STATUS=",
)


def _read_key(path: Path, key: str) -> str | None:
    if not path.is_file():
        return None
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        name, separator, value = line.partition("=")
        if separator and name == key:
            return value.strip()
    return None


def _write_atomic(path: Path, lines: Iterable[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", newline="\n", dir=path.parent,
            prefix=f".{path.name}.", suffix=".tmp", delete=False
        ) as stream:
            temporary_path = Path(stream.name)
            stream.write("\n".join(lines) + "\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_path, path)
    finally:
        if temporary_path is not None and temporary_path.exists():
            temporary_path.unlink()


def finalize_run_result(
    run_dir: Path,
    simulation_result: Path,
    requested_integrity: str,
    simulator_cpu_ms: str | None = None,
    vivado_exit_code: int = 0,
) -> bool:
    run_dir = run_dir.resolve()
    simulation_result = simulation_result.resolve()
    if not simulation_result.is_file():
        raise FileNotFoundError(f"simulation result is missing: {simulation_result}")

    raw_lines = simulation_result.read_text(encoding="utf-8-sig").splitlines()
    simulation_status = _read_key(simulation_result, "STATUS") or "NOT_PASS"
    captured_integrity = _read_key(run_dir / "source-integrity.txt", "SOURCE_INTEGRITY")
    integrity_status = "PASS" if requested_integrity == "PASS" and captured_integrity == "PASS" else "FAIL"
    final_status = (
        "PASS"
        if simulation_status == "PASS" and integrity_status == "PASS" and vivado_exit_code == 0
        else "INCOMPLETE"
    )

    lines = [line for line in raw_lines if not line.startswith(MANAGED_PREFIXES)]
    lines.extend((
        f"STATUS={final_status}",
        f"SIMULATION_STATUS={simulation_status}",
        f"SOURCE_INTEGRITY={integrity_status}",
        f"VIVADO_EXIT_CODE={vivado_exit_code}",
        f"VIVADO_PROCESS_STATUS={'PASS' if vivado_exit_code == 0 else 'FAIL'}",
        "SOURCE_MANIFEST=source-manifest.csv",
        "INPUT_MANIFEST=input_manifest.csv",
    ))
    head = _read_key(run_dir / "git-head.txt", "HEAD")
    if head:
        lines.append(f"GIT_HEAD={head}")
    if simulator_cpu_ms is not None:
        lines.append(f"SIMULATOR_CPU_MS={simulator_cpu_ms}")
    _write_atomic(run_dir / "result.txt", lines)
    return final_status == "PASS"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("--simulation-result", type=Path, required=True)
    parser.add_argument("--source-integrity", choices=("PASS", "FAIL"), required=True)
    parser.add_argument("--simulator-cpu-ms")
    parser.add_argument("--vivado-exit-code", type=int, required=True)
    args = parser.parse_args()
    ok = finalize_run_result(
        args.run_dir, args.simulation_result, args.source_integrity,
        args.simulator_cpu_ms, args.vivado_exit_code
    )
    print(f"STATUS={'PASS' if ok else 'INCOMPLETE'}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
