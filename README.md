# 实验运行与结果管理

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

每轮运行会在 `results/<实验组>/<时间戳>/` 下生成结果。提交前只保留最终验收、报告引用、复查或复现所必需的文件：通过轮次的 `result.txt`、原始 Vivado/Xvlog/Xelab/XSim 阶段日志、source manifest、映像一致性报告、必要的 golden trace、定向输入映像，以及报告确实引用的波形文件。

后续通过轮次已替代的失败重试、重复日志、`.jou`/`.cmd` 启动副本、拼接日志、空 console 文件、重复 ROM 暂存、Vivado 临时工程、probe 输出和其他无用文件应及时清理。只有用于说明根因的失败证据才保留一份，并在报告中注明。不要直接执行 `git add results/`；提交前逐项检查结果目录，只添加最终有用且会在报告中引用或能支持验收结论的文件。
