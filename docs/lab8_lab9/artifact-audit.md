# Results and waveform artifact audit

Audit completed with Vivado 2025.2 before cleanup.

## Validation

- Opened all 40 WDB files found under `results/` and the Vivado project build folders. Every database opened successfully and contained a nonempty HDL scope tree. This includes intermediate databases that were later removed; their structural validity does not make a failed or superseded run report evidence.
- Opened all 33 existing WCFG files against their referenced WDBs. Every configuration loaded in Vivado, and the loaded signal count matched its declared wave count.
- Removed the 10 Lab8/Lab9 WCFG files directly under `report/lab8-9/figures/waveforms/`. They were valid but referenced earlier captures; the corresponding 10 configurations under `final/` supersede them.
- Kept 13 Lab6/Lab7 WCFGs and 10 final Lab8/Lab9 WCFGs. The remaining 23 configs resolve to these seven WDBs:

| WDB | WCFG count |
|---|---:|
| `results/lab3_lab4/lab3-20261028T132600Z/lab3-20261028T132600Z-forwarding.wdb` | 4 |
| `results/lab6_lab7/lab6-20261102T054949Z/lab6-20261102T054949Z-forwarding.wdb` | 3 |
| `results/lab6_lab7/lab6-20261102T060138Z/lab6-20261102T060138Z-forwarding.wdb` | 1 |
| `results/lab6_lab7/lab7-20261102T055526Z/lab7-20261102T055526Z-forwarding.wdb` | 5 |
| `results/lab8_lab9/lab8-20261109T163413Z/lab8-20261109T163413Z-forwarding.wdb` | 1 |
| `results/lab8_lab9/lab9-20261109T163846Z/lab9-20261109T163846Z-forwarding.wdb` | 8 |
| `results/lab8_lab9/interrupt-ip2-20261110T/interrupt-ip2.wdb` | 1 |

After cleanup, reopened all 17 retained WDBs and all 23 retained WCFGs in Vivado. Every WDB still has a nonempty scope tree; every WCFG loaded with its declared number of signals.

## Retained WDBs

The 17 retained databases are grouped by use:

- Seven WDBs listed above back the remaining WCFGs.
- Three historical Lab4/Lab6/Lab7 captures remain because existing verification notes cite them: `lab4-20261022T041931Z/hazard-directed-forwarding.wdb`, `lab6-20261028T093517Z/lab6-20261028T093517Z-forwarding.wdb`, and `lab7-20261028T102942Z/lab7-20261028T102942Z-forwarding.wdb`.
- The final direct external interrupt captures for IP3-IP7 remain at the roots of their passing run directories. Each opens with the `/interrupt_tb` hierarchy.
- Final CP0 and HI/LO unit-test databases were copied out of generated Vivado project trees into their result directories: `results/lab8_lab9/cp0-unit-20261109T141303Z/cp0-unit.wdb` and `results/lab8_lab9/hilo-cancel-20261109T150200Z/hilo-unit.wdb`.

## Removed artifacts

- Removed failed runs: the first CP0 runner attempt, the failed HILO-cancel attempt, the failed hardware-interrupt attempt, the first IP7 attempt, and the Lab7 environment-error run.
- Removed successful but superseded Lab8/Lab9 captures and earlier single-IP2/wave-capture runs after replacing them with the final course runs and the IP2-IP7 directed suite.
- Removed transient Lab3/Lab4/Lab6/Lab7 runs that were replaced by the final regression set. Results explicitly cited as historical baselines in `design-baseline.md` remain.
- Removed generated `reference-work/`, XSim `.sim`/`xsim.dir` contents, the duplicate WDB and build cache under `mycpu_prj1_wave_recapture`, and per-run `vivado_project/` build trees after preserving the final WDBs and logs needed as evidence. Kept the tracked `mycpu_prj1_wave_recapture.xpr` project recipe.

The final run records and report CSVs continue to point to retained files. `implementation.md` was updated to avoid links to removed diagnostic directories. No screenshots or waveform time values were synthesized during this audit.

## Follow-up after the Lab8/Lab9 revisions

On 2026-11-10, six post-revision course regressions passed (Lab3 through Lab9), and four new CPU-directed WDBs were produced for reserved CP0 decode, precise store ordering, CPU HI/LO ordering, and software/timer interrupts. Each new WDB was opened by Vivado 2025.2; it contained 592 HDL scopes and 11 clock-named objects. The 17 WDBs retained from the earlier audit remain unchanged and were already reopened successfully in Vivado. The repository now has 21 retained WDBs and 23 retained WCFGs.

| New directed WDB | Bytes | SHA-256 | Vivado open |
|---|---:|---|---|
| `cp0-decode-20261110T033652Z/cp0_decode_tb.wdb` | 400,935 | `61B460482CB365D9B3BA228F80B868BE99DA3DB936CADB5F05D14012F78271FF` | PASS; 592 scopes, 11 clock objects |
| `precise-store-20261110T/precise_exception_tb.wdb` | 207,740 | `6675C815B094EF02227B8F6890BF50F8A59595ABA654520EE5DCB6A577C678FC` | PASS; 592 scopes, 11 clock objects |
| `hilo-order-20261110T/hilo_order_tb.wdb` | 223,894 | `041CC49DC57B9A68996B36DEF391EC088053A184B416E3B93100A693844F1D68` | PASS; 592 scopes, 11 clock objects |
| `software-timer-20261110T035119Z/software_timer_irq_tb.wdb` | 253,714 | `7A8CADBE126CD809FBD3868F3F130AFA31B6FF5F7458D9464725725A2BEE55C8` | PASS; 592 scopes, 11 clock objects |

All 23 WCFG files also retain an existing WDB reference, were opened in Vivado against that WDB, and loaded the exact number of signals declared in the configuration:

| WCFG | Referenced WDB | Declared / loaded signals |
|---|---|---:|
| `report/lab6-7/figures/waveforms/01_alu_directed_full_run.wcfg` | Lab3 `lab3-20261028T132600Z-forwarding.wdb` | 17 |
| `report/lab6-7/figures/waveforms/01_alu_immediate.wcfg` | Lab3 `lab3-20261028T132600Z-forwarding.wdb` | 17 |
| `report/lab6-7/figures/waveforms/02_variable_shift.wcfg` | Lab3 `lab3-20261028T132600Z-forwarding.wdb` | 14 |
| `report/lab6-7/figures/waveforms/03_forwarding_load_use.wcfg` | Lab3 `lab3-20261028T132600Z-forwarding.wdb` | 24 |
| `report/lab6-7/figures/waveforms/04_mult_hilo.wcfg` | Lab6 `lab6-20261102T054949Z-forwarding.wdb` | 22 |
| `report/lab6-7/figures/waveforms/05_div_hilo_full_lab6.wcfg` | Lab6 `lab6-20261102T054949Z-forwarding.wdb` | 29 |
| `report/lab6-7/figures/waveforms/05_div_stall_branch_directed.wcfg` | Lab6 `lab6-20261102T060138Z-forwarding.wdb` | 29 |
| `report/lab6-7/figures/waveforms/06_branch_delay_slot_jalr.wcfg` | Lab7 `lab7-20261102T055526Z-forwarding.wdb` | 20 |
| `report/lab6-7/figures/waveforms/07_partial_store_mask.wcfg` | Lab7 `lab7-20261102T055526Z-forwarding.wdb` | 17 |
| `report/lab6-7/figures/waveforms/08_byte_half_load.wcfg` | Lab7 `lab7-20261102T055526Z-forwarding.wdb` | 21 |
| `report/lab6-7/figures/waveforms/09_unaligned_load_merge.wcfg` | Lab7 `lab7-20261102T055526Z-forwarding.wdb` | 19 |
| `report/lab6-7/figures/waveforms/10_store_readback.wcfg` | Lab7 `lab7-20261102T055526Z-forwarding.wdb` | 24 |
| `report/lab6-7/figures/waveforms/11_hilo_unsigned_optional.wcfg` | Lab6 `lab6-20261102T054949Z-forwarding.wdb` | 21 |
| `report/lab8-9/figures/waveforms/01_syscall.wcfg` | Lab8 `lab8-20261109T163413Z-forwarding.wdb` | 21 |
| `report/lab8-9/figures/waveforms/02_break.wcfg` | Lab9 `lab9-20261109T163846Z-forwarding.wdb` | 21 |
| `report/lab8-9/figures/waveforms/03_overflow.wcfg` | Lab9 `lab9-20261109T163846Z-forwarding.wdb` | 30 |
| `report/lab8-9/figures/waveforms/04_load_adel.wcfg` | Lab9 `lab9-20261109T163846Z-forwarding.wdb` | 27 |
| `report/lab8-9/figures/waveforms/05_store_ades.wcfg` | Lab9 `lab9-20261109T163846Z-forwarding.wdb` | 30 |
| `report/lab8-9/figures/waveforms/06_fetch_adel.wcfg` | Lab9 `lab9-20261109T163846Z-forwarding.wdb` | 26 |
| `report/lab8-9/figures/waveforms/07_delay_slot.wcfg` | Lab9 `lab9-20261109T163846Z-forwarding.wdb` | 25 |
| `report/lab8-9/figures/waveforms/08_timer_irq.wcfg` | Lab9 `lab9-20261109T163846Z-forwarding.wdb` | 20 |
| `report/lab8-9/figures/waveforms/09_software_irq.wcfg` | Lab9 `lab9-20261109T163846Z-forwarding.wdb` | 16 |
| `report/lab8-9/figures/waveforms/10_external_interrupt_ip2.wcfg` | IP2 `interrupt-ip2.wdb` | 22 |

The following failed or superseded files were removed after checking their Run IDs and keeping the final replacements:

- `cp0-decode-20261110T/` (Vivado startup failure) and `cp0-decode-20261110T033210Z/` (earlier pass superseded by the final Cause/EPC/ERET-checked run `033652Z`).
- `software-timer-20261110T/` (testbench passed, but its first runner failed to produce a valid summary; replaced by `software-timer-20261110T035119Z/`).
- Rebuildable `vivado_project/`, `xsim.dir/`, and generated per-run wave Tcl files under the retained CP0, precise-store, and HI/LO CPU test results. Their final WDB, simulation log, summary, and Vivado logs are kept.
- Vivado also left an incidental `tb_top_behav.wdb` in the shared Lab7 project output while the fresh run record correctly said `WAVEFORM_CAPTURED=False`. The database opened successfully (973 scopes, 26 clock-named objects), but no WCFG referenced it and it was not included in the run record; it was removed with its disposable `xsim.dir/` cache and per-run Tcl copy. Its SHA-256 was `2C611C090FF67F13E28BD55EB86A210A8963B50C5B5D7052CE30D4112FACD990`.
- Temporary audit probe scripts and logs from a rejected clock-value query. The supported validation record uses Vivado's successful WDB open, hierarchy and recorded-clock object checks, plus the matching WCFG load and wave-count check; it does not claim GUI-observed values or screenshots.

The four new CPU-directed WDBs were checked with `scripts/validate_wave_db.tcl`; each Vivado log is retained under `results/lab8_lab9/wdb-audit-20261110T/`.

The six post-revision course result folders are kept as final regression evidence. They contain fresh `result.txt` files and source/simulation logs, and are indexed in `report/lab8-9/data/evidence_index.csv`; the existing screenshot WDBs remain the separate, validated capture baseline.

## IP2 WDB/WCFG display follow-up

On 2026-11-10, the 10 retained Lab8/Lab9 WCFGs were moved from `report/lab8-9/figures/waveforms/final/` to `report/lab8-9/figures/waveforms/`. The WCFG inventory table above reflects their current paths. The report include paths, asset-builder output directory, and capture handoff were updated to use the same location. `.gitignore` now keeps these WCFGs trackable.

The moved `10_external_interrupt_ip2.wcfg` still references the exact `interrupt-ip2.wdb` in its `<db_ref>` entry. Vivado 2025.2 opened that WDB and WCFG, loaded 22 waves, and the added path check resolved all 22 HDL object names against the WDB hierarchy. The testbench reports PASS with 10 assertions and finishes at 446 ns; its capture script runs `log_wave -r /` before `run 100us`.

The screenshot's visible time window is only 0–12 ps. The testbench uses a 1 ns time unit and a 5 ns half-period, so this view ends long before the first clock transition and cannot show the interrupt sequence. The WCFG has an empty `<zoom_setting>`, which leaves the view without a saved full-run range. Use **Zoom Fit**, then place the cursor after time zero and search `trap_pc[31:0] = 0xBFC0001C`. WCFG loading and path resolution validate the pair, but do not by themselves prove that GUI-visible event values were reviewed; no screenshot or observed values are recorded in the CSV.

A one-off attempt to query event values through live-simulation Tcl commands failed because the WDB is a static, completed simulation. Its temporary script, log, and journal are removed; the successful WCFG open and HDL-path validation logs are retained.
