# Lab8 / Lab9 implementation notes

本文件记录各阶段已落地的 RTL 和对应实测证据。每一节只描述已完成并验证的部分。

## S1 — 独立 CP0

新增 `cp0_reg.v`，尚未连接五级 CPU。实现寄存器 BadVAddr、Count、Compare、Status、Cause 和 EPC；只接受 `sel=0` 的列出寄存器，其它选择读零、写忽略。Status 只实现 IE、EXL、IM、BEV，Cause 软件只写 IP0/IP1，硬件异常维护 ExcCode/BD，Cause.IP7 是 timer TI 与 `hw_int[5]` 的 OR。

`Count` 每两个 CPU 时钟加一，与 CPU132 参考实现一致；Count 写优先于当拍自增。Compare 写入清 TI，旧 Count 与 Compare 相等时 TI 锁存，直到下次 Compare 写入。复位时 Count/Compare/EPC/BadVAddr/Status 可见字段和软件 IP 为零，Status.BEV=1；Cause.ExcCode 复位为 CPU132 参考值 `5'h1f`。复位释放后若 Count 与 Compare 同为零，首个有效比较会置 TI；IE/IM 复位为零，不会因此受理中断。

异常提交将 EXL 置位、更新 ExcCode；仅在进入前 EXL=0 时写 EPC 和 BD。延迟槽 EPC 取 `exc_pc - 4`。AdEL/AdES 记录输入的原始 BadVAddr。ERET 清 EXL。异常提交优先于 ERET 和 CP0 软件写；Compare 写优先于同拍 Count/Compare 匹配产生的 TI。

### 自检结果

Vivado 2025.2 / XSim 隔离仿真：

- Run ID：`cp0-unit-20261109T141303Z`
- 结果目录：`results/lab8_lab9/cp0-unit-20261109T141303Z/`
- `CASE_NAME=cp0_reg_unit`
- `ASSERTIONS_PASS=62`
- `TRAPS_OBSERVED=2`
- `STATUS=PASS`

断言覆盖复位值、Count 分频、Compare/TI、Status 写掩码、Cause/IP 保留规则、EPC/BD/EXL/ERET、BadVAddr、软件 IP0/IP1、外部 IP2–IP7 映射和中断屏蔽、IP7 双源合并，以及未实现 CP0 select/register 的明确行为。隔离项目由 `scripts/run_cp0_unit_tb.tcl` 创建在每次新建的结果目录内；未改动原 CPU `.xpr`。

首轮 runner 在测试台 `$finish` 后重复执行 `run all`，造成额外 timeout；该 runner 已修正，首轮目录 `results/lab8_lab9/cp0-unit-20261109T141112Z/` 保留作诊断，不作为通过证据。

本阶段尚未修改流水线总线或 CPU 顶层；以上结果不代表 CP0 已集成，也不代表 Lab8/Lab9 课程映像已通过。

## S2 — CP0/系统指令流水线接入与 Lab8

把 CP0 和同步 `syscall` 元数据接入五级流水线。流水线总线扩展为 `FS_TO_DS=103`、`DS_TO_ES=235`、`ES_TO_MS=195`，字段包含取指异常、延迟槽标记、CP0 操作及异常 PC/code/BadVAddr。CPU 顶层将 `cp0_reg` 接到 MEM；MEM 是唯一 trap/eret 提交点，异常和 `eret` 重定向 IF 并冲刷更年轻 ID/EX，EX 同拍屏蔽 store。`mfc0` 结果从 MEM 通道进入 GPR 写回并参与 MEM 前递；`mtc0` 只在 MEM 提交沿写 CP0，ID 将其 RT 纳入 RAW 依赖；普通控制转移（无论条件是否成立）向其下一条指令传递 delay-slot 标记。

S2 集成时曾在 SoC 顶层增加 `ext_int[5:0]` 输入；S4 已将这个未约束的顶层端口移除，改由已有 XDC 约束的 `switch[5:0]` 经两级同步器产生 IP2-IP7，仿真模式下则固定为零。CP0 RTL 已加入原 Vivado 工程的 `sources_1` 和 `sim_1`，项目 preflight 现在要求两处都恰好存在该文件。`cases.json`、`verify.ps1`、行为仿真 Tcl 和 CPU132 trace 生成入口已支持 Lab8/Lab9；参考 trace 在每个用例独立的 `results/lab8_lab9/reference-work/` 工程中以对应原始镜像生成，没有修改课程 COE/MIF。

### Lab8 实测

- CPU132 reference：Run `reference-lab8-20261109T142849Z`，69/69 功能点，100,913 条 GPR trace 记录，trace SHA-256 `F6A7268A79725186B9EC8602A404CC5BE8E1D439E93ACAD1B2ADA04937723994`。
- DUT：Run `lab8-20261109T143142Z`，Vivado 2025.2/XSim compile、elaborate、simulate 均成功；69/69 功能点、trace 全量匹配，166,827 周期、950 停顿周期；零寄存器写入尝试 0；WDB SHA-256 `B44C7C3A860746D20D91359205696A82A76733049BA8110519B0919AD1706B7C`；`STATUS=PASS`。
- 输入 MIF SHA-256 与 S0 记录相同：`D611D547FFDC000F003673B1B9276D1BA813C15008BE071EE6B639DE278ABF51`。运行状态、参数、trace 和波形路径见 `results/lab8_lab9/lab8-20261109T143142Z/`；reference 日志与 trace 哈希见 `results/lab8_lab9/reference-lab8-20261109T142849Z/`。

本阶段覆盖累计 Lab8 镜像中的 syscall、mfc0/mtc0/eret 和 CP0 异常返回链。它尚未覆盖 break、RI、溢出、Load/Store 对齐异常、Lab9 定时器/软件中断，以及独立外部中断断言；这些在后续阶段执行。Vivado 运行后递增的 XPR 启动计数器已还原；XPR 提交差异仅保留 CP0 在两个文件集中的源文件条目。

### 波形采集修正

S2 早期运行的 WDB 使用了不匹配的 `/tb_top` 静态层级；`xsim-simulate-stage.log` 出现 `[Simtcl 6-55] No matching HDL object or HDL scope found`，因此那份 WDB 不用于截图或报告。`scripts/run_behavioral_sim.tcl` 已改为 `log_wave -r /`，此后才将新 WDB 作为波形证据。后文的最终 Lab8/Lab9 运行均使用修正后的采集方式。

## S3 - 完整同步例外和精确副作用

在现有 CP0/流水线通道上加入 `break`、RI、add/addi/sub 溢出、load/store 对齐错误与取指 AdEL。ID 对已实现合法指令建立完整识别集合；未知编码才产生 RI，已有 IF 取指异常优先保留。EX 用实际 ALU 源和结果判断溢出，用原始字节地址判断对齐，并在本指令异常或更老 trap 冲刷时阻止 RAM 请求。普通分支仍标记紧随的延迟槽指令，MEM 提交延迟槽异常时以分支 PC 写 EPC 并设置 BD。

HI/LO 单元增加 `cancel`。被异常冲刷的除法重置输入/状态机并丢弃未提交结果，既有 HI/LO 值保持不变。`hilo_unit_tb.v` 增加中途取消除法的断言；最终运行日志为 `HILO_UNIT_TB_PASS mult_accepts=3 div_accepts=5 input_pairs=3 commits=6`，证明取消项不增加结果提交次数，之前写入的 HI/LO 值保持不变。

课程 Lab9 的 94 点用例覆盖 break、OV、数据地址 AdEL/AdES、取指 AdEL、RI 和延迟槽异常；每个类型的 expected EPC/BD/BadVAddr 和搜索 PC 已列入波形采集表。精确 store kill 另由 CPU 级硬件中断测试检查年轻 store 在 trap 边界不写内存、ERET 后只执行一次。当前没有额外的同步异常 CPU directed TB 专门排列“老 store / 故障 store / 年轻 store”三项，因此这项更严格的 side-effect 序列不据此单独宣称通过。

## S4 - 定时器、软件和外部硬件中断

`cp0_reg` 把 `hw_int[5:0]` 接到 Cause.IP2-IP7；IP7 与 timer TI 按位 OR。SoC 硬件模式从 `switch[5:0]` 取输入，经两个 `cpu_clk` 寄存器同步后接到 CPU；仿真模式使用常零源，避免课程 testbench 固定 `switch=8'hff` 意外触发中断。CPU 外部端口仍为 `mycpu_top.hw_int`，直接测试可以逐路注入。

独立 CP0 单测 `cp0-unit-20261109T141303Z` 通过 62 条断言、提交 2 次 trap；覆盖 Count 半速递增、Compare 清 TI、Status/Cause 写掩码、Cause.IP0/IP1、外部 IP2-IP7 映射和屏蔽、IP7 双源 OR、EPC/BD/EXL/ERET。

`interrupt_tb.v` 和 `scripts/run_interrupt_tb.tcl` 以 `IRQ_INDEX=0..5` 分别运行 IP2-IP7，每路都让输入从复位期间保持有效开始，先验证 IM 屏蔽，再设置对应 IM 位，检查向量和 ExcCode=0，随后清除输入、在 handler 中修正 EPC 并 ERET。testbench 还断言被打断指令没有 GPR 写回、trap 当拍没有年轻 store、后继 store 在返回后恰好写一次，并且请求清除后不重复进入。

| 硬件源 | Run ID | 自检结果 |
|---|---|---|
| IP2 | `interrupt-ip2-20261110T` | 10 条断言，1 trap，1 eret，1 store，PASS |
| IP3 | `interrupt-ip3-20261110T` | 10 条断言，1 trap，1 eret，1 store，PASS |
| IP4 | `interrupt-ip4-20261110T` | 10 条断言，1 trap，1 eret，1 store，PASS |
| IP5 | `interrupt-ip5-20261110T` | 10 条断言，1 trap，1 eret，1 store，PASS |
| IP6 | `interrupt-ip6-20261110T` | 10 条断言，1 trap，1 eret，1 store，PASS |
| IP7 | `interrupt-ip7-20261110T-retry` | 10 条断言，1 trap，1 eret，1 store，PASS |

IP7 与 timer 共用 Cause.IP7。定向用例先执行 `mtc0 zero,Compare` 清除复位后 `Count==Compare` 锁存的 TI，再开启 IM7，以便该轮 CPU 级 trap 能归因到外部 IP7。首轮未做此隔离的日志保留在 `interrupt-ip7-20261110T/`，不作为 IP7 外部源通过证据。课程 Lab9 n81/n82 与 CP0 单测分别覆盖 timer/software 请求的置位、屏蔽、清除和返回。

## 最终课程回归

所有回归均使用 forwarding 模式，并与原始课程镜像和对应 reference GPR trace 一一配对；COE/MIF 与 reference 输入未修改。

| 用例 | Run ID | 功能点 | 周期 | 停顿 | 状态 |
|---|---|---:|---:|---:|---|
| Lab3 | `lab3-20261109T164953Z` | 23/23 | 172,599 | 0 | PASS |
| Lab4 | `lab4-20261109T165423Z` | 23/23 | 114,577 | 50 | PASS |
| Lab6 | `lab6-20261109T165828Z` | 42/42 | 109,439 | 89 | PASS |
| Lab7 | `lab7-20261109T170251Z` | 68/68 | 166,330 | 926 | PASS |
| Lab8 | `lab8-20261109T163413Z` | 69/69 | 166,850 | 986 | PASS |
| Lab9 | `lab9-20261109T163846Z` | 94/94 | 195,004 | 3,910 | PASS |

Lab8/Lab9 的最终波形 capture 均使用 `log_wave -r /`。各自 WDB 的 SHA-256 已存入对应 `result.txt`；其匹配 WCFG 在 Vivado 静态打开校验后，信号数与 `.wcfg` 声明一致。早期无效 WDB 被保留为诊断产物，不引用作报告证据。

## 板级和证据范围

`soc_lite_top` 的硬件中断接线使用现有 `switch[7:0]` 约束中的低 6 位，所以没有增加未约束顶层端口。此次完成行为仿真，没有运行综合、实现、bitstream 下载或 FPGA 实板验证；switch 极性和板上实际中断交互仍需在硬件环境确认。
