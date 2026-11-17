# Lab10/Lab11 验收交接

## 完成状态

- 分支：`lab10-lab11`
- 最近实现/证据提交：`78132aa`（Lab11 S5），前序 Lab10 S5 为 `eca3023`
- 其他阶段提交：S0 `415c8fc`、S1 `0cd575d`、Lab10 S2 `8f8deba`、Lab11 S3 `2eadc63`、S4 `ac90840`、XSim plusarg 修正 `d597675`
- Vivado：2025.2
- 两个 full-run 均 PASS，功能点各 94/94，golden trace 各比较 111,625 条记录、有效写回 111,583 条。
- S5 WDB/WCFG/CSV 审计 PASS。WDB 留在本机 `results/`，未提交；WCFG 与 CSV 已提交。

## 核心运行

以下命令在仓库根目录的 Windows PowerShell 执行。Lab10/Lab11 full-run 串行完成：

```powershell
& .\scripts\verify_bus.ps1 -Case lab10 -Suite full -CaptureWaveform -RunId 's5-full-capture-lab10-retry1-20261117'
& .\scripts\verify_bus.ps1 -Case lab11 -Suite full -CaptureWaveform -RunId 's5-full-capture-lab11-fix1-20261117'
& .\scripts\build_bus_evidence.ps1 -Case lab10 -RunId 's5-full-capture-lab10-retry1-20261117' -Attempt 3
& .\scripts\build_bus_evidence.ps1 -Case lab11 -RunId 's5-full-capture-lab11-fix1-20261117' -Attempt 1
```

| 实验/Run ID | 状态 | 功能点 | Trace | 事务结果 | WDB（本机相对路径） | SHA-256 |
| --- | --- | ---: | ---: | --- | --- | --- |
| Lab10 `s5-full-capture-lab10-retry1-20261117` | PASS | 94/94 | 111,625/111,625 | IF 172,457/172,457；Load 4,618/4,618；Store 3,753/3,753；duplicate Store 0；stale drop 128 | `results/lab10_lab11/lab10/s5-full-capture-lab10-retry1-20261117/wave-full.wdb` (555,155,143 B) | `449BF0E1FA8BFBCF267822847365E3080237D043BA774AE1F27E1B6F6C79320D` |
| Lab11 `s5-full-capture-lab11-fix1-20261117` | PASS | 94/94 | 111,625/111,625 | AR/R 177,511/177,511；AW/W/B 各 3,753；Load 4,618/4,618；Store 3,753/3,753；duplicate Store 0；protocol fault 0；stale drop 693 | `results/lab10_lab11/lab11/s5-full-capture-lab11-fix1-20261117/wave-full.wdb` (981,404,172 B) | `0D9B9238AA5BE51B92CD6F876FC748CC5B5205D94D81169EA426B4E28BC25A81` |

Full-run 的输入 COE/MIF/trace 哈希以及源提交、dirty diff 哈希记录在 `data/evidence_index.csv`、各 Run 的 `input_manifest.csv` 与 `result.txt`。Lab10 run source commit 为 `d597675`、dirty diff SHA-256 为 `10342a76eb5f32df37a2e76f28d61e313e4dbd0b24e98bc97251674f88c45b6f`；Lab11 source commit 为 `eca3023`、dirty diff SHA-256 为 `4f8b25e16963bc32081af7d0332c948941b0f90930e6436ce6679bed71541f3f`。

## Directed 与历史修复记录

- Lab10 directed：`results/lab10_lab11/lab10/s4-directed-authorized-lab10-20261117/`，PASS。命令：`& .\scripts\verify_bus.ps1 -Case lab10 -Suite directed -RunId 's4-directed-authorized-lab10-20261117'`。
- Lab11 directed：`results/lab10_lab11/lab11/s4-directed-authorized-lab11-20261117/`，PASS。命令：`& .\scripts\verify_bus.ps1 -Case lab11 -Suite directed -RunId 's4-directed-authorized-lab11-20261117'`。
- 较早的 Lab10 full Run `s5-full-capture-lab10-20261117` 保留为 `ENVIRONMENT_ERROR`：XSim trace plusarg 使用了双连字符，修为 `-testplusarg` 后新 Run PASS。
- 较早的 Lab11 full Run `s5-full-capture-lab11-20261117` 保留为 `ENVIRONMENT_ERROR`：testbench telemetry 沿用 Lab10 的层级名，展开时找不到 `soc_lite.cpu_*`；改为 AXI 工程真实的 `soc_lite.u_cpu.*` 层级后，新 Run PASS。
- 早期两次 `s4-directed-telemetry-*` 结果也保留为 `ENVIRONMENT_ERROR`。入口随后加强了 `result.txt`、`simulate.log` 与 PASS 标记核验，避免仅因 Vivado 返回码 0 就误报通过。
- Lab10 WCFG 初次尝试的失败日志保留在 full-run 的 `wave-validation/`、`wave-validation-v2/`；完整有效版本用 `-v3.wcfg`。Lab11 五份 WCFG 均在第一次成功，路径、信号与 run 均由 Vivado 校验。

## 最终文件与手工截图

- 证据索引：[`data/evidence_index.csv`](../data/evidence_index.csv)
- 事务摘要：[`data/transaction-summary.csv`](../data/transaction-summary.csv)
- 波形采集交接：[`data/wave-capture-log.csv`](../data/wave-capture-log.csv)
- WDB/WCFG 验证：[`data/waveform_validation.csv`](../data/waveform_validation.csv)
- 逐图查找值、仿真时间锚点与 WCFG：[`waveform-capture-handoff.md`](waveform-capture-handoff.md)

`proof_status=PENDING_CAPTURE`、`observed` 与 `time_start_ns/time_end_ns` 空白是有意保留：测试台日志提供真实搜索锚点，用户需在 Wave 中读出显示值并保存对应 PNG 后，才改为 `CAPTURED_VERIFIED`。方案明确由用户手工完成截图；当前无需重写波形配置。

本次不推送。全量 XPR、WDB、Vivado 编译目录和失败日志都留在本机结果目录；Lab3 XPR 的用户改动仍未暂存或提交。
