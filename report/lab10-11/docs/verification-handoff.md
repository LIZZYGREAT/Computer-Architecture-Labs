# Lab10 / Lab11 验收交接

## 当前树状态

本文记录的是 `lab10-lab11` 清理提交 `c8a6ea9` 之前的验收交接快照。该清理提交移除了本文件下文所述的 Lab11 directed Run `lab11-source-provenance-directed-20261118-03` 及若干冗余历史 Run；对应汇总 CSV 中的行保留作历史记录，不代表这些 Run 目录仍存在。当前树保留的 Lab11 回归证据见 [AXI3 directed Run result](../../../results/lab13_19/lab14/lab11-axi3-directed-20261118-02/result.txt) 和 [CPU golden-trace Run result](../../../results/lab13_19/lab14/lab11-cpu-golden-20261118-03/result.txt)。

## 最终结论

- 分支：`lab10-lab11`；Vivado：2025.2。
- Lab11 AXI3 `AxPROT` 已修正并通过新的 directed 与 full 验收；Lab10 RTL 未改，原 full PASS 仍有效。
- Lab11 最终 Run：`lab11-prot-fix-full-20261117-01`，94/94 功能点、111,625/111,625 条 trace、AXI protocol assertions 0、重复 Store 0。
- 两个原始 WDB 的路径、大小和 SHA-256 经复核未变。新 Lab11 WDB 保存在本机结果目录，未提交到 Git。
- 最近修订：PROT 定向验收提交 `8af00bf`；证据流水线、WCFG 与运行结果提交 `3450041`；本次提交更新验收交接文档。

## AXI3 Protection 属性修正

采用 unprivileged、non-secure 策略：取指 `ARPROT=3'b110`；Load `ARPROT=3'b010`；Store `AWPROT=3'b010`。Arm AXI 规范定义 `AxPROT[2]` 为指令/数据、`AxPROT[1]` 为 Secure/Non-secure、`AxPROT[0]` 为 privileged/unprivileged；见 [Arm AMBA AXI/ACE Protocol Specification，A4.7](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/IHI0022H_amba_axi_protocol_spec.pdf)。

清理前最终保留的 Lab11 directed Run `lab11-source-provenance-directed-20261118-03` 曾通过验收：读 2 笔、写 2 笔；覆盖 AW-first 与 W-first；检查取指、Load、Store PROT，以及 RID/RRESP/RLAST、BID/BRESP 和 IF 重定向，并通过 PRE/POST 源码完整性核对。该 Run 目录已在后续清理中删除。原 `s4-directed-authorized-lab11-20261117` 当时作为 S0 基线保留；中间 directed 结果由这个带精确源码清单的 Run 替代。

| Run | 功能 | Trace | 事务与协议 | WDB 本机大小 | WDB SHA-256 |
| --- | ---: | ---: | --- | ---: | --- |
| Lab10 `s5-full-capture-lab10-retry1-20261117` | 94/94 | 111,625/111,625 | IF 172,457/172,457；Load 4,618/4,618；Store 3,753/3,753；重复 Store 0；stale drop 128 | 555,155,143 B | `449BF0E1FA8BFBCF267822847365E3080237D043BA774AE1F27E1B6F6C79320D` |
| Lab11 历史 `s5-full-capture-lab11-fix1-20261117` | 94/94 | 111,625/111,625 | 功能回归 PASS；该 Run 使用修正前 PROT，仅作历史对照 | 981,404,172 B | `0D9B9238AA5BE51B92CD6F876FC748CC5B5205D94D81169EA426B4E28BC25A81` |
| Lab11 最终 `lab11-prot-fix-full-20261117-01` | 94/94 | 111,625/111,625 | AR/R 177,511/177,511；AW/W/B 各 3,753；Load 4,618/4,618；Store 3,753/3,753；PROT/协议断言失败 0；重复 Store 0；末尾 CPU IF pending 1 | 981,401,793 B | `DBA494CF17EDD813F38062B20C4A78C14199997375A85CDB8EE4BEECAC8C0A7F` |

最终 Lab11 WDB：`results/lab10_lab11/lab11/lab11-prot-fix-full-20261117-01/wave-full.wdb`。`result.txt` 的 `STATUS`、`WAVEFORM_STATUS`、`WAVEFORM_FILE`、`WAVEFORM_SHA256` 各仅出现一次；原始 Tcl 汇总另存于 `runner-result.txt`。COE、MIF、golden trace 哈希及源码清单在 Run 的 `input_manifest.csv`、`source-manifest.csv` 中，清单 SHA-256 也写入 `evidence_index.csv`。

## 源码清单与阶段状态

更新后的 `verify_bus.ps1` 在每个 directed/full 功能 Run 中生成 `effective-source-manifest.csv`，记录本次 XPR 的 `sources_1` / `sim_1` 文件集、实际仿真 top、解析出的 include 文件和验证脚本，并保存 `PRE_SIM` 与 `POST_SIM` 哈希。生成 XPR 的原始哈希也保留；其配置指纹只覆盖有效文件集、top 和实际解析到的 include 文件，排除 Vivado 自动改写的运行元数据。`SOURCE_INTEGRITY=PASS` 表示活动文件集与哈希在运行前后保持一致；`SOURCE_DIRTY` 仍单独表示启动时 Git 工作区状态。

清理前的闭环 Run `lab11-source-provenance-directed-20261118-03` 为 `STATUS=PASS`、`SOURCE_INTEGRITY=PASS`，包含 directed 测试所需的 PRE/POST 清单，计数为 2 次读、2 次写，R/B 各 2 次；此 Run 未采集 WDB。第一次验证发现 Vivado 会改写生成 XPR 中非仿真相关的 include 元数据；规范化配置指纹和专项回归测试修正后，第三次唯一 RunId 的仿真通过。前两次环境失败目录已清理；该闭环 Run 后续也由分支清理提交移除。

历史 Run 的旧 `source-manifest.csv` 保持原样，不补写当前哈希。其与 Git 的事后关联结果见 [`source-provenance-audit.md`](source-provenance-audit.md) 和 [`source-correlation-audit.csv`](../data/source-correlation-audit.csv)。没有有效清单的旧 `SOURCE_DIRTY=true` Run 仍标为 `HISTORICAL_DIRTY_UNPROVEN`；有 PRE/POST 精确清单且完整性通过的 Run 标为 `EFFECTIVE_MANIFEST_RECORDED`，即使启动时工作区有差异也不会抹掉实际文件哈希证据。

新 Run 将静态输入扫描记录到根级 `input-scan.txt`，将真实 Vivado 工程/IP 预检结果记录到 `vivado-preflight-summary.txt` 和 `preflight/project-preflight.txt`，并在最终 `result.txt` 分开保留 `INPUT_SCAN_STATUS`、`VIVADO_PREFLIGHT_STATUS`、`PREFLIGHT_STATUS` 与功能/协议状态。`preflight-stage-separation-20261118-02` 是单独的 preflight-only 记录：输入扫描和 Vivado 工程预检均 PASS，功能未运行，故 `STATUS=INCOMPLETE` 且不计入事务汇总。它不包含 PRE/POST 仿真清单。

历史运行目录中的根级 `preflight.txt` 是 Vivado 工程检查前由输入扫描器产生的阶段快照，其中的 `NOT_RUN`/`INCOMPLETE` 不代表该 Run 的最终结果。Vivado 预检以 `preflight/project-preflight.txt` 为准，功能及 trace 以最终 `result.txt`、`simulate.log` 为准。构建器优先读取新的 `input-scan.txt`，仅在历史目录中回退读取原 `preflight.txt`，不会把旧 `OVERALL_STATUS=INCOMPLETE` 当成最终 Run 状态。

末尾 `inst_req_accept=172894`、`inst_data_complete=172893`，差额 1 表示仿真终止时一笔 CPU 内部 IF 请求尚未发出外部 AR；外部 AR/R 完全配对，Load 与 Store 也全部配对。因此摘要写作 `PASS_WITH_PENDING_IF`，没有声称所有内部 IF 请求都已完成。Lab10 full 的 `PROTOCOL_ASSERTS_FAIL=N/A` 表示没有 full-run 运行时协议断言数据；它在事务摘要中标为 `assertion_status=NOT_REPORTED`，不与 directed assertions 的 PASS 混为一谈。

## 波形配置与证据表

- 9 个活动截图场景（4 份 Lab10、5 份修正后 Lab11）的 WCFG 使用相对 `db_ref`，并已由 Vivado 重开验证。原 9 份配置保留；另有 Lab10 `-v4.wcfg`、修正前 Lab11 `-v2.wcfg` 和最终 Lab11 的版本化配置。修正前 Lab11 的 5 个截图行标为 `SUPERSEDED`。
- `waveform_validation.csv` 保留历史结构校验，并追加新版 Lab11 配置的验证记录。修正后 Run 的 `L11-01/L11-02` 增加 `cpu_arprot`；截图时只在 `cpu_arvalid && cpu_arready` 接受时刻读值，IF 为 `110`、Load 为 `010`。`L11-03` 继续含 `cpu_wid`、`cpu_awprot`、`cpu_awsize`、`cpu_awlen`、`cpu_awburst`。
- 结构校验只证明 WDB/WCFG 可打开、引用匹配、信号路径存在、日志锚点可定位；不代表已从波形逐拍读值。`wave-capture-log.csv` 有 14 行：9 行 `PENDING_CAPTURE`、5 行历史 `SUPERSEDED`。
- 人工字段 `observed`、时间窗、`proof_status`、`remarks` 会在重建时保留。若已 `CAPTURED_VERIFIED` 的 WDB/WCFG 哈希或锚点变化，生成器会拒绝覆盖。
- CSV 使用原子替换；仅在内容确实变化时把旧表版本化保存到 `report/lab10-11/data/archive/`。幂等性回归仅在临时目录构造 CSV：同一 Run 连续重建两次保留截图字段，改变 WDB 哈希则拒绝写入。

汇总文件：[`evidence_index.csv`](../data/evidence_index.csv)、[`transaction-summary.csv`](../data/transaction-summary.csv)、[`waveform_validation.csv`](../data/waveform_validation.csv)、[`wave-capture-log.csv`](../data/wave-capture-log.csv)。逐图打开与搜索信息见 [`waveform-capture-handoff.md`](waveform-capture-handoff.md)。

## 历史记录与截图

在本交接快照生成时，结果记录已收敛：删除了 5 个没有有效仿真结果且已有通过替代项的环境失败尝试；删除了旧的 Lab11 directed PASS 中间项，由带 PRE/POST 精确清单的 `lab11-source-provenance-directed-20261118-03` 替代。后续 `lab10-lab11` 清理提交又删除了该 directed Run、部分历史 Run 目录和冗余 WCFG 版本；当前有效 Lab11 回归证据见文首链接。Lab10/Lab11 波形交接表中的人工截图字段未改写。

截图仍待用户在 Vivado Wave 中完成：从同一 Run 的 WDB/WCFG 读取实际值、保存 PNG，再将 `observed`、时间窗与 `proof_status` 更新为 `CAPTURED_VERIFIED`。本次脚本不会清除这些字段。
