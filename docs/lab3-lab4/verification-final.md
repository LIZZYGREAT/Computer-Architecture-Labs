# Lab3 / Lab4 最终验收（2026-10-22）

当前最终结果入口见 [`delivery-manifest.md`](delivery-manifest.md)。Vivado GCC 启动上下文的诊断与结论见 [`gcc-startup-incident.md`](gcc-startup-incident.md)。

## 验收环境与 GCC 结论

- Vivado 2025.2（64-bit，Build 6299465，IP Build 6300035），器件 `xc7a200tfbg676-2`，设计顶层 `soc_lite_top`，仿真顶层 `tb_top`。
- Xelab 默认实际调用 Vivado 随附 GCC 6.2.0。调用参数和工作目录见事故记录与 [`gcc-diagnostic-20261022`](../../results/lab3_lab4/gcc-diagnostic-20261022/)。
- Codex 受限 PowerShell 的 token 为 Windows AppContainer；在此上下文启动 GCC 会返回 Win32 623。普通 PowerShell 和隔离 PATH 下 GCC 6.2.0 均可启动，XSim 生成 C 文件的编译命令退出 0。`verify.ps1` 现会记录 token 上下文并在 AppContainer 下提前返回 `ENVIRONMENT_ERROR`。
- 仿真脚本未指定替代 GCC，也未改写 `PATH`、`GCC_SIM_EXE_PATH` 或 `RDI_MINGW_LIB`。Windows loader 没有提供冲突 DLL 的装载跟踪，故报告不指定某个 DLL 为根因。没有替换系统 DLL、重装 Vivado 或重写 CPU。

## 输入与独立参考轨迹

| 用例 | 指令 MIF SHA-256 | Golden trace SHA-256 | 说明 |
|---|---|---|---|
| Lab3 | `D56AEDEB3064A1FF797EF332EABC35C84D3C222CFDA439FFBE9F162E1ED8B05E` | `441D74893AD9AC7C8E40B92E10144639A3B8A700FE1290FDECBF4A8DEC60EFFA` | 课程 Lab3 参考 trace |
| Lab4 | `FF50561C8F7E42B0D4576F989C5C5F99726DC46328CE714DEF65148619387EB6` | `EC1C8C84E14928FED411BF23DA3FB3DD0E2FED090F494710FC8EC21FFCFEB9DB` | 独立 CPU132 生成，44,071 条记录、23 个功能点通过 |
| 定向冒险 | `CF13E2CEEB8B7F1988E525D162D41FCBA5103D15358E2625018E56B0E6E5FD51` | `524D46D80D2EC082D7891D03F1BFD4BB9BA77330F235AC0EEE40FA4FE8F4A4C7` | 独立 CPU132 生成，24 条写回记录 |

Lab4 trace 位于 [`lab4/func_lab4/obj/golden_trace.txt`](../../lab4/func_lab4/obj/golden_trace.txt)，独立生成日志位于 [`reference-lab4-20261022T040401Z`](../../results/lab3_lab4/reference-lab4-20261022T040401Z/)。定向映像、listing、trace 和参考运行日志位于 [`hazard-directed`](../../results/lab3_lab4/hazard-directed/)。

## 完整功能验收

| 用例 | 结果目录 | 功能点 / 记录 | 周期 | stall | EX/MEM/WB 前递 | 状态 |
|---|---|---:|---:|---:|---:|---|
| Lab3 forwarding | [`lab3-20261022T035035Z`](../../results/lab3_lab4/lab3-20261022T035035Z/) | 23/23 | 172,599 | 0 | 1 / 0 / 0 | PASS |
| Lab4 blocking | [`lab4-20261022T040641Z`](../../results/lab3_lab4/lab4-20261022T040641Z/) | 23/23 | 130,891 | 16,364 | 0 / 0 / 0 | PASS |
| Lab4 forwarding | [`lab4-20261022T041047Z`](../../results/lab3_lab4/lab4-20261022T041047Z/) | 23/23 | 114,577 | 50 | 4,505 / 4,818 / 1,032 | PASS |

两轮 Lab4 使用同一 MIF 和 trace。前递减少 16,314 周期（12.46%），load-use 相关仍产生 50 个停顿周期。三个结果目录均记录 `ZERO_REG_WRITEBACK_ATTEMPTS=0`、trace 匹配和仿真 MIF 与源 MIF 匹配。

## 定向冲突与波形

定向程序为 65-word 手工编码 MIPS-I ROM，覆盖 ALU 相关、连续写同一目的寄存器、load-use、ALU/load 到 store 基址和数据、branch delay slot、JR、`$zero` 与气泡。

| 模式 | 结果目录 | 周期 / stall | 检查结果 |
|---|---|---:|---|
| blocking | [`lab4-20261022T041535Z`](../../results/lab3_lab4/lab4-20261022T041535Z/) | 98 / 29 | 3 次 load-use 停顿、无前递、无 `$zero` 写回尝试，PASS |
| forwarding | [`lab4-20261022T041931Z`](../../results/lab3_lab4/lab4-20261022T041931Z/) | 72 / 3 | EX/MEM/WB=6/5/2；store base/data=1/2；branch=2；JR=1；EX 优先级=2；PASS |

Forwarding 波形数据库为 [`hazard-directed-forwarding.wdb`](../../results/lab3_lab4/lab4-20261022T041931Z/hazard-directed-forwarding.wdb)，336,746 字节，SHA-256 `5447B32478FE7896D9399AB5AD7042EE21C437068B209BF218CA01616263DB81`。`log_wave -r /tb_top` 捕获的实际层次波形与 72 周期 PASS 结果同目录保存。带标注的 GUI 图片仍需人工从 WDB 导出；FPGA 上板记录未取得。

## 保留的阶段日志

每个最终 DUT 结果目录保留 `result.txt`、`preflight-vivado.log`、`ip_status.rpt`、`simulation-vivado.log`、Xvlog/Xvhdl/Xelab/XSim 阶段日志、`xsim-sources.prj` 和 `instruction-image-check.txt`。临时命令、重复日志副本、拼接日志和重复 ROM 镜像已清理。GCC 根因证据单独收拢在 `gcc-diagnostic-20261022/`。

从仓库根目录复现：

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\lab\scripts\verify.ps1 -Case lab3 -PipelineMode forwarding
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\lab\scripts\verify.ps1 -Case lab4 -PipelineMode blocking -ReferenceTrace .\lab\lab4\func_lab4\obj\golden_trace.txt
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\lab\scripts\verify.ps1 -Case lab4 -PipelineMode forwarding -ReferenceTrace .\lab\lab4\func_lab4\obj\golden_trace.txt
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\lab\scripts\verify.ps1 -Case lab4 -PipelineMode blocking -ReferenceTrace .\lab\results\lab3_lab4\hazard-directed\golden_trace.txt -InstMif .\lab\results\lab3_lab4\hazard-directed\image\hazard_inst_ram.mif -HazardDirected
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\lab\scripts\verify.ps1 -Case lab4 -PipelineMode forwarding -ReferenceTrace .\lab\results\lab3_lab4\hazard-directed\golden_trace.txt -InstMif .\lab\results\lab3_lab4\hazard-directed\image\hazard_inst_ram.mif -HazardDirected -CaptureWaveform
```

需在 `TokenIsAppContainer=0` 的普通 Windows PowerShell 中运行；否则脚本会在调用 Vivado 前返回环境错误。更通用的运行说明见 [`lab/README.md`](../../README.md)。
