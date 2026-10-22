# Lab6/Lab7 阶段验证记录

## S0 基线

- 环境：Vivado 2025.2，唯一 DUT 工程 `lab3/CPU_CDE/mycpu_verify/run_vivado/mycpu_prj1/mycpu_prj1.xpr`，PowerShell 启动命令见 [environment.md](environment.md)。
- Lab3 forwarding：23/23，172,599 周期，0 stall，reference trace 匹配；结果目录 `results/lab3_lab4/lab3-20261021T131349Z/`。
- S0 记录提交：`4c86c60`。

## S1 验证基础设施

### 变更

- 新增 `scripts/cases.json`，统一 Lab3/4/6/7 的 COE、MIF、reference trace、功能点数、仿真上限和结果目录。
- 扩展 `scripts/verify.ps1` 与 `scripts/run_behavioral_sim.tcl`：参数化案例、功能点数、运行时间、trace 和 ROM；结果检查实际通过点数、trace、仿真加载 MIF，并保留动态指标。
- 新增 `scripts/check_instruction_image.py`，解析 COE/MIF 并与 `inst_ram.xci` 深度逐项校验。
- 新增 `scripts/generate_reference_trace.ps1`，复制独立 CPU132 reference 工程到隔离目录，装入指定课程镜像并调用 `scripts/generate_reference_trace.tcl`。参考 CPU 源码和原始工程不改动；trace 由参考 CPU 生成，不来自 DUT。
- DUT RTL 和总线宽度没有改动。testbench 新增 `EXPECTED_POINTS` plusarg 及累计功能点数断言，以识别过早结束。
- `.gitignore` 屏蔽 Vivado 缓存和隔离 reference 工作副本，并保留本阶段验收日志与稳定 golden trace。
- S1 验证基础设施源码提交：`c6ef7b3`。

### 映像校验

四组 COE/MIF 的解析指令序列完全相同，均未超过 DUT XCI 的 262,144-word 深度。

| 案例 | 指令数 | COE/MIF 规范化序列 SHA-256 |
|---|---:|---|
| Lab3 | 181,011 | `1CF8606F91A9CCD9D083272EE86EF1FF1C73619583B524EEA47D6E498D2AF08D` |
| Lab4 | 123,367 | `4ABA5DF5799A2366F3A7715A8FA7FB3BC5B16EC928C31161FA56F1F72F97EC8E` |
| Lab6 | 102,959 | `88FDCD95DE9C0B0877115805A529F4F25C343FADC69CB026180A7F3661DAD74A` |
| Lab7 | 166,859 | `0B0C31343767D5CEC74E925BF7E153C5F70AD3CE66884D2E6CDCCB9632551899` |

### 执行与结果

以下 PowerShell 命令均从 `C:\Users\lenovo\Desktop\Projects\FPGA` 运行，Vivado 由脚本经 `cmd.exe` 启动。

| 命令 | 结果 | 耗时 | 证据 |
|---|---|---:|---|
| `powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\lab\scripts\verify.ps1 -Case lab3 -PipelineMode forwarding` | PASS，23/23，172,599 cycles，0 stalls，MIF 匹配 | 114 s | `results/lab3_lab4/lab3-20261021T134547Z/` |
| `powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\lab\scripts\verify.ps1 -Case lab4 -PipelineMode forwarding` | PASS，23/23，114,577 cycles，50 stalls，EX/MEM/WB 前递均有覆盖，MIF 匹配 | 108 s | `results/lab3_lab4/lab4-20261021T134852Z/` |
| `powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\lab\scripts\generate_reference_trace.ps1 -Case lab6` | PASS，独立 CPU132 42/42；compile/elaborate/simulate 均为 0 | 约 137 s | `results/lab6_lab7/reference-lab6-20261021T133931Z/` |
| `powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\lab\scripts\generate_reference_trace.ps1 -Case lab7` | PASS，独立 CPU132 68/68；compile/elaborate/simulate 均为 0 | 约 146 s | `results/lab6_lab7/reference-lab7-20261021T134251Z/` |

独立 trace：

- Lab6：66,612 条记录，SHA-256 `FB92799CBA4C42B1ECB729DD6659DADC63195B07E16C3FD6E25B2A6986850CA1`；[golden trace](../../results/lab6_lab7/golden/lab6/golden_trace.txt)。
- Lab7：100,732 条记录，SHA-256 `23ADD75B2BADFDABF98B1863A89896DFC60B4B351CC49321B22BEB22035991C3`；[golden trace](../../results/lab6_lab7/golden/lab7/golden_trace.txt)。

S1 验收已完成。Lab6/Lab7 DUT 累计回归尚未执行；需要先完成对应 RTL 阶段，不能把 reference CPU 通过视为 DUT 通过。当前唯一手动 GUI 入口和启动步骤见 [environment.md](environment.md)。

## 后续阶段记录

每个后续阶段在下方补充变更文件、接口影响、确切命令、PASS/FAIL、耗时、失败首因、日志目录及提交号。波形截图未实际导出前标记为待人工验收。

## S3–S5 当前验证状态（2026-10-22）

- Vivado 2025.2 工程预检：`.\scripts\verify.ps1 -Case lab7 -PreflightOnly`，PASS。设计顶层 `soc_lite_top`、仿真顶层 `tb_top`、五个 IP 均被识别为 Up-to-date；结果 `results/lab6_lab7/lab7-20261022T014113Z/`。
- Lab7 DUT 命令：`.\scripts\verify.ps1 -Case lab7 -PipelineMode forwarding -TimeoutSeconds 1800`。运行 `lab7-20261022T014242Z`，2026-10-22 01:43:53–01:47:14 UTC，耗时约 201.5 s，结果 `STATUS=ENVIRONMENT_ERROR`。
- 本次源代码 Xvlog 编译和 IP VHDL Xvhdl 分析完成；Xelab 完成静态 RTL 展开，随后在 `xsim.dir/tb_top_behav/obj/xsim_5.c` 生成的 C 文件编译时报 `XSIM 43-3409` 并退出。XSim 没有开始运行，因此 0 个功能点和 0 个周期是“未执行”，不是功能测试失败或通过；没有首个失败 opcode/PC。
- 输入一致性检查通过：课程 Lab7 trace SHA-256 `23ADD75B2BADFDABF98B1863A89896DFC60B4B351CC49321B22BEB22035991C3`；课程 MIF 与仿真暂存 MIF SHA-256 均为 `4BCBB028ABAFC257BD1C3E670A2B5324298126F0B7500CD39FE6531EC223068C`。实际日志、manifest、命令及 `result.txt` 在 `results/lab6_lab7/lab7-20261022T014242Z/`。
- HILO wrapper 的早期单元仿真曾通过基础乘除测试：`results/lab6_lab7/ip-probe/hilo-unit-vivado.log` 输出 `HILO_UNIT_TB_PASS mult_accepts=2 div_accepts=4`，覆盖当时测试台中的 signed/unsigned 乘除结果。该次运行早于当前 testbench（当前增加了请求/提交计数和除法中复位取消断言），所以只作为 wrapper 的历史基础证据，不代表当前完整单元验收通过。
- 当前 `hilo_unit_tb.v` 版本的重跑记录在 `results/lab6_lab7/ip-probe/hilo-unit-s3d-vivado.log`：Xvlog/Xvhdl 和静态展开通过，Xelab 在编译生成的 `xsim_3.c` 阶段以 `XSIM 43-3409` 退出，XSim 未启动。CPU 的 Lab3/Lab7 跑法也在相同阶段失败。已知独立诊断 `results/lab3_lab4/gcc-investigation-20261020T150000Z/isolated.log` 记录 Vivado 随附 GCC 无法启动（Windows“无效的系统 DLL 重定位”）；本次没有改写 GCC 路径或环境变量来绕过它。
- 本次 XPR 因 Vivado 启动仿真递增了 `WTXSimLaunchSim` 并移除了 `SimCompileState`；已恢复到此前值（49 / TRUE），并确认没有 `AutoDisabled` 项。新 IP 与 `hilo_unit.v` 的工程引用保留。
- 为区分旧指令与新 Lab7 路径，复跑 Lab3：`./scripts/verify.ps1 -Case lab3 -PipelineMode forwarding -TimeoutSeconds 1800`，运行 `lab3-20261022T015107Z`，耗时约 206 s。preflight、trace/MIF 检查、Xvlog/Xvhdl 及静态展开通过，但在相同 `XSIM 43-3409`（`xsim_5.c`）处退出，XSim 未启动；结果 `results/lab3_lab4/lab3-20261022T015107Z/`。因此本次无法复现功能结果，不是新指令的运行期失败；历史 Lab3 PASS 仍是此前那次运行的证据。
- 旧的独立诊断 `results/lab3_lab4/gcc-investigation-20261020T150000Z/` 记录 Vivado 随附 GCC 启动失败（Windows“无效的系统 DLL 重定位”）；这与本次 Xelab 生成 C 阶段故障相符。没有添加 GCC PATH 覆盖。
- 目前 S3、S4、S5 的 DUT 功能结果均为未验证；Lab6/Lab7 的全量 trace、功能点、WDB 和截图门槛均未达成。保持最终 `lab6-lab7-verified` tag 未创建。

## S2 Lab6 算术与逻辑指令

- 译码实现 `add/sub/addi/slti/sltiu/andi/ori/xori/sllv/srav/srlv`，补齐 `rs_used/rt_used`、目的寄存器和合法写回集合；逻辑立即数在 EX 零扩展、算术/比较立即数符号扩展。`DS_TO_ES_BUS_WD` 保持 136 位。
- 新增可复现的 65-word 定向 ROM，覆盖 `0x8000/0xffff` 边界、signed/unsigned 比较、寄存器移位高位屏蔽、EX/MEM/WB 前递、store/load 后的 load-use。独立 CPU132 reference 与 DUT 使用同一 COE/MIF，图像 SHA-256 为 `5B735649368AAB08ECD4ECC561D26DD4896ED812F9A40DAC56AFAC05CBD7A32B`。
- 定向 DUT：PASS，73 周期，1 次 load-use stall，EX/MEM/WB 前递 7/6/3 次，reference trace 全匹配；结果在 `results/lab3_lab4/lab3-20261021T140840Z/`，定向映像及 trace 在 `results/lab6_lab7/directed/alu/`。
- Lab3 回归：PASS，23/23，172,599 周期，0 stall，结果 `results/lab3_lab4/lab3-20261021T144347Z/`。
- Lab4 回归：PASS，23/23，114,577 周期，50 次 load-use stall，EX/MEM/WB 前递 4,505/4,818/1,032 次，结果 `results/lab3_lab4/lab4-20261021T144741Z/`。第一次重跑在 preflight 读取 IP 状态报告时遇到 Windows 文件短暂不可读；`check_project.tcl` 增加 5 秒有限重试后通过。
- 累计 Lab6：n24–n34 共 34 个功能点通过；在 n35 `div` 后的 `mflo` 首次 trace mismatch，属于 S3 尚未实现的 HI/LO 路径，不记为整套 Lab6 通过。日志 `results/lab6_lab7/lab6-20261021T141122Z/`。
- S2 RTL 与可复现定向用例提交：`c3c6ba4`；验证记录和实测日志在本次后续证据提交中。完整实现记录见 [implementation.md](implementation.md)。
