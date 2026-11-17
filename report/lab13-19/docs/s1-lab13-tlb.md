# S1 Lab13 TLB Implementation and Acceptance

## Implementation

`lab13/tlb_verify/rtl/tlb.v` implements the official Lab13 interface with a parameterized 16-entry default table. Each entry stores VPN2, ASID, Global, and the two PFN/C/D/V page records. Indexed writes update one entry; indexed reads return the stored fields; two independent combinational search ports compare VPN2 and either Global or ASID, then select the even or odd page. The `found` result reports a tag match independently of the selected page's V bit. If multiple entries match, the lowest index wins.

The official module interface has no reset input. The entry-valid vector starts clear in FPGA configuration, so an unwritten entry cannot hit and its indexed read returns zeros. No PA=VA miss fallback is present.

## Acceptance records

| Run | Result | Evidence |
| --- | --- | --- |
| `lab13-tlb-official-unit-20261118-01` | Official wrapper printed `OK!!!write`, `OK!!!read`, `OK!!!search`, `Test end!`, and `----PASS!!!`; 16 writes, 16 indexed readbacks, and 26 lookup-port cases completed with zero test error. | [Run record](../../../results/lab13_19/lab13/lab13-tlb-official-unit-20261118-01/) |
| `lab13-tlb-directed-20261118-04` | Nine directed checks passed, including simultaneous lookup ports, ASID and Global matching, both page halves, invalid-page hit reporting, readback, unwritten-entry behavior, and overwrite. | [Run record](../../../results/lab13_19/lab13/lab13-tlb-directed-20261118-04/) |

The official project wrapper and testbench were used unchanged. Because the legacy Clocking Wizard is locked in Vivado 2025.2, these cycle-based unit runs use the pass-through `clk_pll` shim in an isolated generated project. The original project and XCI remain unchanged; this unit-level result does not claim CPU/CP0 integration, which is covered by S2.

## Waveform evidence

Both official WCFG files are generated from and reopen successfully against the official run's `wave-full.wdb`:

- [`01_tlb_write_read__lab13-tlb-official-unit-20261118-01.wcfg`](../figures/lab13/01_tlb_write_read__lab13-tlb-official-unit-20261118-01.wcfg)
- [`02_tlb_dual_search__lab13-tlb-official-unit-20261118-01.wcfg`](../figures/lab13/02_tlb_dual_search__lab13-tlb-official-unit-20261118-01.wcfg)

The WDB and active-source manifest hashes are recorded in the run directory and evidence CSVs. The configurations are structurally validated, but no screenshot or manual value/time inspection is claimed. `wave-capture-log.csv` therefore keeps both figures at `PENDING_CAPTURE`.

## Reproduction

From the repository root, use `scripts/tlb_cache/run_unit.tcl` with case `lab13` and suite `official` or `directed`. The run record stores its generated XPR, Vivado compile order, compile/elaboration/simulation logs, waveform database, active-source list, input manifest, source hash manifest, and source-integrity status. The official source set substitutes only the PLL clock shim; it includes the unchanged official wrapper and testbench.
