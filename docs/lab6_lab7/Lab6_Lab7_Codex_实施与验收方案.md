# Lab6–Lab7：五级流水线 CPU 指令扩展与实验验收执行方案

> 面向 Codex 的执行说明。基于**已经完成相关检测、阻塞与前递的 Lab3–Lab5 CPU**继续扩展。**不要**从空工程重新实现，不要回退到旧 Lab1 CPU，也不要另复制两个相互独立的 Vivado CPU 工程。
>
> 本文所列文件与技术风险，基于先前提供的 `lab.zip` 工程快照和本次 `lab6-7.zip` 教学资源审查。**先对本地最新工作区复核**：用户随后可能已完成一轮 Lab3–Lab5 收尾修改，不得以旧快照覆盖最新代码。

## 一、任务边界与已有事实

本次按 **MIPS 原版**《CPU设计实战》第五章和第六章实施，而非 LoongArch 版。

- **Lab6 / 第五章**：在现有 CPU 上新增普通算术逻辑指令、乘除法指令和 HI/LO 数据搬运指令。
- **Lab7 / 第六章**：在 Lab6 CPU 上新增转移与访存指令，尤其要正确实现 MIPS 延迟槽、字节/半字与非对齐访存。
- **实现基础**：已有五级流水线（IF/ID/EX/MEM/WB），已实现 GPR 数据相关检测、阻塞、EX/MEM/WB 前递及 `PIPELINE_FORWARDING` 开关。保留该能力，并重新验证。
- **乘除法**：允许直接采用 Vivado IP Core；**没有必要自行编写乘法器/除法器运算算法**，但必须实现 IP 接口适配、握手、流水线停顿、HI/LO 写入和结果依赖处理。
- **验证**：新指令功能测试、独立参考 trace 对比、定向边界测试，以及**实际 XSim 波形截图+文字分析**。不得只给终端 `PASS`。

### 1. 教学测试资源核对结论

上传的 `lab6-7.zip` 主要提供两套测试程序源码与已编译 ROM，以及两个模块级测试顶层；**并未包含可直接替换现有 CPU 的完整 RTL**。

| 阶段 | 测试入口 | 指令覆盖 | `start.S` 中 `TEST_NUM` | 已编译 `inst_ram.mif` 约有多少行 |
|---|---|---|---:|---:|
| Lab3–Lab5 | 既有 Lab3/Lab4 测试 | 基础 23 类指令 | 23 | 沿用现有文件 |
| Lab6 | `lab6/func_lab6/` | 基础 23 + 新增 n24–n42（19 类） | 42 | 102,959 |
| Lab7 | `lab7/func_lab7/` | 基础 42 + 新增 n43–n68（26 类） | 68 | 166,859 |

注意：

1. Lab6 `start.S` 定义 `lab3=1, lab6=1`；Lab7 `start.S` 定义 `lab3=1, lab6=1, lab7=1`。这是**累计功能测试**。Lab7 通过并不能替代 Lab6 阶段的独立回归证据。
2. 测试程序 `Readme_first.txt` 仍写“23 个功能点”，属于复用旧模板。**应以 `start.S` 的 42/68 和实际有效测试入口为准**，不要根据过期 Readme 修改测试数量。
3. Lab6 `inst/` 中存在额外的 `n32_xori.S`，但其正式 `start.S` 调用的 n32 是 `sllv`，随后 n33=`srav`、n34=`srlv`。以编译入口和 `inst/Makefile` 实际链接行为为准，不要把文件个数误认为测试点数。
4. 教学提供的 `mul_tb.v` 和 `div_tb.v` 例化 `mul`、`div` 两个模块；这两个被例化的实现**没有随本次压缩包提供**。可参考测试思路，须为新 IP wrapper 适配接口，不能以“直接运行原样 testbench”作为默认前提。随机测试应固定种子，并具备有限运行时、可复现的 PASS/FAIL。
5. 当前原工程 `inst_ram` 的 XCI 深度为 **262,144×32**；两份新指令 ROM 行数低于该值。仍须验证仿真真实装载内容与地址映射，不能仅凭深度推断成功。

### 2. 需要逐项覆盖的指令

**Lab6（n24–n42，共 19 个）**：

| 模块 | 指令 |
|---|---|
| 算术与立即数、可变移位（11） | `add`, `addi`, `sub`, `slti`, `sltiu`, `andi`, `ori`, `xori`, `sllv`, `srav`, `srlv` |
| 乘除与 HI/LO（8） | `div`, `divu`, `mult`, `multu`, `mfhi`, `mflo`, `mthi`, `mtlo` |

**Lab7（n43–n68，共 26 个）**：

| 模块 | 指令 |
|---|---|
| 转移与延迟槽（16 个功能点） | `j`, `bgez`, `bgtz`, `blez`, `bltz`, `bltzal`, `bgezal`, `jalr`，以及对应的八项 `_ds` 延迟槽测试 |
| 字节、半字与非对齐访存（10） | `lb`, `lbu`, `lh`, `lhu`, `lwl`, `lwr`, `sb`, `sh`, `swl`, `swr` |

**边界约定**：与老师任务和所附测试集保持一致。是否需要实现 `add/addi/sub` 的整数溢出例外、非对齐普通 `lh/lw/sh/sw` 的地址例外等，以原版教材要求和本地测试实际使用情形核实；不要自行扩大到完整 CP0/例外系统，也不能把明确要求的行为悄悄忽略。特别区分带符号加减与 `addu/addiu/subu` 的操作语义，先核验测试宏对溢出的期望。

## 二、目录策略：一份 CPU，两套新增测试，阶段用 Git 标记

### 1. 本轮采用**最小迁移方案**（推荐且必须先执行）

当前 `.xpr`、XCI、参考 CPU、Tcl 都相互引用，直接把 Vivado 工程从 `lab3/CPU_CDE/` 整体移动，风险高、收益有限。本轮**保留现有可运行的工程实际路径**，但在根目录 README 中正式声明它是整个 Lab3–Lab7 的唯一 CPU 工作工程。

期望目录语义：

```text
lab/                                  # 现有仓库根目录（不要另建嵌套 lab/）
├── lab1/                              # 历史实验，不修改
├── lab3/
│   └── CPU_CDE/
│       ├── mycpu_verify/              # 唯一可修改的 CPU + Vivado 工程
│       │   ├── rtl/myCPU/             # Lab3–Lab7 累积修改的 RTL
│       │   ├── rtl/xilinx_ip/         # 原 RAM/PLL IP + 新乘除法 IP 的可复现定义
│       │   ├── testbench/
│       │   └── run_vivado/.../*.xpr
│       ├── cpu132_gettrace/           # 独立参考 CPU，用于生成 golden trace
│       └── soft/func_lab3/            # 历史 Lab3 测试材料
├── lab4/func_lab4/                    # 历史 Lab4 测试材料；Lab5 沿用该 CPU
├── lab6/func_lab6/                    # 新增的 42 点累计测试（原样保留来源）
│   └── ...
├── lab7/func_lab7/                    # 新增的 68 点累计测试（原样保留来源）
│   └── ...
├── scripts/                            # 扩展原有脚本，不另写平行的一套验收系统
│   ├── verify.ps1                     # -Case lab3/lab4/lab6/lab7
│   ├── run_behavioral_sim.tcl
│   ├── generate_reference_trace.tcl
│   └── ... （必要时增加 generate_trace.ps1、wave*.tcl）
├── docs/
│   ├── lab3_lab4/                     # 历史实施与验收记录，保留
│   └── lab6_lab7/
│       ├── implementation.md          # 扩展设计、数据通路与时序
│       ├── verification.md            # 所有功能与回归测试的实际证据索引
│       ├── waveforms.md               # 逐图解释信号、周期、预期及实际结果
│       ├── report_materials.md        # 可用于实验报告的文字与结果表
│       └── figures/                   # 实际导出的仿真波形截图（不是示意图）
├── results/
│   ├── lab3_lab4/                     # 历史验证结果，不删除
│   └── lab6_lab7/                     # 带时间戳的脚本结果、trace、log、WDB
├── README.md                          # 简述各 lab 与唯一 CPU 工程的位置
└── .gitignore                         # 仅排除确认可重建的临时文件
```

- 如本地已有同名路径，审查后复用，**不要覆盖用户已有修改**。
- Lab5 不另复制 `lab5/CPU_CDE`：它与原 Lab4 完成态相同，用 Git 历史提交/标签记录“前递已验收”的代码节点。
- Lab6、Lab7 可以保留各自测试资源中的重复汇编/ROM，因为它们是独立发布的测试套件；**禁止复制完整 CPU RTL、`mycpu_prj1.xpr` 和参考 CPU 工程给每个 lab**。
- 由于路径历史性地包含 `lab3`，在 README 解释这是“Lab3 起始的**累积 CPU 工程**”，**不是只能做 Lab3**。这样既清楚又不会损坏 Vivado 引用。
- 只有在 Lab7 最终通过、且用户明确愿意承担迁移回归成本时，才另行考虑把整套 CPU 工程移动到如 `cpu/` 的中性目录；**本任务禁止顺手迁移**。

### 2. Git 实施约束

1. `git status --short`、`git branch --show-current`，识别用户未提交更改；不得自行覆盖或 `reset --hard`。
2. 确认上一轮 Lab3/Lab4 验收结果和当前工作区相符，保存基线提交号与参数、工具版本；若基础尚未通过，先定位原因。
3. 新建工作分支（如 `lab6-lab7`，如已在合适的工作分支则继续）；在现有干净提交上按阶段创建可回退的 Git commit。标记 `lab5-forwarding-verified` 只能在实际对应提交存在、名称未占用时采用；不要擅自强制改写 tag。
4. 用户的 `lab1/`、历史结果证据以及原始课程测试源码必须保留。
5. 非必要不修改 SoC 及 IP 配置，不重构原有已验证的五级流水线；出现 RTL 设计取舍先记录原因，再做最小修改。

## 三、阶段 0：工作区核查与可重复的回归基线

**输入**：当前实际仓库 + 本次 `lab6-7.zip` + 已安装 Vivado 2025.2。

Codex 操作：

1. 扫描仓库，确定唯一有效 `.xpr`、CPU 源码、reference CPU、Tcl/PowerShell 实际入口及 Git 状态。**不要假设最新本地目录与旧压缩包完全一致**。
2. 确认新教学压缩包已解压至 `lab6/func_lab6/`、`lab7/func_lab7/`；若只有压缩包而本地目录没有资源，先按原相对路径解压；不得使用未声明的其他测试内容代替。
3. 检查 Vivado：`D:\Verilog\2025.2\Vivado\bin\vivado.bat`，执行 `-version`，检查 `clk_pll`、`data_ram`、`inst_ram` IP；沿用已经验证通过的 XSim/GCC 运行环境，**不要重新添加曾导致 Xelab 故障的 GCC 路径覆盖**。
4. 执行 Lab3、Lab4 forwarding 回归（必要时保留 Lab4 blocking 与 hazard-directed）；准确保存 PASS、trace hash、cycles/stalls、源码 commit。
5. 检查新增 ROM 行数、ROM 深度、COE/MIF 内容是否一致（解析为相同 32 位指令序列），并确认仿真**确实使用选定案例的 ROM**。原 `inst_ram.xci` 可能仍指向 Lab3 COE，必须解决 DUT 与 reference 的实际 ROM 映像一致性，不能仅复制文件却没让 IP 加载它。
6. 审查 `scripts/verify.ps1`：旧版本只接受 `lab3/lab4`、预期功能点写死 `23`；`run_behavioral_sim.tcl` 也限定两种 case。**先扩展脚本再开始 Lab6 指令实现**，避免功能实现后无可用的验证入口。

**交付**：`docs/lab6_lab7/verification.md` 中“起始工作区与 Lab3/4 回归证据”小节，列命令、真实 run-id、哈希、通过/失败情况。

## 四、阶段 1：升级测试基础设施（先于 RTL 开发）

### 1. 统一案例配置，不再用散落的 `if Case` 和硬编码数字

在现有 `verify.ps1` 上支持：

| Case | Instruction MIF | 期望累计功能点 | golden trace |
|---|---|---:|---|
| `lab3` | 已有 Lab3 | 23 | 历史 Lab3 reference |
| `lab4` | 已有 Lab4 | 23 | 历史 Lab4 reference |
| `lab6` | `lab6/func_lab6/obj/inst_ram.mif` | 42 | **新生成、独立保存** |
| `lab7` | `lab7/func_lab7/obj/inst_ram.mif` | 68 | **新生成、独立保存** |

同一脚本入口支持 `-Case`、`-PipelineMode forwarding|blocking`、`-ReferenceTrace`、`-MaxSimulationNs`、`-TimeoutSeconds`，保留既有行为兼容性。新增案例默认 forwarding；blocking 作为有意义的性能/正确性对照，**若多周期算术在纯阻塞模式尚未支持也要如实标记，不能把失败说成通过**。

### 2. golden trace 的来源与完整性

必须采用**独立参考 CPU**，例如现有 `lab3/CPU_CDE/cpu132_gettrace/`，加载与 DUT 完全相同的 Lab6/Lab7 ROM 生成 reference trace；**严禁用 DUT 的写回行为生成 DUT 自己的 golden trace**。

原 `generate_reference_trace.tcl` 已支持传入期望点数，但默认 `23`、仿真时间旧值固定为 5,000,000 ns；应扩展为 case 参数、可配置的仿真时间/超时。注意 `.xci` 中 COE 相对路径与 IP 初始化缓存，**在隔离工作副本中切换 reference ROM，不修改原有 Lab3 reference 资源**。

每次 trace 生成与 DUT 验收保存：

- ROM 源 MIF、参考 COE、仿真实际加载 MIF 的 SHA-256，解析后指令字一致性；
- reference trace 路径、非空条目数、哈希及参考 CPU 的 42/68 点功能通过证据；
- DUT trace 全部匹配数、无剩余记录、通过所有功能点、明确结束标志；
- Vivado/Xvlog/Xelab/XSim 原始日志、命令、源提交号、时钟周期统计。

如果参考 CPU 不支持新 ROM、或参考 trace 获取失败，**停止该阶段并提交准确失败记录，不能以跳过 trace 校验继续宣称验收 PASS**。

### 3. 运行时与 PASS 判据

新增测试远长于原 Lab3；避免把“仿真达到设置时限”误记为 PASS。自动脚本必须支持合理的可调整最大仿真时间与系统级 watchdog，并识别：

- `Test end!` 和课程最终 `----PASS!!!`；
- Lab6 **42** / Lab7 **68** 个实际功能点；
- 独立 golden trace 的正确打开、逐条比较、末尾无剩余；
- 不能出现 `TRACE_MISMATCH`、`Error!!!`、`Fail!!!`、IP 仿真错误或模块断言失败；
- 正常进程退出**并不能替代**上述判定（testbench 的 `$finish` 在失败路径也可能发生）。

建议添加防止“只跑完 23 点就提前退出”的最后阶段条件校验，并把 `TEST_NUM` 与 `confreg` 功能点递增结果记录在摘要里。

**阶段验收**：新 case 的配置、文件定位、ROM 哈希和 reference 生成入口可以独立运行；Lab3/Lab4 仍通过。Lab6/7 此时因为 CPU 尚不支持新增指令，功能失败属于**预期**，不得伪造 PASS。

## 五、阶段 2：Lab6 算术逻辑指令（n24–n34）

按实际 RTL 的数据流逐一对齐：**ID 译码和源寄存器使用 → 相关检测与前递 → ID→EX 控制总线 → ALU 计算 → 目的寄存器写回**。

- `add/addi/sub`：区分有符号运算与 `addu/addiu/subu`；按教材/测试的溢出语义做合理边界处理；不要在未确认例外要求时擅自增加 CP0。
- `slti/sltiu`：16 位立即数都按 MIPS 规则符号扩展，再分别按**有符号/无符号**进行比较；不是 `sltiu` 使用零扩展立即数。
- `andi/ori/xori`：16 位立即数**零扩展**。检查现有 EX `src2_is_imm` 是否默认符号扩展，必须为这类指令增加准确的立即数类别控制。
- `sllv/srlv/srav`：移位量为寄存器 `rs[4:0]`，待移位数据为 `rt`；`srav` 算术右移要保留符号扩展。与旧固定 `sa` 移位区分。
- ID 阶段更新每种指令的 `rs_used/rt_used`、destination 及 `gr_we`；EX/MEM/WB producer bus 的 `valid/ready/dest/value` 必须保持正确，避免新增指令绕过 RAW 检测。
- 禁止继续让不支持的 opcode 因旧的 `gr_we = ~...` 逻辑被误标记为 GPR 写回。应显式定义合法写回指令集合，同时保证原 23 条行为不变。

**先做短定向测试**：立即数 `0x8000` 和 `0xFFFF`、有/无符号比较、`rs[4:0]` 与无效高位、EX/MEM/WB 前递及 load-use；之后按累计 Lab6 测试定位失败点。

**阶段验收**：n24–n34 定向正确；旧 Lab3/Lab4 仍 PASS；对尚未完成的 n35–n42 如实记录未通过。

## 六、阶段 3：Lab6 乘除法 IP、HI/LO 与多周期流水线

### 1. 设计前必须确认的时序契约

拟在既有 EX 附近增加模块（名称可依项目现状而定）：`mul_unit.v`、`div_unit.v` 或一个简洁的 `hilo_unit.v`。可以使用 AMD/Xilinx Multiplier/Divider IP，不必自行实现乘除法算法。

**先在 Vivado 2025.2 中通过 Tcl 或 GUI 试建 IP，检查实际 `.xci`/例化模板和接口**，确认：

- 输入与输出位宽：32×32 → 64 位 product；divide quotient 与 remainder 各 32 位。
- 有符号与无符号路径。允许采用一个满足两类语义的 wrapper，也可采用分开的 signed/unsigned IP；选择实现与资源成本合理、便于验证者。
- 延迟固定还是变长；是否存在 valid/ready；复位时/错误时结果能否丢弃。
- 哪个时钟沿接收请求、何时输出有效，是否可以发起下一请求。
- IP 仿真模型是否可在 XSim/Xelab 中编译展开，不只检查 IP 名称存在。

乘法一种可行选项是将 32 位 signed/unsigned 操作数按运算模式扩展到 33 位并执行有符号乘法后取低 64 位，但必须核对 IP 配置和实际输出位宽；不要假定所有 Vivado 乘法 IP 都直接支持这一动态模式。除法可以配置 signed/unsigned 两种运算路径，或在 wrapper 做绝对值及符号恢复；**选择其中一种简单、可验证的实现，不要双套过度封装**。精确接口以自动生成的 IP 模板为准，不要编造接口端口。

参考 `lab6/乘法器模块级验证顶层/mul_tb.v`、`div_tb.v` 中的随机/参考值思路，但需要为具体 IP wrapper 写可复现实测 testbench（原例化模块缺失，随机时序/复位/除零情况也须审查）。保留实测 PASS 日志与代表性波形。

### 2. HI/LO 与 CPU 阶段衔接

使用两个 32 位 HI、LO 寄存器（位置可在 EX 或独立简洁模块中，须有唯一写入所有权），按 MIPS 语义：

- `mult/multu`：64 位乘积的高/低 32 位写入 HI/LO。
- `div/divu`：余数写 HI、商写 LO。signed 情况商按向零截断，余数符号跟随被除数；除零/溢出行为按本次教材/测试实际约定处理，不凭空宣布确定结果。
- `mfhi/mflo`：将 HI/LO 的**最新、正确版本**写回指定 GPR。
- `mthi/mtlo`：从 GPR `rs` 更新指定特殊寄存器，其余特殊寄存器保持原值。

**关键不是算数功能，而是多周期事务与顺序性：**

1. 乘除指令进入 EX 并完成操作数锁存，向 IP 发起请求**恰好一次**。
2. 在 IP 完成前 `es_ready_go=0`（或等价握手），使当前 EX 指令无法继续推进；ID/IF 随 `es_allowin` 停顿，MEM/WB 允许更老指令继续退休。不得反复向 RAM 发出写请求，也不得让乘除 IP 重复启动。
3. IP 返回有效结果后，根据指令 signed/unsigned 类型写 HI/LO 一次；当前 EX 指令仅可推进一次，解除停顿。应明确 commit 边界、复位取消、下一次请求启动条件。
4. 必须检查后继 `mfhi/mflo`、`mthi/mtlo` 的数据相关与写入次序。若 HI/LO 在 EX 使用/更新，则后继指令必须按程序顺序进入 EX；**不能在 ID 过早读取旧的 HI/LO 值**。连续 `mult → mflo`、`div → mfhi`、`mthi → mfhi`、`mtlo → mflo` 等必须定向验证。
5. 关注 `mfhi/mflo` 写 GPR 后紧跟 `beq/jr/sw` 的普通 GPR RAW 相关；`mult/div` 自身一般不写 GPR，但会写特殊寄存器，不能把所有乘除相关简单归入原有 GPR scoreboard。
6. 现有 ID 分支重定向 `br_taken` 原先可能只依赖 `ds_ready_go`；EX 多周期停顿时要确保 **branch 仅在指令能被下一级接收时生效，避免相同 branch 在多个时钟重复改 PC、破坏延迟槽**。务必增加针对“EX 正在做除法，ID 等待的是 branch/jump”的定向测试。
7. `PIPELINE_FORWARDING=0/1` 应继续有定义良好的行为，勿使新 HI/LO 模块与前递开关产生意外耦合。

建议最小化总线扩充：将必要的操作类型、GPR 目的和数据按字段有序随 pipeline bus 传递，并**统一核算每条总线的位宽及打包、解包位置**；不允许 magic bits 或截断。不要为了少改总线而在错误阶段重取指令或复用易变的 ID 操作数。

### 3. 乘除法定向测试矩阵

至少包含：正/负乘法、无符号高位乘积、零乘、signed/unsigned 除法、余数正负、连续乘除、背靠背 HI/LO 读取、HI/LO 写覆盖、复位中断、多周期 EX 停顿期间 IF/ID 保持、前递给乘除操作数，以及请求只启动一次、结果只提交一次。按规范适当避开未规定的除零行为，另将其作为已定义范围或限制说明。

**阶段验收**：模块级 IP testbench PASS；Lab6 共 **42/42** 功能点通过；Lab6 独立 reference trace 全部匹配；Lab3/4 回归通过，保存乘/除/HI-LO 的 WDB 与截图材料。

## 七、阶段 4：Lab7 转移指令（n43–n58）

继续使用当前延迟槽语义：转移指令在 ID 完成条件判断与 PC 目标计算，但紧随的 **一条 delay-slot 指令仍须执行一次**，不能按无延迟槽体系误处理。

- `j`：`{(PC+4)[31:28], instr_index, 2'b00}`，与 `jal` 的目标生成一致，但不写 `$ra`。
- `bgez/bgtz/blez/bltz`：以有符号 `rs` 判定零、正负；不是比较二进制大小的无符号条件。
- `bltzal/bgezal`：除条件分支还涉及链接寄存器 `$ra` 与 `PC+8`、taken/not-taken 语义；**按 MIPS 版本和配套测试宏准确核对链接写入条件**，避免主观假设。
- `jalr`：由**旁路后的** `rs` 指向跳转目标，链接写回指令规定的 `rd`（通常 `$ra`，但不能写死），值 `PC+8`。
- 所有新增 branch 参与 `rs_used` 及 RAW hazard；`j` 不凭空读取寄存器。
- 对照现有 `br_bus`、IF/ID 握手与 `ds_pc`，确保 branch stall 不重复发出重定向；同时覆盖 taken/not-taken、delay-slot 正确执行、目标地址、链接寄存器及 EX 多周期阻塞的交互。

**阶段验收**：新分支独立短程序正确；n43–n58 课程用例逐个正确；Lab6 累计用例保持通过。

## 八、阶段 5：Lab7 访存指令（n59–n68）

本工程使用 32-bit data RAM、**小端字节顺序**及 `data_sram_wen[3:0]` 字节写掩码；`soc_lite_top.v` 的 `data_ram` 以 `data_sram_addr[17:2]` 选择字，RAM IP 的 `Use_Byte_Write_Enable=true`。不能只增加指令译码，必须改写 MEM 数据选择、EX 写掩码和 store data 字节排列。

### 1. 基本宽度与扩展

- `lb/lbu`：用低两位地址选 byte lane；`lb` 符号扩展，`lbu` 零扩展。
- `lh/lhu`：按地址位 1 选择 16-bit 半字；`lh` 符号扩展，`lhu` 零扩展。合法对齐与异常需求按教学范围确认。
- `sb/sh`：`data_sram_wen` 根据有效地址低两位生成对应 1/2 byte 掩码，`data_sram_wdata` 相应左移/复制，使有效 lane 获得预期值；例如小端 `sb` 写入 `addr+1` 应写 word 的 `[15:8]`，不是始终 `[7:0]`。

### 2. 非对齐访存

- `lwl/lwr`：根据 `addr[1:0]` 选择内存 word 的有效片段，并与**旧 rt 值**合并成 32 位结果。原 `lw` 仅读 `rs`，但 `lwl/lwr` 还需要 `rt` 旧值，是读写同一 GPR 的 read-modify-write 指令。必须把 `rt` 纳入源寄存器检测与前递、在正确阶段携带旧值，不能只从寄存器堆读取未经旁路的旧数，也不能将它当作普通完整 32-bit load。
- `swl/swr`：根据低两位地址产生不同的写字节掩码及旋转/移位后的 store 数据；保证只写需要的字节，邻近字节保持原值。已有 `sw` 的源值前递也要用于这些指令。
- 针对所有 `addr & 3 ∈ {0,1,2,3}` 分别建用例，包含 `lwl/lwr` 连续配对、来自 EX/MEM/WB 的旧 `rt`、紧跟消费者、写入后 `lw` 复核未修改字节；交叉验证小端实际内存图。
- 对同步 BRAM 读延迟、`ms_final_result` 前递与写掩码生效时钟进行完整时序核对，禁止用组合读取幻想替代 BRAM 真实时序。

**特别注意**：当前 `EXE_stage.v` 的 `data_sram_wen` 只有 `4'hf` 或 0，`MEM_stage.v` 把所有 load 数据当作整字使用；因此这些模块必须做真实数据通路扩展。还需检查 bridge/CONFREG 的地址分配，避免 byte-lane 变更破坏已有 `sw/lw` 与课程成绩寄存器。

**阶段验收**：n59–n68 独立定向测试正确，**Lab7 累计 68/68** 功能点通过，Lab7 参考 trace 完全匹配，Lab3/Lab4/Lab6 回归仍通过。

## 九、波形证据：必须真实、可复现、与报告逐图对应

老师明确要求“添加指令的功能测试有波形分析”。因此不是只保留 `.wdb` 或终端 PASS，也不能绘制几张想象的时序图当成真实运行。

### 1. 建议收集的至少 8 类波形

| 图文件名（建议） | 指令/场景 | 应当展示的关键逻辑 |
|---|---|---|
| `01_alu_immediate.png` | `andi/ori/sltiu` | imm 扩展类别、rs 操作数、ALU 结果、WB 写回 |
| `02_variable_shift.png` | `sllv/srav/srlv` | `rs[4:0]` 移位量、rt 数据、有符号位变化、WB |
| `03_mult_hilo.png` | `mult/multu→mfhi/mflo` | IP 输入握手、乘积有效、HI/LO 更新及 WB |
| `04_div_stall.png` | `div/divu→mflo` | EX 持有、IF/ID 暂停、complete、HI/LO 更新、只提交一次 |
| `05_branch_delay_slot.png` | `bgez/bgtz/bltz` 或 `jalr` | ds_pc、taken/target、顺序 delay slot、跳转后 PC、链接值 |
| `06_byte_half_load.png` | `lb/lbu/lh/lhu` | 有效地址、内存返回 word、符号/零扩展、WB |
| `07_byte_store.png` | `sb/sh` | addr[1:0]、`data_sram_wen`、`data_sram_wdata`、后续读回 |
| `08_unaligned_merge.png` | `lwl/lwr/swl/swr` | byte offset、旧 rt、合并结果或 byte enable、写回/读回 |

原则：一张图展示**少量相关周期**，不要截取整段上百万周期的全景波形。数据信号请显示十六进制；时间尺度、信号层次和关键沿需要清楚可读。

### 2. 文件和图文对照

- 保存真实 `.wdb` 与 testcase / commit / rom-hash 关联，生成可供用户在 Vivado GUI 打开的波形配置（如 `.wcfg`）；由 GUI 导出 PNG（若批处理可真实导出也可自动化），不可通过静态示意图替代。
- `docs/lab6_lab7/waveforms.md` 对每张图逐项说明：**测试指令及地址 → 输入及期望结果 → 哪个周期开始/完成 → 关键握手/停顿/前递或字节选择 → 实际写回 → 正确性判定**。
- 若本机 Codex 无法操控 GUI 导出图片，应当保留 WDB、WCFG、截图指令和应选择的时间窗口，向用户说明需要亲自完成的最少截图操作；**必须将“尚未截图”标记为待人工验收，不能宣布波形材料完整**。
- 编写 `report_materials.md` 时只使用实际通过的日志与波形证据，波形上精确的 PC、数据、周期请从仿真提取，不能构造数字。

## 十、回归矩阵与最终 PASS 门槛

| 用例 | 目标 | 必须留存的证据 |
|---|---|---|
| Lab3 forwarding | 原 23 条未回退 | 23/23 + 独立 trace + 原始日志 |
| Lab4 forwarding | 相关与前递未回退 | 23/23 + trace + cycles/stalls |
| 原 hazard-directed | EX/MEM/WB 前递、load-use、branch、store | 用例 PASS + 冲突计数 |
| Lab6 ALU directed | 新 11 条 ALU 指令边界 | 指令/输入/预期/实际数据记录 |
| mul/div wrapper unit | signed/unsigned、延迟、复位、结果唯一提交 | 模块级 self-checking PASS + WDB |
| Lab6 forwarding full | 累计 42 点 | **42/42 + 独立参考 trace 全匹配 + WDB** |
| Lab7 branch directed | 分支正反、链接值、delay-slot、EX 停顿交互 | 指令级判定 + WDB |
| Lab7 memory directed | byte/half/unaligned 四种 offset、小端 | RAM byte enable、读回与 GPR 数值断言 + WDB |
| Lab7 forwarding full | 累计 68 点 | **68/68 + 独立参考 trace 全匹配 + WDB** |

如果任务指定前递作为 Lab5 基础，最终的主验收路径必须是 `PIPELINE_FORWARDING=1`；可补充 `PIPELINE_FORWARDING=0` 来证明冲突策略无回退，但不能以 blocking 代替 forwarding。

**推荐命令接口（由 Codex 在现有脚本中实现，以下并非当前已存在的功能）：**

```powershell
# 查看安装环境；Windows 本地 PowerShell 或可实际访问该目录的 Codex 环境
& 'D:\Verilog\2025.2\Vivado\bin\vivado.bat' -version

# 先复用原有验证入口：
.\scripts\verify.ps1 -Case lab3 -PipelineMode forwarding
.\scripts\verify.ps1 -Case lab4 -PipelineMode forwarding

# 扩展脚本后再执行。时限依真实运行状况合理设定，不能视为保证通过：
.\scripts\verify.ps1 -Case lab6 -PipelineMode forwarding -MaxSimulationNs 20000000 -TimeoutSeconds 1800
.\scripts\verify.ps1 -Case lab7 -PipelineMode forwarding -MaxSimulationNs 30000000 -TimeoutSeconds 2400
```

新脚本应提供单独的**参考 trace 生成入口**，例如 `scripts/generate_trace.ps1 -Case lab6|lab7`；如果使用其他名字，应在 README 与 verification 中列出**实际可执行命令**。不得声称一个尚未实现的脚本已可运行。

## 十一、Codex 实施节奏与每阶段报告

请按以下顺序推进，**每一阶段完成后先完成整个阶段的检查、提交与简洁报告，再进入下一阶段**：

1. **S0 基线**：核查工作区、目录与旧回归，创建合理 Git 工作分支；原文件保护与项目导航文档。
2. **S1 验证基础设施**：把 case/点数/ROM/trace/timeout 参数化；独立生成并验证 Lab6/7 golden trace（若当前 reference CPU 可完整执行），留存验证证据。不得用 DUT 输出伪造参考。
3. **S2 新算术指令**：n24–n34 的 decode、立即数、移位、RAW 前递，完成定向测试和旧回归。
4. **S3 乘除法**：IP 配置与模块级自检；HI/LO；多周期 EX 停顿；n35–n42；Lab6 42/42。
5. **S4 新转移**：n43–n58，延迟槽/链接/停顿交互，完成定向测试。
6. **S5 新访存**：n59–n68，byte/half/unaligned 数据通路、对齐/合并、前递，Lab7 68/68。
7. **S6 最终验收与报告材料**：所有回归、trace、波形、截图/人工检查单、目录与 Git 交付审查。

每阶段回应要求（写入 `docs/lab6_lab7/verification.md` 并在回复中精简汇报）：

- 实际变动了哪些文件、为何要改、是否更改了阶段接口/总线宽度；
- 本地确切命令、真实 PASS/FAIL、执行耗时、日志与 commit；
- 若失败：首个失败 opcode/PC、关键寄存器值、预期与实际、失败归属（RTL/IP/ROM/trace/仿真环境）；
- 用户需要操作 Vivado GUI 时：给出逐步按钮、文件路径和目标信号，不泛泛要求“自己检查”；
- 未实现/未验证功能不得称完成。

## 十二、禁止事项与必要取舍

- **不要**新建 Lab6、Lab7 两套 CPU RTL；**不要**删除历史 Lab3/Lab4、Lab1 工程。
- **不要**大量复制或移动 `.xpr`、XCI 和引用它们的相对路径；保持本轮唯一可运行 Vivado 工程。
- **不要**为了让测试通过去篡改课程汇编、测试宏、功能点判断、参考 CPU 逻辑、参考 trace 或 `inst_ram` 指令内容；允许用于诊断的独立 directed 测试应显式命名并与课程原测试区分。
- **不要**把 `xvlog`、`xelab` 成功误判为 CPU 功能正确；也不要把 XSim 打开波形误判为所有用例通过。
- **不要**假设新的 IP 在 Vivado 2025.2 中已经创建好；必须生成 `.xci`、连接到工程，保留可复现的创建/生成配置与必要的仿真源。**不要直接编辑生成的 IP 网表**。
- **不要**强行选择某种乘/除法 IP 接口：先查实际支持能力、 latency/valid 协议与仿真模型，再决定 wrapper；若设计取舍影响流程或需要付出明显工程代价，向用户说明选项后再继续。
- **不要**提前宣布“波形截图齐全”：`figures/` 必须有真实图；缺图则明确待人工配合。
- **不要**无差别删除生成文件。可剔除可重建缓存，但保留 IP 定义、初始化文件、报告必需 WDB/日志以及复现方法。

## 十三、最终交付清单

- **唯一累计 CPU 工程**能在 Vivado 2025.2 中正常打开，并在 XSim 完成 Lab6 和 Lab7 累计功能测试。
- 新增指令的 RTL、必要的乘除 IP `.xci`、wrapper 与模块级 testbench、自动化脚本、MIF/COE/trace 关联均可复现。
- `README.md` 准确解释 Lab3–Lab7 的关系、实验入口与测试套件，Lab5 作为历史 Git 节点记录。
- `docs/lab6_lab7/implementation.md`、`verification.md`、`waveforms.md`、`report_materials.md`，以及至少 8 类**真实截图**或明确剩余人工截图清单。
- `results/lab6_lab7/` 的实际完整日志与少量有代表性的 WDB。禁止仅凭“预计能通过”填报 PASS。
- 测试矩阵全部合格；Git 状态可解释，无非预期大体积生成文件；不改变用户历史 Lab1/3/4 资源。

**停止规则**：若 S0 的旧 CPU 基线无法复现、参考 CPU 无法产生独立 golden trace、IP 模型不能在 XSim 运行，或者课程用例与书本定义产生实质冲突，先保存完整诊断信息，向用户报告需要选择的事项；不通过改写测试或更换架构来掩盖问题。
