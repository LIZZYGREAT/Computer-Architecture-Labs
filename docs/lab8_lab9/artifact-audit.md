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
