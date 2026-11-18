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
| `42ff13b` | P0-01/P0-02 CACHE acceptance contract; latch DCache maintenance index, way, tag and line; propagate bridge faults into ICache/DCache terminal states; add atomic result finalizer | Lab19 maintenance 10/10 (`r2l19maint01`); full Top index contract (`r2l19contract03`); Lab19 CACHE 7/7 (`r2l19cache03`); Lab17 fault checks 28 (`r2l17fault06`); Lab18 fault states 4 (`r2l18fault05`); Lab17/18 functional 94/94 (`r2l17func01`, `r2l18func01`) |
| `ac7c99d` | Add TLB-write front-end redirect and stale-response replay; preserve trap/ERET priority | IF redirect checks 7 (`r2l19redirect03`); full Top maintenance contract recompiled and passed (`r2l19contract03`) |
| `89050b4` | Add dedicated Lab17 AXI fault waveform configuration | Four fault cases rerun with WDB/WCFG (`r2l17fault06`) |
| `92db094` | Include Vivado process exit code in final acceptance gate; prevent PASS when Vivado exits nonzero after writing a simulation PASS | `python -m unittest discover -s scripts/tests -p 'test_*.py'`: 19/19; final result `r2l19cache03` records simulation PASS, source integrity PASS and Vivado exit 0 |
| `38f205d` | Add full CPU Top/real TLB/AXI test for a TLB write during an outstanding old-PFN fetch | `r2l19tlbreplay02`: old response dropped; same VA re-read at the new PFN; result and source manifest PASS |
| `925fd70` | Add a real-Store DCache writeback scoreboard for all four ways, including AXI metadata and beat-level backpressure checks | `r2l19wbs01`: 4 CPU Stores create four dirty ways; 32/32 WDATA words match reference memory; 4 AW, 4 B; final result/source integrity PASS |

## Revision 2 file-level changes

| File group | Change |
|---|---|
| `lab19/cpu_cache/rtl/myCPU/mycpu_top.v` | Classify Index and Hit maintenance; align upstream acceptance with the selected cache; gate untranslated Hit requests; connect bridge faults; flush/replay fetch after TLB writes |
| `lab19/cpu_cache/rtl/myCPU/dcache.v` | Lock the accepted Index/Hit set, way, old tag and line; form writeback from that snapshot; invalidate the same line only after B; make bridge failure globally terminal |
| `lab17`, `lab18`, `lab19` ICache copies | Propagate sticky AXI bridge faults into an explicit ICache terminal state without a false instruction completion |
| `lab18/cpu_dcache/rtl/myCPU/dcache.v` | Give bridge failure global priority and stop new request/completion behavior |
| `lab19/cpu_cache/rtl/myCPU/IF_stage.v` | Drop outstanding stale fetches and replay from the saved PC on TLB write commit |
| `scripts/tlb_cache/verify.ps1`, `capture_run_manifest.py`, `finalize_run_result.py` | Keep raw simulator status in `sim-result.txt`; atomically write final result only after simulation exit and source/input integrity checks |
| New directed testbenches | Cover Index acceptance/writeback payload, real CPU Store plus all-way DCache writeback scoreboard, four ICache AXI faults, four DCache fault states, branch/stale-response replay and TLB remap with an outstanding read |

All new final Runs retain their own `source-manifest.csv`, `input_manifest.csv`, raw `sim-result.txt` and authoritative `result.txt`. The Lab17 and Lab18 94/94 outputs are software functional-point regressions, not full instruction-by-instruction golden trace comparisons. Lab15 precise TLB exceptions remain outside this revision; see [unsupported TLB exception scope](unsupported-tlb-exceptions.md).

