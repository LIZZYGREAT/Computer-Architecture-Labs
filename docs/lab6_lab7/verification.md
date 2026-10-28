# Lab6 / Lab7 验收记录（2026-10-27）

当前结果只按 `result.txt` 中的 `STATUS` 判定。以下 10/26 UTC 运行 ID 对应本次完整复核；Lab3/Lab4 最终验收和 GCC 执行上下文说明见 [`../lab3-lab4/verification-final.md`](../lab3-lab4/verification-final.md) 与 [`../lab3-lab4/gcc-startup-incident.md`](../lab3-lab4/gcc-startup-incident.md)。

## 最近完整回归（2026-10-26，握手修订前基线）

下表的 PASS 均来自 10/26 或更早的运行。它们证明当时的已保存映像和 RTL；不表示 10/27 的 Divider 输入握手修订已通过回归。修订后状态见本文末尾。

| 用例 | 结果目录 | 结果 |
|---|---|---|
| Lab3 forwarding 回归 | [`lab3-20261026T162836Z`](../../results/lab3_lab4/lab3-20261026T162836Z/) | PASS，23/23，172,599 cycles，`ds_stall` 计数 0；44,071/44,071 trace 写回匹配 |
| Lab4 forwarding 回归 | [`lab4-20261026T163305Z`](../../results/lab3_lab4/lab4-20261026T163305Z/) | PASS，23/23，114,577 cycles，`ds_stall` 计数 50；EX/MEM/WB 前递 4,505/4,818/1,032；44,071/44,071 trace 写回匹配 |
| Lab6 forwarding | [`lab6-20261026T163659Z`](../../results/lab6_lab7/lab6-20261026T163659Z/) | PASS，42/42，109,375 cycles，`ds_stall` 计数 89；EX/MEM/WB 前递 35,013/8,320/12,007；66,612/66,612 trace 写回匹配；零寄存器写回尝试 0 |
| Lab7 forwarding | [`lab7-20261026T164130Z`](../../results/lab6_lab7/lab7-20261026T164130Z/) | PASS，68/68，166,226 cycles，`ds_stall` 计数 926；EX/MEM/WB 前递 49,970/12,229/15,454；100,732/100,732 trace 写回匹配；零寄存器写回尝试 0 |
| Lab7 新指令前递定向用例 | [`reference-lab7-20261026T161931Z`](../../results/lab6_lab7/reference-lab7-20261026T161931Z/) + [`lab7-20261026T170957Z`](../../results/lab6_lab7/lab7-20261026T170957Z/) | PASS，CPU132 参考 41 条 trace；DUT 41/41 匹配，64 cycles，1 stall；新增 store base/data/branch/jalr 计数 3/2/6/1；运行源提交为 `7d8a3b5` |
| HI/LO 单元 testbench | [`hilo-unit-20261026T164656Z`](../../results/lab6_lab7/hilo-unit-20261026T164656Z/) | PASS；乘法/除法接受及完成提交计数 3/4/6，覆盖 signed/unsigned 运算、完成保持/消费、MTHI/MTLO、复位取消 |
| 除法期间分支等待定向用例 | [`directed/hilo-stall-branch`](../../results/lab6_lab7/directed/hilo-stall-branch/)；[CPU 仿真结果](../../results/lab3_lab4/lab3-20261022T065139Z/) | PASS；参考 trace 与 DUT 全匹配：delay slot `$3=0x55`，fall-through `$4` 未写回，`mflo/mfhi` 得到 `-4/-3`，分支目标 `$7=0x66` |
| Lab7 独立 CPU132 reference | [`reference-lab7-20261021T134251Z`](../../results/lab6_lab7/reference-lab7-20261021T134251Z/) | PASS，68/68；100,732 条 trace 记录 |
| Lab6 独立 CPU132 reference | [`reference-lab6-20261021T133931Z`](../../results/lab6_lab7/reference-lab6-20261021T133931Z/) | PASS，42/42；66,612 条 trace 记录 |
| Lab6 S2 累计 DUT 历史轮 | [`lab6-20261021T141122Z`](../../results/lab6_lab7/lab6-20261021T141122Z/) | 34/42 后在当时尚未实现的 HI/LO `mflo` 处 FAIL；这是 S2 阶段记录，不是当前完整 Lab6 通过结果 |

Lab6/Lab7 golden trace 分别保存在 [`golden/lab6`](../../results/lab6_lab7/golden/lab6/golden_trace.txt) 和 [`golden/lab7`](../../results/lab6_lab7/golden/lab7/golden_trace.txt)。Lab6 算术逻辑定向 DUT 结果及映像位于 [`lab3-20261021T140840Z`](../../results/lab3_lab4/lab3-20261021T140840Z/) 与 [`directed/alu`](../../results/lab6_lab7/directed/alu/)；该定向 DUT 通过，73 周期、1 次 load-use 停顿、EX/MEM/WB 前递 7/6/3。Lab7 新指令前递映像与 listing 位于 [`directed/extended-forwarding`](../../results/lab6_lab7/directed/extended-forwarding/)。

在上表对应的运行中，Lab6 累计 forwarding 通过 42 个功能点，Lab7 累计 forwarding 通过 68 个功能点，均与独立 CPU132 trace 全匹配；Lab3/Lab4 23/23 基线、HI/LO 模块级 testbench、除法期间分支等待及新增指令前递定向用例也通过。`lab6-20261021T141122Z` 的 34/42 是 S2 阶段旧 RTL 的历史结果，不代表完整 Lab6 状态。以上结果均未启用波形捕获；原波形分析和截图仍由用户完成。

旧 `FORWARD_EX/MEM/WB_USES` 与新增专项计数均只在 `ds_instruction_issued`（ID 指令被 EX 接收）时采样；常规前递每级只要 `rs` 或 `rt` 任一操作数使用该级就记一次，因此它是发射指令周期/前递级别使用次数，不是源操作数总数或 stall 周期。旧 `HAZARD_STORE_BASE_FORWARDS`/`HAZARD_STORE_DATA_FORWARDS` 只统计 `sw`，`HAZARD_BRANCH_FORWARDS` 只统计 `beq/bne`，`HAZARD_JR_FORWARDS` 只统计 `jr`。新增 `HAZARD_NEW_STORE_BASE_FORWARDS`、`HAZARD_NEW_STORE_DATA_FORWARDS` 分别统计 `sb/sh/swl/swr` 的基址和写数据前递；同一条指令若两操作数均前递，可同时增加两个值。`HAZARD_NEW_BRANCH_FORWARDS` 覆盖六种新增条件分支的 `rs` 前递；`HAZARD_JALR_FORWARDS` 覆盖 `jalr` 跳转目标 `rs` 前递。累计 Lab7 值为 112/0/1,229/28；定向映像值为 3/2/6/1。当前累计程序没有触发新增 store-data 前递，故其值为 0；定向程序已对该路径给出非零覆盖。

`PIPELINE_STALL_CYCLES` 逐周期统计 `ID_stage.ds_stall`，即 ID 源操作数因数据相关而不能前进的周期数；它不是全流水线停顿总周期，也不代表 EX 等待乘除 IP 的完整时长。独立的 `HAZARD_LOAD_USE_STALLS` 按 testbench 中 `ds_stall && es_hazard_valid && !es_forward_valid` 的条件计数。若要报告乘除 IP 的等待周期，应另统计 `es_valid && !es_ready_go`，不要从 `PIPELINE_STALL_CYCLES` 推断。

本轮累计回归命令：

```powershell
.\scripts\verify.ps1 -Case lab3 -PipelineMode forwarding
.\scripts\verify.ps1 -Case lab4 -PipelineMode forwarding -ReferenceTrace .\lab4\func_lab4\obj\golden_trace.txt
.\scripts\verify.ps1 -Case lab6 -PipelineMode forwarding -TimeoutSeconds 1800
.\scripts\verify.ps1 -Case lab7 -PipelineMode forwarding -TimeoutSeconds 1800
.\scripts\verify.ps1 -Case lab7 -PipelineMode forwarding -ReferenceTrace .\results\lab6_lab7\directed\extended-forwarding\golden_trace.txt -InstMif .\results\lab6_lab7\directed\extended-forwarding\image\lab7_extended_forwarding.mif -ExpectedPointOverride 0 -HazardDirected
```

除法后分支定向用例先用独立 CPU132 生成 trace，再以相同 MIF 运行 DUT；构建脚本为 `scripts/build_lab6_hilo_stall_branch_image.py`，详细输入、trace 和 CPU 结果见 [`directed/hilo-stall-branch`](../../results/lab6_lab7/directed/hilo-stall-branch/) 与上表链接。

## 参考轨迹与镜像

- Lab6 trace：66,612 条记录，SHA-256 `FB92799CBA4C42B1ECB729DD6659DADC63195B07E16C3FD6E25B2A6986850CA1`；当前课程 MIF SHA-256 `845D97935C29D651D1D73D906DC3E92DC5690C23F77920111A369D33C28E8F28`。
- Lab7 trace：100,732 条记录，SHA-256 `23ADD75B2BADFDABF98B1863A89896DFC60B4B351CC49321B22BEB22035991C3`；当前课程 MIF SHA-256 `8EBF314084B3B06BF40A9F4DF2B402E74BE5D1F705A75F7ADFC858868B9B75BE`。
- 新增指令定向 trace：41 条记录，SHA-256 `4E7557963DB8CB4CDDB99E3B0DEB3A46D5711F4C4E71A95EB1791BB3D65B1D49`；MIF SHA-256 `44E2B856BB12AB82295A7214C161D1616BE19E13AA35F625E9349B2B0A19E03C`。
- Lab6 与 Lab7 最终 DUT 结果均记录 trace 与 MIF 哈希匹配，Xvlog/Xvhdl/Xelab/XSim 全阶段日志完整保存在各自结果目录。

## GCC / XSim 故障复查

早期在 Codex 的 AppContainer PowerShell 中，Xelab 编译 `xsim_5.c` 报 `XSIM 43-3409`，XSim 未启动。重测确认：Codex PowerShell token 的 `TokenIsAppContainer=1`；该上下文用正常或隔离 PATH 启动 Vivado GCC 6.2.0 会失败。普通 Windows PowerShell token 为 `TokenIsAppContainer=0`；GCC `--version` 与 XSim C 编译通过，Lab3/Lab4/Lab7 完整仿真也通过。

`verify.ps1` 已加入 AppContainer 预检和 `host-context.txt` 记录。处于 AppContainer 时会在启动 Vivado 前返回 `ENVIRONMENT_ERROR`，并标记测试点和周期未运行。精简命令、环境、Xelab 与 DLL 错误证据见 [`gcc-diagnostic-20261022`](../../results/lab3_lab4/gcc-diagnostic-20261022/)。未替换 DLL、未重装 Vivado、未修改 Xelab 默认 GCC 配置。

另一次失败轮的 XSim 原因是 XSim 找不到自定义 `xsim-run.tcl`，随后停在交互提示符并超时。该脚本先前直接从结果目录执行，清理失败结果时可能被一并移除；现改为在 `scripts_only` 完成后（该步骤会重建仿真工作目录内容）于仿真工作目录生成并检查运行脚本，再将副本归档到结果目录。超时清理也会终止 Vivado 子进程树，避免遗留 XSim 持有失败日志。

## S2 算术逻辑定向用例

独立 65-word ROM 覆盖立即数边界、signed/unsigned 比较、`sllv/srav/srlv`、EX/MEM/WB 前递和 load-use。定向 DUT 73 周期、1 次停顿，trace 匹配。实现与构建方法见 [`implementation.md`](implementation.md)。

## 保留记录范围

`results` 中保留本轮最终 PASS、必要阶段日志、稳定 golden trace、定向输入映像和 GCC 根因对照。历史 S2 失败仅作为阶段记录，不列入最终验收结果。reference CPU 源码仍在 `lab3/CPU_CDE/cpu132_gettrace/`，可按脚本重新生成。

## Lab6/Lab7 源码重建状态（P1-A）

已从 Lab6 和 Lab7 各删除一个重复的 `inst/n32_xori.S`。删除前四份 `n31_xori.S`/`n32_xori.S` 的 SHA-256 均为 `77559A51A58867B24663D7B0B92CDA2DBB1FBE7E784F3BFA5E97EDCCAB0732C3`；两个 `start.S` 都只调用 `n31_xori_test` 和 `n32_sllv_test`，而对应的 `n32_sllv.S` 保留。未改测试宏、功能点编号或已有 `obj/` 映像。

`SOURCE_REBUILD=PASS`。在隔离的 WSL Ubuntu 22.04 临时副本中，用 GCC 10.3.0、GNU Binutils 2.38 分别构建了 42 个 Lab6 与 68 个 Lab7 汇编单元；清单、完整构建日志、manifest 和重建映像位于 [`source-rebuild-20261027`](../../results/lab6_lab7/source-rebuild-20261027/)。原仓库 `obj/` 映像没有覆盖。

GCC 10 需要显式传入 `-mfp32`。GNU ld 2.38 对旧链接脚本生成的 `.MIPS.abiflags` 元数据与 `.data` LMA 报重叠；只在临时副本的 `bin.lds.S` 加入 `/DISCARD/ : { *(.MIPS.abiflags) }` 后完成链接，丢弃的是 ABI 元数据，不是指令或数据。实际构建参数为 `-mips1 -mfp32 -EL -fno-pic -mno-abicalls`，详见各 case 的 `build-manifest.txt` 和 `build.log`。

重建映像与原始映像的词数及 RAM 深度一致，规范化指令内容则不同：

| Case | 源文件数 | 指令词数 / 深度 | 原映像规范化 SHA-256 | 重建映像规范化 SHA-256 | 不同词数 |
|---|---:|---:|---|---|---:|
| Lab6 | 42 | 102,959 / 262,144 | `88FDCD95DE9C0B0877115805A529F4F25C343FADC69CB026180A7F3661DAD74A` | `777BE20AA83FA99E61B87AAF55FC33E9C083E7A3CDF1BFF8B685D539524EE7D3` | 95,204 |
| Lab7 | 68 | 166,859 / 262,144 | `0B0C31343767D5CEC74E925BF7E153C5F70AD3CE66884D2E6CDCCB9632551899` | `889A8D604809B54F3667362213BDE88D95566CBB4812F9A08E3A3733CBEF1170` | 158,638 |

首次差异在 word 247（PC `0xbfc003dc`），该处是 `jal` 的目标字段；重建版的链接地址布局不同，后续大量指令词随之不同。重建使用的工具链版本与原始映像的构建工具链未能确认相同，因此不把全部差异单独归因于删除重复源文件。通过以下配对 reference/DUT 回归验收了重建产物；新旧 trace 均未混用：

| Case | 重建 COE / MIF SHA-256 | 新 CPU132 trace | Reference | DUT |
|---|---|---|---|---|
| Lab6 | `3d9c478bdf985c7f6d106ad2ac953cb9800b069027c40720bbd7bedd2bb6ea12` / `3336713500a6a7c41c52b6904430a61e3998680ee2bd7f7285a1eb42c95e8569` | 66,612 条，`1C45DC3B5322536878CC6CCBAC88D0C669DF7FD341BFD63694F2CDCEAF34A716` | PASS，42/42，[`reference-lab6-20261027T032906Z`](../../results/lab6_lab7/reference-lab6-20261027T032906Z/) | PASS，42/42，[`lab6-20261027T033402Z`](../../results/lab6_lab7/lab6-20261027T033402Z/)；109,439 cycles，89 `ds_stall`，66,612/66,612 trace |
| Lab7 | `e08d053bf3cd9e7f0bfe5b1d813053fd0c63bb0ffe7ffd622a761547e669ec91` / `d7d9a71898bfa0b59e12e44ba884609bd3c55e9ce89092304b12b9acfa059bcf` | 100,732 条，`FF70411F105009F10FEBFEB38251696DCEDFF76E68FB091B4AA124A75EF53DEB` | PASS，68/68，[`reference-lab7-20261027T033134Z`](../../results/lab6_lab7/reference-lab7-20261027T033134Z/) | PASS，68/68，[`lab7-20261027T033802Z`](../../results/lab6_lab7/lab7-20261027T033802Z/)；166,330 cycles，926 `ds_stall`，100,732/100,732 trace |

## 修订后 RTL 验收状态（2026-10-27 至 28）

修订后的验收均在普通 Windows PowerShell 调用 Vivado/XSim；各结果记录 `WINDOWS_APPCONTAINER=False`。所有仿真均未启用波形捕获。

| 验收项 | 修订后结果 |
|---|---|
| HI/LO 单元 Vivado/XSim testbench（新两路握手断言） | PASS；`hilo-unit-20261027T032000Z`，`HILO_UNIT_TB_PASS mult_accepts=3 div_accepts=4 input_pairs=3 commits=6` |
| 除法期间分支等待定向用例 | PASS；[`lab6-20261027T031906Z`](../../results/lab6_lab7/lab6-20261027T031906Z/)，111 cycles，trace 全匹配 |
| Lab3 forwarding 累计回归 | PASS；[`lab3-20261027T025645Z`](../../results/lab3_lab4/lab3-20261027T025645Z/)，23/23，172,599 cycles |
| Lab4 forwarding 累计回归 | PASS；[`lab4-20261027T030155Z`](../../results/lab3_lab4/lab4-20261027T030155Z/)，23/23，114,577 cycles |
| Lab6 forwarding 累计回归 | PASS；[`lab6-20261027T030621Z`](../../results/lab6_lab7/lab6-20261027T030621Z/)，42/42，109,439 cycles，66,612/66,612 trace |
| Lab7 forwarding 累计回归 | PASS；[`lab7-20261027T031040Z`](../../results/lab6_lab7/lab7-20261027T031040Z/)，68/68，166,330 cycles，100,732/100,732 trace |
| 新汇编源码重建、重建 ROM 的 CPU132 reference 与 DUT | PASS；细节及新旧映像差异见上一节 |
| P2-A 连续依赖定向 reference 与 DUT | PASS；25/25 trace，79 cycles，9 笔 store 与唯一一次 branch redirect 的副作用检查通过；结果见 [`reference-lab7-20261027T025022Z`](../../results/lab6_lab7/reference-lab7-20261027T025022Z/) 和 [`lab7-20261027T025231Z`](../../results/lab6_lab7/lab7-20261027T025231Z/) |
| Lab6 带波形捕获累计回归 | PASS；[`lab6-20261028T093517Z`](../../results/lab6_lab7/lab6-20261028T093517Z/)，42/42，109,439 cycles，66,612/66,612 trace；WDB SHA-256 `4D2A39C08107A145FEB5F63EC76C5BF189447B189DDE7A4B23627A5403EB8036` |
| Lab7 带波形捕获累计回归 | PASS；[`lab7-20261028T102942Z`](../../results/lab6_lab7/lab7-20261028T102942Z/)，68/68，166,330 cycles，100,732/100,732 trace；WDB SHA-256 `0C9391FAB20AC99665F288A9CC59BBF6A78F5CACE2EC34367B70CA5C39D80F7B` |

本轮 reference、DUT、HI/LO 和定向回归的具体结果目录均已归档；10/26 表格保留为握手修订前基线。10/27 的验收运行未捕获波形；10/28 单独执行的 Lab6/Lab7 捕获回归已生成 WDB，PNG 导出和报告信号分析仍待完成。

## 建议人工核验序号（修订后 PASS）

按下列顺序核对 `result.txt` / `reference-result.txt` 中的状态、trace 数量和配对映像。所有编号均为结果目录名：

1. **Lab6 源码重建：**`reference-lab6-20261027T032906Z` → `lab6-20261027T033402Z`；CPU132 与 DUT 均 42/42，trace 66,612/66,612。
2. **Lab7 源码重建：**`reference-lab7-20261027T033134Z` → `lab7-20261027T033802Z`；CPU132 与 DUT 均 68/68，trace 100,732/100,732。
3. **修订后课程 ROM 累计回归：**`lab6-20261027T030621Z`（42/42，66,612/66,612）和 `lab7-20261027T031040Z`（68/68，100,732/100,732）。
4. **HI/LO 双路握手：**`hilo-unit-20261027T032000Z`；`mult_accepts=3`、`div_accepts=4`、`input_pairs=3`、`commits=6`。
5. **DIV 等待期间分支：**`lab6-20261027T031906Z`；111 cycles，独立参考 trace 全匹配。
6. **P2-A 连续依赖：**`reference-lab7-20261027T025022Z` → `lab7-20261027T025231Z`；25/25 trace，79 cycles，9 笔 store 与唯一 branch redirect 检查通过。
7. **Lab3/Lab4 回归：**`lab3-20261027T025645Z`（23/23）和 `lab4-20261027T030155Z`（23/23）。

前述记录均为 `STATUS=PASS`。编号 1–2 是重建汇编产物后重新生成 reference 并配对验证的最终主证据；所有本轮运行均未捕获 Lab6/Lab7 波形。

## P2-A：Lab7 连续依赖与非对齐访存定向用例

从仓库根目录构建 65-word 指令映像：

```powershell
python .\scripts\build_lab7_dependency_directed_image.py
```

输出位于 `results/lab6_lab7/directed/dependency-boundaries/image/`。脚本生成 COE、MIF 和 `lab7_dependency_boundaries_program.txt`；COE/MIF 深度及规范化内容一致性检查结果为 `IMAGE_MATCH=PASS`，包含 65 words，`INST_RAM_DEPTH=262144`。COE 文件 SHA-256 为 `2BB3AB57F3B71B8BD81E9465C69823D673D2C29E6D102FB27E5A35DB611288B9`，MIF 文件 SHA-256 为 `BFAD67266B488A524854D4174F1628002228ED58D690C19ADCA3C258F4CAC76A`。

在普通 Windows PowerShell 中，先用独立 CPU132 生成该镜像的 reference trace，再运行带显式副作用检查的 DUT：

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\generate_reference_trace.ps1 -Case lab7 -InstructionCoe .\results\lab6_lab7\directed\dependency-boundaries\image\lab7_dependency_boundaries.coe -InstructionMif .\results\lab6_lab7\directed\dependency-boundaries\image\lab7_dependency_boundaries.mif -TraceOutput .\results\lab6_lab7\directed\dependency-boundaries\golden_trace.txt -ExpectedFunctionalPointOverride 0
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1 -Case lab7 -PipelineMode forwarding -ReferenceTrace .\results\lab6_lab7\directed\dependency-boundaries\golden_trace.txt -InstMif .\results\lab6_lab7\directed\dependency-boundaries\image\lab7_dependency_boundaries.mif -ExpectedPointOverride 0 -DependencyDirected
```

程序清单记录预期 GPR 与最终 RAM 内容。testbench 对照 9 笔实际写事务的地址、byte-enable 和写数据，并要求唯一一次 taken branch redirect；trace 检查 delay slot 写回、fall-through 未写回和目标指令写回。`verify.ps1` 只有同时识别 `DEPENDENCY_SIDE_EFFECTS_PASS`、全 trace 匹配及标准结束标记才会判 PASS。本次 CPU132 reference（25 条记录）与 DUT 均为 `PASS`，完整 trace 和副作用检查均通过，结果分别见 `reference-lab7-20261027T025022Z` 与 `lab7-20261027T025231Z`。
