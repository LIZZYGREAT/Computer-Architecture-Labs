# Lab3 / Lab4 验收记录（首轮历史）

> 本文件保留首次 GCC 诊断和未通过轮次的原始背景。**当前最终结果已全部更新于 [`verification-final.md`](verification-final.md)**；文中“当前失败”“尚未运行”等状态只表示其记录时间点，不代表最终验收状态。

## 最新验收摘要

- Lab3 forwarding：`STATUS=PASS`，23 个功能点，172,599 周期。
- Lab4 blocking：`STATUS=PASS`，23 个功能点，130,891 周期 / 16,364 stall。
- Lab4 forwarding：`STATUS=PASS`，23 个功能点，114,577 周期 / 50 stall；相比 blocking 减少 12.46%。
- 定向 load-use/store/branch/JR/优先级/`$zero` 用例在 blocking 与 forwarding 均 `STATUS=PASS`。
- GCC 6.2.0 可独立启动并完成 XSim 生成 C 源的原命令编译；移除脚本中的 GCC 覆盖后，Vivado 默认配置全流程通过。
- 波形截图仍待人工从 XSim GUI 实测保存；详细命令、trace 哈希、运行 ID、GCC 证据见 [`verification-final.md`](verification-final.md)。

## 环境与工程预检

- Vivado：2025.2 (64-bit)，Build 6299465，IP Build 6300035。
- 器件：`xc7a200tfbg676-2`；设计顶层 `soc_lite_top`；仿真顶层 `tb_top`。
- Lab3 工程：`lab/lab3/CPU_CDE/mycpu_verify/run_vivado/mycpu_prj1/mycpu_prj1.xpr`。
- `check_project.tcl` 预检通过：`sources_1`、`sim_1` 引用文件存在；`clk_pll`、`data_ram`、`inst_ram` 均为 `Up-to-date` 且未锁定。
- 仿真入口指定了 `D:\Verilog\2025.2\Vivado\tps\mingw\10.0.0\win64.o\nt\bin`（GCC 9.5.0），Vivado 生成的脚本标记 GCC 9.3.0；但 Xelab 详细日志显示实际执行的编译器是 Vivado 内置的 `D:\Verilog\2025.2\Vivado\tps\mingw\6.2.0\win64.o\nt\bin\gcc.exe`。因此，指定 GCC 路径没有改变 Xelab 实际调用的编译器。

## Lab3 前递模式

执行命令：

```powershell
.\lab\scripts\verify.ps1 -Case lab3
```

本轮 ID：`lab3-20261020T141542Z`。结果为 **`STATUS=ENVIRONMENT_ERROR`**。

- 预检：`PREFLIGHT=PASS`。
- Vivado 生成的 XSim 源码清单包含 `mycpu_tb.v`；Xvlog 成功分析 RTL、IP 仿真模型和 `tb_top`，未报告 HDL 语法错误。
- Xelab 已展开 CPU 与 testbench；详细日志记录了 GCC 6.2 的实际调用，随后报 `The system cannot execute the specified program.`，并出现 `ERROR: [XSIM 43-3409] Failed to compile generated C file xsim.dir/tb_top_behav/obj/xsim_2.c.` 和 `ERROR: [XSIM 43-3915] Encountered a fatal error.`。直接启动同一 GCC 6.2 可执行文件也报告 Windows“无效的系统 DLL 重定位”。现有证据指向 Vivado 自带编译器在当前 Windows 环境下无法启动；不是 RTL 已编译通过后才出现的 C 源码诊断。
- XSim 未启动；没有 trace 打开、测试点 PASS、最终 PASS、执行周期、stall 周期或前递激活计数。`PIPELINE_CYCLES=0` 等计数为未运行，不是实测零周期。
- Lab3 源 MIF 与 staged 仿真 MIF 的 SHA-256 相同：`D56AEDEB3064A1FF797EF332EABC35C84D3C222CFDA439FFBE9F162E1ED8B05E`。参考 trace SHA-256：`441D74893AD9AC7C8E40B92E10144639A3B8A700FE1290FDECBF4A8DEC60EFFA`。
- 原始记录：[本轮结果目录](../../results/lab3_lab4/lab3-20261020T141542Z/)，包含 `result.txt`、Vivado 日志、Xvlog/Xelab 日志、源清单和 `xelab-verbose-vivado.log` 中记录的实际 GCC 调用。

开发仿真入口时曾遇到 testbench 未进入自动生成的 XSim 清单，以及自定义 compile hook 引发第二个 Vivado 进程加载 Tcl 应用失败的问题。入口已调整为生成脚本后在主进程中补齐清单，再执行 XSim 阶段脚本。最终轮已越过该问题，失败点是 Xelab C 内核编译。

另有一轮编译器选择诊断记录：`lab3-20261020T142718Z` 尝试设置工程属性 `SIMULATOR.XSIM_GCC_INSTALL_DIR`，Vivado 2025.2 明确返回 `Invalid property name`，因此该轮在 HDL 分析前终止，不是仿真结果。当前 `run_behavioral_sim.tcl` 已移除这项无效设置；该轮结果目录保留用于说明诊断经过。

## Lab4

执行入口：

```powershell
.\lab\scripts\verify.ps1 -Case lab4
```

本轮 ID：`lab4-20261020T141923Z`。预检通过后返回 **`STATUS=ENVIRONMENT_ERROR`**：缺少与 Lab4 指令映像对应的独立参考 trace，因此脚本按设计拒绝启动仿真。没有运行 Lab4 阻塞版、前递版或性能比较。

- Lab4 ROM：`lab/lab4/func_lab4/obj/inst_ram.mif`，SHA-256 `FF50561C8F7E42B0D4576F989C5C5F99726DC46328CE714DEF65148619387EB6`。
- Lab4 COE：SHA-256 `C1EA1B459B0740F1196797CFBB6759A4C4B2B7C65A0566D1E1E1A3A31328F455`。
- 当前 `inst_ram.xci` 配置引用 Lab3 COE。脚本会在实际仿真启动前把选择的 MIF 拷贝到 XSim 工作目录；但由于 Lab4 trace 尚缺，当前没有声称 Lab4 ROM/trace 配对验证通过。
- 生成独立 Lab4 trace 后，使用相同 ROM 和判据分别执行：

```powershell
.\lab\scripts\verify.ps1 -Case lab4 -PipelineMode blocking -ReferenceTrace "C:\path\to\lab4-golden-trace.txt"
.\lab\scripts\verify.ps1 -Case lab4 -PipelineMode forwarding -ReferenceTrace "C:\path\to\lab4-golden-trace.txt"
```

## 验收矩阵

| 项目 | 结果 | 证据/缺口 |
|---|---|---|
| Vivado 工程与 IP 预检 | 通过 | 本轮 `preflight-vivado.log`、`ip_status.rpt`。 |
| RTL 与 testbench 的 Xvlog 分析 | 通过 | `xsim-xvlog.log` 中 `tb_top` 被分析。 |
| Xelab C 内核构建 | 环境错误 | `xsim-elaborate.log` 报 `XSIM 43-3409`。 |
| Lab3 完整功能与 trace | 未完成 | 仿真未进入 XSim。 |
| 纯阻塞 Lab4 | 未完成 | 缺独立 Lab4 trace，且 XSim 内核构建阻塞。 |
| 前递 Lab4 | 未完成 | 缺独立 Lab4 trace，且 XSim 内核构建阻塞。 |
| load-use/store/branch/JR 定向运行 | 未执行 | 仅静态审查，无运行证据。 |
| 前递减少周期 | 未测量 | 无可比较的两轮周期数据。 |
| 真实波形截图 | 未捕获 | 信号建议见 [`report_materials.md`](report_materials.md)。 |

## 后续排查

先修复 Vivado 安装中 GCC 6.2 无法启动的问题（或修复 Vivado/XSim 的编译器选择配置），再复跑 Lab3；单纯向入口指定 GCC 9.5 没有改变 Xelab 实际调用的 GCC 6.2。XSim 恢复后，为 Lab4 独立运行参考核生成 trace，再用同一 ROM 比较阻塞与前递。
