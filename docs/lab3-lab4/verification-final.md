# Lab3 / Lab4 最终验收（2026-10-21）

本文件记录最新完成结果。早期 GCC 故障记录见旧版 [`verification.md`](verification.md)，其中“当前未通过/待验证”均已被本验收覆盖。

最终需提交的结果目录与文档索引见 [`delivery-manifest.md`](delivery-manifest.md)。

## 环境与 GCC 复核

- Vivado 2025.2（64-bit，Build 6299465，IP Build 6300035），器件 `xc7a200tfbg676-2`，设计顶层 `soc_lite_top`，仿真顶层 `tb_top`；工程 IP `clk_pll`、`inst_ram`、`data_ram` 为 `Up-to-date`。
- Xelab 的详细日志明确调用 Vivado 自带 GCC 6.2.0：

```text
D:\Verilog\2025.2\Vivado\data\..\tps\mingw\6.2.0\win64.o\nt\bin\gcc.exe -fPIC -c -Wa,-W -I"D:\Verilog\2025.2\Vivado\data/xsim/include" "xsim.dir/tb_top_verbose/obj/xsim_2.c" -O1 -o "xsim.dir/tb_top_verbose/obj/xsim_2.win64.obj" -DXILINX_SIMULATOR
```

  工作目录为 `C:\Users\lenovo\Desktop\Projects\FPGA\lab\lab3\CPU_CDE\mycpu_verify\run_vivado\mycpu_prj1\mycpu_prj1.sim\sim_1\behav\xsim`。之后的链接命令也使用同一 GCC 6.2.0，链接 XSim kernel 与 `xsim_0/1/2.win64.obj`。
- Xelab 链接命令完整记录如下（目录名取自隔离复现轮）：

```text
D:\Verilog\2025.2\Vivado\data\..\tps\mingw\6.2.0\win64.o\nt\bin\gcc.exe -Wa,-W -O -Wl,--stack,104857600 -o "xsim.dir/xelab-default-env_tb/xsimk.exe" "xsim.dir/xelab-default-env_tb/obj/xsim_0.win64.obj" "xsim.dir/xelab-default-env_tb/obj/xsim_1.win64.obj" "xsim.dir/xelab-default-env_tb/obj/xsim_2.win64.obj" -L"D:\Verilog\2025.2\Vivado\lib\win64.o" -lxv_simulator_kernel -lxv_simbridge_kernel
```

- GCC 6.2.0、9.5.0 在 PowerShell 中 `--version` 均退出 0；GCC 6.2.0 在隔离 PATH 下也启动成功。对上述 `xsim_2.c` 完整复现编译命令退出 0，原始 stdout/stderr 均为空（成功编译没有诊断信息）。证据位于 [`gcc-investigation-20261020T150000Z`](../../results/lab3_lab4/gcc-investigation-20261020T150000Z/)；`compiler-command.txt`、metadata、原始 stdout/stderr 文件保留完整命令和退出码。
- Xelab 的实际 gcc 命令显式指向 6.2.0。旧脚本曾注入 GCC 9.5.0 的 `GCC_SIM_EXE_PATH`、`RDI_MINGW_LIB`、PATH，并传入 `-gcc_install_path`，但没有改变 Xelab 实际调用的可执行文件。默认 Xelab 环境的 `RDI_MINGW_LIB` 指向 GCC 6.2.0 的 bin/libexec；PATH 中先有 Vivado `bin/unwrapped/win64.o` 等组件，6.2.0 bin/libexec 位于尾部。对照环境将 GCC 10.0/9.5 路径放在 PATH 和 `RDI_MINGW_LIB` 前部，但显式调用仍为 6.2.0；两种环境下 PowerShell 复现编译都退出 0。环境记录只捕获 PATH 与 `RDI_MINGW_LIB`，没有 Windows loader 的 DLL 装载跟踪，因此未能锁定某个冲突 DLL，也不把猜测当根因。
- 早期 Xelab 日志保留的错误原文为 `ERROR: [XSIM 43-3409] Failed to compile generated C file xsim.dir/tb_top_verbose/obj/xsim_2.c.`、`ERROR: [XSIM 43-3915] Encountered a fatal error. Cannot continue. Exiting...`、`The system cannot execute the specified program.`；较早一次直接 `Start-Process` 诊断曾返回 `{无效的系统 DLL 重定位}` 及 `%hs` 占用了 Windows 系统 DLL 保留地址范围。该错误保留于 GCC investigation 目录的 `isolated.log`；随后独立 PowerShell 重测与 XSim 全流程均成功。
- 首轮日志的 `The system cannot execute the specified program.` 和 PowerShell 曾捕获的“无效的系统 DLL 重定位”属于早期进程启动上下文；它们不能证明 GCC 6.2.0 本身损坏。移除无效的编译器覆盖后，Vivado 默认编译配置完成 Lab3/Lab4 全流程，证实该配置可用。未替换 DLL、未重装 Vivado。
- 已从 [`verify.ps1`](../../scripts/verify.ps1) 和 [`run_behavioral_sim.tcl`](../../scripts/run_behavioral_sim.tcl) 移除 GCC 路径、环境变量和 `-gcc_install_path` 覆盖。Tcl 只设置本次仿真的 top、pipeline generic、trace plusarg、运行时间与 MIF staging，不改 Vivado GCC 默认值。

## 指令映像与独立参考轨迹

| 用例 | 指令映像 SHA-256 | 参考 trace SHA-256 | 参考记录 |
|---|---|---|---|
| Lab3 | `D56AEDEB3064A1FF797EF332EABC35C84D3C222CFDA439FFBE9F162E1ED8B05E` | `441D74893AD9AC7C8E40B92E10144639A3B8A700FE1290FDECBF4A8DEC60EFFA` | Lab3 参考 CPU trace |
| Lab4 | `FF50561C8F7E42B0D4576F989C5C5F99726DC46328CE714DEF65148619387EB6` | `EC1C8C84E14928FED411BF23DA3FB3DD0E2FED090F494710FC8EC21FFCFEB9DB` | 独立 CPU132 参考运行，44,071 条、1,057,704 字节、23 个功能点 PASS |
| 定向冒险 | `CF13E2CEEB8B7F1988E525D162D41FCBA5103D15358E2625018E56B0E6E5FD51` | `524D46D80D2EC082D7891D03F1BFD4BB9BA77330F235AC0EEE40FA4FE8F4A4C7` | 独立 CPU132 参考运行，24 条写回记录 |

Lab4 golden trace 位于 [`lab4/func_lab4/obj/golden_trace.txt`](../../lab4/func_lab4/obj/golden_trace.txt)，生成时在隔离的 `cpu132_gettrace` 工程中使用 Lab4 COE/MIF 与 Vivado 2025.2 RAM 仿真模型；生成器会核对隔离工程 XCI 中 COE 内容与输入 COE 完全相同。参考运行完整日志见 [`lab4-reference-20261020T161512Z`](../../results/lab3_lab4/lab4-reference-20261020T161512Z/)。定向 trace 和 MIF/COE、listing、参考运行日志见 [`hazard-directed`](../../results/lab3_lab4/hazard-directed/)。

## 完整功能验收

所有轮次均使用 Vivado 2025.2 / XSim、23 个课程功能点、独立参考 trace，且 `SIM_IMAGE_MATCHES_SOURCE=True`。

| 用例与模式 | 结果目录 | 功能点 | 周期 | stall | 前递 EX/MEM/WB |
|---|---|---:|---:|---:|---:|
| Lab3 forwarding | [`lab3-20261021T081224Z`](../../results/lab3_lab4/lab3-20261021T081224Z/) | 23 PASS | 172,599 | 0 | 1 / 0 / 0 |
| Lab4 blocking | [`lab4-20261021T081854Z`](../../results/lab3_lab4/lab4-20261021T081854Z/) | 23 PASS | 130,891 | 16,364 | 0 / 0 / 0 |
| Lab4 forwarding | [`lab4-20261021T082306Z`](../../results/lab3_lab4/lab4-20261021T082306Z/) | 23 PASS | 114,577 | 50 | 4,505 / 4,818 / 1,032 |

周期计数在 `resetn` 解除后、`debug_end` 置位前每个 `soc_clk` 上升沿加一。两轮 Lab4 使用同一 MIF 和 trace。前递将周期减少 16,314（12.46%），stall 从 16,364 降至 50；前递总命中 10,355 个接收周期。Lab4 forwarding 还观察到 store 基址/数据前递 267/289 次、分支源前递 5,370 次、最近 EX 生产者优先 46 次。

前递及 store/branch/JR/优先级计数只在 `ds_to_es_valid && es_allowin` 时增加，即 ID 指令真正被 EX 接收的周期；同一周期同一级同时服务 `rs` 和 `rt` 仍只记一次。修订前的 MEM=4,843、branch=5,372 包含 ID 保持期间的重复观察，不代表额外发射。本轮修正计数口径后，功能点、trace、周期和 stall 均保持不变。完整 Xvlog、Xelab、XSim 阶段日志分别在各结果目录的 `xsim-xvlog.log`、`xsim-elaborate.log`、`xsim-simulate-stage.log`，并包含 `xsim-compile.log`、Vivado 日志、source manifest 和 `result.txt`。

## 定向冲突验收

使用 [`build_hazard_directed_image.py`](../../scripts/build_hazard_directed_image.py) 生成可审计的 65-word MIPS-I 程序，不依赖外部交叉编译器；独立 CPU132 产生期望 trace。程序覆盖紧邻 ALU、间隔一条 ALU、连续写同一目的寄存器、load-use、ALU/load→store 基址和数据、taken/not-taken branch 与 delay slot、紧邻写入后的 `jr`、`$zero` 写入尝试及气泡填充。DUT trace 与参考核逐条一致。

| 模式 | 结果目录 | 周期 / stall | 关键覆盖计数 |
|---|---|---:|---|
| blocking | [`lab4-20261021T083933Z`](../../results/lab3_lab4/lab4-20261021T083933Z/) | 98 / 29 | load-use stall=3；前递=0；`$zero` 实际写回尝试=0 |
| forwarding | [`lab4-20261021T085125Z`](../../results/lab3_lab4/lab4-20261021T085125Z/) | 72 / 3 | EX/MEM/WB=6/5/2；load-use stall=3；store base/data=1/2；branch=2；JR=1；EX 最近生产者优先=2；`$zero` 实际写回尝试=0 |

两轮均 `STATUS=PASS`、trace 开启、抵达相同 END_PC，仿真 MIF 与源 MIF 哈希相同。`HAZARD_ZERO_DEST_WRITES=35` 统计 EX 阶段 `es_valid && es_gr_we && es_dest==0` 的周期，包含 `sll $zero,$zero,0` 形式的 NOP 和映像尾部填充，不能当作有意写 `$zero` 的指令数。独立断言 `ZERO_REG_WRITEBACK_ATTEMPTS=0` 直接监视 WB 调试接口；若出现任何目的寄存器为 0 且写使能非零的周期，验收立即失败。

可复现命令（工作目录 `C:\Users\lenovo\Desktop\Projects\FPGA`）：

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\lab\scripts\verify.ps1 -Case lab3 -PipelineMode forwarding
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\lab\scripts\verify.ps1 -Case lab4 -PipelineMode blocking -ReferenceTrace .\lab\lab4\func_lab4\obj\golden_trace.txt
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\lab\scripts\verify.ps1 -Case lab4 -PipelineMode forwarding -ReferenceTrace .\lab\lab4\func_lab4\obj\golden_trace.txt
python .\lab\scripts\build_hazard_directed_image.py
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\lab\scripts\verify.ps1 -Case lab4 -PipelineMode blocking -ReferenceTrace .\lab\results\lab3_lab4\hazard-directed\golden_trace.txt -InstMif .\lab\results\lab3_lab4\hazard-directed\image\hazard_inst_ram.mif -HazardDirected
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\lab\scripts\verify.ps1 -Case lab4 -PipelineMode forwarding -ReferenceTrace .\lab\results\lab3_lab4\hazard-directed\golden_trace.txt -InstMif .\lab\results\lab3_lab4\hazard-directed\image\hazard_inst_ram.mif -HazardDirected -CaptureWaveform
```

## 波形证据与人工截图状态

定向 forwarding 轮次已用 `log_wave -r /tb_top` 记录真实 XSim WDB：[`hazard-directed-forwarding.wdb`](../../results/lab3_lab4/lab4-20261021T085125Z/hazard-directed-forwarding.wdb)，大小 297,380 字节，SHA-256 `7C6B5DFBEB1649F823B436E2924D060DD7A3BECDC7BC65122C14AA07C20938F4`。同目录 `result.txt` 将该文件与 72 周期 / 3 stall、定向 MIF/trace 哈希及 PASS 结果绑定。此前检查的 `existing-full-forwarding.wdb` 对应 114,577 周期的完整 Lab4 运行，不作为定向截图证据。

当前仍未保存带标注的 GUI 截图，也没有进行 FPGA 上板验证。需要报告附图时，在 Vivado 中打开上述 WDB，观察 `fs_pc`、`ds_pc`、`ds_valid`、`ds_stall`、`ds_to_es_valid`、`es_allowin`、EX/MEM/WB 前递选择、store/branch/JR 控制和 `debug_wb_*`；在 `0xbfc00000–0xbfc00018`、`0xbfc00024–0xbfc00038`、`0xbfc0003c–0xbfc00058`、`0xbfc00060–0xbfc0007c` 四段附近保存截图。详细人工步骤见 [`figures/README.md`](figures/README.md)。
