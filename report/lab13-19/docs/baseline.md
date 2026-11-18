# S0 Baseline and Project Inventory

## Branch and starting state

The implementation branch is `lab12-lab19`. It started at `3ee4fcdc5b512f05000cce47fc2bac658b722a0b` with a clean worktree. The original Lab10/Lab11 integration was merge commit `64e2586cbd94856abef57cabb9142d839c56f3bc`, including commits `e95923c` and `c6c2920`. After the `lab10-lab11` cleanup commit `c8a6ea9a5616f346b20d323bc10c153a20de3567`, that updated branch state was merged here as `ccf9c3f4fc9fad9074af3c3d6b09631687e18c95`.

Vivado 2025.2 is installed and starts in batch mode. The Lab10/Lab11 cleanup removed the earlier directed run `lab11-source-provenance-directed-20261118-03`; its remaining CSV entries are historical audit data, not a retained run directory. Current Lab11 regression evidence is retained in the [AXI3 directed run result](../../../results/lab13_19/lab14/lab11-axi3-directed-20261118-02/result.txt) and the [CPU golden-trace run result](../../../results/lab13_19/lab14/lab11-cpu-golden-20261118-03/result.txt).

## Official unit projects

The original Lab13 and Lab16 XPRs were opened with Vivado 2025.2 using `open_project -read_only`. Their original XPR and XCI files remain unchanged. Both projects target `xc7a200tfbg676-1`, set their simulation top to `testbench`, and contain only two `sources_1` entries: the wrapper RTL and `clk_pll.xci`.

Both projects were created with Vivado 2019.2. Their `clk_pll` Clocking Wizard is IP 6.0 revision 4; Vivado 2025.2 offers revision 17 and reports the IP as locked while the project is read-only. The reports and logs are preserved in [the S0 run record](../../../results/lab13_19/baseline/s0-merge-baseline-20261118-02/). Simulation must use a private project copy and upgrade/regenerate the IP there. Do not upgrade the official XCI in place.

The wrappers instantiate modules absent from the baseline:

- `lab13/tlb_verify/rtl/tlb_top.v` instantiates `tlb`; `lab13/tlb_verify/rtl/tlb.v` is missing.
- `lab16/cache_verify/rtl/cache_top.v` instantiates `cache`; `lab16/cache_verify/rtl/cache.v` is missing.

The project inspection is therefore a baseline capture, not a functional PASS. `gap-audit.csv` records these two expected implementation gaps; there are no missing required program images.

## Test and image inventory

- Lab14 contains nine assembly programs, `n1` through `n9`; this work requires `n1` through `n6`.
- Lab19 contains seven CACHE instruction programs, `n1` through `n7`.
- Lab17 has separate 94-case MIF and COE images. The recorded MIF SHA-256 is `EDBB24B49279647E081627DDF0092420FA756361AB09461DB8B6FE69031ABB3B`.
- The Lab19 performance images are kept separate: Dhrystone MIF SHA-256 `2EBC64DD562DAD57C687327B5F34F94A4929CF505D1A01530A417E97A60FE99F`; CoreMark MIF SHA-256 `02433053DD345EEBE63D19DB96820C4E31B133DC96C6546D83AD013E7AE6AC6E`.
- `lab19/perf_func/include/asm/r4kcache.h` declares four ways, 4 KiB per way, 32-byte I/D lines, and way bit 12. Lab16's official wrapper uses four ways and a 128-bit (16-byte) line. The implementation must preserve both configurations.

Full candidate-source and image hashes are in the S0 `source-candidate-manifest.csv` and `input_manifest.csv`. These are inventory hashes; final runs must separately record Vivado's actual active source set and compile order.

## Baseline checks

`python -m unittest discover -s scripts/tests -p 'test_*.py' -v` passed 14 tests after adding the inventory helper. The official Lab13/Lab16 functional benches are not run at S0 because their required RTL modules are missing. No new TLB or Cache functional result is claimed.

## S0 evidence

The S0 result is `results/lab13_19/baseline/s0-merge-baseline-20261118-02/result.txt`. It includes branch/merge provenance, the Vivado version, read-only project inspection, both IP status reports, candidate source hashes, separate program-image hashes, and the implementation-gap audit.
