# Lab3 / Lab4 最终交付清单

## 最终验收轮次

| 用例 | 结果目录 | 状态 | 核心结果 |
|---|---|---|---|
| Lab3 forwarding | [`lab3-20261021T081224Z`](../../results/lab3_lab4/lab3-20261021T081224Z/) | PASS | 23 功能点，172,599 周期，0 stall |
| Lab4 blocking | [`lab4-20261021T081854Z`](../../results/lab3_lab4/lab4-20261021T081854Z/) | PASS | 23 功能点，130,891 周期，16,364 stall |
| Lab4 forwarding | [`lab4-20261021T082306Z`](../../results/lab3_lab4/lab4-20261021T082306Z/) | PASS | 23 功能点，114,577 周期，50 stall |
| 定向 blocking | [`lab4-20261021T083933Z`](../../results/lab3_lab4/lab4-20261021T083933Z/) | PASS | 98 周期，29 stall |
| 定向 forwarding | [`lab4-20261021T085125Z`](../../results/lab3_lab4/lab4-20261021T085125Z/) | PASS | 72 周期，3 stall，含 WDB |

每个最终结果目录保留 `result.txt`、Vivado preflight/simulation 日志、Xvlog/Xelab/XSim 阶段日志、source manifest 和本轮实际仿真 MIF。定向 forwarding 另保留 [`hazard-directed-forwarding.wdb`](../../results/lab3_lab4/lab4-20261021T085125Z/hazard-directed-forwarding.wdb)。

## 参考与诊断证据

- [`gcc-investigation-20261020T150000Z`](../../results/lab3_lab4/gcc-investigation-20261020T150000Z/)：Xelab GCC 命令、环境对比、独立复现和原始诊断。
- [`lab4-reference-20261020T161512Z`](../../results/lab3_lab4/lab4-reference-20261020T161512Z/)：Lab4 独立 CPU132 golden trace 生成记录。
- [`hazard-directed`](../../results/lab3_lab4/hazard-directed/)：65-word 定向程序、listing、MIF/COE、独立 golden trace 与参考运行记录。

## 报告入口

- [`verification-final.md`](verification-final.md)：完整验收事实、哈希、统计、日志入口和证据边界。
- [`report_materials.md`](report_materials.md)：可直接整理进实验报告的内容。
- [`implementation.md`](implementation.md)：流水线修改与计数口径说明。
- [`figures/README.md`](figures/README.md)：从实测 WDB 导出带标注 GUI 截图的步骤。

带标注的 GUI 截图和 FPGA 上板记录尚未取得，报告中应保持该状态。
