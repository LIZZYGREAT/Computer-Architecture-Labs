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
