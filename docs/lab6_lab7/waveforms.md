# Lab6–Lab7 波形采集与分析指南

## 当前证据状态

最新 Lab6/Lab7 累计回归分别为 [`lab6-20261026T163659Z`](../../results/lab6_lab7/lab6-20261026T163659Z/)（42/42）和 [`lab7-20261026T164130Z`](../../results/lab6_lab7/lab7-20261026T164130Z/)（68/68）；二者均未启用 `-CaptureWaveform`。新增指令前递定向回归 [`lab7-20261026T170957Z`](../../results/lab6_lab7/lab7-20261026T170957Z/) 也 PASS，但同样没有捕获波形。因此当前没有可供报告引用的 Lab6/Lab7 WDB、WCFG 或 Vivado 截图。

本文件是后续人工取证指南，不代表本轮已经生成波形。本轮遵从用户要求，没有创建波形文件或波形图。报告中的 Python 图是结构/流程/统计图，不能替代实测波形。验证入口及普通 Windows PowerShell 要求见 [environment.md](environment.md)。

## 推荐场景与信号

在 Vivado Wave 中按层级搜索以下 RTL 信号名；完整层级前缀取决于当前 `tb_top` 实例结构。优先截取少数周期，保持 `clk` 可见，信号用十六进制显示，并在图注中注明 run ID、PC/指令和实际周期。

| 图 | 代表指令/行为 | 建议重点信号 |
|---|---|---|
| `01_alu_immediate.png` | `andi/ori/sltiu` 立即数扩展与 ALU 结果 | `ds_inst`, `ds_pc`, `es_rs_value`, `es_imm`, `es_alu_src2`, `es_alu_result`, `debug_wb_pc`, `debug_wb_rf_wnum`, `debug_wb_rf_wdata` |
| `02_variable_shift.png` | `sllv/srav/srlv`，移位量来自 `rs[4:0]` | `ds_inst`, `ds_pc`, `es_rs_value`, `es_rt_value`, `es_alu_result`, `debug_wb_*` |
| `03_mult_hilo.png` | `mult/multu` 请求、结果保持和 `mfhi/mflo` | `es_hilo_start`, `es_hilo_busy`, `es_hilo_done`, `es_hilo_consume`, `hilo_hi_value`, `hilo_lo_value`, `es_allowin`, `debug_wb_*` |
| `04_div_stall.png` | `div/divu` 多周期等待与一次性消费 | `es_valid`, `es_allowin`, `es_ready_go`, `ds_valid`, `ds_allowin`, `es_hilo_start/busy/done/consume`，以及 `dividend_ready`, `divisor_ready`, `div_result_valid`、HI/LO 值和提交信号 |
| `05_branch_delay_slot.png` | 新条件分支、`jalr` 目标前递与 delay slot | `ds_pc`, `ds_inst`, `br_taken`, `br_target`, `ds_allowin`, `es_allowin`, IF/FS PC，`debug_wb_*`；显示 delay-slot 和链接寄存器写回 |
| `06_byte_half_load.png` | `lb/lbu/lh/lhu` 地址 lane 与符号/零扩展 | `es_alu_result`, `data_sram_addr`, `data_sram_rdata`, `mem_op`, `ms_mem_result`, `debug_wb_*` |
| `07_byte_store.png` | `sb/sh` 字节使能、移位写数据及 RAM 读回 | `es_alu_result[1:0]`, `es_rt_value`, `es_store_wen`, `es_store_data`, `data_sram_wen`, `data_sram_wdata`, RAM 地址/读回值 |
| `08_unaligned_merge.png` | `lwl/lwr/swl/swr` 四种偏移和旧 `rt` 合并 | `es_alu_result[1:0]`, `es_rt_value`, `mem_op`, `ms_mem_result`, `es_store_wen`, `es_store_data`, `data_sram_wen`, `data_sram_wdata`, 写后读回值 |

`debug_wb_*` 至少包含 `debug_wb_pc`、`debug_wb_rf_wen`、`debug_wb_rf_wnum` 和 `debug_wb_rf_wdata`。如果目标内部信号因综合/展开层级而不可见，请在截图说明中指出，并用可见的总线、指令 PC 和写回证据代替；不要推断未显示的值。

## Vivado GUI 操作

1. 在**普通 Windows PowerShell**（`WINDOWS_APPCONTAINER=False`）从 `lab` 仓库根运行对应 case 的 `scripts/verify.ps1`，加入 `-CaptureWaveform`。完整课程程序命令为 `.\scripts\verify.ps1 -Case lab6 -PipelineMode forwarding -CaptureWaveform -TimeoutSeconds 1800` 或将 case 改为 `lab7`。使用短定向场景时传入其 MIF 与 golden trace，并保留 `-HazardDirected` 期望配置。
2. 只使用本次新建结果目录中的波形。结果的 WDB 文件名为 `<RUN_ID>-forwarding.wdb`；先检查 `result.txt` 的 `STATUS=PASS`、`WAVEFORM_CAPTURED=True`、`WAVEFORM_FILE`、`WAVEFORM_SHA256`，以及 trace 匹配和 MIF 哈希。不要用旧运行目录中的同名文件。
3. 在 Vivado 的 Wave 窗口打开 WDB，展开 `tb_top` 与 CPU 层级，用 Name/Find 搜索表中信号。添加 `clk`、`ds_pc/ds_inst`、目标路径信号和最终写回证据；把 bus 设置为 Hex，缩放到覆盖指令进入 ID、执行/等待和写回的最少窗口。
4. 逐项核对预期/实际：立即数与 ALU 结果、HI/LO 完成只消费一次、分支只重定向一次且 delay slot 保留、store byte enable 与写数据、load/merge 最终写回。波形无法显示内存内部写后状态时，应另截可见的 RAM 读回，而不要只凭写使能宣称写入成功。
5. 为每张图保存独立 WCFG，并从 Wave 窗口导出清晰 PNG 到报告图目录。图中保留信号名、时间刻度和数个时钟沿。图注记录测试用例/run ID、MIF/trace SHA-256、PC/指令、周期或时间窗、预期值、实际值及对应 PASS 记录链接；WDB 可以本机留存，PNG 和小型证据清单再纳入报告。

## 当前待人工完成

需要人工运行带波形捕获的 PASS 仿真，按上表导出所需代表图并填写实际时间窗/数值；再将 PNG 和信号级分析纳入 `main.tex`、重新编译并检查 `main.pdf`。在这些步骤完成前，不能把任何图登记为实际波形证据。
