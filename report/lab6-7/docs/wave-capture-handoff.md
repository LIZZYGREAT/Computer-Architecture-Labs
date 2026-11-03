# Lab6/Lab7 Vivado 波形采集交接单

本文按 `docs/private/lab6-lab7/Lab6_Lab7_波形快速采集与报告填写手册.md` 整理，供打开 WDB、采集图片和后续完善报告时使用。所有实际时间窗和波形读数都应从对应 WDB 读取；表中的 expected 是测试向量，不应直接抄成 observed。

## 已准备的证据

- Python 图表及其 CSV 已由 `scripts/build_figures.py` 重建。图表、数据来源和报告可用指标见 `figures/`、`data/` 与 `docs/report-data-notes.md`。这些图包括结构说明、trace 退休事件和累计统计，不代替 Vivado 时序波形。
- ALU 定向 WDB：Run `lab3-20261028T132600Z`，PASS，73 周期，1 次记录的停顿，EX/MEM/WB 前递计数 7/6/3，36 条 reference trace 记录匹配。
- 该 ALU WDB 的仿真日志使用 `log_wave -r /`，未出现 HDL 层级未匹配警告，文件大小 5,060,445 bytes；`01_alu_immediate.wcfg`、`02_variable_shift.wcfg`、`03_forwarding_load_use.wcfg` 均引用此 WDB，可保留用于截图。
- 完整 Lab6 重采集：Run `lab6-20261102T054949Z`，PASS，42/42，109,439 周期；WDB 113,757,682 bytes，SHA-256 `9704AA3BB6446A03DAA02D06C9A45E15858A894F2087467CF8B6A35BB7CCBC98`。
- 完整 Lab7 重采集：Run `lab7-20261102T055526Z`，PASS，68/68，166,330 周期；WDB 175,790,426 bytes，SHA-256 `F5B2935BA085351AE79D0FE32FCFA05C53FF9AD44CAD4BAB31474F533FA5541B`。
- DIV 等待期间分支保持定向重采集：Run `lab6-20261102T060138Z`，PASS，111 周期，6 条 reference trace 写回记录匹配；WDB 5,038,883 bytes，SHA-256 `ACDA06311C4467DBC8C0EA8325736D5B6AF145A9BA97AC6A98B20EE0B21DB5CA`。
- 当前 13 个 Vivado Wave 配置位于 `figures/waveforms/`，均通过 XML 解析、WDB 路径存在性和信号清单检查。`01`–`03` 继续引用原先有效的 ALU 定向 WDB；`04`、`05`、`11` 绑定重采集 Lab6 WDB，`06`–`10` 绑定重采集 Lab7 WDB，另有 `05_div_stall_branch_directed.wcfg` 绑定定向 WDB。原有 WCFG 文件保留。

## 采集可用性与限制

### 当前 WDB 捕获问题

2026-11-02 在 Vivado 打开历史 Lab6 WDB 时，信号名可见但 Value 列和波形区为空。对应 `xsim-simulate-stage.log` 显示脚本调用 `log_wave -r /tb_top` 后报告 `[Simtcl 6-55] No matching HDL object or HDL scope found`；这是仿真采集层级不匹配，不是加载 WCFG 的操作错误。WCFG 只保存信号布局，不能补回 WDB 未记录的数据。历史 Lab7 阶段日志缺失，因此旧 Lab7 WDB 也不再用于新截图配置。

经用户授权，以仓库基线 XPR 在隔离目录重采集，没有修改原工程 XPR。新 Lab6、Lab7 和定向用例的 `xsim-simulate-stage.log` 均显示 `log_wave -r /` 且没有 `No matching HDL object` 警告；`result.txt`、WDB 哈希与新配置绑定均已核对。旧 `WAVEFORM_CAPTURED=True` 只证明文件存在，不作为波形有效性的单独依据。

| 主题 | 建议波形来源 | 当前状态 |
|---|---|---|
| 立即数、可变移位、前递与 load-use | ALU 定向 WDB | 有效记录；使用新的 `01`–`03` 配置副本 |
| MULT/MULTU 与 HI/LO | 新完整 Lab6 WDB | 已重采集；按 `inst_mult`/`inst_multu` 和操作数定位 |
| DIV 运算及 HI/LO | 新完整 Lab6 WDB | 已重采集；按实际 DIV 和操作数定位。完整课程运行不替代 DIV 后紧接分支的定向用例 |
| 条件分支、JALR、部分 store、LB/LBU/LH/LHU、LWL/LWR 和 store 读回 | 新完整 Lab7 WDB | 已重采集；按译码信号、PC 和当前 Run 的 reference trace 定位 |
| DIV 等待期间分支保持的组合场景 | 新定向 Lab6 WDB | 已重采集；使用 `05_div_stall_branch_directed.wcfg`，全程视图为 0–3,200 ns |

原 Vivado 工程 XPR 仍含 3 个 `AutoDisabled=1`（两个 `lab6_div32` 仿真文件和一个 `lab6_mult33` 仿真文件）。本次按用户授权从仓库基线建立隔离副本，预检通过后串行重采集；原工程 XPR、原 WDB/WCFG 和工作树差异均保留。未来在原工程上直接重跑前，仍需按工程流程处理这些源文件状态并通过预检。

已有的三个原始 `.wcfg` 曾关联到已不存在的 Run `lab6-20261028T115344Z`。它们仍被保留；请优先打开本交接单提到的新配置副本。Wave 配置以 XML 生成并检查过 WDB 路径和文件格式；首次在 Vivado 打开时仍应确认每个信号可见。

## 截图顺序、目标值与信号

每张实际截图各占 `data/wave-capture-log.csv` 一行，含精确 PNG 文件名、WDB 路径、搜索信号和值及搜索上下文。短定向 MIF 的固定 PC 与向量只适用于相应短用例；累计运行需按指令、操作数和对应 Run 的 reference trace 定位。截图中的读数和时间窗仍应以当前 PNG/WDB 为准。

| 图片名 | WDB / 定位方式 | 关键 expected 与观察重点 | 配置 |
|---|---|---|---|
| `01_alu_immediate.png` | ALU 定向 WDB；PC `BFC0002C/30/34` | `andi r12` → `00008000`；`ori r13` → `00008000`；`xori r14` → `FFFF0000`。观察立即数扩展、ALU 输入/结果及同 PC 的 WB。 | `01_alu_immediate.wcfg` |
| `02_variable_shift.png` | 同一 ALU 定向 WDB；PC `BFC00044/48/4C` | 有效移位量为 `r16[4:0]=5`；SLLV=`FFF00000`、SRLV=`04000000`、SRAV=`FC000000`。同时显示 rs/rt、ALU 结果和 WB。 | `02_variable_shift.wcfg` |
| `03_forwarding_load_use-BFC00054.png`；`03_forwarding_load_use-BFC00084.png` | ALU 定向 WDB；PC `BFC00054` 与 `BFC00084–8C` | EX/MEM/WB 前递结果包括 `r21=00002468`、`r23=00000022`、`r25=00000024`；load-use 从 `lw` 得 `r30=00007FFF`，随后得 `r31=00008000`。 | `03_forwarding_load_use.wcfg` |
| `04_mult_signed.png`；`04_multu_unsigned.png` | 重采集 Lab6 WDB；按 `inst_mult`/`inst_multu` 和操作数定位 | `mult 45B90738 × D70D64F0` → `HI:LO=F4D903BB:0A20A480`；`multu 99C9A500 × 6C1A1B60` → `40F0C088:B204E000`。观察请求、busy/done/consume、HI/LO 与乘积。 | `04_mult_hilo.wcfg` |
| `05_div_stall_branch-BFC00008.png`；`05_div_stall_branch-BFC0000C.png` | 定向 Lab6 WDB `results/lab6_lab7/lab6-20261102T060138Z/`；PC `BFC00008/0C` | 短向量 `-23 / 5` → 商 `FFFFFFFC`、余数 `FFFFFFFD`；延迟槽写 `r3=00000055`，目标标记写 `r7=00000066`，错误路径 `BFC00014` 不退休。截图 `BFC00008` 显示请求/等待，`BFC0000C` 显示分支等待及后续推进。 | `05_div_stall_branch_directed.wcfg` |
| `06_branch_delay_slot_jalr-BFC70398.png`；`06_branch_delay_slot_jalr-BFC96694.png` | 重采集 Lab7 WDB；按 `inst_bgez`、`inst_jalr` 定位 | JALR 链接 `r31=BFC703A0`，延迟槽 LUI 写 `r8=800D0000`；BGEZ 延迟槽 MFHI 写 `r15=00004000`。 | `06_branch_delay_slot_jalr.wcfg` |
| `07_partial_store_mask-BFC8E15C.png`；`07_partial_store_mask-BFC1AACC.png`；`07_partial_store_mask-BFC8759C.png`；`07_partial_store_mask-BFC2B5CC.png` | 重采集 Lab7 WDB；按 PC `BFC8E15C/1AACC/8759C/2B5CC` 定位 | 分别对应 SB、SH、SWL、SWR；观察地址、写数据和字节写使能。完整运行中的地址与数据以 CSV 搜索项及当前波形为准。 | `07_partial_store_mask.wcfg` |
| `08_byte_half_load-BFC5D874.png`；`08_byte_half_load-BFC1D2B4.png`；`08_byte_half_load-BFC6ABC0.png`；`08_byte_half_load-BFC7E7D4.png` | 重采集 Lab7 WDB；按 PC 搜索 LB/LBU/LH/LHU | LB=`FFFFFFAF`、LBU=`000000FF`、LH=`FFFFBE4D`、LHU=`0000C5E0`。对齐地址、RAM 返回字、扩展结果和 WB；译码旗标需对齐 DS 周期查看。 | `08_byte_half_load.wcfg` |
| `09_unaligned_load_merge-BFC5BEAC.png`；`09_unaligned_load_merge-BFC9A1E0.png` | 重采集 Lab7 WDB；按 PC 搜索 LWL/LWR | LWL：旧 RT `F507F480` 与 RAM `79E8D3EE` 合并为 `E8D3EE80`；LWR：旧 RT `ED6D7900` 与 RAM `CE7208CC` 合并为 `ED6DCE72`。 | `09_unaligned_load_merge.wcfg` |
| `10_store_readback-BFC8E170.png`；`10_store_readback-BFC1AAE0.png`；`10_store_readback-BFC875B0.png`；`10_store_readback-BFC2B5E0.png` | 重采集 Lab7 WDB；按后续 LW PC 搜索 | 读回值分别为 SB `B4F0090A`、SH `36008848`、SWL `CEEB8EA8`、SWR `13424CE8`。当前帧展示读回，前一条 store 的写掩码/数据未完整入镜。 | `10_store_readback.wcfg` |
| `11_hilo_unsigned_optional.png` | 重采集 Lab6 WDB；PC `BFC1F5F8`，操作数 `D7042938 / 018A7078` | 当前 PNG 显示 DIVU busy 阶段，最终商 `0000008B`、余数 `00D91810` 尚未出现在截图中；该图仅证明运算进行中。 | `11_hilo_unsigned_optional.wcfg` |

各组 `.wcfg` 的初始时间轴只是便于打开的视图设置。完整 Lab6/Lab7 中应按指令类型、PC 和操作数定位事件，再缩放到截图范围；只有用户从 Vivado Wave 读取的时间窗和数值才填写到 `data/wave-capture-log.csv`。

## 报告用证据记录

逐图填写实际 `Run ID`、WDB、reference trace、目标 PC/指令、时间窗、输入/控制值、实际输出和 PASS 依据。Python 退休事件图没有周期轴，不能称为 Vivado 时序波形。报告正文只引用实际采集的图片和实测值；该交接单中的环境状态与采集状态属于内部工作记录。
