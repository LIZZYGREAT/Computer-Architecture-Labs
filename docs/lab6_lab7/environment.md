# Lab6/Lab7 环境启动记录

## Vivado GUI

1. 启动 Vivado 2025.2，打开 `lab3/CPU_CDE/mycpu_verify/run_vivado/mycpu_prj1/mycpu_prj1.xpr`。
2. 选择 **Run Simulation → Run Behavioral Simulation**。
3. 确认仿真顶层为 `tb_top`，然后点击 **Run All**，等待 testbench 自行结束。

Lab3/Lab4 映像更新和 reference trace 流程见 [`Lab3_Lab4_流水线冲突实验指南.md`](../lab3-lab4/Lab3_Lab4_流水线冲突实验指南.md)。

## PowerShell 回归

在 `C:\Users\lenovo\Desktop\Projects\FPGA` 打开 PowerShell。原有 Lab3/Lab4 回归：

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\lab\scripts\verify.ps1 -Case lab3 -PipelineMode forwarding
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\lab\scripts\verify.ps1 -Case lab4 -PipelineMode forwarding -ReferenceTrace .\lab\lab4\func_lab4\obj\golden_trace.txt
```

不要在 PowerShell 里直接执行 `vivado.bat`；回归脚本会通过 `cmd.exe` 启动 Vivado。

Lab6/Lab7 先生成独立 reference trace，再运行累计回归：

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\lab\scripts\generate_reference_trace.ps1 -Case lab6
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\lab\scripts\verify.ps1 -Case lab6 -PipelineMode forwarding
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\lab\scripts\generate_reference_trace.ps1 -Case lab7
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\lab\scripts\verify.ps1 -Case lab7 -PipelineMode forwarding
```

Lab6/Lab7 的 reference trace 已生成；DUT 累计回归需待对应指令 RTL 完成后执行。手动 GUI 的 `Run All` 用于默认 Lab3 基线；Lab4/Lab6/Lab7 请通过脚本传入正确映像、trace 和功能点数。

## 当前复核结果

2026-10-21 使用 Vivado 2025.2 运行 Lab3 forwarding：23/23 功能点通过、172599 周期、0 stall，独立 trace 匹配。日志：[`lab3-20261021T131349Z`](../../results/lab3_lab4/lab3-20261021T131349Z/)。S1 最新回归及 Lab6/Lab7 trace 记录见 [`verification.md`](verification.md)。
