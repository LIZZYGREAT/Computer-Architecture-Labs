# 波形查看与截图交接

## 打开方式

每个活动交接行都使用同一 Run 的 WDB 与 WCFG：

1. Vivado → **Flow → Open Static Simulation**，打开表中 `.wdb`。
2. Wave → **File → Simulation Waveform → Open Configuration**，打开对应 `.wcfg`。
3. 用 `search_signal` 与 `search_value` 搜索，再缩放到日志锚点附近。
4. 从 Wave 实际读值并填写 `observed`，将实际时间窗填写到 `time_start_ns/time_end_ns`，PNG 按 `png_filename` 保存到 `report/lab10-11/figures/<case>/`。

活动 WCFG 使用相对 `db_ref` 指向本机同一 Run 的 WDB；Vivado 已逐份重开，确认 WDB 路径解析、波形对象数和信号路径。`waveform_validation.csv` 中的 PASS 仅代表结构校验和日志锚点准备完成，不代表读过 WDB 的信号值。截图后才将对应行设为 `CAPTURED_VERIFIED`。

## Lab10：类 AXI SRAM

WDB：`results/lab10_lab11/lab10/s5-full-capture-lab10-retry1-20261117/wave-full.wdb`<br>
SHA-256：`449BF0E1FA8BFBCF267822847365E3080237D043BA774AE1F27E1B6F6C79320D`

| 图 | 主题 | 活动 WCFG | 搜索信号 | 搜索值 | 日志锚点 | 核对重点 | PNG |
| --- | --- | --- | --- | --- | ---: | --- | --- |
| L10-01 | 类 AXI 取指 | `report/lab10-11/figures/lab10/01_inst_request__s5-full-capture-lab10-retry1-20261117-v4.wcfg` | `/tb_top/soc_lite/cpu/if_stage/request_pc` | `0xbfc00000` | 2,025 ns | req/address acceptance 与 data_ok 分开出现；IF 缓冲后交付 | `L10-01.png` |
| L10-02 | Load 与流水线等待 | `report/lab10-11/figures/lab10/02_load_wait__s5-full-capture-lab10-retry1-20261117-v4.wcfg` | `/tb_top/soc_lite/cpu/mem_stage/ms_pc` | `0xbfc00d64` | 97,455 ns | data req/addr_ok 后等待 data_ok；响应数据进入写回 | `L10-02.png` |
| L10-03 | Store 与字节写掩码 | `report/lab10-11/figures/lab10/03_store_write__s5-full-capture-lab10-retry1-20261117-v4.wcfg` | `/tb_top/soc_lite/cpu/mem_stage/ms_pc` | `0xbfc006f4` | 3,325 ns | 地址 `0xbfaff008`、size=2、wstrb=`f`、wdata=`00000002`；只提交一次 | `L10-03.png` |
| L10-04 | 异常重定向与旧取指响应 | `report/lab10-11/figures/lab10/04_redirect_stale__s5-full-capture-lab10-retry1-20261117-v4.wcfg` | `/tb_top/soc_lite/cpu/if_stage/restart_pc` | `0xbfc00380` | stale drop 12,184,515 ns | redirect 在 12,177,115 ns；旧响应被丢弃，目标 PC 保持正确 | `L10-04.png` |

L10-03 的地址接受与 MEM PC 可能需要稍微扩展时间窗。L10-04 的 redirect 与 stale-drop 相隔约 7.4 μs；时间轴需覆盖两者，或优先展示 stale-drop 周围的 restart PC、旧响应与下一请求。

## Lab11：修正后 AXI3

WDB：`results/lab10_lab11/lab11/lab11-prot-fix-full-20261117-01/wave-full.wdb`<br>
SHA-256：`DBA494CF17EDD813F38062B20C4A78C14199997375A85CDB8EE4BEECAC8C0A7F`

| 图 | 主题 | 活动 WCFG | 搜索信号 | 搜索值 | 日志锚点 | 核对重点 | PNG |
| --- | --- | --- | --- | --- | ---: | --- | --- |
| L11-01 | AXI3 单拍读事务 | `report/lab10-11/figures/lab11/01_axi_read__lab11-prot-fix-full-20261117-01-v2.wcfg` | `/tb_top/soc_lite/cpu_araddr` | `0xbfc00000` | AR 2,045 ns | 在 `ARVALID && ARREADY` 接受时刻读取 ARID=0、ARPROT=`110`、ARLEN=0；之后 RVALID/RREADY、RID、RRESP、RLAST 配对 | `L11-01.png` |
| L11-02 | IF/Load 读仲裁 | `report/lab10-11/figures/lab11/02_read_arbitration__lab11-prot-fix-full-20261117-01-v2.wcfg` | `/tb_top/soc_lite/u_cpu/mem_stage/ms_pc` | `0xbfc00d64` | Load 74,565 ns | 在各自 `ARVALID && ARREADY` 接受时刻比较：IF ARPROT=`110`，Load ARPROT=`010`；`rd_owner_data=1`、ID=1 的 Load 响应回到 MEM，IF owner 为 ID=0 | `L11-02.png` |
| L11-03 | AW/W/B 写事务与保护属性 | `report/lab10-11/figures/lab11/03_axi_write__lab11-prot-fix-full-20261117-01-v2.wcfg` | `/tb_top/soc_lite/u_cpu/mem_stage/ms_pc` | `0xbfc006f4` | Store 3,285 ns | AWPROT=`010`、AWID=WID、AWSIZE=`010`、AWLEN=0、AWBURST=`01`、WLAST=1；B 后 MEM 完成 | `L11-03.png` |
| L11-04 | READY 反压 | `report/lab10-11/figures/lab11/04_axi_backpressure__lab11-prot-fix-full-20261117-01-v2.wcfg` | `/tb_top/soc_lite/cpu_arvalid` | `1` | AR backpressure 2,035 ns | 同一 AR 地址 `0xbfc00000`、ID=0；下一锚点 2,045 ns 握手 | `L11-04.png` |
| L11-05 | 异常期间旧读响应丢弃 | `report/lab10-11/figures/lab11/05_redirect_stale__lab11-prot-fix-full-20261117-01-v2.wcfg` | `/tb_top/soc_lite/u_cpu/if_stage/restart_pc` | `0xbfc00380` | stale drop 9,304,945 ns | redirect 在 9,304,925 ns；旧 IF 读排空后丢弃，转到目标 PC | `L11-05.png` |

`AWPROT=010` 表示数据访问、Non-secure、unprivileged；取指 ARPROT=`110`，Load ARPROT=`010`。新版 `L11-01`、`L11-02` 分别包含 13、17 个信号并显示 `cpu_arprot`；`L11-03` 保持 21 个信号，含 `cpu_wid`、`cpu_awprot`、`cpu_awsize`、`cpu_awlen`、`cpu_awburst`。`L11-04` 的 `search_value=1` 只对应 ARVALID；地址和 ID 在同次 Run 的 `search_context` 锚点中，不要把 VALID 值与地址 payload 混淆。

## 状态与历史版本

`wave-capture-log.csv` 中 Lab10 四行和修正后 Lab11 五行仍是 `PENDING_CAPTURE`；旧的修正前 Lab11 五行标为 `SUPERSEDED`，请勿用旧 Run 截图作为 AxPROT 验收证据。原有 9 份 WCFG 均保留；Lab10 `-v4`、历史 Lab11 `-v2` 及修正后 Run 的 `-v2` 配置为版本化副本，均使用相对 WDB 路径。

截图前的 `expected` 与日志锚点仅供定位和对照，不是 `observed`。请在 Vivado Wave 实际读取显示值并保存 PNG 后，再填写观测值、时间窗并将对应行改为 `CAPTURED_VERIFIED`。
