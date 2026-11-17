from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import source_provenance as provenance  # noqa: E402


class EffectiveSourceManifestTests(unittest.TestCase):
    def make_fixture(self, root: Path) -> tuple[Path, dict[str, str]]:
        cpu_dir = root / "lab11/CPU_CDE_AXI/mycpu_axi_verify/rtl/myCPU"
        cpu_dir.mkdir(parents=True)
        (cpu_dir / "IF_stage.v").write_text('`include "mycpu.h"\nmodule if_stage; endmodule\n', encoding="utf-8")
        (cpu_dir / "axi3_cpu_bus.v").write_text("module axi3_cpu_bus; endmodule\n", encoding="utf-8")
        (cpu_dir / "candidate.v").write_text("module unused; endmodule\n", encoding="utf-8")
        (cpu_dir / "mycpu.h").write_text("`define WIDTH 32\n", encoding="utf-8")
        bench = root / "lab11/CPU_CDE_AXI/mycpu_axi_verify/testbench/tb_lab11_axi3_bus.sv"
        soc_bench = bench.with_name("mycpu_tb.v")
        bench.parent.mkdir(parents=True)
        bench.write_text("module tb_lab11_axi3_bus; endmodule\n", encoding="utf-8")
        soc_bench.write_text("module tb_top; endmodule\n", encoding="utf-8")
        trace = root / "lab11/CPU_CDE_AXI/cpu132_gettrace/golden_trace.txt"
        coe = root / "lab11/CPU_CDE_AXI/soft/inst_ram.coe"
        mif = root / "lab11/CPU_CDE_AXI/soft/inst_ram.mif"
        for path in (trace, coe, mif):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture\n", encoding="utf-8")
        base_xpr = root / "lab11/CPU_CDE_AXI/project/base.xpr"
        base_xpr.parent.mkdir(parents=True)
        xpr = root / "results/run/project.xpr"
        xpr.parent.mkdir(parents=True)
        xml = """<?xml version="1.0"?>
<Project><FileSets>
  <FileSet Name="sources_1">
    <File Path="{if_file}"><FileInfo><Attr Name="UsedIn" Val="simulation"/></FileInfo></File>
    <File Path="{bus_file}"><FileInfo><Attr Name="UsedIn" Val="simulation"/></FileInfo></File>
    <File Path="{candidate_file}"><FileInfo><Attr Name="UsedIn" Val="synthesis"/></FileInfo></File>
    <Config><Option Name="TopModule" Val="if_stage"/></Config>
  </FileSet>
  <FileSet Name="sim_1">
    <File Path="{unit_tb}"><FileInfo><Attr Name="UsedIn" Val="simulation"/></FileInfo></File>
    <Config><Option Name="TopModule" Val="tb_lab11_axi3_bus"/></Config>
  </FileSet>
</FileSets></Project>""".format(
            if_file=(cpu_dir / "IF_stage.v").as_posix(),
            bus_file=(cpu_dir / "axi3_cpu_bus.v").as_posix(),
            candidate_file=(cpu_dir / "candidate.v").as_posix(),
            unit_tb=bench.as_posix(),
        )
        xpr.write_text(xml, encoding="utf-8")
        base_xpr.write_text(xml.replace('Val="tb_lab11_axi3_bus"', 'Val="tb_top"'), encoding="utf-8")
        scripts = {
            "verify_bus.ps1": "scripts/verify_bus.ps1",
            "check_bus_inputs.py": "scripts/check_bus_inputs.py",
            "check_bus_project.tcl": "scripts/check_bus_project.tcl",
            "source_provenance.py": "scripts/source_provenance.py",
            "capture_bus_source_manifest.py": "scripts/capture_bus_source_manifest.py",
            "cases_bus.json": "scripts/cases_bus.json",
            "build_bus_evidence.py": "scripts/build_bus_evidence.py",
            "validate_wave_configs.tcl": "scripts/validate_wave_configs.tcl",
            "unit_creator": "scripts/create_bus_unit_xpr.py",
            "unit_runner": "scripts/run_lab11_axi3_directed.tcl",
        }
        for relative in scripts.values():
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture\n", encoding="utf-8")
        settings = {
            "CpuSourceDir": "lab11/CPU_CDE_AXI/mycpu_axi_verify/rtl/myCPU",
            "DirectedTestbench": "lab11/CPU_CDE_AXI/mycpu_axi_verify/testbench/tb_lab11_axi3_bus.sv",
            "BaseSocXpr": "lab11/CPU_CDE_AXI/project/base.xpr",
            "UnitRunner": "scripts/run_lab11_axi3_directed.tcl",
            "UnitCreator": "scripts/create_bus_unit_xpr.py",
            "SocCreator": "scripts/create_lab11_soc_xpr.py",
            "SocRunner": "scripts/run_lab11_soc.tcl",
        }
        return xpr, settings

    def test_actual_xpr_selects_cpu_rtl_header_and_suite_testbench(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            xpr, settings = self.make_fixture(root)
            rows = provenance.collect_source_rows(root, "lab11", "directed", "run-a", xpr, settings)
            by_name = {(row["role"], Path(row["path"]).name): row for row in rows}
            for name in ("IF_stage.v", "axi3_cpu_bus.v"):
                self.assertEqual(by_name[("active_cpu_rtl", name)]["active_for_suite"], "true")
                self.assertEqual(by_name[("active_cpu_rtl", name)]["declared_in_xpr"], "true")
            header = by_name[("active_cpu_header", "mycpu.h")]
            self.assertEqual(header["active_for_suite"], "true")
            self.assertEqual(header["source_basis"], "INCLUDE_DIRECTIVE")
            self.assertEqual(by_name[("unit_testbench", "tb_lab11_axi3_bus.sv")]["active_for_suite"], "true")
            self.assertEqual(by_name[("soc_testbench", "mycpu_tb.v")]["active_for_suite"], "false")
            candidate = by_name[("candidate_only", "candidate.v")]
            self.assertEqual(candidate["declared_in_xpr"], "true")
            self.assertEqual(candidate["active_for_suite"], "false")
            raw_project = by_name[("generated_project", "project.xpr")]
            self.assertEqual(raw_project["active_for_suite"], "false")
            project_config = by_name[("project_configuration", "project.xpr")]
            self.assertEqual(project_config["active_for_suite"], "true")
            self.assertEqual(project_config["hash_basis"], "CANONICAL_XPR_CONFIGURATION")

    def test_integrity_ignores_nonactive_hash_changes_and_fails_active_changes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            xpr, settings = self.make_fixture(root)
            before = provenance.collect_source_rows(root, "lab11", "directed", "run-b", xpr, settings)
            nonactive = root / "lab11/CPU_CDE_AXI/mycpu_axi_verify/rtl/myCPU/candidate.v"
            nonactive.write_text("module changed_candidate; endmodule\n", encoding="utf-8")
            after_candidate_change = before + provenance.refresh_post_rows(root, before)
            self.assertEqual(provenance.integrity_report(after_candidate_change)[0], "PASS")
            active = root / "lab11/CPU_CDE_AXI/mycpu_axi_verify/rtl/myCPU/axi3_cpu_bus.v"
            active.write_text("module changed_axi3_cpu_bus; endmodule\n", encoding="utf-8")
            after_active_change = before + provenance.refresh_post_rows(root, before)
            status, details = provenance.integrity_report(after_active_change)
            self.assertEqual(status, "FAIL")
            self.assertTrue(any("axi3_cpu_bus.v" in detail for detail in details))

    def test_vivado_metadata_changes_are_ignored_but_xpr_source_changes_fail(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            xpr, settings = self.make_fixture(root)
            before = provenance.collect_source_rows(root, "lab11", "directed", "run-c", xpr, settings)

            # Vivado may rewrite XPR run metadata without changing the selected sources.
            original = xpr.read_text(encoding="utf-8")
            xpr.write_text(original.replace(
                '<Attr Name="UsedIn" Val="simulation"/>',
                '<Attr Name="UsedIn" Val="implementation"/><Attr Name="UsedIn" Val="simulation"/>'
                '<Attr Name="IsVisible" Val="1"/>'
            ).replace(
                "</Project>", '<Runs><Run Name="sim_1_synth_1"/></Runs></Project>'
            ), encoding="utf-8")
            metadata_change = before + provenance.refresh_post_rows(root, before)
            self.assertEqual(provenance.integrity_report(metadata_change)[0], "PASS")

            # A changed simulation top is part of the project configuration and must fail.
            xpr.write_text(xpr.read_text(encoding="utf-8").replace(
                'Val="tb_lab11_axi3_bus"', 'Val="unexpected_top"'
            ), encoding="utf-8")
            config_change = before + provenance.refresh_post_rows(root, before)
            status, details = provenance.integrity_report(config_change)
            self.assertEqual(status, "FAIL")
            self.assertTrue(any("project.xpr" in detail for detail in details))


if __name__ == "__main__":
    unittest.main()
