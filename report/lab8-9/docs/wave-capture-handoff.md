# Lab8 / Lab9 Wave screenshot handoff

## Open the matching run

Use Vivado 2025.2 and open each WDB from the same row as its WCFG in `data/wave-capture-log.csv`:

1. Open the run's `.wdb` using **Flow -> Open Static Simulation**.
2. In the Wave window choose **File -> Simulation Waveform -> Open Configuration** and load the listed `.wcfg`.
3. Use **Zoom Fit**, then locate the `search_signal` and exact `search_value` from the CSV. Zoom to the short interval that shows the triggering instruction/event, trap/CP0 updates, flush, and return.
4. Save the PNG using the exact `image_name` under `report/lab8-9/figures/waveforms/final/`.
5. Fill `observed_time_window` and `observed_values` from the Wave display. Keep the expected fields unchanged.

## Final WDB/WCFG pairs

- Lab8 syscall: `lab8-20261109T163413Z/lab8-20261109T163413Z-forwarding.wdb` with `01_syscall.wcfg`.
- Lab9 exceptions/interrupts: `lab9-20261109T163846Z/lab9-20261109T163846Z-forwarding.wdb` with `02_break.wcfg` through `09_software_irq.wcfg`.
- CPU-level external IP2: `interrupt-ip2-20261110T/interrupt-ip2.wdb` with `10_external_interrupt_ip2.wcfg`.

All paths are relative to the repository root; the CSV includes the full path and SHA-256 for each WDB. Other hardware-source WDBs for IP3-IP7 are in `results/lab8_lab9/interrupt-ip3-20261110T/` through `interrupt-ip6-20261110T/`, plus the passing `interrupt-ip7-20261110T-retry/` run.

The WCFGs have already been opened in Vivado against those exact WDBs, and the loaded wave count was checked. No GUI screenshot or observed time/value has been recorded yet.
