# IP2 WDB close-order diagnostic

Run ID: `ip2-wave-debug-20261110T213020`; Vivado 2025.2; isolated `interrupt_tb` project; IP2 (`IRQ_INDEX=0`). The production RTL and testbench were not changed. `diagnostic-runner.tcl` is a local copy of the production runner with markers and before/after-close WDB capture added.

## Observations

- The actual generated `capture_interrupt_wave.tcl` ran. The Vivado log records, in order: `CUSTOM_CAPTURE_BEGIN=1`, VCD open, `CUSTOM_CAPTURE_LOG_WAVE_BEGIN=1`, `CUSTOM_CAPTURE_LOG_WAVE_DONE=1`, the IP2 `INTERRUPT_TB_PASS`, then VCD close. Thus `log_wave -r /` ran before `run 100us` and returned without error.
- Testbench result: 10 assertions passed, one trap, one ERET, one resumed store, `$finish` at 446 ns.
- The candidate list contained exactly one WDB both before and after `close_sim`, at `fresh-ip2-run/vivado_project/interrupt_tb.sim/sim_1/behav/xsim/interrupt_tb_behav.wdb`.
- Before close: 209,137 bytes, SHA-256 `6F61DCB1AC726B6244231B46EB8E7C5EDDC04E176FEC976FA9894913B8B7BEF3`.
- `CLOSE_SIM_STATUS=PASS`.
- After close: 251,593 bytes, SHA-256 `0A51EC751C7F51357B800F77BA1F61462F5F31D244468550440C9FD74CE0FC60`.
- `CLOSE_PROJECT_STATUS=PASS`.
- Same-run VCD validation passed: 22 configured paths matched, 89 clock transitions, expected interrupt/trap/EPC/ERET/store values.
- Separate Vivado batch static sessions opened each database with its paired 22-wave WCFG and resolved all 22 HDL paths. Headless Tcl did not expose historical numeric values; both display checks remain `GUI_PENDING`.

## Conclusion

The database is materially changed by `close_sim`, and the old production script copied it before that close. Therefore WDB archival has been moved after close in the production runner. This is an evidence-backed export-order correction, but byte growth alone does not prove it is the root cause of the original blank Wave window. Final value visibility still requires a single GUI check of the new post-close run.
