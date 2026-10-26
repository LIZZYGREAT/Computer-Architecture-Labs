# Vivado 仿真环境与入口

## 工程

Lab3–Lab7 共用唯一 Vivado 工程：`lab3/CPU_CDE/mycpu_verify/run_vivado/mycpu_prj1/mycpu_prj1.xpr`。目标器件为 `xc7a200tfbg676-2`，设计顶层 `soc_lite_top`，仿真顶层 `tb_top`。脚本入口为 `scripts/verify.ps1`；支持 Lab3、Lab4、Lab6、Lab7、blocking/forwarding、参考 trace、定向映像、preflight 与 WDB 捕获。

## PowerShell 回归

从 `C:\Users\lenovo\Desktop\Projects\FPGA\lab`（本实验仓库根目录）打开**普通 Windows PowerShell**运行：

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1 -Case lab3 -PipelineMode forwarding
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1 -Case lab4 -PipelineMode forwarding -ReferenceTrace .\lab4\func_lab4\obj\golden_trace.txt
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1 -Case lab6 -PipelineMode forwarding
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1 -Case lab7 -PipelineMode forwarding
```

Lab4 必须传入与 Lab4 ROM 对应的独立 trace。Lab6/Lab7 默认使用已生成的 golden trace；首次运行或更新课程映像后，可用 `scripts/generate_reference_trace.ps1 -Case lab6|lab7` 重新生成。通用命令模板和 `-VivadoBin`、`-PreflightOnly`、`-CaptureWaveform` 等选项见 [`../../README.md`](../../README.md)。

不要从 Codex 的 AppContainer 受限 PowerShell 启动 Vivado。`verify.ps1` 会检测当前 token：`WINDOWS_APPCONTAINER=True` 时在启动 Vivado 前返回 `ENVIRONMENT_ERROR`；`False` 时正常进行 Vivado 预检和仿真。该检查避免 GCC 子进程限制被误报为 DUT 功能故障。事故复查见 [`../lab3-lab4/gcc-startup-incident.md`](../lab3-lab4/gcc-startup-incident.md)。

Vivado GUI 可打开上述工程用于查看设计和 WDB；默认 Run All 使用工程当前仿真属性，不替代针对 Lab4/Lab6/Lab7 指定镜像与 trace 的自动验收脚本。

## 最新复核结果

- Lab3 forwarding：23/23，172,599 周期，0 stall；trace 44,071/44,071；[`lab3-20261026T162836Z`](../../results/lab3_lab4/lab3-20261026T162836Z/)。
- Lab4 forwarding：23/23，114,577 周期，50 stalls；trace 44,071/44,071；[`lab4-20261026T163305Z`](../../results/lab3_lab4/lab4-20261026T163305Z/)。
- Lab6 forwarding：42/42，109,375 周期，89 stalls；trace 66,612/66,612；[`lab6-20261026T163659Z`](../../results/lab6_lab7/lab6-20261026T163659Z/)。
- Lab7 forwarding：68/68，166,226 周期，926 stalls；trace 100,732/100,732；[`lab7-20261026T164130Z`](../../results/lab6_lab7/lab7-20261026T164130Z/)。
- 新指令前递定向：trace 41/41，新增前递计数 store base/data/branch/jalr = 3/2/6/1；[`lab7-20261026T170957Z`](../../results/lab6_lab7/lab7-20261026T170957Z/)。
- HI/LO 单元 testbench：PASS，接受/提交计数 3/4/6；[`hilo-unit-20261026T164656Z`](../../results/lab6_lab7/hilo-unit-20261026T164656Z/)。

上述仿真均未捕获波形。真实 Vivado WDB/PNG 的人工取证步骤见 [`waveforms.md`](waveforms.md)；Lab3/Lab4 完整结果矩阵见 [`Lab3/Lab4 verification`](../lab3-lab4/verification-final.md)，Lab6/Lab7 哈希和细项见 [`Lab6/Lab7 verification`](verification.md)。
