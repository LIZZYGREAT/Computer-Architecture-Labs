# 实验运行与结果管理

## 完成实验后的证据准备

实验结束并取得结果后，按 [`docs/workflow.md`](docs/workflow.md) 准备数据、Python 图表、Vivado WDB/WCFG 和报告素材。默认由用户最后在 Vivado 打开匹配的 WDB/WCFG 并截图。

## 如何运行

从本目录（`lab` 仓库根目录）打开**普通 Windows PowerShell**。`-Case` 可选 `lab3`、`lab4`、`lab6`、`lab7`；`-PipelineMode` 可选 `blocking` 或 `forwarding`。按要验收的实验运行对应命令：

```powershell
.\scripts\verify.ps1 -Case lab3 -PipelineMode forwarding
.\scripts\verify.ps1 -Case lab4 -PipelineMode forwarding -ReferenceTrace .\lab4\func_lab4\obj\golden_trace.txt
.\scripts\verify.ps1 -Case lab6 -PipelineMode forwarding
.\scripts\verify.ps1 -Case lab7 -PipelineMode forwarding
```

Vivado 默认安装在 `D:\Verilog\2025.2\Vivado\bin`。安装位置不同时加 `-VivadoBin '实际的Vivado\bin路径'`。Lab4 首次运行或更新指令映像后，先运行 `.\scripts\generate_reference_trace.ps1 -Case lab4`；其他实验需要重新生成参考轨迹时，将 `-Case` 设为对应实验。定向测试可按需增加 `-HazardDirected`、`-InstMif`、`-ReferenceTrace`；需要波形时增加 `-CaptureWaveform`；只检查工程/IP 时增加 `-PreflightOnly`。

请使用普通 Windows PowerShell。若运行结果提示 `WINDOWS_APPCONTAINER=True` 或 `ENVIRONMENT_ERROR`，请在普通 Windows PowerShell 中重新运行。每轮结果目录中的 `result.txt` 必须显示 `STATUS=PASS` 才表示该轮验收通过。

## 结果保留与清理

每轮运行会在 `results/<实验组>/<时间戳>/` 下生成结果。清理或提交前先检查 Git 状态和证据引用。保留报告、复查、复现和 Vivado 截图所需的 `result.txt`、日志、source manifest、映像、golden trace、WDB/WCFG 与波形文件；默认不批量清理结果目录。

只有在用户明确要求清理，或已确认某个临时文件无需保留且不被报告/采集配置引用时，才删除该具体文件。移除截图时只移除指定图片，不删除对应的 `.wcfg`、`.wdb` 或数据记录。不要直接执行 `git add results/`；提交前逐项检查结果目录，只添加最终有用且会在报告中引用或能支持验收结论的文件。
