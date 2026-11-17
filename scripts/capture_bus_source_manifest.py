#!/usr/bin/env python3
"""Capture PRE_SIM and POST_SIM hashes for the exact generated Vivado XPR inputs."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from source_provenance import (
    SourceProvenanceError,
    collect_source_rows,
    read_manifest,
    refresh_post_rows,
    write_integrity_report,
    write_manifest,
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--case", choices=("lab10", "lab11"), required=True)
    parser.add_argument("--suite", choices=("directed", "full"), required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--xpr", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--phase", choices=("PRE_SIM", "POST_SIM"), required=True)
    parser.add_argument("--coe", type=Path)
    parser.add_argument("--mif", type=Path)
    parser.add_argument("--trace", type=Path)
    parser.add_argument("--inst-override", action="store_true")
    args = parser.parse_args()

    root = args.repo_root.resolve()
    settings_path = root / "scripts/cases_bus.json"
    settings = json.loads(settings_path.read_text(encoding="utf-8"))[args.case]
    xpr = args.xpr if args.xpr.is_absolute() else root / args.xpr
    manifest = args.manifest if args.manifest.is_absolute() else root / args.manifest
    integrity_path = manifest.parent / "source-integrity.txt"

    try:
        if args.phase == "PRE_SIM":
            rows = collect_source_rows(
                root, args.case, args.suite, args.run_id, xpr, settings,
                coe_path=args.coe, mif_path=args.mif, trace_path=args.trace,
                has_inst_override=args.inst_override, phase="PRE_SIM",
            )
            write_manifest(manifest, rows)
            status = write_integrity_report(integrity_path, rows, "PRE_SIM")
            print(f"EFFECTIVE_SOURCE_MANIFEST={manifest}")
            print(f"PRE_SIM_SOURCE_COUNT={len(rows)}")
            print(f"SOURCE_INTEGRITY={status}")
            if status == "FAIL":
                return 3
            return 0

        if not manifest.is_file():
            raise SourceProvenanceError(f"PRE_SIM source manifest is missing: {manifest}")
        pre_rows = read_manifest(manifest)
        if not pre_rows or any(row.get("source_phase") != "PRE_SIM" for row in pre_rows):
            raise SourceProvenanceError("POST_SIM capture requires an existing PRE_SIM-only manifest")
        post_rows = refresh_post_rows(root, pre_rows)
        all_rows = pre_rows + post_rows
        write_manifest(manifest, all_rows, allow_replace=True)
        status = write_integrity_report(integrity_path, all_rows, "POST_SIM")
        print(f"EFFECTIVE_SOURCE_MANIFEST={manifest}")
        print(f"POST_SIM_SOURCE_COUNT={len(post_rows)}")
        print(f"SOURCE_INTEGRITY={status}")
        return 0
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(f"SOURCE_MANIFEST_ERROR={type(exc).__name__}: {exc}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
