# Lab3 / Lab4 五级流水线实现说明

## 范围与状态

本次改造只针对 `lab3/CPU_CDE/mycpu_verify/` 中现有的 MIPS 五级流水线 CPU 与 Vivado 工程。Lab1 未修改。实现包含纯阻塞和前递两种可选模式，默认启用前递。

**状态：** RTL 已在 Vivado 2025.2 / XSim 完成 Lab3、Lab4 完整程序和定向相关测试。最终轮次、周期统计及 GCC 复核见 [`verification-final.md`](verification-final.md)。

## 数据相关处理

ID 阶段按指令类型识别真正使用的寄存器：R 型算术使用 `rs/rt`，立即数算术和 `lw` 使用 `rs`，`sw` 使用地址基址 `rs` 与写入数据 `rt`，移位指令使用 `rt`，`beq/bne` 使用 `rs/rt`，`jr` 使用 `rs`。`$zero` 不形成 RAW 冲突。

生产者信息由 39 位总线携带：`{valid_write, result_ready, destination, value}`。

| 消费者 | 可用生产者 | 结果就绪条件 | 前递/停顿行为 | 数据来源 |
|---|---|---|---|---|
| ID 中的 ALU 源、store 源、branch 比较、`jr` 目标 | EX | EX 有效且写寄存器；仅非 load 的 ALU 结果就绪 | 前递模式下优先选择 EX；若最新 EX 是 load，则 ID 保持、向 EX 注入气泡 | EX ALU 结果 |
| 同上 | MEM | MEM 有效且写寄存器；`mem_stage` 输出最终结果 | EX 没有更近的同目的生产者时选择 MEM；若未就绪则保持 ID | load 使用 `data_sram_rdata`，其他指令使用 ALU 结果 |
| 同上 | WB | WB 写使能有效且目的寄存器非 `$zero` | EX/MEM 均无更近匹配项时选择 WB | WB 写回总线 |
| 上述全部源操作数（纯阻塞模式） | EX、MEM、WB | 生产者仍在对应阶段 | 不进行旁路；相关消费者在 ID 等到写回离开 WB | 寄存器堆异步读端口 |

优先级按程序顺序为 **EX → MEM → WB**，所以连续写同一目的寄存器时，较新的生产者优先。EX load 不会把地址当作加载值前递。`inst_ram` 与 `data_ram` 的 XCI 配置是同步 Block RAM，读取延迟为 1；MEM 阶段以 RAM 返回数据作为 load 的最终值。Lab3、Lab4 完整指令映像和独立定向映像均已在 XSim 中验证，逐条写回轨迹与参考 CPU 一致。

纯阻塞模式用 `PIPELINE_FORWARDING=0` 关闭所有旁路。ID 因 RAW 停顿时，`ds_allowin` 阻止 IF/ID 前进，`ds_to_es_valid` 为低，使 EX 接收 bubble；EX/MEM/WB 中较早指令继续向前排空。前递模式只对数据尚未就绪的最近生产者停顿。

## 流水线与 MIPS 语义

- ID 的有效位在 reset 时清零；仅在 `ds_allowin` 时接收新的 IF 指令。停顿时保留当前指令，未被接收的气泡不会提交。
- BEQ/BNE 使用当前 ID 指令的 `ds_pc + 4` 计算分支目标；`jr` 采用旁路后的 `rs`；JAL 目标地址高位来自 `PC+4`，链接值由 EX 计算为 `PC+8`。
- 分支决定在 ID 阶段生效。IF 在同一握手周期取顺序后继指令作为 MIPS 延迟槽，再转到分支目标。
- `sw` 的地址基址和写入数据都在 ID 解析/旁路，并随 ID→EX 总线锁存；EX 使用修正后的两个 ALU 输入。
- WB 屏蔽对 `$zero` 的写使能，寄存器堆读 `$zero` 恒为 0。

testbench 的 EX/MEM/WB 前递统计只在 `ds_to_es_valid && es_allowin` 的 ID→EX 接收周期增加；同一周期同一级为 rs 与 rt 提供数据时，该级计数仍只增加 1。字段 `FORWARD_EX_USES`、`FORWARD_MEM_USES`、`FORWARD_WB_USES` 因兼容性保留旧名，单位是**接收周期**，不是源操作数个数。store 基址/数据、branch、JR 和 EX 最近生产者优先计数采用相同的接收门控；load-use 指标统计停顿周期。

`HAZARD_ZERO_DEST_WRITES` 统计 EX 阶段 `es_valid && es_gr_we && es_dest == 0` 的周期，其中包括机器码 NOP（`sll $zero,$zero,0`）和定向映像 word 64 前的填充 NOP，不能解释成有意 `$zero` 写入用例数。testbench 另独立监视 WB 写回接口，要求 `debug_wb_rf_wen` 对目的寄存器 0 始终为 0；任何实际零寄存器写回尝试都会使该轮仿真失败。定向程序中的 `addiu $zero,$zero,5` 后跟一条读取 `$zero` 的指令，其写回结果也继续与独立 CPU132 trace 比较。

## RTL 修改文件

| 文件 | 修改 |
|---|---|
| `rtl/myCPU/mycpu.h` | 分支总线宽度设为 33 位，匹配 taken 与 32 位 target。 |
| `rtl/myCPU/ID_stage.v` | 修复 ID valid/握手；增加源操作数使用掩码、RAW 比较、EX/MEM/WB 旁路优先级、纯阻塞选择、load 未就绪停顿、分支与跳转源数据旁路。 |
| `rtl/myCPU/EXE_stage.v` | 修正 ALU 源操作数连接；输出 EX producer 信息，load 不标为可前递。 |
| `rtl/myCPU/MEM_stage.v` | 以非阻塞赋值锁存阶段总线；输出 MEM 最终写回值供 ID 前递。 |
| `rtl/myCPU/alu.v` | OR 由两个操作数直接计算；移位结果保留 32 位。 |
| `rtl/myCPU/IF_stage.v` | 显式使用 32 位 PC 增量常数。 |
| `rtl/myCPU/mycpu_top.v`、`rtl/soc_lite_top.v` | 传递 `PIPELINE_FORWARDING` 参数，允许同一 ROM 下选择阻塞或前递。 |
| `rtl/myCPU/WB_stage.v` | 禁止写入 `$zero`。 |
| `testbench/mycpu_tb.v` | 允许用 plusarg 指定 trace；增加严格 trace 文件打开、尾部记录检查、周期/停顿计数、按已接收指令统计旁路、定向 hazard 计数与 `$zero` 写回断言；trace 或断言不匹配进入失败状态。 |
| `scripts/verify.ps1` | 增加 Lab3/Lab4 与定向用例验收、MIF 覆盖、Xvlog/Xelab/XSim 完整阶段日志归档、`$zero` 写回断言检查、可选 WDB 归档和严格 PASS 判定；移除额外 GCC 环境覆盖。 |
| `scripts/run_behavioral_sim.tcl` | 在现有 Vivado 工程运行 XSim、暂存指定 MIF 并保留 Vivado 默认 GCC 配置；按可选参数对 `/tb_top` 递归记录波形。 |
| `scripts/generate_reference_trace.tcl` | 在隔离参考工程内使用课程 CPU132 生成 trace，并核对输入 COE 与参考工程 XCI 的 COE 内容。 |
| `scripts/build_hazard_directed_image.py` | 生成可审计的短 MIPS-I 冒险测试映像及汇编式 listing。 |

## 代码审查边界

最终动态证据确认：Lab3 与 Lab4 各 23 个课程功能点通过，独立参考 trace 全部匹配；短测试验证 EX/MEM/WB 旁路、最近生产者优先、load-use stall、store 基址/数据、branch、JR、delay slot 和 `$zero` 写入屏蔽。Lab4 相同映像下，blocking 为 130,891 周期 / 16,364 stall，forwarding 为 114,577 周期 / 50 stall，周期减少 12.46%。详细结果与日志链接见 [`verification-final.md`](verification-final.md)。

无 FPGA 上板记录，也没有保存带标注的 XSim GUI 图片；定向 forwarding 的真实 WDB 已归档，可按 [`figures/README.md`](figures/README.md) 人工打开并导出截图。
