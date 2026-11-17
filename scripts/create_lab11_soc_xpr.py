#!/usr/bin/env python3
"""Create an isolated Lab11 SoC XPR with private IP XCI copies."""

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


def find_coe_setting(root: ET.Element) -> ET.Element:
    matches = []
    for node in root.iter():
        if node.tag.endswith("configurableElementValue") and any(
            key.endswith("referenceId") and value == "PARAM_VALUE.Coe_File"
            for key, value in node.attrib.items()
        ):
            matches.append(node)
    if len(matches) != 1:
        raise ValueError(f"expected one Coe_File setting, found {len(matches)}")
    return matches[0]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("--inst-coe", type=Path)
    args = parser.parse_args()

    repo = args.repo_root.resolve()
    run_dir = args.run_dir.resolve()
    base_xpr = repo / "lab11/CPU_CDE_AXI/mycpu_axi_verify/run_vivado/mycpu_prj1/mycpu_lab11_bus.xpr"
    project_dir = base_xpr.parent
    output_xpr = project_dir / f"mycpu_lab11_soc_{run_dir.name}.xpr"
    ip_copy_dir = run_dir / "ip_sources"
    coe_path = (args.inst_coe.resolve() if args.inst_coe else
                repo / "lab11/CPU_CDE_AXI/soft/func_lab9/obj/inst_ram.coe")
    if not base_xpr.is_file():
        parser.error(f"base XPR is missing: {base_xpr}")
    if not run_dir.is_dir():
        parser.error(f"run directory is missing: {run_dir}")
    if not coe_path.is_file():
        parser.error(f"Lab11 instruction image is missing: {coe_path}")
    if output_xpr.exists():
        parser.error(f"refusing to overwrite an existing run XPR: {output_xpr}")

    tree = ET.parse(base_xpr)
    root = tree.getroot()
    project = root.find("Project") if root.tag != "Project" else root
    configuration = root.find("Configuration")
    file_sets = root.find("FileSets")
    if project is None or configuration is None or file_sets is None:
        parser.error("XPR is missing Project, Configuration, or FileSets metadata")
    project.set("Path", output_xpr.as_posix())
    project_id = configuration.find("Option[@Name='Id']")
    if project_id is not None:
        project_id.set("Val", uuid.uuid4().hex)
    unique_ip_dir = f"$PPRDIR/{output_xpr.stem}.ip_user_files"
    option(configuration, "IPUserFilesDir", unique_ip_dir)
    option(configuration, "IPStaticSourceDir", unique_ip_dir + "/ipstatic")

    design_set = next((item for item in file_sets.findall("FileSet") if item.get("Name") == "sources_1"), None)
    sim_set = next((item for item in file_sets.findall("FileSet") if item.get("Name") == "sim_1"), None)
    if design_set is None or sim_set is None:
        parser.error("sources_1 or sim_1 fileset is missing")
    design_config = design_set.find("Config")
    sim_config = sim_set.find("Config")
    if design_config is None or sim_config is None:
        parser.error("source or simulation fileset Config is missing")
    option(design_config, "TopModule", "soc_axi_lite_top")
    option(design_config, "TopAutoSet", "TRUE")
    option(sim_config, "TopModule", "tb_top")
    option(sim_config, "TopAutoSet", "TRUE")
    option(sim_config, "SrcSet", "sources_1")

    coe_refs = 0
    copied_ips: list[str] = []
    for file_node in design_set.findall("File"):
        raw_path = file_node.get("Path", "")
        if not raw_path.lower().endswith(".xci"):
            continue
        if not raw_path.startswith("$PPRDIR/"):
            parser.error(f"unexpected non-project-relative XCI path: {raw_path}")
        source_path = (project_dir / raw_path.removeprefix("$PPRDIR/")).resolve()
        if not source_path.is_file():
            parser.error(f"source XCI is missing: {source_path}")
        name = source_path.stem
        destination = ip_copy_dir / name / source_path.name
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists():
            parser.error(f"refusing to overwrite private IP copy: {destination}")
        destination.write_bytes(source_path.read_bytes())
        file_node.set("Path", "$PPRDIR/" + Path(os.path.relpath(destination, project_dir)).as_posix())
        if name == "axi_ram":
            private_tree = ET.parse(destination)
            coe_setting = find_coe_setting(private_tree.getroot())
            coe_setting.text = coe_path.as_posix()
            ET.indent(private_tree, space="  ")
            private_tree.write(destination, encoding="UTF-8", xml_declaration=True)
            coe_refs += 1
        copied_ips.append(name)

    if len(copied_ips) != 5 or len(set(copied_ips)) != 5:
        parser.error(f"expected five unique private IPs (PLL, AXI RAM/crossbar, HILO), found {copied_ips}")
    if coe_refs != 1:
        parser.error(f"expected exactly one private AXI RAM COE path, found {coe_refs}")

    tree.write(output_xpr, encoding="UTF-8", xml_declaration=True)
    print(f"PROJECT_XPR={output_xpr}")
    print(f"BASE_XPR={base_xpr}")
    print(f"PRIVATE_IPS={','.join(copied_ips)}")
    sim_top = sim_config.find("Option[@Name='TopModule']").get("Val")
    print(f"SIM_TOP={sim_top}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
