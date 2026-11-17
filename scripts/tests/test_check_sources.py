from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tlb_cache import check_sources  # noqa: E402


class BaselineInventoryTests(unittest.TestCase):
    def test_hash_is_sha256_uppercase(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "image.mif"
            path.write_bytes(b"abc")
            self.assertEqual(
                check_sources.sha256_file(path),
                "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD",
            )

    def test_known_implementation_gaps_are_explicit_at_baseline(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _, gaps = check_sources.collect_candidates(root)
            expected = {relative for relative, role in gaps if role.startswith("required_lab")}
            self.assertEqual(
                expected,
                {"lab13/tlb_verify/rtl/tlb.v", "lab16/cache_verify/rtl/cache.v"},
            )

    def test_completed_modules_are_not_reported_as_gaps(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for relative in ("lab13/tlb_verify/rtl/tlb.v", "lab16/cache_verify/rtl/cache.v"):
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("module placeholder; endmodule\n", encoding="ascii")
            _, gaps = check_sources.collect_candidates(root)
            expected = {relative for relative, role in gaps if role.startswith("required_lab")}
            self.assertEqual(expected, set())


if __name__ == "__main__":
    unittest.main()
