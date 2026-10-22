# Lab6 / Lab7 验收记录（2026-10-22）

当前结果只按 `result.txt` 中的 `STATUS` 判定。Lab3/Lab4 最终验收和 GCC 执行上下文说明见 [`../lab3-lab4/verification-final.md`](../lab3-lab4/verification-final.md) 与 [`../lab3-lab4/gcc-startup-incident.md`](../lab3-lab4/gcc-startup-incident.md)。

## 当前可报告结果

| 用例 | 结果目录 | 结果 |
|---|---|---|
| Lab6 forwarding | [`lab6-20261022T051800Z`](../../results/lab6_lab7/lab6-20261022T051800Z/) | PASS，42/42，109,375 cycles，89 stalls；EX/MEM/WB 前递 35,013/8,320/12,007；零寄存器写回尝试 0 |
| Lab7 forwarding | [`lab7-20261022T035619Z`](../../results/lab6_lab7/lab7-20261022T035619Z/) | PASS，68/68，166,226 cycles，926 stalls；EX/MEM/WB 前递 49,970/12,229/15,454；零寄存器写回尝试 0 |
| Lab7 独立 CPU132 reference | [`reference-lab7-20261021T134251Z`](../../results/lab6_lab7/reference-lab7-20261021T134251Z/) | PASS，68/68；100,732 条 trace 记录 |
| Lab6 独立 CPU132 reference | [`reference-lab6-20261021T133931Z`](../../results/lab6_lab7/reference-lab6-20261021T133931Z/) | PASS，42/42；66,612 条 trace 记录 |
| Lab6 S2 累计 DUT 历史轮 | [`lab6-20261021T141122Z`](../../results/lab6_lab7/lab6-20261021T141122Z/) | 34/42 后在当时尚未实现的 HI/LO `mflo` 处 FAIL；这是 S2 阶段记录，不是当前完整 Lab6 通过结果 |

Lab6/Lab7 golden trace 分别保存在 [`golden/lab6`](../../results/lab6_lab7/golden/lab6/golden_trace.txt) 和 [`golden/lab7`](../../results/lab6_lab7/golden/lab7/golden_trace.txt)。Lab6 算术逻辑定向 DUT 结果及映像位于 [`lab3-20261021T140840Z`](../../results/lab3_lab4/lab3-20261021T140840Z/) 与 [`directed/alu`](../../results/lab6_lab7/directed/alu/)；该定向 DUT 通过，73 周期、1 次 load-use 停顿、EX/MEM/WB 前递 7/6/3。

当前 RTL 的 Lab6 累计 forwarding 运行通过 42 个功能点，Lab7 累计 forwarding 运行通过 68 个功能点，均与各自独立 trace 匹配。`lab6-20261021T141122Z` 的 34/42 是 S2 阶段旧 RTL 的历史结果，不代表当前 Lab6 状态。两轮最新累计验收均未启用 `-CaptureWaveform`，故没有对应的 Lab6/Lab7 WDB 或截图；Lab3/Lab4 定向 forwarding WDB 不是 Lab6/Lab7 波形证据。

## 参考轨迹与镜像

- Lab6 trace：66,612 条记录，SHA-256 `FB92799CBA4C42B1ECB729DD6659DADC63195B07E16C3FD6E25B2A6986850CA1`；MIF SHA-256 `E446C87CD740A1B6C36D10F2CBCE3A29FFB4733AAD37096D852D09F7D438AF46`。
- Lab7 trace：100,732 条记录，SHA-256 `23ADD75B2BADFDABF98B1863A89896DFC60B4B351CC49321B22BEB22035991C3`；MIF SHA-256 `4BCBB028ABAFC257BD1C3E670A2B5324298126F0B7500CD39FE6531EC223068C`。
- Lab6 与 Lab7 最终 DUT 结果均记录 trace 与 MIF 哈希匹配，Xvlog/Xvhdl/Xelab/XSim 全阶段日志完整保存在各自结果目录。

## GCC / XSim 故障复查

早期在 Codex 的 AppContainer PowerShell 中，Xelab 编译 `xsim_5.c` 报 `XSIM 43-3409`，XSim 未启动。重测确认：Codex PowerShell token 的 `TokenIsAppContainer=1`；该上下文用正常或隔离 PATH 启动 Vivado GCC 6.2.0 会失败。普通 Windows PowerShell token 为 `TokenIsAppContainer=0`；GCC `--version` 与 XSim C 编译通过，Lab3/Lab4/Lab7 完整仿真也通过。

`verify.ps1` 已加入 AppContainer 预检和 `host-context.txt` 记录。处于 AppContainer 时会在启动 Vivado 前返回 `ENVIRONMENT_ERROR`，并标记测试点和周期未运行。精简命令、环境、Xelab 与 DLL 错误证据见 [`gcc-diagnostic-20261022`](../../results/lab3_lab4/gcc-diagnostic-20261022/)。未替换 DLL、未重装 Vivado、未修改 Xelab 默认 GCC 配置。

## S2 算术逻辑定向用例

独立 65-word ROM 覆盖立即数边界、signed/unsigned 比较、`sllv/srav/srlv`、EX/MEM/WB 前递和 load-use。定向 DUT 73 周期、1 次停顿，trace 匹配。实现与构建方法见 [`implementation.md`](implementation.md)。

## 保留记录范围

`results` 中保留最终 PASS、必要的阶段日志、稳定 golden trace、定向输入映像和 GCC 根因对照。被后续成功轮次替代的重复失败尝试、Vivado reference 工作副本、IP probe 输出与重复日志已清理；reference CPU 源码仍在 `lab3/CPU_CDE/cpu132_gettrace/`，可按脚本重新生成。
