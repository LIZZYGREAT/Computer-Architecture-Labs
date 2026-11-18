# Lab13–Lab19 Revision 2 Baseline

## Repository state at revision start

- Date: 2026-11-18 (Asia/Shanghai)
- Branch: `lab13-lab19`
- HEAD: `1fe75eeb74f9f5c54d681fae32a4ffba6935af41` (`chore(results): rename lab13-lab19 evidence directory`)
- Working tree: clean before this baseline file was added.
- The review memo names `lab12-lab19@7cab72cf`; the checked-out branch has advanced to the evidence-directory rename commit above. No remote fetch or source rewrite was performed. Historical acceptance Runs continue to point to the source commits recorded in `evidence_index.csv`.

## Baseline RTL SHA-256

| File | SHA-256 |
|---|---|
| `lab19/cpu_cache/rtl/myCPU/mycpu_top.v` | `CF882477E94D896ABDE44821A0ED3A47874595785705FB7582EB1AE3A379F523` |
| `lab19/cpu_cache/rtl/myCPU/dcache.v` | `990AFB30588674765A58E217F5F36043645495CFD0C8A97BB05338746F72BCCD` |
| `lab19/cpu_cache/rtl/myCPU/icache.v` | `AD7E13CFB2267FBCBCF0BF60F1CD8D673853EA51A8FEB9A220D0133DA069A28B` |
| `lab18/cpu_dcache/rtl/myCPU/dcache.v` | `78E47AE8C4AEBD6CEFD29A3A81D0E7FE571A5771B4D71BDF781D3B9CF090805B` |
| `lab18/cpu_dcache/rtl/myCPU/icache.v` | `7E39BAF03D3EEE638938BC227E73BE9F49E90ACFCEA71250C4BFF54674868BAF` |
| `lab17/cpu_icache/rtl/myCPU/icache.v` | `7E39BAF03D3EEE638938BC227E73BE9F49E90ACFCEA71250C4BFF54674868BAF` |
| `scripts/tlb_cache/run_unit.tcl` | `6FB3E3AE89230D72F1FDAA49FEA9DF5E9D9BCBCFB241211AAA5063CAFDD36042` |
| `scripts/tlb_cache/verify.ps1` | `191E3DC7F8C116A590144E340DCAB62609AED261A3A2FDCE78428EA167A382BE` |

## Existing accepted Runs

These are the Runs indexed by `report/lab13-19/data/evidence_index.csv` and present under `results/lab13-lab19/`. They are historical evidence tied to their recorded source SHAs; they are not evidence for the Revision 2 source.

| Area | Run ID | Result |
|---|---|---|
| Baseline/merge | `s0-merge-baseline-20261118-02` | `BASELINE_CAPTURED` |
| Lab13 official / directed | `lab13-tlb-official-unit-20261118-01` / `lab13-tlb-directed-20261118-04` | PASS / PASS |
| Lab14 official / translation | `lab14-n1-n6-official-20261118-05` / `lab14-translate-directed-20261118-02` | PASS / PASS |
| Lab11 AXI3 / golden trace | `lab11-axi3-directed-20261118-02` / `lab11-cpu-golden-20261118-03` | PASS / PASS (94/94; 111,625 trace rows) |
| Lab16 official / directed | `lab16-official-20261118-05` / `lab16-directed-20261118-02` | PASS / PASS |
| Lab17 functional / bridge directed / no-cache baseline | `lab17-icache-functional-20261118-02` / `lab17-bridge-directed-20261118-06` / `lab17-baseline-functional-20261118-01` | PASS / PASS / PASS |
| Lab18 functional / DCache directed / arbitration / MEM exception | `lab18-dcache-functional-20261118-02` / `lab18-dcache-directed-20261118-01` / `lab18-cache-arbitration-20261118-02` / `lab18-mem-exception-20261118-02` | PASS / PASS / PASS / PASS |
| Lab19 CACHE / maintenance / Dhrystone / CoreMark / synthesis | `lab19-cache-20261118-06` / `lab19-maint-directed-20261118-06` / `lab19-dhrystone-20261118-06` / `lab19-coremark-20261118-03` / `lab19-synthesis-20261118-01` | PASS / PASS / PASS / PASS / PASS |

All indexed Run directories have a purpose in the evidence index or the final verification report. No prior Run directory is removed by this revision. Rebuildable root simulator caches `.Xil/` and `xsim.dir/` are excluded from retained evidence and may be removed after confirming they contain only generated products.

## Revision 2 scope and evidence rules

- Review targets: Lab19 CACHE Index acceptance/target selection, bridge-fault termination in ICache/DCache, targeted regressions, verification-result integrity, and accurately indexed Revision 2 evidence.
- Lab17/18 copies are changed only where the shared ICache fault behavior is applicable; their distinct DCache and pipeline changes remain local.
- Each new Run uses a unique ID and records its actual source/input manifests. Existing historical Run files and hashes remain unchanged.
- Lab15 TLB Refill/Invalid/Modified precise exceptions remain `NOT_REQUIRED` / unsupported by scope. Place/route hold closure and manual waveform screenshots remain separate evidence items.
- Baseline evidence and plans are not represented as newly rerun. New test results are recorded only after the actual tool exits successfully and their manifest is captured.

## Implementation and test log

| Revision commit | Change | Test / result |
|---|---|---|
| Pending | P0-01/P0-02 CACHE acceptance and DCache Index target locking | Pending |
| Pending | P1-03/P1-04 bridge fault termination | Pending |
| Pending | Verification script status gating and P2 targeted checks | Pending |

