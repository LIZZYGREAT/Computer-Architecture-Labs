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
| Lab6 S2 历史累计 ROM | 34/42 点通过；旧 RTL 首次失败在 n35 `div` 后的 `mflo` trace。该结果保留为 S2 阶段记录，不代表当前完整 RTL。 |
| 当前 Lab6 累计 ROM | PASS，42/42，109,375 cycles，89 stalls；EX/MEM/WB forwards 35,013/8,320/12,007；trace 全匹配，见 [`lab6-20261022T051800Z`](../../results/lab6_lab7/lab6-20261022T051800Z/)。 |

累计 Lab6 首次失败的 trace 对照为：reference 在 `0xbfc2c9ec` 写 `$21=0x00000002`（n35 的 `mflo`），DUT 未实现 HI/LO 读取，下一条可见写回为 `0xbfc2c9f4` 对 `$2`；此前 n24–n34 已通过。

详细命令输出和 Vivado/XSim 日志见 `results/lab6_lab7/directed/alu/`、`results/lab6_lab7/lab6-20261021T141122Z/` 及对应 Lab3/Lab4 结果目录。S2 RTL 与定向用例提交为 `c3c6ba4`；验证证据和本记录另行提交。

## S3：Lab6 乘除法 IP 与 HI/LO

- 新增 `hilo_unit.v`，使用 Vivado `mult_gen` 33×33 signed、1 级流水乘法 IP，以及 32-bit Radix-2 unsigned divider IP。wrapper 对 signed/unsigned 操数做扩展或幅值转换，并恢复商和余数符号；结果按 HI=高/余数、LO=低/商提交。
- EX 以 `busy/done/consume_done` 保持 mult/div 指令，只在该指令能够离开 EX 时提交一次 HI/LO。`mthi/mtlo` 在离开 EX 的同一提交边界写入。`mfhi/mflo` 在 EX 读取特殊寄存器，避免 ID 提前取到旧值。
- `DS_TO_ES_BUS_WD` 从 136 扩为 154 位；`ES_TO_MS_BUS_WD` 扩为 114 位，以随流水传递 HI/LO 类型和新增访存元数据。累计 Lab7 DUT 已在最终 forwarding 验收中通过 68/68 个功能点；单独的 `hilo_unit_tb.v` 当前版本没有独立 PASS 结果。
- 新增 `hilo_unit_tb.v` 覆盖 signed/unsigned 乘除、除零预期、复位取消及接受/提交计数。模块级 testbench 的历史探针日志已清理；CPU 累计验收结果见 [verification.md](verification.md)。

## S4：Lab7 转移指令

- 新增 `j`、`jalr`、`bgez/bgtz/blez/bltz`、`bgezal/bltzal` 的译码与控制。条件按 signed `rs` 判断；`jalr` 使用 ID 前递后的 `rs` 作为目标并使用指令的 `rd` 作为链接寄存器。
- 条件分支目标使用 `PC+4 + signext(imm<<2)`，`j` 使用 `(PC+4)[31:28]` 拼接索引；链接结果为 `PC+8`。`bltzal/bgezal` 的链接行为按课程 `TEST_BLTZAL/TEST_BGEZAL` 宏要求处理：不论分支是否成立均写链接值，只有重定向取决于条件。
- 分支只在 ID 指令可被 EX 接收时发出，保留一条 delay-slot 指令，并避免多周期 EX 停顿时重复重定向。当前 Lab7 累计 DUT 仿真 68/68 功能点通过，详见 [verification.md](verification.md)。

## S5：Lab7 访存指令

- 将单一 load/store 控制扩为 12-bit one-hot `mem_op`，覆盖 `lw/lb/lbu/lh/lhu/lwl/lwr/sw/sb/sh/swl/swr`。EX→MEM 增加原 `rt` 值及有效地址的携带字段。
- `lb/lbu` 按低两位选择 byte lane 并分别符号扩展/零扩展；`lh/lhu` 按地址位 1 选择半字。`sb/sh` 通过 `data_sram_wen[3:0]` 选择小端字节 lane 并对写数据移位。
- `lwl/lwr` 使用经过前递与 RAW 检测的旧 `rt` 合并，`swl/swr` 按四种低地址偏移产生掩码及对应移位数据。公式与独立 CPU132 reference 的执行级合并/字节使能表逐项核对。
- SoC 仍使用 32-bit data RAM 与 `data_sram_addr[17:2]` 字索引；同步读在 EX→MEM 交接沿采样。Lab7 最终累计 forwarding 仿真覆盖 68 个课程功能点并与独立 trace 匹配；验收日志及哈希见 [verification.md](verification.md)。
