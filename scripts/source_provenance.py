#!/usr/bin/env python3
"""Build and verify a run-scoped source manifest from the generated Vivado XPR."""

from __future__ import annotations

import csv
import hashlib
import io
import json
import os
import re
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Iterable


MANIFEST_FIELDS = [
    "case", "run_id", "suite", "role", "path", "sha256", "hash_basis", "exists",
    "active_for_suite", "declared_in_xpr", "source_phase", "source_basis",
]
SOURCE_SUFFIXES = {".v", ".sv", ".vh", ".h", ".inc"}
ACTIVE_PHASES = {"PRE_SIM", "POST_SIM"}


class SourceProvenanceError(ValueError):
    """Raised when the selected run project cannot provide a trustworthy source set."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def display_path(root: Path, path: Path) -> str:
    resolved = path.resolve(strict=False)
    try:
        return resolved.relative_to(root.resolve()).as_posix()
    except ValueError:
        return resolved.as_posix()


def resolve_xpr_path(project_dir: Path, raw_path: str) -> Path:
    """Resolve the project-relative macros used by Vivado XPR File entries."""
    normalized = raw_path.strip().strip("{}").replace("\\", "/")
    for macro in ("$PPRDIR", "$PSRCDIR"):
        normalized = normalized.replace(macro, project_dir.resolve().as_posix())
    candidate = Path(normalized)
    if not candidate.is_absolute():
        candidate = project_dir / candidate
    return candidate.resolve(strict=False)


def _local_name(element: ET.Element) -> str:
    return element.tag.rsplit("}", 1)[-1]


def _child(element: ET.Element | None, name: str) -> ET.Element | None:
    if element is None:
        return None
    return next((child for child in element if _local_name(child) == name), None)


def _children(element: ET.Element | None, name: str) -> list[ET.Element]:
    if element is None:
        return []
    return [child for child in element if _local_name(child) == name]


def _option_value(fileset: ET.Element, option_name: str) -> str:
    config = _child(fileset, "Config")
    for option in _children(config, "Option"):
        if option.get("Name") == option_name:
            return option.get("Val", "")
    return ""


def _file_attributes(file_node: ET.Element) -> dict[str, list[str]]:
    attributes: dict[str, list[str]] = {}
    for info in file_node.iter():
        if _local_name(info) != "Attr":
            continue
        name = info.get("Name", "")
        if name:
            attributes.setdefault(name, []).append(info.get("Val", ""))
    return attributes


def _enabled_for_simulation(attributes: dict[str, list[str]]) -> bool:
    for key in ("IsEnabled", "Enabled"):
        values = [value.strip().lower() for value in attributes.get(key, [])]
        if values and all(value in {"0", "false", "no", "disabled"} for value in values):
            return False
    used_in = {value.strip().lower() for value in attributes.get("UsedIn", [])}
    return not used_in or "simulation" in used_in


def parse_xpr(xpr_path: Path) -> dict[str, object]:
    """Read sources_1/sim_1 declarations and their simulation usage from an XPR."""
    xpr_path = xpr_path.resolve()
    if not xpr_path.is_file():
        raise SourceProvenanceError(f"run XPR is missing: {xpr_path}")
    try:
        root = ET.parse(xpr_path).getroot()
    except ET.ParseError as exc:
        raise SourceProvenanceError(f"cannot parse run XPR {xpr_path}: {exc}") from exc

    file_sets = _child(root, "FileSets")
    by_name = {item.get("Name", ""): item for item in _children(file_sets, "FileSet")}
    if "sources_1" not in by_name or "sim_1" not in by_name:
        raise SourceProvenanceError(f"run XPR must contain sources_1 and sim_1: {xpr_path}")

    entries: list[dict[str, object]] = []
    include_dirs: list[Path] = []
    for fileset_name in ("sources_1", "sim_1"):
        fileset = by_name[fileset_name]
        for file_node in _children(fileset, "File"):
            raw_path = file_node.get("Path", "")
            if not raw_path:
                continue
            attributes = _file_attributes(file_node)
            entries.append({
                "fileset": fileset_name,
                "raw_path": raw_path,
                "path": resolve_xpr_path(xpr_path.parent, raw_path),
                "attributes": attributes,
                "active_in_simulation": _enabled_for_simulation(attributes),
            })
        raw_include_dirs = _option_value(fileset, "VerilogIncludeDirs")
        for raw in filter(None, re.split(r"[;\r\n]+", raw_include_dirs)):
            include_dirs.append(resolve_xpr_path(xpr_path.parent, raw.strip()))
    design_top = _option_value(by_name["sources_1"], "TopModule")
    simulation_top = _option_value(by_name["sim_1"], "TopModule")
    return {
        "entries": entries,
        "include_dirs": include_dirs,
        "design_top": design_top,
        "simulation_top": simulation_top,
    }


def xpr_configuration_sha256(root: Path, parsed: dict[str, object]) -> str:
    """Hash the elaboration-relevant XPR configuration, excluding Vivado run metadata."""
    active_verilog = [
        Path(entry["path"]).resolve(strict=False)
        for entry in parsed["entries"]
        if entry["fileset"] == "sources_1"
        and entry["active_in_simulation"]
        and Path(entry["path"]).suffix.lower() in {".v", ".sv"}
    ]
    resolved_includes = _discover_includes(active_verilog, parsed["include_dirs"])
    entries = [
        {
            "fileset": entry["fileset"],
            "path": display_path(root, Path(entry["path"])),
            "attributes": {
                name: values
                for name, values in entry["attributes"].items()
                if name.lower() not in {"usedin", "isenabled", "enabled", "isvisible"}
            },
            "active_in_simulation": entry["active_in_simulation"],
        }
        for entry in parsed["entries"]
    ]
    payload = {
        "design_top": parsed["design_top"],
        "simulation_top": parsed["simulation_top"],
        "resolved_include_files": sorted(display_path(root, path) for path in resolved_includes),
        "entries": entries,
    }
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest().upper()


def _include_references(path: Path) -> list[str]:
    if not path.is_file() or path.suffix.lower() not in {".v", ".sv", ".vh", ".h", ".inc"}:
        return []
    text = path.read_text(encoding="utf-8", errors="replace")
    return re.findall(r'^\s*`include\s+["<]([^">]+)[">]', text, flags=re.MULTILINE)


def _discover_includes(active_sources: Iterable[Path], include_dirs: Iterable[Path]) -> dict[Path, bool]:
    resolved: dict[Path, bool] = {}
    pending = list(active_sources)
    visited: set[Path] = set()
    search_dirs = list(include_dirs)
    while pending:
        source = pending.pop()
        source = source.resolve(strict=False)
        if source in visited:
            continue
        visited.add(source)
        local_dirs = [source.parent, *search_dirs]
        for reference in _include_references(source):
            candidates = [directory / reference for directory in local_dirs]
            found = next((candidate.resolve() for candidate in candidates if candidate.is_file()), None)
            if found is not None:
                resolved[found] = True
                pending.append(found)
            else:
                # Keep the first legal search location so missing includes remain visible.
                missing = (local_dirs[0] / reference).resolve(strict=False)
                resolved[missing] = False
    return resolved


def _row(root: Path, case: str, run_id: str, suite: str, role: str, path: Path,
         active: bool, declared: bool, phase: str, basis: str, *,
         sha256_override: str | None = None, hash_basis: str = "FILE_CONTENT") -> dict[str, str]:
    exists = path.is_file()
    return {
        "case": case,
        "run_id": run_id,
        "suite": suite,
        "role": role,
        "path": display_path(root, path),
        "sha256": (sha256_override or sha256_file(path)) if exists else "MISSING",
        "hash_basis": hash_basis,
        "exists": str(exists).lower(),
        "active_for_suite": str(active).lower(),
        "declared_in_xpr": str(declared).lower(),
        "source_phase": phase,
        "source_basis": basis,
    }


def _expected_testbench(root: Path, case: str, suite: str, settings: dict[str, str]) -> Path:
    if suite == "directed":
        relative = settings["DirectedTestbench"]
    elif suite == "full":
        cpu_dir = Path(settings["CpuSourceDir"])
        relative = (cpu_dir.parents[1] / "testbench" / "mycpu_tb.v").as_posix()
    else:
        raise SourceProvenanceError(f"unsupported source-capture suite: {suite}")
    return (root / relative).resolve(strict=False)


def _verification_scripts(root: Path, case: str, suite: str,
                          settings: dict[str, str], has_inst_override: bool) -> list[tuple[str, Path, bool]]:
    common = [
        ("verify_bus.ps1", root / "scripts/verify_bus.ps1", True),
        ("check_bus_inputs.py", root / "scripts/check_bus_inputs.py", True),
        ("check_bus_project.tcl", root / "scripts/check_bus_project.tcl", True),
        ("source_provenance.py", root / "scripts/source_provenance.py", True),
        ("capture_bus_source_manifest.py", root / "scripts/capture_bus_source_manifest.py", True),
        ("cases_bus.json", root / "scripts/cases_bus.json", True),
        ("build_bus_evidence.py", root / "scripts/build_bus_evidence.py", False),
        ("validate_wave_configs.tcl", root / "scripts/validate_wave_configs.tcl", False),
    ]
    if suite == "full":
        common.extend([
            ("soc_creator", root / settings["SocCreator"], True),
            ("soc_runner", root / settings["SocRunner"], True),
        ])
    else:
        if settings.get("UnitCreator"):
            common.append(("unit_creator", root / settings["UnitCreator"], True))
        common.append(("unit_runner", root / settings["UnitRunner"], True))
    if suite == "directed" and case == "lab11":
        common.append(("unit_project_creator", root / "scripts/create_bus_unit_xpr.py", True))
    if has_inst_override:
        common.append(("mif_converter", root / "scripts/mif_to_coe.py", True))
    return common


def collect_source_rows(root: Path, case: str, suite: str, run_id: str, xpr_path: Path,
                        settings: dict[str, str], *, coe_path: Path | None = None,
                        mif_path: Path | None = None, trace_path: Path | None = None,
                        has_inst_override: bool = False,
                        phase: str = "PRE_SIM") -> list[dict[str, str]]:
    """Collect exact XPR file declarations plus related inputs and marked candidates."""
    root = root.resolve()
    xpr_path = xpr_path.resolve()
    parsed = parse_xpr(xpr_path)
    entries = parsed["entries"]
    design_top = str(parsed["design_top"])
    simulation_top = str(parsed["simulation_top"])
    expected_top = (Path(settings["DirectedTestbench"]).stem if suite == "directed" else "tb_top")
    if simulation_top != expected_top:
        raise SourceProvenanceError(
            f"run XPR simulation top {simulation_top!r} does not match {suite} top {expected_top!r}"
        )

    expected_tb = _expected_testbench(root, case, suite, settings)
    unit_tb = (root / settings["DirectedTestbench"]).resolve(strict=False)
    cpu_dir = (root / settings["CpuSourceDir"]).resolve()
    soc_tb = (root / cpu_dir.parents[1] / "testbench" / "mycpu_tb.v").resolve(strict=False)
    sim_entries = [entry for entry in entries if entry["fileset"] == "sim_1"]
    matching_tb = [entry for entry in sim_entries if Path(entry["path"]).resolve(strict=False) == expected_tb]
    if len(matching_tb) != 1 or not matching_tb[0]["active_in_simulation"]:
        raise SourceProvenanceError(f"expected active {suite} testbench is not declared in sim_1: {expected_tb}")

    active_verilog = [
        Path(entry["path"]).resolve(strict=False)
        for entry in entries
        if Path(entry["path"]).suffix.lower() in {".v", ".sv"}
        and entry["active_in_simulation"]
        and entry["fileset"] == "sources_1"
    ]
    includes = _discover_includes(active_verilog, parsed["include_dirs"])

    rows: list[dict[str, str]] = []
    xpr_paths = {Path(entry["path"]).resolve(strict=False) for entry in entries}
    design_top_path = next((Path(entry["path"]).resolve(strict=False) for entry in entries
                            if entry["fileset"] == "sources_1"
                            and Path(entry["path"]).stem.lower() == design_top.lower()), None)
    for entry in entries:
        path = Path(entry["path"]).resolve(strict=False)
        suffix = path.suffix.lower()
        active_in_sim = bool(entry["active_in_simulation"])
        declared = True
        basis = f"RUN_XPR_{str(entry['fileset']).upper()}"
        if path == expected_tb:
            role = "unit_testbench" if suite == "directed" else "soc_testbench"
            active = active_in_sim
            basis = "RUN_XPR_SIM_TOP"
        elif path == unit_tb:
            role, active = "unit_testbench", suite == "directed" and active_in_sim
            basis = "RUN_XPR_SIM_DECLARATION"
        elif path == soc_tb:
            role, active = "soc_testbench", suite == "full" and active_in_sim
            basis = "RUN_XPR_SIM_DECLARATION"
        elif path == design_top_path and case in {"lab10", "lab11"} and suite == "full":
            role, active = "soc_top", active_in_sim
        elif path.is_relative_to(cpu_dir):
            if suffix in {".h", ".vh", ".inc"}:
                role = "active_cpu_header" if includes.get(path, active_in_sim) else "candidate_only"
                active = includes.get(path, active_in_sim) and active_in_sim
            elif suffix in {".v", ".sv"}:
                role, active = ("active_cpu_rtl", True) if active_in_sim else ("candidate_only", False)
            else:
                role, active = "active_cpu_input", active_in_sim
        elif suffix == ".xci":
            role, active = "ip_config", active_in_sim
        elif suffix in {".coe", ".mif", ".mem", ".txt"}:
            role, active = "reference_input", active_in_sim
        elif suffix in SOURCE_SUFFIXES:
            role, active = "soc_wrapper", active_in_sim
        else:
            role, active = "project_input", active_in_sim
        rows.append(_row(root, case, run_id, suite, role, path, active, declared, phase, basis))

    # Enumerate CPU-directory candidates only as candidates; never imply they were compiled.
    for candidate in sorted(cpu_dir.iterdir(), key=lambda item: item.name.lower()) if cpu_dir.is_dir() else []:
        if not candidate.is_file() or candidate.suffix.lower() not in SOURCE_SUFFIXES:
            continue
        resolved = candidate.resolve()
        if resolved in xpr_paths or any(row["path"] == display_path(root, resolved) for row in rows):
            continue
        included = includes.get(resolved)
        role = "active_cpu_header" if included else "candidate_only"
        basis = "INCLUDE_DIRECTIVE" if included else "CPU_SOURCE_CANDIDATE"
        rows.append(_row(root, case, run_id, suite, role, resolved, bool(included), False, phase, basis))

    # Record transitive include files that are actually read, even when Vivado does not list them as File entries.
    for header, exists in includes.items():
        if header in xpr_paths or any(row["path"] == display_path(root, header) for row in rows):
            continue
        rows.append(_row(root, case, run_id, suite, "active_cpu_header", header, True, False, phase,
                         "INCLUDE_DIRECTIVE"))

    # Preserve the old Lab3 reference as an explicitly inactive comparison baseline.
    baseline_cpu = root / "lab3/CPU_CDE/mycpu_verify/rtl/myCPU"
    for candidate in sorted(baseline_cpu.iterdir(), key=lambda item: item.name.lower()) if baseline_cpu.is_dir() else []:
        if candidate.is_file() and candidate.suffix.lower() in SOURCE_SUFFIXES:
            rows.append(_row(root, case, run_id, suite, "baseline_reference", candidate, False, False,
                             phase, "LAB3_REFERENCE_ONLY"))

    base_xpr = (root / settings["BaseSocXpr"]).resolve()
    rows.append(_row(root, case, run_id, suite, "base_project_template", base_xpr, True, False,
                     phase, "CASE_BASE_XPR"))
    if base_xpr.is_file():
        base_parsed = parse_xpr(base_xpr)
        for entry in base_parsed["entries"]:
            path = Path(entry["path"]).resolve(strict=False)
            if path.suffix.lower() == ".xci":
                rows.append(_row(root, case, run_id, suite, "base_ip_config", path, False, False,
                                 phase, "BASE_XPR_TEMPLATE"))

    rows.append(_row(root, case, run_id, suite, "generated_project", xpr_path, False, False,
                     phase, "RUN_XPR_FILE"))
    rows.append(_row(
        root, case, run_id, suite, "project_configuration", xpr_path, True, False,
        phase, "RUN_XPR_ELABORATION_CONFIGURATION",
        sha256_override=xpr_configuration_sha256(root, parsed),
        hash_basis="CANONICAL_XPR_CONFIGURATION",
    ))

    for role, candidate in (("unit_testbench", unit_tb), ("soc_testbench", soc_tb)):
        if not any(row["role"] == role and row["path"] == display_path(root, candidate) for row in rows):
            rows.append(_row(root, case, run_id, suite, role, candidate, False, False, phase,
                             "CASE_CONFIG_TESTBENCH_CANDIDATE"))

    for role, path, active in _verification_scripts(root, case, suite, settings, has_inst_override):
        rows.append(_row(root, case, run_id, suite, role, path, active, False, phase, "WORKTREE_FILE"))

    for label, path in (("instruction_coe", coe_path), ("instruction_mif", mif_path),
                        ("reference_trace", trace_path)):
        if path is not None:
            rows.append(_row(root, case, run_id, suite, "reference_input", path, True, False,
                             phase, label.upper()))

    unique: dict[tuple[str, str, str, str], dict[str, str]] = {}
    for row in rows:
        key = (row["role"], row["path"], row["source_basis"], row["declared_in_xpr"])
        unique[key] = row
    return sorted(unique.values(), key=lambda row: (row["role"], row["path"], row["source_basis"]))


def manifest_payload(rows: list[dict[str, str]]) -> str:
    buffer = io.StringIO(newline="")
    writer = csv.DictWriter(buffer, fieldnames=MANIFEST_FIELDS, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return buffer.getvalue()


def write_manifest(path: Path, rows: list[dict[str, str]], *, allow_replace: bool = False) -> None:
    if path.exists() and not allow_replace:
        raise FileExistsError(f"refusing to overwrite source manifest: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = manifest_payload(rows)
    temporary: str | None = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", newline="", encoding="utf-8-sig", dir=path.parent,
                                         prefix=f".{path.name}.", suffix=".tmp", delete=False) as stream:
            temporary = stream.name
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)


def read_manifest(path: Path) -> list[dict[str, str]]:
    with path.open("r", newline="", encoding="utf-8-sig") as stream:
        return list(csv.DictReader(stream))


def integrity_report(rows: list[dict[str, str]]) -> tuple[str, list[str]]:
    def identity(row: dict[str, str]) -> tuple[str, ...]:
        return tuple(row.get(field, "") for field in (
            "case", "run_id", "suite", "role", "path", "active_for_suite", "declared_in_xpr",
            "source_basis", "hash_basis",
        ))

    before = {identity(row): row for row in rows if row.get("source_phase") == "PRE_SIM"}
    after = {identity(row): row for row in rows if row.get("source_phase") == "POST_SIM"}
    active = [key for key, row in before.items() if row.get("active_for_suite") == "true"]
    changes: list[str] = []
    missing: list[str] = []
    if not active or set(before) != set(after):
        changes.append("source manifest rows differ between PRE_SIM and POST_SIM")
    for key in active:
        path = key[4]
        first = before[key]
        second = after.get(key)
        if not second:
            changes.append(f"missing POST_SIM row: {path}")
            continue
        if first.get("exists") != "true" or second.get("exists") != "true":
            missing.append(path)
        if first.get("sha256") != second.get("sha256") or first.get("exists") != second.get("exists"):
            changes.append(f"active source changed: {path}")
    status = "PASS" if active and not changes and not missing else "FAIL"
    return status, changes + [f"active source missing: {path}" for path in missing]


def refresh_post_rows(root: Path, pre_rows: list[dict[str, str]]) -> list[dict[str, str]]:
    """Re-hash PRE_SIM inputs and compare the XPR's elaboration-relevant configuration."""
    root = root.resolve()
    post: list[dict[str, str]] = []
    for source in pre_rows:
        if source.get("source_phase") != "PRE_SIM":
            raise SourceProvenanceError("POST_SIM capture requires PRE_SIM rows only")
        path = Path(source["path"])
        if not path.is_absolute():
            path = root / path
        hash_override = None
        if source.get("hash_basis") == "CANONICAL_XPR_CONFIGURATION":
            hash_override = xpr_configuration_sha256(root, parse_xpr(path))
        post.append(_row(root, source["case"], source["run_id"], source["suite"], source["role"], path,
                         source["active_for_suite"] == "true", source["declared_in_xpr"] == "true",
                         "POST_SIM", source["source_basis"], sha256_override=hash_override,
                         hash_basis=source.get("hash_basis", "FILE_CONTENT")))
    return post


def write_integrity_report(path: Path, rows: list[dict[str, str]], phase: str) -> str:
    if phase == "PRE_SIM":
        active_rows = [row for row in rows if row.get("active_for_suite") == "true"]
        missing = [row["path"] for row in active_rows if row.get("exists") != "true"]
        active = len(active_rows)
        status = "FAIL" if not active_rows or missing else "PENDING"
        details = [f"active source missing before simulation: {path}" for path in missing]
    else:
        status, details = integrity_report(rows)
        active = sum(row.get("active_for_suite") == "true" and row.get("source_phase") == "PRE_SIM"
                     for row in rows)
    lines = [
        f"SOURCE_INTEGRITY={status}",
        f"SOURCE_CAPTURE_PHASE={'PRE_SIM' if phase == 'PRE_SIM' else 'PRE_SIM_AND_POST_SIM'}",
        f"ACTIVE_SOURCE_COUNT={active}",
        f"INTEGRITY_DETAIL_COUNT={len(details)}",
    ] + [f"INTEGRITY_DETAIL={detail}" for detail in details]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return status
