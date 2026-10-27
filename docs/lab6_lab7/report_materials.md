# Lab6–Lab7 实验报告材料（2026-10-26 验收基线）

## 最近完整回归

本轮完整回归已通过：Lab3 23/23、Lab4 23/23、Lab6 42/42、Lab7 68/68。Lab6 与 Lab7 分别与独立 CPU132 trace 的 66,612/66,612 和 100,732/100,732 条写回记录匹配；HI/LO 单元 testbench、除法后分支等待定向用例和新增指令前递定向用例也通过。结果目录、哈希及运行日志索引见 [verification.md](verification.md)。

旧记录 `lab6-20261021T141122Z` 的 34/42 是 HI/LO 完成前 S2 阶段的历史失败，不能描述完整累计结果。2026-10-22 的 GCC/Xelab 失败也是早期环境诊断；后续普通 Windows PowerShell 下的完整 XSim 回归通过。上述 PASS 是 10/27 Divider 握手修订前的基线。

## 2026-10-27 修订后状态

`hilo_unit.v` 已改为锁存除法输入并保持两路 `TVALID` 直到 NonBlocking Divider 的成对 ready；HI/LO testbench 已增加 ready 同步、payload 保持及唯一配对输入检查。当前会话运行在 AppContainer，项目脚本按要求拒绝启动 Vivado，因此修订后的 HI/LO、Lab3/Lab4/Lab6/Lab7 和除法分支定向验收均为 `NOT_RUN`。请以 [verification.md](verification.md) 的修订后验收表为准，不要把下面的历史 PASS 当成本次修订后的结果。

## 新增指令前递统计

Lab7 新增计数在 `ds_instruction_issued` 时采样，避免 EX 背压期间重复计数。累计回归的新增 store 基址/数据、条件分支、`jalr` 前递计数分别为 112/0/1,229/28；独立短定向程序相应得到 3/2/6/1，覆盖 `sb/sh/swl/swr`、六种新增条件分支与 `jalr`。这是发射指令周期或操作数使用次数，不是 stall 数或每条指令动态执行数；两操作数均前递时 store 基址与数据项可同时增加。旧 `HAZARD_STORE_*`、`HAZARD_BRANCH_FORWARDS`、`HAZARD_JR_FORWARDS` 只覆盖 `sw`、`beq/bne`、`jr`。累计 Lab7 的 `PIPELINE_STALL_CYCLES=926` 仅表示 ID `ds_stall` 周期，不覆盖完整的 EX 乘除等待时长。具体定义和 ROM/trace 哈希见 [verification.md](verification.md)。

## 连续依赖定向用例（P2-A）

新增 Lab7 短映像覆盖 load 到 `sb/sh/swl/swr` 的写数据依赖、部分存储后紧跟 byte/halfword 读回、连续 `lwl/lwr` 合并及 load 到 `bltz` 的分支依赖。镜像生成及 COE/MIF 一致性检查为 `PASS`；当前 AppContainer 无法启动 Vivado，因此这份镜像的 CPU132 reference 和 DUT 行为仿真仍为 `NOT_RUN`。回归命令、预期状态与哈希见 [verification.md](verification.md)。

## Vivado 波形人工材料

按用户本轮要求，本次没有运行 `-CaptureWaveform`，没有生成 WDB、WCFG 或 PNG。报告中的结构示意图、流程图和功能点汇总图均非仿真波形；不得将它们作为真实波形分析证据。剩余人工事项是根据 [waveforms.md](waveforms.md) 的步骤，从新鲜且 PASS 的 XSim 运行捕获 WDB，定位代表性指令并导出真实信号图，再把实测时间窗、PC/指令、信号值、预期/实际结果和运行 ID 写入证据表。

本材料当前准确反映了完整数字回归状态；真实波形图与逐图分析仍待用户按课程提交要求人工完成。
