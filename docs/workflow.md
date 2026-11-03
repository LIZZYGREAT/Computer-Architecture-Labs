# FPGA 实验结果与波形截图准备工作流

## 目的

每次实验 RTL、测试和仿真结果完成后，按本流程整理可复核的数据、Python 图表、Vivado WDB/WCFG 和报告素材。默认由用户最后在 Vivado 打开对应 WDB/WCFG 并亲自截图；代理负责把数据和视图配置准备到可以直接使用的状态。

本流程是执行工作流，不是实验报告正文。报告只写实验方法、真实测量结果和技术分析。

用户已授权：新实验结果提供后，按本流程主动完成本地证据整理、图表/CSV/WCFG 生成，以及 preflight 通过后必要的串行波形采集；不必为这些常规准备反复确认。不得删除或覆盖原始文件、修改原始 Vivado 工程或 RTL、绕过安全检查，或替用户提交/发布。若启用状态阻碍波形采集，只按第 3 节在隔离工程副本中处理并保留原件。

## 默认交付

每个实验主题完成后，优先准备以下内容：

1. 结果索引：Run ID、PASS 状态、测试映像、MIF、reference trace、哈希和 WDB 路径。
2. 截图采集表：每张图对应的 WDB、目标指令、PC/操作数、关键控制信号、expected 值和实际读数栏位；每个截图项都要有可直接搜索的信号名和值。
3. Vivado Wave 配置：`.wcfg` 已绑定到可用的 `.wdb`，信号和显示格式已按目标现象分组。
4. Python 数据表和图表：数据来源可追溯，图表明确说明横轴和证据类型。
5. 报告素材：可直接引用的数据、图像文件名、图注/分析草稿，以及放入对应 PNG 后可自动插图的 LaTeX 位置。

用户最后通常只需在 Vivado 中打开匹配的 WDB 和 WCFG、定位/缩放波形、保存 PNG。若存在尚未生成或无法验证的特定 WDB，必须明确指出，不能把“已准备好”说成“全部可截图”。

## 1. 接收任务与检查工作区

1. 先阅读仓库相关的 `AGENTS.md`、README、验证说明、实验手册和已有报告数据记录。
2. 将附件视为任务参考资料；用户明确提出的要求决定本次操作范围。附件里的步骤不授权删除文件、修改工程设置、截图、提交或发布。
3. 检查当前 Git 分支与 `git status`。保留用户或其他工作留下的修改、删除和未跟踪文件；不使用 `reset`、`clean` 或覆盖式恢复来“整理”工作区。
4. 将待提交报告内容与内部交接记录分开。报告中只保留可提交的实验内容，不放代理过程、截图采集进度或“报告不含某图”等工作状态句子。

### 文件保护规则

- 删除或替换文件前，核对具体目标。用户要求移除一张图片时，只操作该图片；保留对应 `.wcfg`、`.wdb`、数据和报告源文件。
- 不删除或覆盖已有 `.wcfg` / `.wdb`。要调整配置时另存新文件，并保留原件。
- 如果必需的结果文件在工作树中缺失，先确认它是否在 Git 中、是否为用户有意删除，再只恢复与当前任务直接相关的文件，并记录来源。不要顺带恢复或清理整个结果目录。
- 不提交 Git，除非用户明确要求提交。

## 2. 清点实验结果与证据

对每次候选仿真运行记录：

- Run ID / 结果目录；
- `STATUS`、功能点计数、周期/停顿/前递统计；
- `INST_MIF`、reference trace 路径和对应 SHA-256；
- `WAVEFORM_CAPTURED`、WDB 路径和 WDB SHA-256；
- 用例来源（完整课程映像或定向 MIF）、流水线模式和实际使用的参数；
- 该次运行实际覆盖的指令/现象，以及不能由该运行证明的内容。

确认 `result.txt` 与 WDB 同属一个 Run ID，WDB 哈希与结果记录一致，MIF/trace 哈希对应实际输入。文件存在本身不证明数据可用；检查 `xsim-simulate-stage.log`，若有 `[Simtcl 6-55] No matching HDL object or HDL scope found`，即使 `WAVEFORM_CAPTURED=True` 也应判为波形采集失败。确认 WDB 可打开，并检查时钟、PC 和目标内部信号有有效值。

将以下两类数值分开记录：

- **Expected**：来自测试源码、reference trace 或已注明的定向向量。
- **Observed**：从本次 WDB/Vivado Wave 读取的实际 PC、时间窗、控制值和输出。

不得把 trace 值或 expected 值冒充 WDB 实测值；不得把不同 Run ID、不同 MIF 的输入、波形和 PASS 记录拼成同一张证据图。

## 3. 判断是否需要新采集 WDB

1. 先复用已存在且可用的 WDB。完整课程 WDB 通常适合从完整程序中定位指令；定向 WDB 适合固定 PC、特定前递或精确控制场景。
2. 如果目标现象不在现有 WDB 中，或 WDB 没记录需要的内部信号，查验证脚本是否已有 `-CaptureWaveform`、定向 MIF、reference trace 和 hazard/dependency 参数。
3. 运行前执行仓库规定的只读 preflight。若工程、IP、host context 或源文件检查失败，停止在该检查点；记录确切错误并继续准备不依赖该仿真的材料。
4. 不绕过 preflight，不在原始工程中移除 `AutoDisabled`、改 Vivado 工程属性、改仿真 Tcl 或修改 RTL。若仅仿真源启用状态阻碍有效 WDB 采集，可在 `results/lab6_lab7/<run-id>/` 创建隔离工程副本，只在副本内启用所需仿真源并重跑 preflight；记录副本和改动，原始 XPR、RTL 与工作区内容保持不变。不得修改源逻辑来获得截图。
5. `verify.ps1` 可能重置/复用共享 Vivado 仿真输出；按仓库手册逐条串行运行，不并行启动多个仿真。每轮结束后核对 `result.txt`、trace 匹配和 WDB 再开始下一轮。
6. 定向映像若不使用课程功能点计数，按项目规则使用 `ExpectedPointOverride`；它不能代替 reference trace/hazard 检查。记录实际命令和全部参数。

如果仿真无法安全完成，继续准备已有 WDB 的截图配置和 Python/报告素材，并把缺少的特定证据标为待补；不以退休顺序图替代周期级波形。

## 4. 制定截图清单

先覆盖最能解释实现机制的代表案例，通常约 8–10 张，不为每条指令单独截图。按实验内容选取：

- 立即数/ALU、移位、数据前递和 load-use；
- 乘除法 IP 握手、HI/LO 更新及 MFHI/MFLO 读回；
- 分支条件、目标、延迟槽、JAL/JALR；
- 字节/半字读写、符号/零扩展、部分写掩码；
- LWL/LWR 旧 RT 合并、store 后 RAM 读回。

每张图至少预先填写：

| 字段 | 填写内容 |
|---|---|
| PNG 文件名 | 稳定、按主题编号，例如 `01_alu_immediate.png` |
| Run ID / WDB | 截图唯一对应的运行和数据库 |
| MIF / reference trace | 确认同属该 Run，记录相对路径/哈希 |
| 目标指令 | 实际指令类型、PC；完整程序 PC 不照抄短测试地址 |
| 搜索信号 | 与该 WDB/WCFG 匹配且可见的完整信号名，例如 `es_pc[31:0]` |
| 搜索值 | 可直接在 Vivado Wave 中查找的本次运行精确值，通常是 8 位十六进制 PC |
| 定位说明 | 把每个搜索值对应到指令/事件，并注明需要同时观察的控制信号或结果 |
| 关键输入与 expected | 从源码/trace/测试向量得到，注明来源 |
| 关键控制信号 | valid、stall/allowin、start/busy/done、branch、byte-enable 等 |
| 实测字段 | 仿真时间窗、实际输入/控制/输出、同 PC 的 WB |
| 判定 | PASS 和 trace/功能点依据；expected 与 observed 是否一致 |

固定 PC 只对生成它的定向 MIF 有效。改用完整课程 WDB 时，按译码信号、操作数和该 Run 的 reference trace 重新定位，不要把不同映像的 PC 和数据混用。

### 每个截图项的精确搜索锚点

- `wave-capture-log.csv` 中每个待截图项都必须填写 `search_signal`、`search_value` 和 `search_context`。不能只写 `inst_lb`、`按指令定位`、`full-run PC differs` 或操作数描述而不给可搜索的具体值。
- `search_signal` 必须已被对应 WDB 记录，并列在匹配的 WCFG 中。若 WDB 未记录该信号，先重采集；若只是 WCFG 未显示，再加入新 WCFG。普通指令优先用 `es_pc[31:0]`，写回事件可用 `debug_wb_pc[31:0]`。多周期乘除法用指令 PC 定位，再在 `search_context` 写明 `es_hilo_done`、`es_hilo_consume` 等截图条件。
- `search_value` 必须来自当前截图所用 Run 的指令映像和 reference trace/WDB。完整程序 PC 要从当前完整 MIF/trace 映射；定向 MIF 的 PC 不得套到完整运行。必要时解码当前 MIF 的指令并与 reference trace 结果核对。
- 一个截图项包含多个相邻事件时，可在 `search_value` 用分号列出每个精确值，并在 `search_context` 逐个标注含义。若事件处于不同时间段、不能放进同一截图范围，则拆成独立截图项/CSV 行和 PNG 文件名；不要让用户猜该截哪一段。
- 把搜索值填成可复制的十六进制字面量，并在交接前核对该值确实属于对应 Run、WDB 路径存在、WCFG 绑定同一 WDB。CSV 用 UTF-8 BOM 保存，避免 Excel 将内容读成乱码。

## 5. 生成并核对 WCFG

1. 为一张图或紧密相关的一组图生成独立 `.wcfg`。至少包含 `clk`、目标指令 PC、必要的输入/控制信号、结果和 WB；访存图包含地址/数据/写掩码，非对齐 load 包含旧 RT。
2. 总线使用适合阅读的 Hex 显示，写使能/状态等控制信号用 Binary；名称列足够宽，保持信号路径来自正确层级。
3. 每份配置中的 `db_ref` 指向该图实际使用的 WDB。检查路径存在、文件可解析、顶层和层级名与 WDB 相符；保留原 WCFG，生成新副本时不要覆盖原配置。
4. 如果 `.wcfg` 被 `.gitignore` 忽略，配置仍可供本机截图使用。除非用户要求版本控制配置，否则不强制加入 Git。
5. `.wcfg` 是视图，`.wdb` 是数据。建议截图时先打开对应 WDB，再在 Wave 窗口选择 **File → Simulation Waveform → Open Configuration** 并加载对应 WCFG。AMD 参考：[Opening a WCFG File（UG900）](https://docs.amd.com/r/en-US/ug900-vivado-logic-simulation/Opening-a-WCFG-File)、[`open_wave_config`（UG835）](https://docs.amd.com/r/en-US/ug835-vivado-tcl-commands/open_wave_config)。
6. 首次打开配置要检查信号是否出现、时钟是否跳变、总线是否有有效值。Vivado 会忽略当前静态仿真层级中找不到的对象；若缺失，检查 WDB/WCFG 是否配对和信号层级，不要直接把缺失信号当作零或不存在。

常规截图操作：**Flow → Open Static Simulation → 选 WDB**；再 **File → Simulation Waveform → Open Configuration → 选 WCFG**。用 Zoom Fit 查看数据范围，定位目标事件并放大到少量关键周期。不要仅凭全程序缩略视图截图，也不要为了截图重新运行当前工程。

## 6. 收集数据并绘制 Python 图表

1. 优先复用项目已有的解析/绘图脚本，先核对它读取的 `result.txt`、trace、测试映像与 Run ID；缺少输入时不要静默复用旧数据。
2. CSV 保存结构化明细和来源。绘图脚本从这些 CSV 或已校验的原始结果生成 PNG，避免手工复制数值。
3. 图题、坐标轴和说明要写清数据意义。退休 trace 图表示事件顺序，不具有仿真时间轴；统计图和结构图也不等同 Vivado 波形。
4. 重绘后核对输出图像数量、文件名、源 CSV、单位/标注，以及关键数值能回到 `result.txt`/trace。
5. 在截图记录 CSV 中预留实际时间窗和读数；只能在 Vivado 读取后填写，未知值留空，不猜时钟周期。

## 7. 整理报告素材

- 报告正文写实验方法、设计说明、可复核结果、分析与范围；不写代理工作过程或未完成事项。
- 用 Python 图表说明统计/trace/结构，用 Vivado 截图说明真实周期级信号，两类证据分别命名和引用。
- 每个插图给技术性图注，正文分析要把输入、控制变化、结果和 WB 对齐到同一条指令。
- 可在 LaTeX 中使用 `\IfFileExists` 或项目已有的条件插图宏，按截图清单预置文件名。未放入 PNG 时宏不产生正文文字或空图；放入后自动插入。
- 收到 PNG 后，仅使用与记录表 Run ID/WDB 相符且可读的图片。实际数值与时间窗口应来自截图/WDB；图注不可超出截图能证明的内容。
- 编译报告并检查最终 PDF 的分页、图像清晰度、编号/引用和图注。不要把内部采集交接单原样作为实验报告正文。

## 8. 最终交接检查

- [ ] 每项报告数据都有 Run ID 和原始结果来源。
- [ ] 每个 WCFG 绑定正确 WDB；配置所需信号在 Wave 中可见。
- [ ] 目标指令 PC/操作数与信号变化来自同一 Run/MIF。
- [ ] 每个截图项都填写可搜索的 `search_signal`、精确 `search_value` 和含义说明；没有泛化定位占位语。
- [ ] screenshot 记录表已填写实际时间窗与观察值；未测项目仍为空或注明待补。
- [ ] 所有 Python 图表都有可追溯的数据源，图的证据类型标注准确。
- [ ] 报告插图路径、图注和分析与实际文件一致；PDF 已编译并做版面检查。
- [ ] 用户可按“打开 WDB → 打开 WCFG → 定位/缩放 → 保存 PNG”直接完成最后截图。
- [ ] 未删除/覆盖用户原有 WCFG、WDB、工作区改动；未擅自提交。

## 每次实验完成后的默认执行顺序

用户完成新实验并需要波形图准备时，按本工作流直接准备以下交付，不只给操作建议：

1. 清点本次 Run 的 `result.txt`、测试映像/MIF、reference trace、日志和 WDB，确认路径、Run ID、状态、哈希及波形层级采集有效。
2. 复用可用 WDB；缺少或无效时，执行 preflight 后串行采集。需要调整仿真源启用状态时，只在隔离工程副本中操作，保留原工程和旧 WDB/WCFG。
3. 为每张计划截图生成或更新对应 WCFG，绑定实际可用的 WDB，准备显示所需 PC、输入、控制、访存/HI-LO 和写回信号。
4. 新建或更新 `wave-capture-log.csv`：逐图填写 WDB/trace、目标指令、精确搜索信号和值、搜索值含义、expected 和采集状态。实际时间窗、observed 数值只留给用户从 Vivado Wave 截图后填写，不从 expected/trace 冒充实测。
5. 核对 CSV 中每个截图项都有可直接搜索的定位值，WDB/WCFG 路径真实存在且相互匹配；将目录、Run ID、配置文件和截图顺序交接给用户。用户随后只需打开匹配的 WDB/WCFG，按 CSV 搜索并截图。

## 默认目录布局

```text
report/<lab>/
├── main.tex
├── data/
│   ├── evidence_index.csv
│   └── wave-capture-log.csv
├── docs/
│   ├── report-data-notes.md
│   └── wave-capture-handoff.md
├── figures/
│   ├── *.png                 # Python 结构/统计/trace 图
│   └── waveforms/
│       ├── *.wcfg            # 视图配置，绑定对应 WDB
│       └── *.png             # 用户从 Vivado Wave 保存的真实波形图
└── scripts/
    ├── build_figures.py
    └── build_wave_configs.py

results/<lab>/
└── <run-id>/
    ├── result.txt
    └── <run-id>-forwarding.wdb
```
