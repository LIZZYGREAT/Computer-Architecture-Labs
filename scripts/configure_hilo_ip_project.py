#!/usr/bin/env python3
"""Add independent copies of the CPU multiplier/divider IP to a Lab10/11 XPR."""

from __future__ import annotations

import argparse
import hashlib
import re
import shutil
from pathlib import Path


IP_NAMES = ("lab6_mult33", "lab6_div32")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--case", choices=("lab10", "lab11"), required=True)
    args = parser.parse_args()

    repo = args.repo_root.resolve()
    if args.case == "lab10":
        case_root = repo / "lab10/CPU_CDE_SRAM/mycpu_sram_verify"
        project = case_root / "run_vivado/mycpu_prj1/mycpu_lab10_bus.xpr"
    else:
        case_root = repo / "lab11/CPU_CDE_AXI/mycpu_axi_verify"
        project = case_root / "run_vivado/mycpu_prj1/mycpu_lab11_bus.xpr"

    ip_root = case_root / "rtl/xilinx_ip"
    source_root = repo / "lab3/CPU_CDE/mycpu_verify/rtl/xilinx_ip"
    if not project.is_file():
        parser.error(f"project is missing: {project}")

    copied = []
    for name in IP_NAMES:
        source = source_root / name / f"{name}.xci"
        destination = ip_root / name / f"{name}.xci"
        if not source.is_file():
            parser.error(f"reference XCI is missing: {source}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists():
            if sha256(destination) != sha256(source):
                parser.error(f"refusing to replace a different local XCI: {destination}")
        else:
            shutil.copy2(source, destination)
        copied.append((name, destination))

    text = project.read_text(encoding="utf-8")
    if "<FileSet Name=\"sources_1\"" not in text:
        parser.error("sources_1 fileset was not found")

    missing_entries = []
    for name, _ in copied:
        expected_path = f"$PPRDIR/../../rtl/xilinx_ip/{name}/{name}.xci"
        if expected_path not in text:
            attrs = "".join(
                f'<Attr Name="UsedIn" Val="{stage}"/>'
                for stage in ("synthesis", "implementation", "simulation")
            )
            missing_entries.append(
                f'      <File Path="{expected_path}">\n'
                f'        <FileInfo>{attrs}</FileInfo>\n'
                f'      </File>'
            )

    if missing_entries:
        boundary = re.search(r'(<FileSet Name="sources_1"[^>]*>.*?)(      <Config>)', text, re.S)
        if not boundary:
            parser.error("cannot locate the sources_1 Config boundary")
        text = text[: boundary.start(2)] + "\n".join(missing_entries) + "\n" + text[boundary.start(2) :]
        with project.open("w", encoding="utf-8", newline="") as stream:
            stream.write(text)

    print(f"CASE={args.case}")
    print(f"PROJECT_XPR={project.relative_to(repo).as_posix()}")
    for name, destination in copied:
        print(f"IP_XCI={destination.relative_to(repo).as_posix()}")
        print(f"IP_SHA256={name}:{sha256(destination)}")
    print(f"XPR_ENTRIES={len(copied)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
