# Lab10 / Lab11 验收交接

## 最终结论

- 分支：`lab10-lab11`；Vivado：2025.2。
- Lab11 AXI3 `AxPROT` 已修正并通过新的 directed 与 full 验收；Lab10 RTL 未改，原 full PASS 仍有效。
- Lab11 最终 Run：`lab11-prot-fix-full-20261117-01`，94/94 功能点、111,625/111,625 条 trace、AXI protocol assertions 0、重复 Store 0。
- 两个原始 WDB 的路径、大小和 SHA-256 经复核未变。新 Lab11 WDB 保存在本机结果目录，未提交到 Git。
- 最近修订：PROT 定向验收提交 `8af00bf`；证据流水线、WCFG 与运行结果提交 `3450041`；本次提交更新验收交接文档。

## AXI3 Protection 属性修正

采用 unprivileged、non-secure 策略：取指 `ARPROT=3'b110`；Load `ARPROT=3'b010`；Store `AWPROT=3'b010`。Arm AXI 规范定义 `AxPROT[2]` 为指令/数据、`AxPROT[1]` 为 Secure/Non-secure、`AxPROT[0]` 为 privileged/unprivileged；见 [Arm AMBA AXI/ACE Protocol Specification，A4.7](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/IHI0022H_amba_axi_protocol_spec.pdf)。

Lab11 directed Run `lab11-prot-fix-directed-elevated-20261117-01` PASS：读 2 笔、写 2 笔；覆盖 AW-first 与 W-first；检查取指、Load、Store PROT，以及 RID/RRESP/RLAST、BID/BRESP 和 IF 重定向。

| Run | 功能 | Trace | 事务与协议 | WDB 本机大小 | WDB SHA-256 |
| --- | ---: | ---: | --- | ---: | --- |
| Lab10 `s5-full-capture-lab10-retry1-20261117` | 94/94 | 111,625/111,625 | IF 172,457/172,457；Load 4,618/4,618；Store 3,753/3,753；重复 Store 0；stale drop 128 | 555,155,143 B | `449BF0E1FA8BFBCF267822847365E3080237D043BA774AE1F27E1B6F6C79320D` |
| Lab11 历史 `s5-full-capture-lab11-fix1-20261117` | 94/94 | 111,625/111,625 | 功能回归 PASS；该 Run 使用修正前 PROT，仅作历史对照 | 981,404,172 B | `0D9B9238AA5BE51B92CD6F876FC748CC5B5205D94D81169EA426B4E28BC25A81` |
| Lab11 最终 `lab11-prot-fix-full-20261117-01` | 94/94 | 111,625/111,625 | AR/R 177,511/177,511；AW/W/B 各 3,753；Load 4,618/4,618；Store 3,753/3,753；PROT/协议断言失败 0；重复 Store 0；末尾 CPU IF pending 1 | 981,401,793 B | `DBA494CF17EDD813F38062B20C4A78C14199997375A85CDB8EE4BEECAC8C0A7F` |

最终 Lab11 WDB：`results/lab10_lab11/lab11/lab11-prot-fix-full-20261117-01/wave-full.wdb`。`result.txt` 的 `STATUS`、`WAVEFORM_STATUS`、`WAVEFORM_FILE`、`WAVEFORM_SHA256` 各仅出现一次；原始 Tcl 汇总另存于 `runner-result.txt`。COE、MIF、golden trace 哈希及源码清单在 Run 的 `input_manifest.csv`、`source-manifest.csv` 中，清单 SHA-256 也写入 `evidence_index.csv`。

末尾 `inst_req_accept=172894`、`inst_data_complete=172893`，差额 1 表示仿真终止时一笔 CPU 内部 IF 请求尚未发出外部 AR；外部 AR/R 完全配对，Load 与 Store 也全部配对。因此摘要写作 `PASS_WITH_PENDING_IF`，没有声称所有内部 IF 请求都已完成。Lab10 full 的 `PROTOCOL_ASSERTS_FAIL=N/A` 表示没有 full-run 运行时协议断言数据；它在事务摘要中标为 `assertion_status=NOT_REPORTED`，不与 directed assertions 的 PASS 混为一谈。

## 波形配置与证据表

- 9 个活动截图场景（4 份 Lab10、5 份修正后 Lab11）的 WCFG 使用相对 `db_ref`，并已由 Vivado 重开验证。原 9 份配置保留；另有 Lab10 `-v4.wcfg`、修正前 Lab11 `-v2.wcfg` 和最终 Lab11 新 Run 配置。修正前 Lab11 的 5 个截图行标为 `SUPERSEDED`。
- `waveform_validation.csv` 共 23 条：原 9 份配置、9 份可移植副本、最终 Run 的 5 份配置；结构校验全部 PASS。`L11-03` 最终配置有 21 个信号，包括 `cpu_wid`、`cpu_awprot`、`cpu_awsize`、`cpu_awlen`、`cpu_awburst`。
- 结构校验只证明 WDB/WCFG 可打开、引用匹配、信号路径存在、日志锚点可定位；不代表已从波形逐拍读值。`wave-capture-log.csv` 有 14 行：9 行 `PENDING_CAPTURE`、5 行历史 `SUPERSEDED`。
- 人工字段 `observed`、时间窗、`proof_status`、`remarks` 会在重建时保留。若已 `CAPTURED_VERIFIED` 的 WDB/WCFG 哈希或锚点变化，生成器会拒绝覆盖。
- CSV 使用原子替换；仅在内容确实变化时把旧表版本化保存到 `report/lab10-11/data/archive/`。幂等性回归仅在临时目录构造 CSV：同一 Run 连续重建两次保留截图字段，改变 WDB 哈希则拒绝写入。

汇总文件：[`evidence_index.csv`](../data/evidence_index.csv)、[`transaction-summary.csv`](../data/transaction-summary.csv)、[`waveform_validation.csv`](../data/waveform_validation.csv)、[`wave-capture-log.csv`](../data/wave-capture-log.csv)。逐图打开与搜索信息见 [`waveform-capture-handoff.md`](waveform-capture-handoff.md)。

## 历史记录与截图

此前促成修复的 Lab10/Lab11 telemetry 与首次 full-run 失败记录保留。Lab11 directed 验收前的 Vivado 初始化失败保留一份摘要、命令、输入/源码清单、preflight 和错误日志，供追溯执行环境问题；确认同类重跑报出完全相同的 `Common 17-354` 错误后，移除了重复记录及冗余初始化日志。该失败不进入事务验收汇总。历史 WDB 与原始 WCFG 保持不变。

截图仍待用户在 Vivado Wave 中完成：从同一 Run 的 WDB/WCFG 读取实际值、保存 PNG，再将 `observed`、时间窗与 `proof_status` 更新为 `CAPTURED_VERIFIED`。本次脚本不会清除这些字段。
