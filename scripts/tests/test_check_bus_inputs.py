from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check_bus_inputs as inputs  # noqa: E402


class InputScanTests(unittest.TestCase):
    def make_fixture(self, root: Path) -> dict[str, object]:
        cpu_dir = root / "lab11/CPU_CDE_AXI/mycpu_axi_verify/rtl/myCPU"
        cpu_dir.mkdir(parents=True)
        (cpu_dir / "IF_stage.v").write_text("module if_stage; endmodule\n", encoding="utf-8")
        (cpu_dir / "candidate.v").write_text("module unused; endmodule\n", encoding="utf-8")
        bench = root / "lab11/CPU_CDE_AXI/mycpu_axi_verify/testbench/tb_lab11_axi3_bus.sv"
        bench.parent.mkdir(parents=True)
        bench.write_text("module tb_lab11_axi3_bus; endmodule\n", encoding="utf-8")
        coe = root / "lab11/CPU_CDE_AXI/soft/inst_ram.coe"
        mif = root / "lab11/CPU_CDE_AXI/soft/inst_ram.mif"
        trace = root / "lab11/CPU_CDE_AXI/cpu132_gettrace/golden_trace.txt"
        for path in (coe, mif, trace):
            path.parent.mkdir(parents=True, exist_ok=True)
        coe.write_text("memory_initialization_radix=16;\nmemory_initialization_vector=00000001;\n", encoding="ascii")
        mif.write_text("00000000000000000000000000000001\n", encoding="ascii")
        trace.write_text("trace fixture\n", encoding="ascii")
        scripts = [
            "scripts/check_bus_inputs.py", "scripts/source_provenance.py",
            "scripts/capture_bus_source_manifest.py", "scripts/check_bus_project.tcl",
            "scripts/verify_bus.ps1", "scripts/soc_creator.py", "scripts/soc_runner.tcl",
            "scripts/unit_creator.py", "scripts/unit_runner.tcl",
        ]
        for script in scripts:
            target = root / script
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("fixture\n", encoding="utf-8")
        xpr = root / "lab11/CPU_CDE_AXI/project/base.xpr"
        xpr.parent.mkdir(parents=True)
        xpr.write_text(
            """<?xml version="1.0"?>
<Project><FileSets>
<FileSet Name="sources_1"><File Path="{if_file}"/><Config><Option Name="TopModule" Val="soc_axi_lite_top"/></Config></FileSet>
<FileSet Name="sim_1"><File Path="{bench}"/><Config><Option Name="TopModule" Val="tb_top"/></Config></FileSet>
</FileSets></Project>""".format(if_file=(cpu_dir / "IF_stage.v").as_posix(), bench=bench.as_posix()),
            encoding="utf-8",
        )
        return {
            "BaseSocXpr": xpr.relative_to(root).as_posix(),
            "CpuSourceDir": cpu_dir.relative_to(root).as_posix(),
            "DirectedTestbench": bench.relative_to(root).as_posix(),
            "InstructionCoe": coe.relative_to(root).as_posix(),
            "InstructionMif": mif.relative_to(root).as_posix(),
            "ReferenceTrace": trace.relative_to(root).as_posix(),
            "SocCreator": "scripts/soc_creator.py", "SocRunner": "scripts/soc_runner.tcl",
            "UnitRunner": "scripts/unit_runner.tcl", "UnitCreator": "scripts/unit_creator.py",
        }

    def test_scans_declared_and_candidate_files_without_calling_them_effective_sources(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            settings = self.make_fixture(root)
            result, rows, issues = inputs.scan_case(root, "lab11", settings)
            self.assertEqual(result["input_scan_status"], "PASS")
            self.assertEqual(issues, [])
            declared = next(row for row in rows if row["path"].endswith("IF_stage.v"))
            candidate = next(row for row in rows if row["path"].endswith("candidate.v"))
            self.assertEqual(declared["declared_in_base_xpr"], "true")
            self.assertEqual(candidate["role"], "candidate_only")
            self.assertEqual(candidate["declared_in_base_xpr"], "false")
            previous_hash = candidate["sha256"]
            (root / settings["CpuSourceDir"] / "candidate.v").write_text("module changed; endmodule\n", encoding="utf-8")
            _, changed_rows, _ = inputs.scan_case(root, "lab11", settings)
            changed = next(row for row in changed_rows if row["path"].endswith("candidate.v"))
            self.assertNotEqual(changed["sha256"], previous_hash)

    def test_missing_trace_fails_input_scan(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            settings = self.make_fixture(root)
            (root / settings["ReferenceTrace"]).unlink()
            result, _, issues = inputs.scan_case(root, "lab11", settings)
            self.assertEqual(result["input_scan_status"], "FAIL")
            self.assertTrue(any("reference_trace" in issue for issue in issues))


if __name__ == "__main__":
    unittest.main()
