# Lab13–Lab19 TLB 与 Cache 最终验收报告

- **更新日期：** 2026-11-19
- **分支：** `lab13-lab19`
- **范围：** Lab13、Lab14 n1–n6、Lab16、Lab17、Lab18、Lab19、Dhrystone/CoreMark。
- **验收结论：** 当前 Lab19 必需功能回归、94/94 CPU 验收、真实软件 TLBWI、Cache/维护/写回/IF 重放和两项性能程序均有通过记录。`synth_design` 已完成；综合报告另有一条 Vivado 工具路径诊断，且 hold 时序、板级 I/O 约束和布局布线未闭合。20 项截图仍待人工核验。

## 本轮最终 Lab19 结果

表中 `GIT_HEAD` 是各次运行时的提交，不是报告提交后的 HEAD。每次 Run 的源文件和输入镜像清单均保存在对应结果目录；历史 `4ba901c` 结果只作基线，不冒充当前结果。

| 验收项 | RunId / GIT_HEAD | 结果 |
| --- | --- | --- |
| 最终 Lab19 CPU + `func_all94` | [r3l19-all94-04](../../../results/lab13-lab19/lab19/r3l19-all94-04/result.txt) / `0c1f206e1e4c3c79dc6ccc49709520c0b27db194` | 94/94；3,752 Store 接受并完成，重复 0；95 次外设写完成 |
| 软件指令 TLBWI | [r3l19-tlbwi-e2e-01](../../../results/lab13-lab19/lab19/r3l19-tlbwi-e2e-01/result.txt) / `94898dc1a42ff7003ba707202a92a2a33eb41a52` | 软件 `mtc0` / `tlbwi` 正常提交一次；VA `00400100` 取指映射到 PA `00000100`；245 周期 |
| TLB 旧响应重放交叉检查 | [r3l19-tlbreplay-01](../../../results/lab13-lab19/lab19/r3l19-tlbreplay-01/result.txt) / `a73b51f1ec3d51474e7fd824d54e75b537cc9810` | 独立 force-event 检查：旧 PA `abcde100` 丢弃，VA 按新 PFN `12345100` 重放；它不代表软件执行 TLBWI |
| 官方 CACHE 程序 | [r3l19-cache-01](../../../results/lab13-lab19/lab19/r3l19-cache-01/result.txt) / `f504c94fae79b2c4ed37f225a56795b214f895af` | 7/7；28/28 Store；重复 0；WDB/WCFG 留存 |
| 维护定向回归 | [r3l19-maint-01](../../../results/lab13-lab19/lab19/r3l19-maint-01/result.txt) / `8126dee13fd064064214b24dcf946bc11d27ca6f` | 10/10；Way 2/3、未映射 IndexWBInv、B 等待和 sentinel 检查通过 |
| 顶层 Index/Hit 契约 | [r3l19-index-02](../../../results/lab13-lab19/lab19/r3l19-index-02/result.txt) / `731041f0ee78d5afa555ca3d9f5a76996766b79a` | IDX-01/02/04 通过；IDX-03 明确记为 `UNSUPPORTED_BY_SCOPE`，不声称产生 TLBL/TLBS 异常 |
| 四路 DCache 写回 scoreboard | [r3l19-wb-02](../../../results/lab13-lab19/lab19/r3l19-wb-02/result.txt) / `f4a0b7fedba0985f5371172089fc9fde3b6cc2bf` | 四个 Way；32/32 WDATA 与 reference memory 一致；4 AW/4 B；B 返回前不完成 |
| IF redirect | [r3l19-redirect-01](../../../results/lab13-lab19/lab19/r3l19-redirect-01/result.txt) / `b158a0f3621b6948ebaa815e7966389ca4ba9fab` | 7 项通过，含 delay slot、旧响应丢弃和异常优先级；WDB/WCFG 留存 |
| Dhrystone | [r3l19-dhrystone-01](../../../results/lab13-lab19/lab19/r3l19-dhrystone-01/result.txt) / `234910f8b4aa54d0dc5fe71c0cfc4eb619920025` | 程序输出通过；251,834 周期、51,073 条退休指令 |
| CoreMark | [r3l19-coremark-01](../../../results/lab13-lab19/lab19/r3l19-coremark-01/result.txt) / `b01a43b51f2ddabd76d7e7a8522e8c6f37b873ea` | 程序输出通过；2,305,331 周期、416,073 条退休指令 |
| 当前 Lab19 综合 | [r3l19-synthesis-02](../../../results/lab13-lab19/lab19/r3l19-synthesis-02/result.txt) / `4709468f65bac621486685efb06c76a0bc207e40` | `SYNTHESIS_STATUS=PASS`，外层 `PASS_WITH_TOOL_DIAGNOSTIC`；`TIMING_NOT_CLOSED`，未布局布线 |

### 功能与事务口径

- Lab19 all94 的 94 个软件功能点不是逐条寄存器写回黄金 trace；它与 Lab19 `CACHE 7/7`、Lab14 n1–n6 以及 Lab11 111,625 行 golden trace 是四种不同的验收计数。
- all94 镜像主要通过不可缓存映射运行，因此 ICache hit/miss/refill 为 0、uncache read 为 172,900；DCache hit/miss/writeback 为 0、uncache 请求为 8,370。这些是本次镜像和访问映射下的合法统计，不代表缓存路径没有测试；缓存路径由独立 CACHE 与定向用例覆盖。
- all94 外部 AXI AR/R 为 177,517/177,517，AW/W/B 为 3,752/3,752/3,752；Store 接受/完成 3,752/3,752，重复 0；NUM 外设写 95/95。
- `r3l19-tlbwi-e2e-01` 覆盖软件 `mtc0 EntryHi/EntryLo/Index; tlbwi` 提交及新映射取指；在途旧响应丢弃由单独的 force-event 交叉检查覆盖。二者不能合并描述成同一种测试。
- Index 契约中未翻译的 Hit 操作被阻止在 I/D Cache 之前。Lab15 的 TLBL/TLBS/Modified 异常入口没有实现，也不属于本轮范围，统一记为 `UNSUPPORTED_BY_SCOPE`，没有列为 PASS。
- Lab17/18 的相关 RTL 在本轮未改动，所以按方案不重复跑长程功能测试；其最近有效的 94/94 与 fault/仲裁回归继续作为对应源提交的证据，见 [Lab17 functional](../../../results/lab13-lab19/lab17/r2l17func01/result.txt)、[Lab17 fault](../../../results/lab13-lab19/lab17/r2l17fault06/result.txt)、[Lab18 functional](../../../results/lab13-lab19/lab18/r2l18func01/result.txt) 和 [Lab18 fault](../../../results/lab13-lab19/lab18/r2l18fault05/result.txt)。

## 性能结果与时钟说明

| 程序 / RunId | 周期 / retired | ICache hit/miss/refill | DCache hit/miss/writeback/uncache | AXI AR/R/AW/W/B | 程序标志 |
| --- | --- | --- | --- | --- | --- |
| Dhrystone / `r3l19-dhrystone-01` | 251,834 / 51,073 | 40,789 / 133 / 133 | 6,579 / 13 / 0 / 4,559 | 12,675 / 13,697 / 2,185 / 2,185 / 2,185 | `num_data=0003343c` |
| CoreMark / `r3l19-coremark-01` | 2,305,331 / 416,073 | 260,271 / 508 / 508 | 77,338 / 70 / 0 / 7,507 | 162,251 / 166,297 / 1,130 / 1,130 / 1,130 | `num_data=01394d3c` |

两次仿真的 CPU 时钟为 100 MHz；Dhrystone 固件打印 47,846 Dhrystones/s、0.544 DMIPS/MHz，CoreMark 打印 48,704 iterations/1000s、0.974 CoreMark/MHz，均按固件设置的 50 MHz 口径计算。报告保留该配置口径，不把它表述成 100 MHz 实测吞吐率。没有同配置 Lab19 无 Cache 基线，因此不声称 Lab19 性能加速。Dhrystone、CoreMark 是长跑，只保留结果、仿真/UART 日志和事务计数，没有制造 WDB/WCFG。

## 综合资源与时序边界

`r3l19-synthesis-02` 使用 Vivado 2025.2、器件 `xc7a200tfbg676-2` 和当前 Lab19 RTL 完成 `synth_design`。综合网表资源如下：

| 资源 | 使用量 | 器件容量 | 利用率 |
| --- | ---: | ---: | ---: |
| LUT | 34,400 | 134,600 | 25.56% |
| LUT as memory | 10,582 | 46,200 | 22.90% |
| Registers | 11,546 | 269,200 | 4.29% |
| BRAM tiles | 256 | 365 | 70.14% |
| DSP | 0 | 740 | 0% |
| IOB | 55 | 400 | 13.75% |
| PLLE2_ADV / BUFGCTRL | 1 / 3 | 10 / 32 | — |

与旧提交 `4ba901c` 的 25,278 LUT baseline 相比增加 36.09%，BRAM tiles 不变。当前层次报告把大部分组合逻辑定位到 CPU/DCache/ICache 层级：CPU 30,025 LUT、DCache 17,055 LUT（其中 7,512 LUTRAM）、ICache 5,314 LUT（其中 2,504 LUTRAM）；未据此猜测并擅自改 RTL。

- Setup WNS/TNS：`+4.235 ns / 0 ns`，setup failing endpoints 为 0。
- Hold WHS/THS：`-0.087 ns / -5.338 ns`，66 个 failing endpoints。
- 综合 warning 131、critical warning 0、`synth_design` error 0。Vivado 总日志另有一条 `Common 17-1257` 创建路径诊断；所以运行状态写成 `PASS_WITH_TOOL_DIAGNOSTIC`，没有把它计入综合错误，也没有隐去该诊断。
- 板级 XDC 不存在；15 个输入、39 个输出没有外部 delay。没有执行 place/route。因此本报告结论是 `TIMING_NOT_CLOSED`，不是 FPGA 硬件时序签核。

## 回归脚本与诊断记录

为解决写回波形 hook 在 XSim post Tcl 中丢失 `stdout`、导致仿真虽通过但 Vivado 退出码为 1 的问题，提交 `f4a0b7f` 将 hook 移到 Vivado 主 Tcl 流程，并将 WCFG 生成加入写回用例验收门禁。`r3l19-wb-02` 与随后 `r3l19-redirect-01` 均以 Vivado 退出码 0 完成。没有修改 Lab19 RTL。

以下失败记录保留了有定位价值的摘要、源/输入清单和原始关键日志；从 all94-01/02/03 各删除了约 70–81 MB 可再生成的整份 IP 源与仿真工程副本：

- [all94-01](../../../results/lab13-lab19/lab19/r3l19-all94-01/result.txt)：编译时报 `tb_lab19_all94.sv` unexpected EOF，仿真未启动。
- [all94-02](../../../results/lab13-lab19/lab19/r3l19-all94-02/result.txt)：94 个 marker 均到达，最终 scoreboard 报 DCache 统计缺失。
- [all94-03](../../../results/lab13-lab19/lab19/r3l19-all94-03/result.txt)：94 个 marker 均到达，最终 scoreboard 报 ICache 统计缺失；在后续迭代中补齐统计并由 all94-04 通过。
- [index-01](../../../results/lab13-lab19/lab19/r3l19-index-01/result.txt)：快照构建后，XSim USF-XSIM-95 读取 `elaborate.log` 失败；仿真未启动，index-02 在新 RunId 通过。
- [wb-01](../../../results/lab13-lab19/lab19/r3l19-wb-01/result.txt)：scoreboard 仿真 marker 通过，但 post-hook 的 stdout 错误使 Vivado 退出 1；修复 hook 后由 wb-02 在新 RunId 通过。
- [synthesis-01](../../../results/lab13-lab19/lab19/r3l19-synthesis-01/result.txt)：Vivado 初始化失败，尚未进入 RTL 综合；由 synthesis-02 在新 RunId 完成。

## 历史阶段与证据索引

S0–S5 的历史验收保持原运行源提交，Lab11 golden trace 仍是独立历史证据；Lab13 官方 TLB、Lab14 n1–n6、Lab16 独立 Cache、Lab17/18 功能与 fault 回归没有被 Lab19 数字替代。Lab19 旧提交 `4ba901c` 的 CACHE、性能与综合记录已在证据索引标记 `HISTORICAL_BASELINE`；各条结果和 hash 均未改写。后续 `r2l19*` 记录标记为 `HISTORICAL_REVISION`，当前验收以本报告表内的 `r3l19-*` 为准。

| 阶段 | 保留的有效历史验收 |
| --- | --- |
| S0 基线/合并 | Lab10–11 合并和 Lab11 参考基线，见[基线记录](../docs/baseline.md)。 |
| S1 Lab13 TLB | 官方 16 项写入/读回、26 个双端口查找案例；定向 9 项通过，见[官方结果](../../../results/lab13-lab19/lab13/lab13-tlb-official-unit-20261118-01/result.txt)与[定向结果](../../../results/lab13-lab19/lab13/lab13-tlb-directed-20261118-04/result.txt)。 |
| S2 Lab14 CP0/TLB | n1–n6 6/6、4,705 周期；地址翻译定向 11 项；Lab11 AXI3 回归；Lab11 golden trace 94/94、111,625 行。见[Lab14 官方结果](../../../results/lab13-lab19/lab14/lab14-n1-n6-official-20261118-05/result.txt)和[Lab11 trace](../../../results/lab13-lab19/lab14/lab11-cpu-golden-20261118-03/result.txt)。 |
| S3 Lab16 独立 Cache | 官方索引 256/256；定向 20 项，21 次请求接受、20 次完成、1 次复位取消，见[官方结果](../../../results/lab13-lab19/lab16/lab16-official-20261118-05/result.txt)和[定向结果](../../../results/lab13-lab19/lab16/lab16-directed-20261118-02/result.txt)。 |
| S4 Lab17 ICache | 94/94 功能点、bridge/cache 24 项、AXI fault 28 项。与同镜像无 Cache 基线相比，周期 1,402,080 → 1,038,101，AXI AR 177,518 → 43,108；这是 Lab17 同镜像对照，不是 Lab19 性能加速。见[功能](../../../results/lab13-lab19/lab17/r2l17func01/result.txt)、[fault](../../../results/lab13-lab19/lab17/r2l17fault06/result.txt)。 |
| S5 Lab18 DCache | 94/94 功能点；DCache 定向、I/D 并发 miss、MEM 异常/提交和 fault 状态回归均通过；3,752 Store、95 外设写一一完成。见[功能](../../../results/lab13-lab19/lab18/r2l18func01/result.txt)、[DCache fault](../../../results/lab13-lab19/lab18/r2l18fault05/result.txt)。 |
| S6 Lab19 收尾 | 当前 94/94、真实软件 TLBWI、CACHE 7/7、维护 10/10、Index/Hit、四路写回、redirect、性能和综合结果见本节上方 RunId 表；旧 `4ba901c` 仅为历史基线。 |

- [证据索引](../data/evidence_index.csv)：保留历史记录、当前通过项和有用诊断；状态不会将未运行项算作 PASS。
- [事务指标](../data/transaction-metrics.csv)：当前 Lab19 数据均绑定 RunId 和结果日志；旧 `4ba901c` 指标标为历史 baseline。
- [波形截图交接](../data/wave-capture-log.csv)：共 20 项；`proof_status` 全部仍为 `PENDING_CAPTURE`，人工观察值和时间窗保持空白。
- [Lab19 WDB/WCFG 哈希清单](../../../results/lab13-lab19/lab19/waveform-index.txt)：列出当前 CACHE、维护、Index/Hit、force replay 和四路写回截图所用文件的 SHA-256。

`L19-06` 的截图 WDB 属于 force-event stale-response 交叉检查；真实软件 TLBWI 提交和映射取指由另一个 Run 验证。`L19-03` 是日志/指标图项，没有 WDB/WCFG。所有截图仍需在 Vivado 中打开对应 WDB/WCFG、人工核对信号值和时间窗，再更新 CSV；当前没有生成或伪造 PNG 截图。

运行结束检查：`python -m unittest discover -s scripts/tests -p 'test_*.py'` 为 19/19 PASS；`python -m compileall -q scripts/tlb_cache scripts/tests`、`verify.ps1` PowerShell AST 解析和最终 `git diff --check` 均通过。Lab19 CACHE、all94、Dhrystone、CoreMark 分别使用其匹配的 COE/MIF 输入，没有混用镜像。

两份早期成功目录 `revision2-l19-maint-p0-03` 和 `r2l19top03` 未改动；自动审批审查拒绝删除成功运行目录，它们也没有被本报告列作当前最终证据。
