# Lab6/Lab7 报告证据索引

报告结论基于以下仓库内保存的最新完整回归记录。报告不使用未捕获的 Vivado 波形截图；插图由 Python 根据 RTL 结构或结果文件绘制。

| 结论 | 证据 |
|---|---|
| Lab3/Lab4 forwarding 基线 PASS，各 23/23 | `results/lab3_lab4/lab3-20261026T162836Z/result.txt`、`results/lab3_lab4/lab4-20261026T163305Z/result.txt` |
| Lab6 累计 forwarding PASS，42/42，66,612/66,612 trace 匹配 | `results/lab6_lab7/lab6-20261026T163659Z/result.txt` 与同目录 XSim 日志 |
| Lab7 累计 forwarding PASS，68/68，100,732/100,732 trace 匹配 | `results/lab6_lab7/lab7-20261026T164130Z/result.txt` 与同目录 XSim 日志 |
| 新指令前递定向覆盖 PASS，trace 41/41，计数 3/2/6/1 | `results/lab6_lab7/lab7-20261026T170957Z/result.txt`、`results/lab6_lab7/directed/extended-forwarding/` |
| HI/LO 单元接受/提交及运算检查通过 | `results/lab6_lab7/hilo-unit-20261026T164656Z/result.txt`、`console.log` |
| 除法期间 held branch、delay slot、目标路径检查通过 | `results/lab6_lab7/directed/hilo-stall-branch/golden_trace.txt` 与 `results/lab3_lab4/lab3-20261022T065139Z/result.txt` |
| 算术逻辑定向 ROM 通过 | `results/lab6_lab7/directed/alu/` 与 `results/lab3_lab4/lab3-20261021T140840Z/` |
| RTL 实施范围与设计决策 | `docs/lab6_lab7/implementation.md` |
| 仿真环境、复现命令和哈希 | `docs/lab6_lab7/verification.md`、`docs/lab6_lab7/environment.md` |

## 范围说明

- `WAVEFORM_CAPTURED=False`：本轮没有启用 Vivado 波形捕获，按用户要求未创建 WDB/WCFG/PNG；报告未将结构图冒充波形。人工采集步骤见 `docs/lab6_lab7/waveforms.md`。
- HI/LO testbench 未覆盖除数为零；报告不对该场景作正确性结论。
- PASS 结论针对保存的课程映像、定向程序和仿真环境，不代表形式化证明、板上实测或综合后时序验证。
- Lab6/Lab7 使用不同累计课程程序，周期数仅各自描述，不作为横向性能比较。
