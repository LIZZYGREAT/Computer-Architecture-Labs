#!/usr/bin/env python3
"""Create a minimal, read-only-openable Vivado project for a bus unit test."""

from __future__ import annotations

import argparse
import os
import uuid
import xml.etree.ElementTree as ET
from pathlib import Path


def option(config: ET.Element, name: str, value: str) -> None:
    item = config.find(f"Option[@Name='{name}']")
    if item is None:
        item = ET.SubElement(config, "Option", {"Name": name})
    item.set("Val", value)


def xpr_path(project_dir: Path, source: Path) -> str:
    """Return Vivado's project-relative path spelling for a source file."""
    return "$PPRDIR/" + Path(os.path.relpath(source, project_dir)).as_posix()


def resolve_xpr_path(project_dir: Path, value: str) -> Path:
    value = value.replace("$PPRDIR", project_dir.as_posix()).replace("$PSRCDIR", project_dir.as_posix())
    return Path(os.path.normpath(value))


def append_source(fileset: ET.Element, source: Path, project_dir: Path, attrs: list[tuple[str, str]]) -> None:
    file_node = ET.Element("File", {"Path": xpr_path(project_dir, source)})
    info = ET.SubElement(file_node, "FileInfo")
    for name, value in attrs:
        ET.SubElement(info, "Attr", {"Name": name, "Val": value})

    # Vivado's XPR reader expects File entries before the fileset Config node.
    config = fileset.find("Config")
    index = list(fileset).index(config) if config is not None else len(fileset)
    fileset.insert(index, file_node)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-xpr", type=Path, required=True)
    parser.add_argument("--cpu-dir", type=Path, required=True)
    parser.add_argument("--design-top", default="if_stage")
    parser.add_argument("--sim-top", required=True)
    parser.add_argument("--sim-file", type=Path, action="append", required=True)
    parser.add_argument("--design-file", action="append", default=[])
    parser.add_argument("--preserve-fileset", action="append", default=[])
    parser.add_argument("--output-xpr", type=Path, required=True)
    args = parser.parse_args()

    base_xpr = args.base_xpr.resolve()
    cpu_dir = args.cpu_dir.resolve()
    output_xpr = args.output_xpr.resolve()
    if output_xpr.exists():
        parser.error(f"refusing to overwrite an existing XPR: {output_xpr}")
    if not base_xpr.is_file():
        parser.error(f"base project is missing: {base_xpr}")
    if not cpu_dir.is_dir():
        parser.error(f"CPU source directory is missing: {cpu_dir}")

    design_files = [Path(path).resolve() for path in args.design_file]
    sim_files = [Path(path).resolve() for path in args.sim_file]
    missing = [path for path in design_files + sim_files if not path.is_file()]
    if missing:
        parser.error("source files are missing: " + ", ".join(map(str, missing)))

    tree = ET.parse(base_xpr)
    root = tree.getroot()
    project = root.find("Project") if root.tag != "Project" else root
    if project is None:
        parser.error("XPR Project element was not found")
    project.set("Path", output_xpr.as_posix())

    configuration = root.find("Configuration")
    if configuration is not None:
        project_id = configuration.find("Option[@Name='Id']")
        if project_id is not None:
            project_id.set("Val", uuid.uuid4().hex)
        ip_user_dir = "$PPRDIR/" + output_xpr.stem + ".ip_user_files"
        option(configuration, "IPUserFilesDir", ip_user_dir)
        option(configuration, "IPStaticSourceDir", ip_user_dir + "/ipstatic")

    file_sets = root.find("FileSets")
    if file_sets is None:
        parser.error("FileSets element was not found")
    filesets_by_name = {item.get("Name"): item for item in file_sets.findall("FileSet")}
    design_set = filesets_by_name.get("sources_1")
    sim_set = filesets_by_name.get("sim_1")
    if design_set is None or sim_set is None:
        parser.error("sources_1 or sim_1 fileset was not found")

    # Keep the project's fileset and run scaffolding intact. Vivado expects
    # those named filesets to exist even when the isolated unit test does not
    # use their source files.
    preserve_filesets = set(args.preserve_fileset)
    for fileset in file_sets.findall("FileSet"):
        if fileset.get("Name") not in {"sources_1", "sim_1"}:
            if fileset.get("Name") in preserve_filesets:
                for file_node in fileset.findall("File"):
                    old_path = file_node.get("Path", "")
                    source = resolve_xpr_path(base_xpr.parent, old_path)
                    if not source.is_file():
                        parser.error(f"preserved fileset source is missing: {old_path} -> {source}")
                    file_node.set("Path", xpr_path(output_xpr.parent, source))
                continue
            for file_node in list(fileset.findall("File")):
                fileset.remove(file_node)

    for file_node in list(design_set.findall("File")):
        design_set.remove(file_node)
    for source in design_files:
        attrs = [
            ("UsedIn", "synthesis"),
            ("UsedIn", "implementation"),
            ("UsedIn", "simulation"),
        ]
        if source.name == "mycpu.h":
            attrs.append(("IsVisible", "1"))
        append_source(design_set, source, output_xpr.parent, attrs)

    design_config = design_set.find("Config")
    if design_config is None:
        design_config = ET.SubElement(design_set, "Config")
    option(design_config, "TopModule", args.design_top)
    option(design_config, "TopAutoSet", "TRUE")
    option(design_config, "VerilogIncludeDirs", xpr_path(output_xpr.parent, cpu_dir))

    for file_node in list(sim_set.findall("File")):
        sim_set.remove(file_node)
    for source in sim_files:
        append_source(
            sim_set,
            source,
            output_xpr.parent,
            [("UsedIn", "synthesis"), ("UsedIn", "implementation"), ("UsedIn", "simulation")],
        )

    sim_config = sim_set.find("Config")
    if sim_config is None:
        sim_config = ET.SubElement(sim_set, "Config")
    option(sim_config, "TopModule", args.sim_top)
    option(sim_config, "TopLib", "xil_defaultlib")
    option(sim_config, "TopAutoSet", "TRUE")
    option(sim_config, "SrcSet", "sources_1")
    option(sim_config, "VerilogIncludeDirs", xpr_path(output_xpr.parent, cpu_dir))

    output_xpr.parent.mkdir(parents=True, exist_ok=True)
    ET.indent(tree, space="  ")
    tree.write(output_xpr, encoding="UTF-8", xml_declaration=True)
    print(f"PROJECT_XPR={output_xpr}")
    print(f"DESIGN_SOURCE_COUNT={len(design_files)}")
    print(f"SIM_SOURCE_COUNT={len(sim_files)}")
    print(f"SIM_TOP={args.sim_top}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
