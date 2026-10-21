# Lab6/Lab7 实现记录

## S2：Lab6 算术与逻辑指令

### RTL

- 在 `ID_stage.v` 加入 `add/sub/addi/slti/sltiu/andi/ori/xori/sllv/srav/srlv` 译码。
- 更新源寄存器使用、目标寄存器选择和显式 GPR 写回合法指令集合，避免未知指令产生伪写回。
- 在 `EXE_stage.v` 对 `andi/ori/xori` 使用零扩展立即数，其余立即数保持符号扩展。
- `sllv/srlv/srav` 使用 `rs[4:0]` 作为移位量、`rt` 作为数据。流水线 bus 宽度与 Lab3/Lab4 forwarding 接口不变。
- 为 S2 定向用例新增 `verify.ps1` 的测试映像及期望功能点覆盖参数；参考 trace 生成脚本支持输入自定义 COE/MIF。定向 reference 仍由独立 CPU132 产生。
- `check_project.tcl` 在读取 Vivado 生成的 IP 状态报告时增加有界重试，缓解 Windows 文件短暂不可读导致的 preflight 中止。

### 定向 ROM

构建命令：

```powershell
python .\scripts\build_lab6_alu_directed_image.py
```

镜像位于 `results/lab6_lab7/directed/alu/image/`，65 words，COE/MIF 与 IP RAM 深度校验通过。程序覆盖立即数边界值、signed/unsigned 比较、三种可变移位及高位忽略、流水线前递和 load-use 停顿。镜像规范化序列 SHA-256：

```text
5B735649368AAB08ECD4ECC561D26DD4896ED812F9A40DAC56AFAC05CBD7A32B
```

参考生成和 DUT 回归命令（仓库根目录 `C:\Users\lenovo\Desktop\Projects\FPGA\lab`）：

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\generate_reference_trace.ps1 -Case lab3 -InstructionCoe .\results\lab6_lab7\directed\alu\image\lab6_alu_directed.coe -InstructionMif .\results\lab6_lab7\directed\alu\image\lab6_alu_directed.mif -TraceOutput .\results\lab6_lab7\directed\alu\golden_trace.txt -ExpectedFunctionalPointOverride 0
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1 -Case lab3 -PipelineMode forwarding -ReferenceTrace .\results\lab6_lab7\directed\alu\golden_trace.txt -InstMif .\results\lab6_lab7\directed\alu\image\lab6_alu_directed.mif -ExpectedPointOverride 0
```

### 验收结果

| 验收 | 结果 |
|---|---|
| 定向算术/逻辑 ROM | PASS，73 cycles，1 load-use stall，EX/MEM/WB forwards 7/6/3，trace 全匹配 |
| Lab3 forwarding 回归 | PASS，23/23，172,599 cycles，0 stalls |
| Lab4 forwarding 回归 | PASS，23/23，114,577 cycles，50 load-use stalls，EX/MEM/WB forwards 4,505/4,818/1,032 |
| Lab6 累计 ROM | 34/42 点通过；首次失败在 n35 `div` 后的 `mflo` trace。该处需要尚未实现的 HI/LO 与乘除法路径，按 S2 范围记录为预期阶段边界，不宣称 Lab6 全量通过。 |

累计 Lab6 首次失败的 trace 对照为：reference 在 `0xbfc2c9ec` 写 `$21=0x00000002`（n35 的 `mflo`），DUT 未实现 HI/LO 读取，下一条可见写回为 `0xbfc2c9f4` 对 `$2`；此前 n24–n34 已通过。

详细命令输出和 Vivado/XSim 日志见 `results/lab6_lab7/directed/alu/`、`results/lab6_lab7/lab6-20261021T141122Z/` 及对应 Lab3/Lab4 结果目录。S2 RTL 与定向用例提交为 `c3c6ba4`；验证证据和本记录另行提交。
