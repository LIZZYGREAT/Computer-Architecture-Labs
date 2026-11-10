# IP2 waveform capture sequence

## Existing capture flow

The checked-in `scripts/run_interrupt_tb.tcl` creates a fresh `interrupt_tb` project and makes `interrupt_tb` the simulation top. For IP2 it defines `IRQ_INDEX=0`, corresponding to hardware interrupt bit 2. It generates `capture_interrupt_wave.tcl`, sets it as `XSIM.SIMULATE.CUSTOM_TCL`, then calls `launch_simulation`.

The generated Tcl runs in this order:

1. `open_vcd` creates the same-run VCD.
2. 22 explicit `log_vcd` commands record the configured signal paths.
3. `log_wave -r /` is executed before any simulation time advances.
4. `run 100us` runs the testbench to completion; the testbench finishes at 446 ns.
5. `close_vcd` completes VCD output.

The fresh diagnostic Vivado log contains `CUSTOM_CAPTURE_BEGIN`, `CUSTOM_CAPTURE_VCD_OPEN`, `CUSTOM_CAPTURE_LOG_WAVE_BEGIN`, `CUSTOM_CAPTURE_LOG_WAVE_DONE`, `INTERRUPT_TB_PASS`, and `CUSTOM_CAPTURE_VCD_CLOSED` in that order. `log_wave -r /` emitted no error, and there was no `[Simtcl 6-55] No matching HDL object` message. The same-run VCD validator reports 89 clock transitions and all expected IP2 events.

## Close-order experiment

Diagnostic run `ip2-wave-debug-20261110T213020` enumerated exactly one WDB candidate at the expected project path before closing. The diagnostic copy before close was 209,137 bytes. `close_sim` returned PASS. The same single source remained afterward and was 251,593 bytes; `close_project` also returned PASS. Separate static batch sessions opened both copies and loaded their paired 22-path WCFGs. The CLI did not expose numerical values from either static database; therefore these checks do not prove that either copy renders values.

This directly establishes that copying before `close_sim` exports a different file from copying afterward. It supports moving archival after close, but does not by itself prove that close order was the user's blank-wave root cause.

## Production-script rerun

Run `ip2-wave-debug-20261110T221317Z` used the revised production script:

1. Vivado 2025.2 batch mode created and elaborated a fresh project.
2. The XSim custom Tcl logged 22 VCD paths and called `log_wave -r /` before `run 100us`.
3. Testbench reported `ASSERTIONS_PASS=10`, `TRAPS_OBSERVED=1`, `STATUS=PASS`, and `INTERRUPT_TB_PASS`; `$finish` occurred at 446 ns.
4. VCD closed; `close_sim` returned PASS.
5. The script found exactly one post-close WDB at `vivado_project/interrupt_tb.sim/sim_1/behav/xsim/interrupt_tb_behav.wdb`, copied it, and verified equal source/destination sizes. Independent SHA-256 checks also match: `42EC99EF073385D5773BE8D77C4334E47B928AE6423E0E40D3BA30DA12A141F1`.
6. `close_project` returned PASS.
7. `validate_interrupt_vcd.py` passed on this run's VCD and paired WCFG. Vivado batch static validation opened the same WDB/WCFG and resolved all 22 paths.

The headless static-value probe loaded the WDB and WCFG and enumerated 22 waves. `current_time` returned Vivado error `[Simulator 45-12]` because no live simulation exists, and `get_value` returned empty output in static mode. AMD documents `get_value` as a current simulation run-time query; this is not evidence that the WDB's graphical waveform data is empty. No GUI inspection was performed, so `WDB_VALUE_VISIBLE=GUI_PENDING`.

No RTL or testbench logic was changed. No Vivado GUI window was opened for these latest batch runs; no `vivado` or `xsim` process remained afterward.
