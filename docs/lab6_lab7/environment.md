# Lab6/Lab7 环境启动记录

## Vivado GUI

1. 启动 Vivado 2025.2，打开 `lab3/CPU_CDE/mycpu_verify/run_vivado/mycpu_prj1/mycpu_prj1.xpr`。
2. 选择 **Run Simulation → Run Behavioral Simulation**。
3. 确认仿真顶层为 `tb_top`，然后点击 **Run All**，等待 testbench 自行结束。

Lab3/Lab4 映像更新和 reference trace 流程见 [`Lab3_Lab4_流水线冲突实验指南.md`](../lab3-lab4/Lab3_Lab4_流水线冲突实验指南.md)。

## PowerShell 回归

在 `C:\Users\lenovo\Desktop\Projects\FPGA` 打开 PowerShell：

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\lab\scripts\verify.ps1 -Case lab3 -PipelineMode forwarding
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\lab\scripts\verify.ps1 -Case lab4 -PipelineMode forwarding -ReferenceTrace .\lab\lab4\func_lab4\obj\golden_trace.txt
```

不要在 PowerShell 里直接执行 `vivado.bat`；回归脚本会通过 `cmd.exe` 启动 Vivado。

## 当前复核结果

2026-10-21 使用 Vivado 2025.2 运行 Lab3 forwarding：23/23 功能点通过、172599 周期、0 stall，独立 trace 匹配。日志：[`lab3-20261021T131349Z`](../../results/lab3_lab4/lab3-20261021T131349Z/)。
