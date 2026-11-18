# Lab13–Lab19 TLB 与 Cache 最终验收报告

- **分支：** `lab12-lab19`
- **实现范围：** Lab13、Lab14 n1–n6、Lab16、Lab17、Lab18、Lab19 和 Dhrystone/CoreMark 运行
**最终功能状态：** 必须完成的功能验收均通过；顶层综合完成并生成资源/时序报告。截图仍按方案交接，综合 hold 时序尚未收敛。

## 总结

本分支已完成 Lab10–11 合并和 Lab13–19 的 TLB、Cache 实现与验收。Lab15 的 TLB Refill/Invalid/Modified 异常处理按任务方案标记为 **NOT_REQUIRED**，没有将其算作 PASS。Lab17 的同镜像无 Cache 对比通过；Lab19 Dhrystone 和 CoreMark 正常结束，但没有同条件 Lab19 基线，所以没有声称性能加速。

顶层 `soc_axi_lite_top` 在 Vivado 2025.2 中综合成功，资源报告可用。合成时序估算的 setup WNS 为 3.975 ns；hold 报告仍有 66 个失败端点，且未进行布局布线，因此本报告不代表 FPGA 实际时序签核。GUI 截图和人工读值尚未完成；15 行截图交接表均保留 `PENDING_CAPTURE`，`observed` 和时间窗为空。

## 分阶段实现与验收

| 阶段 | 主要实现提交 | 最终验收结果 | 最终证据 |
| --- | --- | --- | --- |
| S0 基线/合并 | merge `64e2586` | `lab10-lab11` 合并进入本分支；保留 Lab11 回归参考与基线审计 | [基线记录](../docs/baseline.md) |
| S1 Lab13 TLB | `1e201f1`; evidence `c7e6eeb` | 官方 write/read/search PASS；16 项写入与读回、26 个查找端口案例、`test_error=0`；定向 9/9 | [官方运行](../../../results/lab13-lab19/lab13/lab13-tlb-official-unit-20261118-01/result.txt)、[定向运行](../../../results/lab13-lab19/lab13/lab13-tlb-directed-20261118-04/result.txt)、[S1 报告](s1-lab13-tlb.md) |
| S2 Lab14 CP0/TLB | `ce1cd75`; 回归 `fc34199`, `985f64f`; evidence `719252c` | 官方 n1–n6 6/6、4,705 周期；地址翻译定向 11/11；Lab11 AXI3 directed PASS；Lab11 golden trace 94/94、111,625 行 | [官方运行](../../../results/lab13-lab19/lab14/lab14-n1-n6-official-20261118-05/result.txt)、[S2 报告](../../../docs/lab13-lab19/S2_Lab14_CP0_TLB_验收报告.md) |
| S3 Lab16 独立 Cache | `e326675` | 官方索引 `00`–`ff` 共 256/256；定向 20 项通过，复位取消单独记账 | [官方运行](../../../results/lab13-lab19/lab16/lab16-official-20261118-05/result.txt)、[S3 报告](../../../docs/lab13-lab19/S3_Lab16_Cache_验收报告.md) |
| S4 Lab17 ICache | `c1cfd93` | 功能 94/94；定向 bridge/cache 24 项；同镜像无 Cache 基线也为 94/94，3,752 次 Store 全部恰好完成一次 | [定向运行](../../../results/lab13-lab19/lab17/lab17-bridge-directed-20261118-06/result.txt)、[S4 报告](../../../docs/lab13-lab19/S4_Lab17_ICache_验收报告.md) |
| S5 Lab18 DCache | `b222239`; evidence `139d085` | 功能 94/94；DCache 定向 9 项；并发 I/D miss、MEM 异常/提交检查通过；无重复 Store | [DCache 定向运行](../../../results/lab13-lab19/lab18/lab18-dcache-directed-20261118-01/result.txt)、[S5 报告](../../../docs/lab13-lab19/S5_Lab18_DCache_验收报告.md) |
| S6 Lab19 CACHE/性能 | `4ba901c` | CACHE 官方 7/7；维护定向 9 项并覆盖 way2/way3；Dhrystone 与 CoreMark 均正常结束 | [Lab19 报告](../../../results/lab13-lab19/lab19/acceptance-report.md) |
| Lab19 综合 | `4ba901c` | 顶层 `soc_axi_lite_top` `synth_design` 完成；0 errors、0 critical warnings；资源与 timing summary 已保存 | [综合结果](../../../results/lab13-lab19/lab19/lab19-synthesis-20261118-01/result.txt)、[综合摘要](../../../results/lab13-lab19/lab19/lab19-synthesis-20261118-01/synthesis-summary.txt) |

Lab14 n7–n9 及 Lab15 专用 TLB 异常均不在本轮硬性验收范围。Lab11 原始 CPU/AXI 回归结果仍在证据索引中；Lab13–19 的实现放在隔离目录/副本中，旧 Lab11 验收 RTL 未被替换。

## 关键功能与总线数据

- **Lab16：** 独立 16B/行 Cache 官方索引 256/256；定向 21 次请求接受、20 次完成、1 次复位取消；16 次 refill read、1 次脏行写回。
- **Lab17：** 同一 `func_all94` 镜像、100 MHz 仿真条件下，无 Cache 为 1,402,080 周期，ICache 为 1,038,101 周期，周期比为 1.3506×；AXI AR 从 177,518 降至 43,108（减少 75.72%）。缓存行回填为 8 beat，因此 R beat 数不能和 AR 事务数混为一谈。
- **Lab18：** DCache hit/miss 为 6,937/950；脏行写回 446；Uncache 483；AXI AR/R/AW/W/B 为 39,684/197,331/685/3,807/685。3,752 个 CPU Store 和 95 个 NUM 外设写均接受、完成一一对应。
- **Lab19 官方 CACHE：** 2,836 周期、458 条退休指令；I hit/miss/refill 为 397/51/51，D hit/miss/writeback/Uncache 为 2/4/2/45；AXI AR/R/AW/W/B 为 95/480/26/40/26；Store 28/28，重复 0。
- **Lab19 Dhrystone：** 251,834 周期、51,073 条退休指令；I hit/miss/refill 40,789/133/133；D hit/miss/writeback/Uncache 6,579/13/0/4,559；正常输出 `num_data=0003343c`。
- **Lab19 CoreMark：** 2,305,331 周期、416,073 条退休指令；I hit/miss/refill 260,271/508/508；D hit/miss/writeback/Uncache 77,338/70/0/7,507；正常输出 `num_data=01394d3c`。

Lab19 仿真 CPU 时钟是 100 MHz；固件性能输出按配置的 50 MHz 报告。Dhrystone 输出 47,846 Dhrystones/s、0.544 DMIPS/MHz；CoreMark 输出 48,704 iterations/1000s、0.974 CoreMark/MHz。CoreMark 还打印了源码占位串 `Memory location: Please put data memory location here`，但其功能 PASS 与结束标志正常。没有同配置 Lab19 无 Cache 基线，不计算 Lab19 speedup。

## 综合资源与时序边界

目标器件为 `xc7a200tfbg676-2`。Vivado 2025.2 综合资源：

| 资源 | 使用量 | 利用率 |
| --- | ---: | ---: |
| LUT | 25,278 / 134,600 | 18.78% |
| LUT as memory | 5,574 / 46,200 | 12.06% |
| Registers | 11,112 / 269,200 | 4.13% |
| BRAM tiles | 256 / 365 | 70.14% |
| DSP | 0 / 740 | 0% |
| IOB | 55 / 400 | 13.75% |
| PLLE2_ADV / BUFGCTRL | 1 / 10；3 / 32 | — |

合成 timing summary：setup WNS/TNS 为 3.975 ns/0 ns；hold WHS/THS 为 -0.087 ns/-5.338 ns，有 66 个 hold-failing endpoints，主要涉及相关 `cpu_clk`/`timer_clk` 路径。当前为综合估算，没有 place/route，也没有对 15 个输入与 39 个输出端口设置外部延时。131 条 warning 归类在综合运行的 `warnings-summary.txt` 中，0 critical warning、0 error。需要后续补全外部时序约束并完成布局布线、hold 收敛后，才能判断板级时序。

## 证据与截图交接

[证据索引](../data/evidence_index.csv)列出 21 份最终/基线 Run；[事务指标表](../data/transaction-metrics.csv)集中记录各阶段关键计数；[截图交接 CSV](../data/wave-capture-log.csv)列出方案中的 15 个图项。截图交接所选的 Lab13–Lab19 WDB 均配有对应 WCFG；Lab14–Lab19 的新增配置已用 Vivado 对应 WDB 打开并校验信号路径。其他非截图运行的 WDB 不一定另存 WCFG。Lab19 两个 WDB/WCFG 的 SHA-256 与信号数见 [Lab19 waveform index](../../../results/lab13-lab19/lab19/waveform-index.txt)。

这次没有生成或代填 PNG 截图、人工 `observed` 值或 `time_start_ns/time_end_ns`。请从交接 CSV 指定的最终 WDB/WCFG 截图并人工读数后，再把对应行改成 `CAPTURED_VERIFIED`。Lab17 的第二张配置展示 directed bridge run 中的 KSEG1 Uncache 与 RID fault；该 WDB 不含 CPU redirect 信号，所以不把它标成 redirect 证明。Dhrystone/CoreMark 长跑没有 WDB，L19-03 只交接真实日志/计数。

## 运行留存与可复现材料

每个类别只保留一份最终有效 RunId；已删除/未纳入索引的失败尝试和替代结果不作为验收证据。最终目录保留 `result.txt`、Vivado/编译/展开/仿真日志、活动源清单、输入清单、hash 与必要的 WDB/WCFG。Lab19 性能与综合输入均有 hash；综合的 34 项源清单完整匹配 `4ba901c`。

此前脚本单元测试运行 `python -m unittest discover -s scripts/tests -p 'test_*.py'` 通过 16 项；`verify.ps1` PowerShell AST 解析、Python helper 编译和 `git diff --check` 均通过。Lab19 run 使用各自的 COE/MIF 镜像，Dhrystone/CoreMark 输入没有和 94 点功能镜像混用。
