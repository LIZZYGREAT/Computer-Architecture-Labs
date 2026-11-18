# Lab19 CACHE and Performance Acceptance

**Branch:** `lab12-lab19`
**Implementation commit:** `4ba901c186567560dea1ca2fdfd1a73edf895fc5`
**Status:** functional acceptance PASS; synthesis completed with timing limitations recorded below.

## Results

| Suite | Final run | Result |
| --- | --- | --- |
| Official CACHE instruction tests | [lab19-cache-20261118-06](../../../results/lab13-lab19/lab19/lab19-cache-20261118-06/result.txt) | PASS, 7/7; 2,836 cycles; 458 retired instructions; 28/28 stores accepted/completed, no duplicate stores |
| CACHE maintenance directed | [lab19-maint-directed-20261118-06](../../../results/lab13-lab19/lab19/lab19-maint-directed-20261118-06/result.txt) | PASS, 9 directed checks; ways 2/3, TagLo valid/dirty state, hit invalidation without writeback, dirty writeback delayed by B response |
| Dhrystone | [lab19-dhrystone-20261118-06](../../../results/lab13-lab19/lab19/lab19-dhrystone-20261118-06/result.txt) | PASS; 251,834 cycles, 51,073 retired instructions; normal program completion |
| CoreMark | [lab19-coremark-20261118-03](../../../results/lab13-lab19/lab19/lab19-coremark-20261118-03/result.txt) | PASS; 2,305,331 cycles, 416,073 retired instructions; normal program completion |
| Top-level synthesis | [lab19-synthesis-20261118-01](../../../results/lab13-lab19/lab19/lab19-synthesis-20261118-01/result.txt) | `soc_axi_lite_top` synth_design completed; 0 errors, 0 critical warnings; resource and timing reports generated |

The official CACHE run executed the expected maintenance sequence: `ICIndexInv=2`, `ICIndexStTag=2`, `ICHitInv=1`, `DCIndexWBInv=2`, `DCIndexStTag=2`, `DCHitInv=1`, and `DCHitWBInv=1`. Its counters were ICache hit/miss/refill `397/51/51`, ICache uncache reads `19`, DCache hit/miss/writeback/uncache `2/4/2/45`, and AXI AR/R/AW/W/B `95/480/26/40/26`. The directed test verifies 9 additional cases and chooses ways 2 and 3. Its marker records `hitinv_no_writeback=1`, `writebacks=2`, and a wait for B before completion.

## Performance

| Program | Cycles | Retired | I hit/miss/refill | D hit/miss/writeback/uncache | AXI AR/R/AW/W/B | Program output |
| --- | ---: | ---: | --- | --- | --- | --- |
| Dhrystone | 251,834 | 51,073 | 40,789 / 133 / 133 | 6,579 / 13 / 0 / 4,559 | 12,675 / 13,697 / 2,185 / 2,185 / 2,185 | `num_data=0003343c`; program PASS |
| CoreMark | 2,305,331 | 416,073 | 260,271 / 508 / 508 | 77,338 / 70 / 0 / 7,507 | 162,251 / 166,297 / 1,130 / 1,130 / 1,130 | `num_data=01394d3c`; program PASS |

The simulation testbench ran at 100 MHz (10 ns clock). The firmware's performance report is calibrated/configured at 50 MHz: Dhrystone reports 47,846 Dhrystones/s and 0.544 DMIPS/MHz; CoreMark reports 48,704 iterations/1000 s and 0.974 CoreMark/MHz. These are observed program outputs, not a same-condition speedup comparison. No Lab19 non-cache baseline was run, so no speedup is claimed. CoreMark also prints the source placeholder `Memory location: Please put data memory location here`; the program's correctness and PASS markers are present.

## Synthesis and limits

Vivado 2025.2 synthesized `soc_axi_lite_top` for `xc7a200tfbg676-2`. Utilization is LUT 25,278/134,600 (18.78%), registers 11,112/269,200 (4.13%), BRAM tiles 256/365 (70.14%), DSP 0/740, and IOB 55/400. Setup WNS/TNS are 3.975 ns/0 ns in the synthesis summary. Hold WHS/THS are -0.087 ns/-5.338 ns with 66 hold-failing endpoints, mainly between related CPU and timer clock paths. No placement/routing was run, and external I/O delays are not constrained. Thus the RTL synthesizes and resources are available, but hardware timing closure remains outstanding. The 131 warnings are categorized in `warnings-summary.txt`.

## Waveform evidence

The official and directed runs keep paired WDB/WCFG files. `wave-validation/config-validation.log` confirms each WCFG opens in Vivado with every signal path resolved; `wcfg-structure.txt` records the hashes and WDB references. See [waveform-index.txt](waveform-index.txt) and the L19 rows in [wave-capture-log.csv](../../../report/lab13-19/data/wave-capture-log.csv). GUI screenshots and manually read waveform values/times have not been captured; those fields remain `PENDING_CAPTURE` as required by the handoff plan.
