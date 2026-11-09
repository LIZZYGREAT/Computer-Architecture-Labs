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

SoC 顶层新增 `ext_int[5:0]` 输入，普通 `mycpu_tb` 明确驱动零。CP0 RTL 已加入原 Vivado 工程的 `sources_1` 和 `sim_1`，项目 preflight 现在要求两处都恰好存在该文件。`cases.json`、`verify.ps1`、行为仿真 Tcl 和 CPU132 trace 生成入口已支持 Lab8/Lab9；参考 trace 在每个用例独立的 `results/lab8_lab9/reference-work/` 工程中以对应原始镜像生成，没有修改课程 COE/MIF。

### Lab8 实测

- CPU132 reference：Run `reference-lab8-20261109T142849Z`，69/69 功能点，100,913 条 GPR trace 记录，trace SHA-256 `F6A7268A79725186B9EC8602A404CC5BE8E1D439E93ACAD1B2ADA04937723994`。
- DUT：Run `lab8-20261109T143142Z`，Vivado 2025.2/XSim compile、elaborate、simulate 均成功；69/69 功能点、trace 全量匹配，166,827 周期、950 停顿周期；零寄存器写入尝试 0；WDB SHA-256 `B44C7C3A860746D20D91359205696A82A76733049BA8110519B0919AD1706B7C`；`STATUS=PASS`。
- 输入 MIF SHA-256 与 S0 记录相同：`D611D547FFDC000F003673B1B9276D1BA813C15008BE071EE6B639DE278ABF51`。运行状态、参数、trace 和波形路径见 `results/lab8_lab9/lab8-20261109T143142Z/`；reference 日志与 trace 哈希见 `results/lab8_lab9/reference-lab8-20261109T142849Z/`。

本阶段覆盖累计 Lab8 镜像中的 syscall、mfc0/mtc0/eret 和 CP0 异常返回链。它尚未覆盖 break、RI、溢出、Load/Store 对齐异常、Lab9 定时器/软件中断，以及独立外部中断断言；这些在后续阶段执行。Vivado 运行后递增的 XPR 启动计数器已还原；XPR 提交差异仅保留 CP0 在两个文件集中的源文件条目。
