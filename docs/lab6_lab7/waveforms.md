# Lab6–Lab7 波形记录

## 当前状态

真实 DUT 波形尚未生成。Lab7 forwarding 仿真已通过源代码语法编译和静态展开，但 Xelab 在生成 C 编译阶段报 `XSIM 43-3409`，XSim 没有启动，故当前没有可分析的 CPU WDB 或截图。不得将静态时序说明当作实测波形。

失败运行及日志：`results/lab6_lab7/lab7-20261022T014242Z/`。Vivado 环境和启动命令见 [environment.md](environment.md)。修复 Xelab 编译环境后，使用以下命令生成可供查看的波形数据库：

```powershell
.\scripts\verify.ps1 -Case lab6 -PipelineMode forwarding -CaptureWaveform
.\scripts\verify.ps1 -Case lab7 -PipelineMode forwarding -CaptureWaveform
```

脚本会把运行中的波形保存为结果目录内的 WDB。每次记录须同时写入 testcase、commit、ROM SHA-256、仿真结果与 WDB SHA-256；只在 WDB 来自实际运行且功能/trace 判据通过后再导出并登记 PNG。

## 待导出的实测图

| 图 | 测试场景 | 重点信号 | 状态 |
|---|---|---|---|
| `01_alu_immediate.png` | `andi/ori/sltiu` | `ds_inst`, `es_imm`, `es_alu_src2`, `es_alu_result`, `debug_wb_*` | 待实测 |
| `02_variable_shift.png` | `sllv/srav/srlv` | `es_rs_value[4:0]`, `es_rt_value`, `es_alu_result`, `debug_wb_*` | 待实测 |
| `03_mult_hilo.png` | `mult/multu` 后 `mfhi/mflo` | `es_hilo_start`, `busy/done`, `hilo_hi_value`, `hilo_lo_value`, `debug_wb_*` | 待实测 |
| `04_div_stall.png` | `div/divu` 多周期停顿 | EX valid/allowin、ID valid、IP ready/valid、done、HI/LO 提交 | 待实测 |
| `05_branch_delay_slot.png` | 条件分支、`jalr` 与 delay slot | `ds_pc`, `br_taken`, `br_target`, IF PC、delay-slot WB、链接寄存器写回 | 待实测 |
| `06_byte_half_load.png` | `lb/lbu/lh/lhu` | 有效地址、RAM 返回 word、lane、扩展结果、WB | 待实测 |
| `07_byte_store.png` | `sb/sh` | 地址低位、`data_sram_wen`, `data_sram_wdata`、RAM 读回 | 待实测 |
| `08_unaligned_merge.png` | `lwl/lwr/swl/swr` | byte offset、旧 `rt`、读合并值或 byte enable、读回值 | 待实测 |

## 人工导出步骤（仿真可运行后）

1. 用 Vivado 2025.2 打开 `lab3/CPU_CDE/mycpu_verify/run_vivado/mycpu_prj1/mycpu_prj1.xpr`。
2. 在 Tcl Console 或 PowerShell 从仓库根目录按上方命令运行指定累计 case，并确认该次结果不是 `ENVIRONMENT_ERROR`、`FAIL` 或 `INCOMPLETE`。
3. 打开该次结果目录中的 WDB，定位表中指定指令的 EX/WB 周期，信号数据改为十六进制显示并缩放至少量相关周期。
4. 添加图表所列信号，保存对应 WCFG，再通过 Vivado Wave 窗口导出 PNG 到 `docs/lab6_lab7/figures/`。逐图注明 PC、周期、输入、预期/实际值和判定；不得仅截图整段仿真日志。

目前没有任何一张图可以标为 PASS 或完成。
