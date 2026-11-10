# Lab8 / Lab9 waveform plan

The screenshot set is prepared as 10 focused Wave configurations. Exact run IDs, paths, hashes, search values, expected values and blank observed-value fields are in `report/lab8-9/data/wave-capture-log.csv`.

| Figure | Event | WDB source | Search anchor |
|---|---|---|---|
| 01 | Lab8 syscall | Final Lab8 course WDB | `ds_pc[31:0] = 0xBFC1DDFC` |
| 02 | Lab9 break | Final Lab9 course WDB | `es_pc[31:0] = 0xBFC864EC` |
| 03 | Signed ADD overflow | Final Lab9 course WDB | `es_pc[31:0] = 0xBFC3BA4C` |
| 04 | Misaligned LW / AdEL | Final Lab9 course WDB | `es_pc[31:0] = 0xBFC68E4C` |
| 05 | Misaligned SW / AdES | Final Lab9 course WDB | `es_pc[31:0] = 0xBFC7E348` |
| 06 | Misaligned instruction fetch | Final Lab9 course WDB | `bad_vaddr[31:0] = 0xB27F9789` |
| 07 | Syscall in branch delay slot | Final Lab9 course WDB | `epc[31:0] = 0xBFC97F3C` |
| 08 | Count/Compare timer interrupt | Final Lab9 course WDB | `epc[31:0] = 0xBFC5FA8C` |
| 09 | Cause software interrupt | Final Lab9 course WDB | `epc[31:0] = 0xBFC16C54` |
| 10 | CPU-level external IP2 | Standalone IP2 directed WDB | `trap_pc[31:0] = 0xBFC0001C` |

Every WCFG is bound to the matching WDB and has already been opened in Vivado to confirm the declared signal count. The full Lab9 exception and interrupt configurations include PC, exception metadata, CP0 state and flush/return signals. The standalone IP2 configuration includes the `hw_int`, Cause, Status, trap, ERET and interrupted GPR/store evidence.

The CPU-level tests also create separate WDBs for IP3-IP7. They are indexed in `evidence_index.csv`; the selected 10-image report set uses IP2 as the representative hardware-interrupt waveform and does not imply that the other five routes were skipped.

Do not fill `observed_time_window` or `observed_values` using the expected column, course source, reference trace, or static PC extraction. Record those only after reading the matching WDB in Vivado.
