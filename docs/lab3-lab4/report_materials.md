# 实验报告素材（按最终实测更新）

> 可直接引用的最终统计、指令/trace 哈希、日志 ID 和完整命令见 [`verification-final.md`](verification-final.md)。下面内容按本轮实测更新；波形截图和上板情况单独标为未完成。

## 实验目的

在既有 MIPS 五级流水线 CPU 上处理 RAW 数据相关，先以阻塞保证消费者读取正确值，再增加旁路，在数据已准备好时减少不必要的停顿。以 Lab3 验证基础指令行为，以 Lab4 验证紧凑相关指令序列，并用独立参考结果检查写回轨迹。

## 实验环境

- 工具：Vivado 2025.2，XSim；工程器件 `xc7a200tfbg676-2`。
- 当前工程：`lab/lab3/CPU_CDE/mycpu_verify/run_vivado/mycpu_prj1/mycpu_prj1.xpr`。
- 目标设计顶层：`soc_lite_top`；仿真顶层：`tb_top`。
- Vivado 预检结果：工程、源文件集及 `clk_pll`、`data_ram`、`inst_ram` IP 检查通过。

## 实现方法

ID 阶段辨认指令实际使用的源寄存器，并检测 EX、MEM、WB 中有效的写回生产者。纯阻塞配置在相关值写回前保持 ID；前递配置优先选择最新且数据就绪的 EX、MEM、WB 结果，仅对未就绪的 load 保留停顿。对 `$zero` 不检测真实 RAW，也不写回。

Lab3 的参考轨迹来自 `lab/lab3/CPU_CDE/cpu132_gettrace/golden_trace.txt`。Lab4 已由隔离的 `cpu132_gettrace` 参考 CPU 使用 Lab4 COE/MIF 独立生成 golden trace；Lab4 阻塞和前递测试均使用相同映像与该 trace。定向程序也由独立 CPU132 生成自己的参考 trace。

## 已执行步骤与真实结果

1. Vivado 项目预检通过，`clk_pll`、`inst_ram`、`data_ram` 均为 `Up-to-date`。
2. 复核 GCC 诊断后，确认 Xelab 默认实际调用 Vivado 内置 GCC 6.2.0。Codex 受限 PowerShell 的 Windows token 是 AppContainer，在该上下文启动 GCC 会返回 Win32 623，即使隔离 PATH 也无法启动；普通 PowerShell（非 AppContainer）中 GCC 可运行 `--version`，并能以相同参数编译 XSim 生成的 C 文件。仿真脚本保留 Vivado 默认编译器环境；目前没有锁定具体冲突 DLL。`verify.ps1` 已加入 AppContainer 预检，避免产生无效的 XSim 失败记录。
3. Lab3 forwarding 完整验收通过 23 个功能点：172,599 周期、0 stall。
4. Lab4 CPU132 参考运行生成 44,071 条、1,057,704 字节独立 trace；阻塞和前递各 23 个功能点通过。同一映像下阻塞为 130,891 周期 / 16,364 stall，前递为 114,577 周期 / 50 stall，周期下降 12.46%。
5. 独立手工编码短程序并由 CPU132 生成预期 trace；blocking 和 forwarding 均通过，分别为 98/29 和 72/3 周期/stall。用例包括 ALU 相关、最近生产者优先、load-use、load/ALU→store、branch delay slot、JR、`$zero` 和气泡。
6. 修正 testbench 统计口径后，前递、store、branch、JR 和优先级计数只在 `ds_to_es_valid && es_allowin` 的真实发射周期增加。Lab4 forwarding 的 EX/MEM/WB 为 4,505/4,818/1,032，定向 forwarding 为 6/5/2；功能点、trace、周期和 stall 不变。
7. `HAZARD_ZERO_DEST_WRITES` 包含 NOP 和填充 NOP；独立 WB 断言的实际 `$zero` 写回尝试为 0，五轮验收均通过该断言。

## 当前可复现命令

在 `C:\Users\lenovo\Desktop\Projects\FPGA`（仓库根目录）打开 PowerShell：

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\lab\scripts\verify.ps1 -Case lab3 -PipelineMode forwarding
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\lab\scripts\verify.ps1 -Case lab4 -PipelineMode blocking -ReferenceTrace .\lab\lab4\func_lab4\obj\golden_trace.txt
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\lab\scripts\verify.ps1 -Case lab4 -PipelineMode forwarding -ReferenceTrace .\lab\lab4\func_lab4\obj\golden_trace.txt
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\lab\scripts\verify.ps1 -Case lab4 -PipelineMode blocking -ReferenceTrace .\lab\results\lab3_lab4\hazard-directed\golden_trace.txt -InstMif .\lab\results\lab3_lab4\hazard-directed\image\hazard_inst_ram.mif -HazardDirected
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\lab\scripts\verify.ps1 -Case lab4 -PipelineMode forwarding -ReferenceTrace .\lab\results\lab3_lab4\hazard-directed\golden_trace.txt -InstMif .\lab\results\lab3_lab4\hazard-directed\image\hazard_inst_ram.mif -HazardDirected -CaptureWaveform
```

若需重新生成定向测试映像，先运行 `python .\lab\scripts\build_hazard_directed_image.py`。若 PowerShell 当前目录已经是 `C:\Users\lenovo\Desktop\Projects\FPGA\lab`，以上命令中的 `-File .\lab\scripts\verify.ps1` 改为 `-File .\scripts\verify.ps1`，参考文件路径相应去掉前缀 `lab\`。

每轮结果和完整 Vivado/XSim 日志保存在 `lab/results/lab3_lab4/<run-id>/`。最终 Lab3、Lab4 和定向用例的结果 ID、哈希、计数及原始日志入口见 [`verification-final.md`](verification-final.md)。

## 波形证据与待取得证据

- 已保存 65-word 定向 forwarding 实测 WDB：[`lab4-20261022T041931Z/hazard-directed-forwarding.wdb`](../../results/lab3_lab4/lab4-20261022T041931Z/hazard-directed-forwarding.wdb)，大小 336,746 字节，SHA-256 `5447B32478FE7896D9399AB5AD7042EE21C437068B209BF218CA01616263DB81`。该轮 `STATUS=PASS`，72 周期、3 stall，记录 `/tb_top` 全层次波形。
- 实验功能验收和可复查波形数据库已完成。带标注的 XSim GUI 截图仍需人工从该 WDB 导出；FPGA 上板验证也未执行。截图步骤和 PC 窗口见 [`figures/README.md`](figures/README.md)。

## 结论写作边界

可报告：Lab3、Lab4 及定向冒险程序在 Vivado 2025.2 / XSim 中通过独立 trace 验收；Lab4 前递版相较相同 ROM 的阻塞版减少 16,314 周期（12.46%），仍保留 50 个 load-use 停顿周期；定向 forwarding WDB 已保存。带标注的 GUI 截图和 FPGA 上板仍应按未完成表述。
