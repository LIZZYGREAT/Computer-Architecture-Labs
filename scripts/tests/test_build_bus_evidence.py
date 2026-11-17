from __future__ import annotations

import csv
import hashlib
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build_bus_evidence as evidence  # noqa: E402


class WaveCaptureIdempotencyTests(unittest.TestCase):
    def test_new_and_legacy_preflight_files_are_read_as_separate_stages(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            run_dir = Path(directory)
            (run_dir / "preflight.txt").write_text(
                "OVERALL_STATUS=INCOMPLETE\nVIVADO_VERSION=NOT_RUN\n", encoding="utf-8"
            )
            (run_dir / "preflight").mkdir()
            (run_dir / "preflight/project-preflight.txt").write_text(
                "PREFLIGHT=PASS\nVIVADO_VERSION=2025.2\n", encoding="utf-8"
            )
            input_row, legacy = evidence.run_manifest("lab11", run_dir)
            self.assertEqual(input_row, {})
            self.assertEqual(legacy["INPUT_SCAN_STATUS"], "LEGACY_INPUT_SNAPSHOT")
            self.assertEqual(legacy["VIVADO_PREFLIGHT_STATUS"], "PASS")
            self.assertNotEqual(legacy["INPUT_SCAN_STATUS"], legacy.get("OVERALL_STATUS"))

            (run_dir / "input-scan.txt").write_text(
                "STAGE=INPUT_SCAN\nINPUT_SCAN_STATUS=PASS\n", encoding="utf-8"
            )
            (run_dir / "vivado-preflight-summary.txt").write_text(
                "VIVADO_PREFLIGHT_STATUS=PASS\n", encoding="utf-8"
            )
            _, current = evidence.run_manifest("lab11", run_dir)
            self.assertEqual(current["INPUT_SCAN_STATUS"], "PASS")
            self.assertEqual(current["VIVADO_PREFLIGHT_STATUS"], "PASS")

    def test_lab11_read_themes_show_arprot_and_handshake_expectations(self) -> None:
        themes = {row["figure"]: row for row in evidence.theme_rows("lab11")}
        for figure in ("L11-01", "L11-02"):
            self.assertIn("soc_lite/cpu_arprot[2:0]~bin", themes[figure]["signals"])
            self.assertIn("cpu_arvalid && cpu_arready", themes[figure]["context"])
        self.assertIn("ARPROT=110", themes["L11-01"]["expected"])
        self.assertIn("ARPROT=110", themes["L11-02"]["expected"])
        self.assertIn("ARPROT=010", themes["L11-02"]["expected"])

    def test_preflight_only_results_do_not_enter_transaction_summary(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            run_dir = Path(directory)
            (run_dir / "result.txt").write_text(
                "RUN_ID=preflight-only\nCASE=lab11\nSUITE=preflight\nSTATUS=PASS\n",
                encoding="utf-8",
            )
            self.assertEqual(evidence.build_transaction_rows([
                ("lab11", run_dir, evidence.read_kv(run_dir / "result.txt"))
            ]), [])

    def test_rebuild_preserves_verified_fields_and_rejects_changed_database(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            run_id = "lab11-idempotency-temp"
            run_dir = root / "results" / "lab10_lab11" / "lab11" / run_id
            run_dir.mkdir(parents=True)
            (run_dir / "wave-full.wdb").write_bytes(b"temporary WDB fixture")
            (run_dir / "result.txt").write_text(
                f"RUN_ID={run_id}\nSTATUS=PASS\nWAVEFORM_FILE=wave-full.wdb\n",
                encoding="utf-8",
            )

            wdb_rel = f"results/lab10_lab11/lab11/{run_id}/wave-full.wdb"
            wcfg_rel = f"report/lab10-11/figures/lab11/03_axi_write__{run_id}.wcfg"
            generated = {
                "case": "lab11", "run_id": run_id, "figure_id": "L11-03",
                "png_filename": "L11-03.png", "wdb_file": wdb_rel,
                "wdb_sha256": "A" * 64, "wcfg_file": wcfg_rel,
                "wcfg_sha256": "B" * 64, "wcfg_validation": "PASS",
                "target_pc": "0xbfc00100", "search_signal": "/tb_top/soc_lite/cpu_awvalid",
                "search_value": "1", "search_context": "BUS_ANCHOR event=store pc=bfc00100",
                "expected": "AWPROT=010; WID=AWID", "expected_source": "AXI3 adapter",
                "required_signals": "cpu_awid;cpu_wid", "observed": "",
                "time_start_ns": "", "time_end_ns": "", "proof_status": "PENDING_CAPTURE",
                "remarks": "generated row",
            }
            validation = {
                "case": "lab11", "run_id": run_id, "wdb_file": wdb_rel,
                "wdb_sha256": "A" * 64, "wcfg_file": wcfg_rel,
                "wcfg_sha256": "B" * 64, "structural_validation_status": "PASS",
                "manual_waveform_proof_status": "CAPTURED_VERIFIED",
            }
            manual = dict(generated)
            manual.update({
                "observed": "0x12345678", "time_start_ns": "100", "time_end_ns": "200",
                "proof_status": "CAPTURED_VERIFIED", "remarks": "manual screenshot verified",
            })
            capture_path = root / "report" / "lab10-11" / "data" / "wave-capture-log.csv"
            evidence.write_csv(capture_path, evidence.WAVE_FIELDS, [manual])

            runs = [("lab11", run_dir, {"RUN_ID": run_id, "STATUS": "PASS", "SUITE": "full"})]
            archive_dir = capture_path.parent / "archive"
            with (patch.object(evidence, "make_wcfgs", return_value=([{}], [validation], {})),
                  patch.object(evidence, "make_wave_rows_for_run", return_value=[generated]),
                  patch.object(evidence, "theme_rows", return_value=[{"figure": "L11-03", "file": "03_axi_write"}]),
                  patch.object(evidence, "build_evidence_rows", return_value=[]),
                  patch.object(evidence, "build_transaction_rows", return_value=[]),
                  redirect_stdout(StringIO())):
                evidence.write_outputs(root, runs, {}, None, "lab11", run_id, 1)
                backups_after_first = list(archive_dir.glob("wave-capture-log-*.csv"))
                evidence.write_outputs(root, runs, {}, None, "lab11", run_id, 1)
                self.assertEqual(list(archive_dir.glob("wave-capture-log-*.csv")), backups_after_first)

            with capture_path.open("r", newline="", encoding="utf-8-sig") as stream:
                saved = next(csv.DictReader(stream))
            for field, expected in {
                "observed": "0x12345678", "time_start_ns": "100", "time_end_ns": "200",
                "proof_status": "CAPTURED_VERIFIED", "remarks": "manual screenshot verified",
            }.items():
                self.assertEqual(saved[field], expected)

            before_conflict = hashlib.sha256(capture_path.read_bytes()).hexdigest()
            changed = dict(generated, wdb_sha256="C" * 64)
            with (patch.object(evidence, "make_wcfgs", return_value=([{}], [validation], {})),
                  patch.object(evidence, "make_wave_rows_for_run", return_value=[changed]),
                  patch.object(evidence, "theme_rows", return_value=[{"figure": "L11-03", "file": "03_axi_write"}]),
                  patch.object(evidence, "build_evidence_rows", return_value=[]),
                  patch.object(evidence, "build_transaction_rows", return_value=[]),
                  redirect_stdout(StringIO())):
                with self.assertRaisesRegex(ValueError, "manual proof was not overwritten"):
                    evidence.write_outputs(root, runs, {}, None, "lab11", run_id, 1)
            self.assertEqual(hashlib.sha256(capture_path.read_bytes()).hexdigest(), before_conflict)

    def test_portable_wcfg_uses_relative_wdb_reference(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            wdb = root / "results" / "wave-full.wdb"
            wdb.parent.mkdir(parents=True)
            wdb.write_bytes(b"temporary WDB fixture")
            source = root / "absolute.wcfg"
            source.write_text(
                f'<Waveform><db_ref_list><db_ref path="{wdb.as_posix()}" id="1"></db_ref>'
                "</db_ref_list><wvobject fp_name=\"/tb_top/clk\" type=\"logic\" /></Waveform>",
                encoding="utf-8",
            )
            target = root / "figures" / "portable.wcfg"
            target.parent.mkdir(parents=True)
            portable = evidence.make_portable_wcfg(source, target, wdb)
            reference = evidence.wcfg_db_ref(portable)
            self.assertFalse(Path(reference).is_absolute())
            self.assertEqual(evidence.resolve_wcfg_db_ref(portable), wdb.resolve())
            self.assertIn("/tb_top/clk", portable.read_text(encoding="utf-8"))
            with self.assertRaises(FileExistsError):
                evidence.make_portable_wcfg(source, target, wdb)

    def test_transaction_summary_labels_directed_and_terminal_if(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)

            def make_run(case: str, run_id: str, suite: str, metrics: str,
                         extra: str = "") -> tuple[str, Path, dict[str, str]]:
                run_dir = root / run_id
                run_dir.mkdir()
                (run_dir / "result.txt").write_text(
                    f"RUN_ID={run_id}\nCASE={case}\nSUITE={suite}\nSTATUS=PASS\n"
                    f"PROTOCOL_ASSERTS_PASS={'PASS' if suite == 'directed' else 'N/A'}\n"
                    f"PROTOCOL_ASSERTS_FAIL={extra or ('N/A' if suite == 'directed' else '0')}\n",
                    encoding="utf-8",
                )
                (run_dir / "simulate.log").write_text(f"BUS_METRICS {metrics}\n", encoding="utf-8")
                return case, run_dir, evidence.read_kv(run_dir / "result.txt")

            directed = make_run("lab11", "directed", "directed",
                                "load_req_accept=2 load_data_complete=2 store_req_accept=2 store_data_complete=2")
            full11 = make_run(
                "lab11", "full11", "full",
                "inst_req_accept=172894 inst_data_complete=172893 "
                "load_req_accept=4618 load_data_complete=4618 "
                "store_req_accept=3753 store_data_complete=3753 "
                "ar_handshakes=177511 r_handshakes=177511 "
                "aw_handshakes=3753 w_handshakes=3753 b_handshakes=3753",
            )
            full10 = make_run(
                "lab10", "full10", "full",
                "inst_req_accept=172457 inst_data_complete=172457 "
                "load_req_accept=4618 load_data_complete=4618 "
                "store_req_accept=3753 store_data_complete=3753",
                extra="N/A",
            )
            rows = {row["run_id"]: row for row in evidence.build_transaction_rows([directed, full11, full10])}
            self.assertEqual(rows["directed"]["summary_status"], "DIRECTED_PASS")
            self.assertEqual(rows["directed"]["assertion_status"], "PASS")
            self.assertEqual(rows["full11"]["terminal_pending_if"], 1)
            self.assertEqual(rows["full11"]["summary_status"], "PASS_WITH_PENDING_IF")
            self.assertEqual(rows["full11"]["assertion_status"], "PASS")
            self.assertEqual(rows["full10"]["terminal_pending_if"], 0)
            self.assertEqual(rows["full10"]["summary_status"], "PASS")
            self.assertEqual(rows["full10"]["assertion_status"], "NOT_REPORTED")


if __name__ == "__main__":
    unittest.main()
