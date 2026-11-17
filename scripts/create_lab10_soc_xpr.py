#!/usr/bin/env python3
"""Create a writable Lab10 SoC simulation project with private IP XCI copies."""

from __future__ import annotations

import argparse
import os
import shutil
import uuid
import xml.etree.ElementTree as ET
from pathlib import Path


def xpr_path(project_dir: Path, source: Path) -> str:
    return "$PPRDIR/" + Path(os.path.relpath(source, project_dir)).as_posix()


def option(config: ET.Element, name: str, value: str) -> None:
    item = config.find(f"Option[@Name='{name}']")
    if item is None:
        item = ET.SubElement(config, "Option", {"Name": name})
    item.set("Val", value)


def patch_coe_path(xci: Path, coe_path: Path) -> None:
    tree = ET.parse(xci)
    matches = []
    for node in tree.iter():
        if node.tag.endswith("configurableElementValue") and any(
            key.endswith("referenceId") and value == "PARAM_VALUE.Coe_File"
            for key, value in node.attrib.items()
        ):
            matches.append(node)
    if len(matches) != 1:
        raise ValueError(f"expected one Coe_File setting in {xci}, found {len(matches)}")
    matches[0].text = coe_path.as_posix()
    ET.indent(tree, space="  ")
    tree.write(xci, encoding="UTF-8", xml_declaration=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--run-dir", type=Path, required=True)
    args = parser.parse_args()

    repo = args.repo_root.resolve()
    run_dir = args.run_dir.resolve()
    base_xpr = repo / "lab10/CPU_CDE_SRAM/mycpu_sram_verify/run_vivado/mycpu_prj1/mycpu_lab10_bus.xpr"
    project_dir = base_xpr.parent
    output_xpr = project_dir / f"mycpu_lab10_soc_directed_{run_dir.name}.xpr"
    ip_copy_dir = run_dir / "ip_sources"
    if output_xpr.exists():
        parser.error(f"refusing to overwrite an existing XPR: {output_xpr}")
    if not base_xpr.is_file():
        parser.error(f"base XPR is missing: {base_xpr}")
    if not run_dir.is_dir():
        parser.error(f"run directory is missing: {run_dir}")

    tree = ET.parse(base_xpr)
    root = tree.getroot()
    project = root.find("Project") if root.tag != "Project" else root
    if project is None:
        parser.error("XPR Project element was not found")
    project.set("Path", output_xpr.as_posix())

    configuration = root.find("Configuration")
    if configuration is None:
        parser.error("XPR Configuration element was not found")
    project_id = configuration.find("Option[@Name='Id']")
    if project_id is not None:
        project_id.set("Val", uuid.uuid4().hex)
    user_dir = "$PPRDIR/mycpu_lab10_soc_directed.ip_user_files"
    option(configuration, "IPUserFilesDir", user_dir)
    option(configuration, "IPStaticSourceDir", user_dir + "/ipstatic")

    file_sets = root.find("FileSets")
    if file_sets is None:
        parser.error("XPR FileSets element was not found")
    filesets_by_name = {item.get("Name"): item for item in file_sets.findall("FileSet")}
    design_set = filesets_by_name.get("sources_1")
    sim_set = filesets_by_name.get("sim_1")
    if design_set is None or sim_set is None:
        parser.error("sources_1 or sim_1 fileset is missing")

    sim_config = sim_set.find("Config")
    design_config = design_set.find("Config")
    if sim_config is None or design_config is None:
        parser.error("source or simulation fileset Config is missing")
    option(design_config, "TopModule", "soc_sram_lite_top")
    option(design_config, "TopAutoSet", "TRUE")
    option(sim_config, "TopModule", "tb_top")
    option(sim_config, "TopAutoSet", "TRUE")
    option(sim_config, "SrcSet", "sources_1")

    xci_map = {}
    for name in ("clk_pll", "data_ram", "inst_ram"):
        fileset = filesets_by_name.get(name)
        if fileset is None:
            parser.error(f"expected IP fileset is missing: {name}")
        file_nodes = fileset.findall("File")
        if len(file_nodes) != 1:
            parser.error(f"expected one XCI entry in {name}, found {len(file_nodes)}")
        source_rel = file_nodes[0].get("Path", "").replace("$PPRDIR/", "", 1)
        source_path = (project_dir / source_rel).resolve()
        if not source_path.is_file():
            parser.error(f"IP source XCI is missing: {source_path}")
        destination = ip_copy_dir / name / f"{name}.xci"
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_path, destination)
        if name == "inst_ram":
            coe = repo / "lab10/CPU_CDE_SRAM/soft/func_lab9/obj/inst_ram.coe"
            if not coe.is_file():
                parser.error(f"instruction image is missing: {coe}")
            patch_coe_path(destination, coe)
        file_nodes[0].set("Path", xpr_path(project_dir, destination))
        xci_map[name] = destination

    # The CPU's multiply/divide units are also generated IP. Keep private
    # XCI copies with the run so Vivado can create simulation products
    # without borrowing or modifying Lab3's project outputs.
    for name in ("lab6_mult33", "lab6_div32"):
        source_path = repo / "lab10/CPU_CDE_SRAM/mycpu_sram_verify/rtl/xilinx_ip" / name / f"{name}.xci"
        if not source_path.is_file():
            parser.error(f"independent CPU IP source is missing: {source_path}")
        destination = ip_copy_dir / name / f"{name}.xci"
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_path, destination)
        for file_node in list(design_set.findall("File")):
            current_path = file_node.get("Path", "")
            if current_path.endswith(f"/xilinx_ip/{name}/{name}.xci"):
                design_set.remove(file_node)
        append_file = ET.Element("File", {"Path": xpr_path(project_dir, destination)})
        info = ET.SubElement(append_file, "FileInfo")
        for used_in in ("synthesis", "implementation", "simulation"):
            ET.SubElement(info, "Attr", {"Name": "UsedIn", "Val": used_in})
        index = list(design_set).index(design_config)
        design_set.insert(index, append_file)
        xci_map[name] = destination

    tree.write(output_xpr, encoding="UTF-8", xml_declaration=True)
    print(f"PROJECT_XPR={output_xpr}")
    print(f"BASE_XPR={base_xpr}")
    print(f"PRIVATE_XCI_COUNT={len(xci_map)}")
    print(f"SIM_TOP={option_value(sim_config, 'TopModule')}")
    return 0


def option_value(config: ET.Element, name: str) -> str:
    item = config.find(f"Option[@Name='{name}']")
    return item.get("Val", "") if item is not None else ""


if __name__ == "__main__":
    raise SystemExit(main())
