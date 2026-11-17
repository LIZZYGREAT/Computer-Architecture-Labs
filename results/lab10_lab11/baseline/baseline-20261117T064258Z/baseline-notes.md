# Lab10/Lab11 S0 baseline

Run ID: `baseline-20261117T064258Z`

Captured: 2026-11-17 06:42–06:45 UTC

Repository: `C:\Users\lenovo\Desktop\Projects\FPGA\lab`

Branch / HEAD: `lab10-lab11` / `f0448dc4c83cf38f19451ab87262bec612076c97`
Pre-existing repository changes: `lab3/CPU_CDE/mycpu_verify/run_vivado/mycpu_prj1/mycpu_prj1.xpr` was modified and `docs/lab10-lab11/` was untracked before task edits. Neither is included in this stage's commit. The source diff hash records tracked changes; `source-manifest.csv` records the RTL and input files used here.

## Findings

- Both XPRs opened with `open_project -read_only` in Vivado 2025.2 and retained their Vivado 2019.2 files. Tops are `soc_sram_lite_top` and `soc_axi_lite_top`; simulation top is `tb_top` for both.
- `report_ip_status` shows the existing IP as “Project read-only. IP revision change” with newer revisions available in Vivado 2025.2. No upgrade or project write was performed.
- The project and IP configuration expect `soft/func_lab9/obj/inst_ram.coe` under each Lab10/Lab11 project parent. Those aliases do not exist at baseline; the source image is `lab9/func_lab9/obj/`.
- COE and MIF decode to 171,587 identical 32-bit words. The instruction RAM XCI depth is 262,144 words, so the image fits.
- Both golden traces are present and byte-identical (SHA-256 `8aee862561b79a7020e1753590b25e37dbb4ecc379e9b75b234f9fa6212f30cf`). Matching the trace to the current image still requires an independent run.
- Neither new project has `rtl/myCPU/` source files at baseline. The XPR source sets omit the CPU modules; the Vivado compile-order report is empty.
- COE SHA-256: `978140ec69d63a6f264fa6a95a2d28210d9d8a50e2ab105766a1429aa1ce888e`.
- MIF SHA-256: `392c6386b57f4780536a54f1f5af34e7749e9af61cb2db5703685c4c04cfeb01`.
- Both read-only Vivado batch preflights exited 0. The separate `vivado.bat -version` probe printed Vivado 2025.2 but returned exit code 1; batch project checks work when launched from the Vivado `bin` directory.

## Status

`S0=INCOMPLETE`: baseline and image-content comparison are recorded. The Lab10/Lab11 image aliases, CPU RTL, strict trace-to-image evidence, compile order, compilation and simulation remain outstanding. No functional PASS is claimed.

The earlier `baseline-20261117T063052Z` folder was created while inspecting the outer workspace repository. It is retained as a preliminary discovery record and is not authoritative for the `lab10-lab11` repository.
