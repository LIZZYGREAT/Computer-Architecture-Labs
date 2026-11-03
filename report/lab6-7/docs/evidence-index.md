# Lab6/Lab7 报告证据索引

报告结论基于以下仓库内保留的最终回归记录。结构、握手和流程图按 RTL 或测试场景绘制；统计图和退休事件图由 Python 从验收结果与匹配后的参考 trace 生成；周期级波形证据使用对应运行的 WDB。

| 结论 | 证据 |
|---|---|
| Lab3/Lab4 forwarding 基线 PASS，各 23/23 | `results/lab3_lab4/lab3-20261027T025645Z/result.txt`、`results/lab3_lab4/lab4-20261027T030155Z/result.txt` |
| Lab6 累计 forwarding PASS，42/42，66,612/66,612 trace 匹配并捕获有效 WDB | `results/lab6_lab7/lab6-20261102T054949Z/result.txt`、对应 WDB 与 `xsim-simulate-stage.log` |
| Lab7 累计 forwarding PASS，68/68，100,732/100,732 trace 匹配并捕获有效 WDB | `results/lab6_lab7/lab7-20261102T055526Z/result.txt`、对应 WDB 与 `xsim-simulate-stage.log` |
| 新指令前递定向覆盖 PASS，trace 41/41，计数 3/2/6/1 | `results/lab6_lab7/lab7-20261026T170957Z/result.txt`、`results/lab6_lab7/directed/extended-forwarding/` |
| HI/LO 单元接受/提交及运算检查通过 | `results/lab6_lab7/hilo-unit-20261027T032000Z/result.txt`、`vivado.log` |
| 除法期间 held branch、delay slot、目标路径检查通过并采集 WDB | `results/lab6_lab7/directed/hilo-stall-branch/golden_trace.txt`、`results/lab6_lab7/lab6-20261102T060138Z/result.txt` 与对应 WDB |
| 算术逻辑定向 ROM 通过并保存补充 WDB | `results/lab6_lab7/directed/alu/`、基线 `results/lab3_lab4/lab3-20261021T140840Z/`、波形运行 `results/lab3_lab4/lab3-20261028T132600Z/` |
| Python 生成图表与采集数据 | `report/lab6-7/figures/`、`report/lab6-7/data/`；`data/evidence_index.csv` 记录每张图的数据源与运行 ID |
| 面向报告改写的完整指标、定向事件值与图表映射 | `report/lab6-7/docs/report-data-notes.md` |
| RTL 实施范围与设计决策 | `docs/lab6_lab7/implementation.md` |
| 仿真环境、复现命令和哈希 | `docs/lab6_lab7/verification.md`、`docs/lab6_lab7/environment.md` |

## 范围说明

- 退休事件图表示 trace 顺序，不代表周期级时序；周期级波形应使用 `docs/wave-capture-handoff.md` 所列的 WDB 和 WCFG。
- HI/LO testbench 未覆盖除数为零；报告不对该场景作正确性结论。
- PASS 结论针对保存的课程映像、定向程序和仿真环境，不代表形式化证明、板上实测或综合后时序验证。
- Lab6/Lab7 使用不同累计课程程序，周期数仅各自描述，不作为横向性能比较。
