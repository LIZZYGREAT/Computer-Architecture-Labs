# Lab6 / Lab7 验收记录（2026-10-27）

当前结果只按 `result.txt` 中的 `STATUS` 判定。以下 10/26 UTC 运行 ID 对应本次完整复核；Lab3/Lab4 最终验收和 GCC 执行上下文说明见 [`../lab3-lab4/verification-final.md`](../lab3-lab4/verification-final.md) 与 [`../lab3-lab4/gcc-startup-incident.md`](../lab3-lab4/gcc-startup-incident.md)。

## 当前可报告结果

| 用例 | 结果目录 | 结果 |
|---|---|---|
| Lab3 forwarding 回归 | [`lab3-20261026T162836Z`](../../results/lab3_lab4/lab3-20261026T162836Z/) | PASS，23/23，172,599 cycles，0 stalls；44,071/44,071 trace 写回匹配 |
| Lab4 forwarding 回归 | [`lab4-20261026T163305Z`](../../results/lab3_lab4/lab4-20261026T163305Z/) | PASS，23/23，114,577 cycles，50 stalls；EX/MEM/WB 前递 4,505/4,818/1,032；44,071/44,071 trace 写回匹配 |
| Lab6 forwarding | [`lab6-20261026T163659Z`](../../results/lab6_lab7/lab6-20261026T163659Z/) | PASS，42/42，109,375 cycles，89 stalls；EX/MEM/WB 前递 35,013/8,320/12,007；66,612/66,612 trace 写回匹配；零寄存器写回尝试 0 |
| Lab7 forwarding | [`lab7-20261026T164130Z`](../../results/lab6_lab7/lab7-20261026T164130Z/) | PASS，68/68，166,226 cycles，926 stalls；EX/MEM/WB 前递 49,970/12,229/15,454；100,732/100,732 trace 写回匹配；零寄存器写回尝试 0 |
| Lab7 新指令前递定向用例 | [`lab7-20261026T170957Z`](../../results/lab6_lab7/lab7-20261026T170957Z/) | PASS，64 cycles，1 stall；trace 41/41；新增 store base/data/branch/jalr 计数 3/2/6/1；运行源提交为当前 `7d8a3b5` |
| HI/LO 单元 testbench | [`hilo-unit-20261026T164656Z`](../../results/lab6_lab7/hilo-unit-20261026T164656Z/) | PASS；乘法/除法接受及完成提交计数 3/4/6，覆盖 signed/unsigned 运算、完成保持/消费、MTHI/MTLO、复位取消 |
| 除法期间分支等待定向用例 | [`directed/hilo-stall-branch`](../../results/lab6_lab7/directed/hilo-stall-branch/)；[CPU 仿真结果](../../results/lab3_lab4/lab3-20261022T065139Z/) | PASS；参考 trace 与 DUT 全匹配：delay slot `$3=0x55`，fall-through `$4` 未写回，`mflo/mfhi` 得到 `-4/-3`，分支目标 `$7=0x66` |
| Lab7 独立 CPU132 reference | [`reference-lab7-20261021T134251Z`](../../results/lab6_lab7/reference-lab7-20261021T134251Z/) | PASS，68/68；100,732 条 trace 记录 |
| Lab6 独立 CPU132 reference | [`reference-lab6-20261021T133931Z`](../../results/lab6_lab7/reference-lab6-20261021T133931Z/) | PASS，42/42；66,612 条 trace 记录 |
| Lab6 S2 累计 DUT 历史轮 | [`lab6-20261021T141122Z`](../../results/lab6_lab7/lab6-20261021T141122Z/) | 34/42 后在当时尚未实现的 HI/LO `mflo` 处 FAIL；这是 S2 阶段记录，不是当前完整 Lab6 通过结果 |

Lab6/Lab7 golden trace 分别保存在 [`golden/lab6`](../../results/lab6_lab7/golden/lab6/golden_trace.txt) 和 [`golden/lab7`](../../results/lab6_lab7/golden/lab7/golden_trace.txt)。Lab6 算术逻辑定向 DUT 结果及映像位于 [`lab3-20261021T140840Z`](../../results/lab3_lab4/lab3-20261021T140840Z/) 与 [`directed/alu`](../../results/lab6_lab7/directed/alu/)；该定向 DUT 通过，73 周期、1 次 load-use 停顿、EX/MEM/WB 前递 7/6/3。Lab7 新指令前递映像与 listing 位于 [`directed/extended-forwarding`](../../results/lab6_lab7/directed/extended-forwarding/)。

当前 RTL 的 Lab6 累计 forwarding 运行通过 42 个功能点，Lab7 累计 forwarding 运行通过 68 个功能点，均与独立 CPU132 trace 全匹配；Lab3/Lab4 23/23 基线、HI/LO 模块级 testbench、除法期间分支等待及新增指令前递定向用例也通过。`lab6-20261021T141122Z` 的 34/42 是 S2 阶段旧 RTL 的历史结果，不代表当前 Lab6 状态。以上结果均未启用波形捕获；本轮按用户要求只修订波形取证指南，不生成 WDB 或截图。

旧 `FORWARD_EX/MEM/WB_USES` 与新增专项计数均只在 `ds_instruction_issued`（ID 指令被 EX 接收）时采样；常规前递每级只要 `rs` 或 `rt` 任一操作数使用该级就记一次，因此它是发射指令周期/前递级别使用次数，不是源操作数总数或 stall 周期。新增 `HAZARD_NEW_STORE_BASE_FORWARDS`、`HAZARD_NEW_STORE_DATA_FORWARDS` 分别统计 `sb/sh/swl/swr` 的基址和写数据前递；同一条指令若两操作数均前递，可同时增加两个值。`HAZARD_NEW_BRANCH_FORWARDS` 覆盖六种新增条件分支的 `rs` 前递；`HAZARD_JALR_FORWARDS` 覆盖 `jalr` 跳转目标 `rs` 前递。累计 Lab7 值为 112/0/1,229/28；定向映像值为 3/2/6/1。当前累计程序没有触发新增 store-data 前递，故其值为 0；定向程序已对该路径给出非零覆盖。

本轮累计回归命令：

```powershell
.\scripts\verify.ps1 -Case lab3 -PipelineMode forwarding
.\scripts\verify.ps1 -Case lab4 -PipelineMode forwarding -ReferenceTrace .\lab4\func_lab4\obj\golden_trace.txt
.\scripts\verify.ps1 -Case lab6 -PipelineMode forwarding -TimeoutSeconds 1800
.\scripts\verify.ps1 -Case lab7 -PipelineMode forwarding -TimeoutSeconds 1800
.\scripts\verify.ps1 -Case lab7 -PipelineMode forwarding -ReferenceTrace .\results\lab6_lab7\directed\extended-forwarding\golden_trace.txt -InstMif .\results\lab6_lab7\directed\extended-forwarding\image\lab7_extended_forwarding.mif -ExpectedPointOverride 0 -HazardDirected
```

除法后分支定向用例先用独立 CPU132 生成 trace，再以相同 MIF 运行 DUT；构建脚本为 `scripts/build_lab6_hilo_stall_branch_image.py`，详细输入、trace 和 CPU 结果见 [`directed/hilo-stall-branch`](../../results/lab6_lab7/directed/hilo-stall-branch/) 与上表链接。

## 参考轨迹与镜像

- Lab6 trace：66,612 条记录，SHA-256 `FB92799CBA4C42B1ECB729DD6659DADC63195B07E16C3FD6E25B2A6986850CA1`；当前课程 MIF SHA-256 `845D97935C29D651D1D73D906DC3E92DC5690C23F77920111A369D33C28E8F28`。
- Lab7 trace：100,732 条记录，SHA-256 `23ADD75B2BADFDABF98B1863A89896DFC60B4B351CC49321B22BEB22035991C3`；当前课程 MIF SHA-256 `8EBF314084B3B06BF40A9F4DF2B402E74BE5D1F705A75F7ADFC858868B9B75BE`。
- 新增指令定向 trace：41 条记录，SHA-256 `4E7557963DB8CB4CDDB99E3B0DEB3A46D5711F4C4E71A95EB1791BB3D65B1D49`；MIF SHA-256 `44E2B856BB12AB82295A7214C161D1616BE19E13AA35F625E9349B2B0A19E03C`。
- Lab6 与 Lab7 最终 DUT 结果均记录 trace 与 MIF 哈希匹配，Xvlog/Xvhdl/Xelab/XSim 全阶段日志完整保存在各自结果目录。

## GCC / XSim 故障复查

早期在 Codex 的 AppContainer PowerShell 中，Xelab 编译 `xsim_5.c` 报 `XSIM 43-3409`，XSim 未启动。重测确认：Codex PowerShell token 的 `TokenIsAppContainer=1`；该上下文用正常或隔离 PATH 启动 Vivado GCC 6.2.0 会失败。普通 Windows PowerShell token 为 `TokenIsAppContainer=0`；GCC `--version` 与 XSim C 编译通过，Lab3/Lab4/Lab7 完整仿真也通过。

`verify.ps1` 已加入 AppContainer 预检和 `host-context.txt` 记录。处于 AppContainer 时会在启动 Vivado 前返回 `ENVIRONMENT_ERROR`，并标记测试点和周期未运行。精简命令、环境、Xelab 与 DLL 错误证据见 [`gcc-diagnostic-20261022`](../../results/lab3_lab4/gcc-diagnostic-20261022/)。未替换 DLL、未重装 Vivado、未修改 Xelab 默认 GCC 配置。

另一次失败轮的 XSim 原因是 XSim 找不到自定义 `xsim-run.tcl`，随后停在交互提示符并超时。该脚本先前直接从结果目录执行，清理失败结果时可能被一并移除；现改为在 `scripts_only` 完成后（该步骤会重建仿真工作目录内容）于仿真工作目录生成并检查运行脚本，再将副本归档到结果目录。超时清理也会终止 Vivado 子进程树，避免遗留 XSim 持有失败日志。

## S2 算术逻辑定向用例

独立 65-word ROM 覆盖立即数边界、signed/unsigned 比较、`sllv/srav/srlv`、EX/MEM/WB 前递和 load-use。定向 DUT 73 周期、1 次停顿，trace 匹配。实现与构建方法见 [`implementation.md`](implementation.md)。

## 保留记录范围

`results` 中保留本轮最终 PASS、必要阶段日志、稳定 golden trace、定向输入映像和 GCC 根因对照。本轮失败的 AppContainer 预检及临时 reference 尝试没有作为验收依据；历史 S2 失败用于解释 34/42 旧状态。reference CPU 源码仍在 `lab3/CPU_CDE/cpu132_gettrace/`，可按脚本重新生成。
