#!/usr/bin/env python3
"""Create a new Vivado WCFG copy with a WDB path relative to the WCFG."""

from __future__ import annotations

import argparse
from pathlib import Path

from build_bus_evidence import make_portable_wcfg, wcfg_db_ref


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-wcfg", type=Path, required=True)
    parser.add_argument("--target-wcfg", type=Path, required=True)
    parser.add_argument("--wdb", type=Path, required=True)
    args = parser.parse_args()
    created = make_portable_wcfg(args.source_wcfg, args.target_wcfg, args.wdb)
    print(f"WCFG={created.resolve()}")
    print(f"WDB={args.wdb.resolve()}")
    print(f"DB_REF={wcfg_db_ref(created)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
