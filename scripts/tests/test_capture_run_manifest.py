from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tlb_cache import capture_run_manifest as capture  # noqa: E402


class RunManifestTests(unittest.TestCase):
    def test_captures_active_project_and_simulation_sources(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            run = root / "results/run-01"
            run.mkdir(parents=True)
            project = root / "project.xpr"
            rtl = root / "tlb.v"
            testbench = root / "tb.sv"
            for path, content in ((project, "xpr"), (rtl, "rtl"), (testbench, "tb")):
                path.write_text(content, encoding="ascii")
            (run / "active-sources.txt").write_text(
                "PROJECT_XPR=" + str(project) + "\nSOURCE=" + str(rtl) + "\nSIM_SOURCE=" + str(testbench) + "\n",
                encoding="utf-8",
            )
            self.assertTrue(capture.capture_run_manifest(root, run))
            text = (run / "source-manifest.csv").read_text(encoding="utf-8")
            self.assertIn("project.xpr,vivado_project", text)
            self.assertIn("tlb.v,design_source", text)
            self.assertIn("tb.sv,simulation_source", text)
            self.assertIn("no_external_image", (run / "input_manifest.csv").read_text(encoding="utf-8"))

    def test_missing_active_source_fails_integrity(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            run = root / "results/run-02"
            run.mkdir(parents=True)
            (run / "active-sources.txt").write_text("SOURCE=" + str(root / "missing.v") + "\n", encoding="utf-8")
            self.assertFalse(capture.capture_run_manifest(root, run))
            self.assertIn("SOURCE_INTEGRITY=FAIL", (run / "source-integrity.txt").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
