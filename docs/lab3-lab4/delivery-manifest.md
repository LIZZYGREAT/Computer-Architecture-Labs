# Lab3 / Lab4 最终交付清单

## 最终通过结果

| 用例 | 结果目录 | 状态 | 核心结果 |
|---|---|---|---|
| Lab3 forwarding | [`lab3-20261027T025645Z`](../../results/lab3_lab4/lab3-20261027T025645Z/) | PASS | 23/23，172,599 周期，0 stall |
| Lab4 blocking | [`lab4-20261022T040641Z`](../../results/lab3_lab4/lab4-20261022T040641Z/) | PASS | 23/23，130,891 周期，16,364 stall |
| Lab4 forwarding | [`lab4-20261027T030155Z`](../../results/lab3_lab4/lab4-20261027T030155Z/) | PASS | 23/23，114,577 周期，50 stall |
| 定向 blocking | [`lab4-20261022T041535Z`](../../results/lab3_lab4/lab4-20261022T041535Z/) | PASS | 98 周期，29 stall |
| 定向 forwarding | [`lab4-20261022T041931Z`](../../results/lab3_lab4/lab4-20261022T041931Z/) | PASS | 72 周期，3 stall，含 WDB |

每个保留的 DUT 结果保留 `result.txt`、Vivado/XSim 阶段日志、source manifest、图像一致性检查及 IP 状态报告。重复完整回归、失败轮、拼接/复制/控制台日志及启动命令副本已清理。

## 参考与诊断证据

- [`reference-lab4-20261022T040401Z`](../../results/lab3_lab4/reference-lab4-20261022T040401Z/)：独立 CPU132 生成 Lab4 golden trace 的通过日志。
- [`hazard-directed`](../../results/lab3_lab4/hazard-directed/)：定向 MIPS 程序、COE/MIF、listing、golden trace 和独立参考运行日志。
- [`gcc-startup-incident.md`](gcc-startup-incident.md)：AppContainer 与普通 PowerShell 的启动边界及已采取的防误报措施；原始故障日志已清理。

## 报告入口

- [`verification-final.md`](verification-final.md)：本轮完整结果、哈希和验收命令。
- [`gcc-startup-incident.md`](gcc-startup-incident.md)：准确的 GCC/Xelab 根因边界。
- [`report_materials.md`](report_materials.md)：可整理进实验报告的素材。
- [`implementation.md`](implementation.md)：流水线实现与计数口径。
- [`figures/README.md`](figures/README.md)：从 WDB 导出标注截图的步骤。

带标注的 GUI 截图和 FPGA 上板记录尚未取得。
