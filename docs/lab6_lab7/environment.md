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

## 修订后复核结果（2026-10-27）

- Lab3 forwarding：23/23，172,599 周期；[`lab3-20261027T025645Z`](../../results/lab3_lab4/lab3-20261027T025645Z/)。
- Lab4 forwarding：23/23，114,577 周期；[`lab4-20261027T030155Z`](../../results/lab3_lab4/lab4-20261027T030155Z/)。
- Lab6 forwarding：42/42，109,439 周期，trace 66,612/66,612；[`lab6-20261027T030621Z`](../../results/lab6_lab7/lab6-20261027T030621Z/)。
- Lab7 forwarding：68/68，166,330 周期，trace 100,732/100,732；[`lab7-20261027T031040Z`](../../results/lab6_lab7/lab7-20261027T031040Z/)。
- 源码重建后的 reference / DUT 配对回归：Lab6 42/42、Lab7 68/68；结果序号与哈希见 [`verification.md`](verification.md)。
- HI/LO 双路握手：PASS，`hilo-unit-20261027T032000Z`；DIV 等待期间分支：PASS，`lab6-20261027T031906Z`。
- P2-A 连续依赖定向 reference / DUT：PASS，25/25 trace，`reference-lab7-20261027T025022Z` → `lab7-20261027T025231Z`。

以上结果均未捕获波形。真实 Vivado WDB/PNG 的人工取证步骤见 [`waveforms.md`](waveforms.md)；Lab3/Lab4 完整结果矩阵见 [`Lab3/Lab4 verification`](../lab3-lab4/verification-final.md)，Lab6/Lab7 哈希和核验序号见 [`Lab6/Lab7 verification`](verification.md)。

2026-10-28 已另外完成 Lab6/Lab7 `-CaptureWaveform` 累计回归；两个 WDB 的准确路径、哈希和 PASS 指标见 [`waveforms.md`](waveforms.md)。
