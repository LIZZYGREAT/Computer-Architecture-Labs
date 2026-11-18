from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from scripts.tlb_cache.finalize_run_result import finalize_run_result


class FinalizeRunResultTests(unittest.TestCase):
    def make_run(self, temp_dir: str, integrity: str) -> tuple[Path, Path]:
        run_dir = Path(temp_dir)
        simulation_result = run_dir / "sim-result.txt"
        simulation_result.write_text(
            "RUN_ID=sample\nCASE=lab19\nSTATUS=PASS\nPASS_MARKER=SIM_PASS\n",
            encoding="utf-8",
        )
        (run_dir / "source-integrity.txt").write_text(
            f"SOURCE_INTEGRITY={integrity}\n", encoding="utf-8"
        )
        (run_dir / "git-head.txt").write_text("HEAD=abc123\n", encoding="utf-8")
        return run_dir, simulation_result

    def test_manifest_failure_cannot_leave_final_pass(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            run_dir, simulation_result = self.make_run(temp_dir, "FAIL")
            passed = finalize_run_result(run_dir, simulation_result, "FAIL")
            result = (run_dir / "result.txt").read_text(encoding="utf-8")
            self.assertFalse(passed)
            self.assertIn("STATUS=INCOMPLETE", result)
            self.assertIn("SIMULATION_STATUS=PASS", result)
            self.assertIn("SOURCE_INTEGRITY=FAIL", result)
            self.assertIn("STATUS=PASS", simulation_result.read_text(encoding="utf-8"))

    def test_pass_requires_simulation_and_manifest_pass(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            run_dir, simulation_result = self.make_run(temp_dir, "PASS")
            passed = finalize_run_result(run_dir, simulation_result, "PASS", "123")
            result = (run_dir / "result.txt").read_text(encoding="utf-8")
            self.assertTrue(passed)
            self.assertIn("STATUS=PASS", result)
            self.assertIn("SOURCE_INTEGRITY=PASS", result)
            self.assertIn("SIMULATOR_CPU_MS=123", result)


if __name__ == "__main__":
    unittest.main()
