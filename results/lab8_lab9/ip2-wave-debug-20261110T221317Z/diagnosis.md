# IP2 blank-wave diagnosis

## Finding

The production capture Tcl was executing: the actual XSim log shows `log_wave -r /` before `run 100us`, then `INTERRUPT_TB_PASS`, followed by `close_vcd`. The fresh VCD contains real activity and passes the existing 22-path/event validator. The top is `interrupt_tb`; no missing-object or `log_wave` error was found. A multiple-WDB selection error was not reproduced: the diagnostic run had exactly one candidate before and after close.

The WDB export order was unsafe. A diagnostic copy taken before `close_sim` was 209,137 bytes; after a successful `close_sim`, the same sole source was 251,593 bytes. The production script previously selected and copied the first WDB before closing. The minimal script change now closes the simulation first, requires exactly one candidate, then copies and size-checks it. A fresh production-script IP2 run created a 251,577-byte post-close WDB whose hash exactly matches the source.

This proves the export timing defect and that the new run uses the finalized WDB. It does **not** prove that this was the sole cause of the original blank Wave window. Both diagnostic copies and the final WDB open statically and bind to all 22 WCFG paths, but headless static Vivado Tcl does not provide historical values: `current_time` returns `[Simulator 45-12]` after the simulation has exited, while `get_value` is documented for current live simulation time and returns empty output here.

## Status

| Check | Result |
|---|---|
| Fresh IP2 testbench | `PASS` — 10 assertions, 1 trap, 1 ERET, 1 resumed store |
| Custom capture Tcl execution | `PASS` — markers confirm the generated Tcl ran |
| `log_wave -r /` before first run | `PASS` |
| Same-run VCD events | `PASS` — 89 clock transitions; interrupt, trap, EPC, ERET, and resumed store values verified |
| WDB source candidate uniqueness | `PASS` — exactly one before and after close in diagnostic; exactly one after close in revised production run |
| Close/copy behavior | `PASS` — close changes the database; revised script copies after close and the archive hash matches its source |
| WDB/WCFG path binding | `PASS` — final static database opens with 22/22 configured HDL objects |
| Numeric values rendered in Vivado Wave UI | `GUI_PENDING` — not tested, per user's instruction not to use computer-use/UI automation |

## User-facing artifact

Candidate paired files from the fresh post-close run:

- `results/lab8_lab9/ip2-wave-debug-20261110T221317Z/interrupt-ip2.wdb`
- `results/lab8_lab9/ip2-wave-debug-20261110T221317Z/final-interrupt-ip2.wcfg`

The WCFG references this exact WDB and preserves the 22 configured paths. The original WDB/WCFG remain untouched. A one-time GUI read is still required before claiming the original blank-wave issue is fully fixed.
