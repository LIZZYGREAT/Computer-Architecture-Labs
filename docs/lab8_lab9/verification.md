# Lab8 / Lab9 verification record

## Environment and method

- Tool: Vivado 2025.2 / XSim, Windows host outside AppContainer.
- CPU mode: forwarding.
- Reference: CPU132 GPR trace generated from the matching, unchanged course MIF.
- Vivado project checks: repository preflight passed before each `verify.ps1` run.
- Course scripts: `scripts/verify.ps1`, `scripts/run_behavioral_sim.tcl`, `scripts/generate_reference_trace.ps1`.
- Wave logging: final Lab8/Lab9 captures use `log_wave -r /`; their simulation logs contain no `[Simtcl 6-55] No matching HDL object or HDL scope found` warning.

The final course-run `result.txt` records the actual MIF, trace, hashes, counters, WDB hash, fresh compile/elaborate/simulate logs, and PASS status. WDB files are intentionally left in `results/` and are not part of the RTL commits.

## Final course regressions

| Case | Run ID | Points | Cycles | Stall cycles | Reference trace | Result |
|---|---|---:|---:|---:|---|---|
| Lab3 | `lab3-20261109T164953Z` | 23/23 | 172,599 | 0 | Full match | PASS |
| Lab4 | `lab4-20261109T165423Z` | 23/23 | 114,577 | 50 | Full match | PASS |
| Lab6 | `lab6-20261109T165828Z` | 42/42 | 109,439 | 89 | Full match | PASS |
| Lab7 | `lab7-20261109T170251Z` | 68/68 | 166,330 | 926 | Full match | PASS |
| Lab8 | `lab8-20261109T163413Z` | 69/69 | 166,850 | 986 | Full match | PASS, WDB captured |
| Lab9 | `lab9-20261109T163846Z` | 94/94 | 195,004 | 3,910 | Full match | PASS, WDB captured |

The final Lab8 input hashes are MIF `D611D547FFDC000F003673B1B9276D1BA813C15008BE071EE6B639DE278ABF51` and trace `F6A7268A79725186B9EC8602A404CC5BE8E1D439E93ACAD1B2ADA04937723994`. Lab9 uses MIF `392C6386B57F4780536A54F1F5AF34E7749E9AF61CB2DB5703685C4C04CFEB01` and trace `8AEE862561B79A7020E1753590B25E37DBB4ECC379E9B75B234F9FA6212F30CF`. Both final `result.txt` files contain the corresponding WDB SHA-256.

The final SoC wrapper reruns used the same simulation behavior as the earlier legacy tests: `SIMULATION=1` hardwires the external interrupt source to zero. The six final course runs below were all executed after this wrapper change.

## Directed tests

| Test | Run ID / evidence folder | Assertions and result |
|---|---|---|
| CP0 register unit | `cp0-unit-20261109T141303Z` | 62 assertions, 2 traps, PASS |
| CP0 reserved-field CPU decode | `cp0-decode-20261110T033652Z` | 24 assertions; legal MFC0/MTC0 unchanged; 2 malformed MFC0 + 2 malformed MTC0 each RI=10, Cause/EPC/ERET verified, no GPR/CP0/SRAM side effects; PASS |
| HI/LO divide cancellation | `hilo-cancel-20261109T150200Z` | `HILO_UNIT_TB_PASS`; 3 mult accepts, 5 div accepts, 6 result commits; cancelled divide did not commit |
| External IP2 | `interrupt-ip2-20261110T` | 10 assertions, 1 trap, 1 ERET, 1 resumed store, PASS |
| External IP3 | `interrupt-ip3-20261110T` | 10 assertions, 1 trap, 1 ERET, 1 resumed store, PASS |
| External IP4 | `interrupt-ip4-20261110T` | 10 assertions, 1 trap, 1 ERET, 1 resumed store, PASS |
| External IP5 | `interrupt-ip5-20261110T` | 10 assertions, 1 trap, 1 ERET, 1 resumed store, PASS |
| External IP6 | `interrupt-ip6-20261110T` | 10 assertions, 1 trap, 1 ERET, 1 resumed store, PASS |
| External IP7 | `interrupt-ip7-20261110T-retry` | 10 assertions, 1 trap, 1 ERET, 1 resumed store, PASS |

Each external-input test starts with one `hw_int` bit asserted while its Status.IM bit is clear. It checks that the request remains masked, enables that bit, verifies the trap vector and EPC path, confirms the interrupted GPR write and trap-cycle store are suppressed, clears the source in the trap monitor, and checks that ERET resumes the program and its following store commits once. The IP7 test first writes Compare to clear the reset-time TI latch, so the accepted event is attributable to external IP7.

## Requirement coverage and remaining test depth

| Plan area | Evidence | Status |
|---|---|---|
| T00 legacy behavior | Final Lab3/4/6/7 course runs and full trace matches | PASS |
| T01 CP0 behavior | CP0 unit test: masks, exceptions, EPC/BD, timer, software/hardware IP mapping | PASS |
| T02 syscall and Lab8 | Final Lab8 69/69 and matching trace | PASS |
| T03 CP0 instructions and return | Lab8 course run; CP0 read/write and ERET flow | PASS |
| T03a reserved CP0 instruction fields | CPU-level decode test for `[10:6]` and `[5:3]` on MFC0/MTC0 | PASS |
| T04-T08 synchronous exceptions | Lab9 94/94 and matching trace, including break, OV, data/fetch AdEL, AdES, RI, delay-slot EPC/BD | PASS at course-image level |
| T09 timer interrupt | Lab9 `n81` path plus CP0 timer unit checks for TI/IP7, mask and Compare clear | PASS at course-image and CP0-unit levels |
| T10 software interrupt | Lab9 `n82` path plus CP0 IP0/IP1 mask and clear checks | PASS at course-image and CP0-unit levels |
| T11-T12 external hardware IP2-IP7 | Six separate CPU-level mask/take/clear/ERET tests | PASS |
| T13 interrupt masks and IP7 merge | CP0 unit covers IE/IM and IP7 OR; direct IP7 run isolates external input | PASS at CP0 and CPU levels |
| T14 synchronous exception store ordering | Course image and external-interrupt flush test cover relevant pieces | Partial: no dedicated old-store/faulting-store/younger-store sequence with RAM scoreboard |
| T15 exception during in-flight HI/LO operation | HI/LO unit directly tests cancel and preservation | Partial: no integrated CPU test that raises a synchronous exception while a divide is in flight |
| T16 complete Lab9 image | Final Lab9 94/94 and full reference trace | PASS |
| T17 branch, delay slot and ERET | Lab9 delay-slot tests and CP0/ERET integration | PASS at course-image level |
| T18 timeout and waveform quality | Verify timeout, fresh log checks, WDB hash, static WCFG load/count validation | PASS for executed tests |

The two partial rows are kept explicit; course functional points and a HI/LO unit test do not prove those stronger directed interleavings by themselves.

## Waveform validation

The final screenshot set contains 10 WCFG files under `report/lab8-9/figures/waveforms/final/`: one syscall profile bound to the final Lab8 WDB, eight exception/timer/software profiles bound to the final Lab9 WDB, and one CPU-level IP2 profile bound to its standalone WDB. `scripts/validate_wave_configs.tcl` opened all 10 against their matching WDBs in Vivado. Each loaded wave count matched the WCFG declaration (21, 21, 30, 27, 30, 26, 25, 20, 16, and 22 signals).

No PNG screenshots or GUI-observed time windows have been created. The observed-time and observed-value columns in `report/lab8-9/data/wave-capture-log.csv` remain blank for the user to fill after opening each matching WDB/WCFG. Expected values in that table come from the course instruction image, source or the directed CPU testbench; they are not labelled as WDB observations.
