#!/usr/bin/env python3
"""Create a separate Vivado project file with an independent CPU source set."""

from __future__ import annotations

import argparse
import re
import uuid
from pathlib import Path


CPU_FILES = (
    "mycpu.h",
    "EXE_stage.v",
    "ID_stage.v",
    "IF_stage.v",
    "MEM_stage.v",
    "WB_stage.v",
    "alu.v",
    "cp0_reg.v",
    "hilo_unit.v",
    "mycpu_top.v",
    "regfile.v",
    "tools.v",
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--case", choices=("lab10", "lab11"), required=True)
    args = parser.parse_args()
    repo = args.repo_root.resolve()
    if args.case == "lab10":
        project_dir = repo / "lab10/CPU_CDE_SRAM/mycpu_sram_verify/run_vivado/mycpu_prj1"
        source_root = repo / "lab10/CPU_CDE_SRAM/mycpu_sram_verify/rtl/myCPU"
        original = project_dir / "mycpu.xpr"
        project_name = "mycpu_lab10_bus"
    else:
        project_dir = repo / "lab11/CPU_CDE_AXI/mycpu_axi_verify/run_vivado/mycpu_prj1"
        source_root = repo / "lab11/CPU_CDE_AXI/mycpu_axi_verify/rtl/myCPU"
        original = project_dir / "mycpu.xpr"
        project_name = "mycpu_lab11_bus"

    if not original.is_file():
        parser.error(f"original XPR is missing: {original}")
    missing = [name for name in CPU_FILES if not (source_root / name).is_file()]
    if missing:
        parser.error("CPU source copy is incomplete: " + ", ".join(missing))

    target = project_dir / f"{project_name}.xpr"
    if target.exists():
        parser.error(f"refusing to overwrite an existing project copy: {target}")

    text = original.read_text(encoding="utf-8")
    if "<FileSet Name=\"sources_1\"" not in text:
        parser.error("sources_1 fileset was not found")
    existing = set(re.findall(r'<File Path="\$PPRDIR/../../rtl/myCPU/([^\"]+)"', text, re.I))
    duplicates = sorted(set(CPU_FILES) & existing)
    if duplicates:
        parser.error("CPU sources are already present; review before continuing: " + ", ".join(duplicates))

    file_entries = []
    for filename in CPU_FILES:
        attrs = ['<Attr Name="UsedIn" Val="synthesis"/>',
                 '<Attr Name="UsedIn" Val="simulation"/>']
        if filename.endswith(".v"):
            attrs.insert(1, '<Attr Name="UsedIn" Val="implementation"/>')
        if filename == "mycpu.h":
            attrs.append('<Attr Name="IsVisible" Val="1"/>')
        file_entries.append(
            f'      <File Path="$PPRDIR/../../rtl/myCPU/{filename}">\n'
            f'        <FileInfo>{"".join(attrs)}</FileInfo>\n'
            f'      </File>'
        )

    source_set = re.search(r'(<FileSet Name="sources_1"[^>]*>.*?)(      <Config>)', text, re.S)
    if not source_set:
        parser.error("cannot locate the sources_1 Config boundary")
    text = text[:source_set.start(2)] + "\n".join(file_entries) + "\n" + text[source_set.start(2):]
    new_path = target.resolve().as_posix()
    text, path_count = re.subn(r'(<Project\b[^>]*\bPath=")[^\"]*("[^>]*>)',
                               lambda match: match.group(1) + new_path + match.group(2), text, count=1)
    if path_count != 1:
        parser.error("could not update the copied project's Path attribute")
    text, id_count = re.subn(r'(<Option Name="Id" Val=")[^\"]*("/>)',
                             lambda match: match.group(1) + uuid.uuid4().hex + match.group(2), text, count=1)
    if id_count != 1:
        parser.error("could not create a unique project id")
    if args.case == "lab10":
        text = text.replace(
            '$PPRDIR/../../../../ucas_CDE_axi_ref/mycpu_axi_verify/run_vivado/mycpu_prj1/mycpu.ip_user_files',
            f"$PPRDIR/{project_name}.ip_user_files",
        )
        text = text.replace(
            '$PPRDIR/../../../../ucas_CDE_axi_ref/mycpu_axi_verify/run_vivado/mycpu_prj1/mycpu.ip_user_files/ipstatic',
            f"$PPRDIR/{project_name}.ip_user_files/ipstatic",
        )

    target.write_text(text, encoding="utf-8")
    print(f"CASE={args.case}")
    print(f"ORIGINAL_XPR={original.relative_to(repo).as_posix()}")
    print(f"PROJECT_XPR={target.relative_to(repo).as_posix()}")
    print(f"CPU_SOURCE_COUNT={len(CPU_FILES)}")
    print(f"PROJECT_COPY_ONLY=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
