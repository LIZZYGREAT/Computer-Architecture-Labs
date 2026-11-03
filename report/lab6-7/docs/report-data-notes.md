# Lab6/Lab7 报告数据备忘

供后续整理或改写 `main.tex` 时使用。验收证据的完整路径与结论索引见 [`evidence-index.md`](evidence-index.md)；这里集中列出可直接写入报告的指标、定向用例事件和图表数据来源。仓库内 `results/` 路径以 `lab/` 为根目录。

## 累计课程回归

| 指标 | Lab6 | Lab7 |
|---|---:|---:|
| 验收状态与功能点 | PASS，42/42 | PASS，68/68 |
| 流水线周期 | 109,439 | 166,330 |
| 报告的停顿周期 | 89 | 926 |
| EX/MEM/WB 前递使用 | 35,013 / 8,320 / 12,007 | 49,970 / 12,229 / 15,454 |
| 新增 store-base/store-data/conditional-branch/JALR 前递 | 0 / 0 / 0 / 0 | 112 / 0 / 1,229 / 28 |
| 退休 trace 记录数 | 66,612 | 100,732 |
| 零号寄存器实际写回尝试 | 0 | 0 |
| 波形数据库 | 已在隔离工程中重新采集有效 WDB；42/42 PASS | 已在隔离工程中重新采集有效 WDB；68/68 PASS |

Lab6 trace SHA-256：`FB92799CBA4C42B1ECB729DD6659DADC63195B07E16C3FD6E25B2A6986850CA1`；MIF SHA-256：`845D97935C29D651D1D73D906DC3E92DC5690C23F77920111A369D33C28E8F28`。本次有效波形运行 `lab6-20261102T054949Z` 复用了相同输入。

Lab7 trace SHA-256：`23ADD75B2BADFDABF98B1863A89896DFC60B4B351CC49321B22BEB22035991C3`；MIF SHA-256：`8EBF314084B3B06BF40A9F4DF2B402E74BE5D1F705A75F7ADFC858868B9B75BE`。本次有效波形运行 `lab7-20261102T055526Z` 复用了相同输入。

两轮课程 ROM 长度和测试内容不同，周期与停顿数用于描述各自运行，不据此比较性能。前递计数按被 EX 接收的指令采样；每条指令每级至多计一次，不能解释为源操作数总数。

2026-11-02 波形重采集：Lab6 完整运行 `lab6-20261102T054949Z`，Lab7 完整运行 `lab7-20261102T055526Z`。两者均使用与原课程回归相同的 reference trace/MIF，STATUS=PASS；WDB 分别为 113,757,682 bytes（SHA-256 `9704AA3BB6446A03DAA02D06C9A45E15858A894F2087467CF8B6A35BB7CCBC98`）和 175,790,426 bytes（SHA-256 `F5B2935BA085351AE79D0FE32FCFA05C53FF9AD44CAD4BAB31474F533FA5541B`）。定向 DIV/分支保持运行 `lab6-20261102T060138Z`，111 周期、6 条 trace 写回记录匹配；WDB 5,038,883 bytes，SHA-256 `ACDA06311C4467DBC8C0EA8325736D5B6AF145A9BA97AC6A98B20EE0B21DB5CA`。所有新运行的仿真日志记录 `log_wave -r /`，未出现 HDL 层级未匹配警告；对应结果目录在 `results/lab6_lab7/`。

## 定向用例

### 算术逻辑与前递

运行 `lab3-20261028T132600Z`：PASS，73 周期，1 次记录的停顿，EX/MEM/WB 前递 7/6/3，36 条参考退休记录全部匹配。WDB 已保存于 `results/lab3_lab4/lab3-20261028T132600Z/lab3-20261028T132600Z-forwarding.wdb`。该 WDB 可用于后续 Vivado 波形采集；此前生成的截图已被判定不可用，不能放入报告。

| 检查点 | 指令/行为 | 参考写回值 |
|---|---|---|
| 立即数扩展 | `andi r12, r5, 0x8000` | `r12 = 00008000` |
| 立即数扩展 | `ori r13, r0, 0x8000` | `r13 = 00008000` |
| 立即数扩展 | `xori r14, r5, 0xffff` | `r14 = FFFF0000` |
| 可变移位，移位量 5 | SLLV / SRLV / SRAV | `r17=FFF00000`, `r18=04000000`, `r19=FC000000` |
| 可变移位，移位量 31 | SLLV / SRLV / SRAV | `r17=80000000`, `r18=00000001`, `r19=FFFFFFFF` |
| EX/MEM/WB 前递 | 连续相关运算 | `r21=00002468`, `r23=00000022`, `r25=00000024` |
| load-use | 插入一次等待后写回 | `r31=00008000` |

逐 PC、指令和数据见 `data/alu_key_events.csv`；完整 trace 摘要见 `data/alu_reference_trace.csv`。

### 除法期间的分支等待与延迟槽

运行 `lab6-20261027T031906Z`：PASS，111 周期，6 条目标退休写回记录匹配参考 trace。该自定义验证预期功能点数为 0，应按 trace 比对判定，不表示没有执行指令。该次未保存 WDB；`PIPELINE_STALL_CYCLES` 为 0，因此不要将此字段写成多周期 DIV/分支等待次数。

- 输入：`r1=-23`（`FFFFFFE9`），`r2=5`。
- signed DIV 后，延迟槽写回 `r3=00000055`。
- taken BEQ 的 fall-through 指令位于 PC `BFC00014`，预期写入 `r4=00001234`；该 PC 没有对应写回记录。
- 目标路径：`MFLO` 写回 `r5=FFFFFFFC`（商 -4），`MFHI` 写回 `r6=FFFFFFFD`（余数 -3），目标标记写回 `r7=00000066`。

逐事件数据见 `data/div_branch_events.csv`；该图展示退休顺序，不含周期尺度。

### Lab7 条件分支与 JALR

运行 `lab7-20261026T170957Z`：PASS，64 周期，1 次记录的停顿，trace 41 条记录；EX/MEM/WB 前递 20/3/2，新 store-base/store-data/branch/JALR 前递 3/2/6/1。该运行未保存 WDB；其自定义功能点数为 0，验收依据是自定义 trace 与 hazard checks。

- 条件分支：PC `BFC00068` 将 `r2` 设为 1；taken `BGEZ` 在 `BFC0006C`；延迟槽 PC `BFC00070` 写回 `r3=00000040`；fall-through PC `BFC00074` 没有写回；目标 PC `BFC00078` 写回 `r2=00000001`。
- JALR：PC `BFC000E0` 建立目标 `r25=BFC000F0`；PC `BFC000E4` 的 `jalr r26,r25` 写回链接值 `r26=BFC000EC`（PC+8）；延迟槽 `BFC000E8` 写回 `r4=00000061`；fall-through PC `BFC000EC` 没有写回；目标 PC `BFC000F0` 写回 `r2=00000001`。

逐事件数据见 `data/extended_control_events.csv`；对应图只表达参考退休 trace 中可核对的写回事件，不代表波形时序。

### HI/LO 单元 testbench

运行 `hilo-unit-20261027T032000Z`：乘法接受 3 次，除法接受 4 次，共接受 7 次；完成并提交 6 次；另有 1 次进行中的除法被复位取消。测试通过。除数为零未覆盖，不对该场景作正确性结论。结构化记录见 `data/hilo_unit_summary.csv`。

## 图表与数据文件

| 图表 | 数据源/性质 |
|---|---|
| `figures/alu_key_values.png` | `data/alu_key_events.csv`；ALU 写回值和结果位，不编码周期 |
| `figures/div_branch_retirement.png` | `data/div_branch_events.csv`；DIV 后分支定向 trace 的写回次序，无 WDB |
| `figures/extended_branch_retirement.png` | `data/extended_control_events.csv`；条件分支延迟槽/目标退休记录，无 WDB |
| `figures/jalr_retirement.png` | `data/extended_control_events.csv`；JALR 链接、延迟槽和目标退休记录，无 WDB |
| `figures/cumulative_metrics.png` | `data/verification_summary.csv`；累计周期、停顿和前递计数 |
| `figures/hilo_unit_counts.png` | `data/hilo_unit_summary.csv`；HI/LO 单元接受、提交和复位取消计数 |
| `figures/functional_coverage.png` | 两轮累计回归的功能点通过数 |
| `figures/cpu_pipeline.png`, `figures/hilo_handshake.png`, `figures/div_branch_delay_slot.png` | RTL 结构、握手和控制流说明图，不是仿真测量图 |

完整 trace CSV 为 `lab6_reference_trace.csv` 和 `lab7_reference_trace.csv`（文件较大）；文件来源、运行 ID 与哈希索引见 `data/evidence_index.csv`。

## 后续写作提示

### WDB 捕获状态核查（2026-11-02）

历史 Lab6 Run `lab6-20261028T093517Z` 的 WDB 不可用：`xsim-simulate-stage.log` 记录 `log_wave -r /tb_top` 后出现 `[Simtcl 6-55] No matching HDL object or HDL scope found`。历史 Lab7 Run `lab7-20261028T102942Z` 的阶段日志缺失，不能仅凭旧 `WAVEFORM_CAPTURED=True` 判断其 WDB 有效。两份旧文件均保留，但新的截图配置不再引用它们。

已按用户授权在隔离副本 `lab3/CPU_CDE/mycpu_verify/run_vivado/mycpu_prj1_wave_recapture/mycpu_prj1_wave_recapture.xpr` 中重跑 Lab6、Lab7 和 DIV/分支保持定向用例。三次运行均通过只读预检，使用 `log_wave -r /`，仿真日志无层级未匹配警告；结果和哈希见上文。13 份 WCFG 位于 `figures/waveforms/`，已更新为重采集 WDB 的路径；实际截图时间窗和观察值仍应从 Vivado Wave 读取，不从 expected 推断。

- 正文应写实验方法、已测数据、分析和技术范围；不要写“没有导出截图”或代理工作过程等交付状态说明。
- 不要把 trace 顺序图称为 Vivado 波形。其横轴为退休记录序号，没有时钟周期含义。
- 先前的 Vivado JPG 不是有效证据，不应放入报告。原有 `figures/01_alu.wcfg`、`02_shift.wcfg`、`03_mul.wcfg` 均保留；`figures/waveforms/01_alu_directed_full_run.wcfg` 已根据 ALU 信号布局重建，并关联到当前 PASS 的定向 ALU WDB。该配置副本不依赖旧 JPG。

## 当前草稿交接状态

- 正文中的截图采集状态和代理工作过程说明已清理；后续改稿继续只写实验技术内容，不要加入“本版不含 Vivado 截图”一类工作状态。
- `main.pdf` 是前次编译的旧版，需在正文和图表最终修订后重新编译并检查版面。
- WCFG 与 JPG 是不同文件；波形配置保存在 `figures/waveforms/`，不依赖旧 JPG。
