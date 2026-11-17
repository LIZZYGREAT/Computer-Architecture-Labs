# 波形查看与截图交接

## 打开方式

对每一行都使用同一 Run 的 WDB 与 WCFG：

1. Vivado → **Flow → Open Static Simulation**，打开表中 `.wdb`。
2. Wave → **File → Simulation Waveform → Open Configuration**，打开对应 `.wcfg`。
3. 用表中 `search_signal` 与 `search_value` 定位，再按 `anchor_time_ns` 附近放大。
4. 将显示值写进 `observed`，实际视窗写入 `time_start_ns/time_end_ns`，PNG 按 `png_filename` 保存到 `report/lab10-11/figures/<case>/`。

当前 `.wcfg` 均由 Vivado 从本次 WDB 层级创建，并由 `validate_wave_configs.tcl` 重开：WDB 路径引用匹配、波形对象数一致、信号全部解析、顶层时钟及目标锚点存在。搜索时间由同次仿真 `BUS_ANCHOR` 输出；它用于定位，不代替用户从波形读出的 `observed`。

## Lab10：类 AXI SRAM

WDB：`results/lab10_lab11/lab10/s5-full-capture-lab10-retry1-20261117/wave-full.wdb`
WDB SHA-256：`449BF0E1FA8BFBCF267822847365E3080237D043BA774AE1F27E1B6F6C79320D`

| 图 | 主题 | WCFG | 搜索信号 | 搜索值 | 日志锚点 | 核对重点 | PNG |
| --- | --- | --- | --- | --- | ---: | --- | --- |
| L10-01 | 类 AXI 取指 | `report/lab10-11/figures/lab10/01_inst_request__s5-full-capture-lab10-retry1-20261117-v3.wcfg` | `/tb_top/soc_lite/cpu/if_stage/request_pc` | `0xbfc00000` | 2,025 ns | req/address acceptance 与 data_ok 响应分开出现；IF 缓冲后交付 | `L10-01.png` |
| L10-02 | Load 与流水线等待 | `report/lab10-11/figures/lab10/02_load_wait__s5-full-capture-lab10-retry1-20261117-v3.wcfg` | `/tb_top/soc_lite/cpu/mem_stage/ms_pc` | `0xbfc00d64` | 97,455 ns | data req/addr_ok 后等待 data_ok；响应数据进入写回 | `L10-02.png` |
| L10-03 | Store 与字节写掩码 | `report/lab10-11/figures/lab10/03_store_write__s5-full-capture-lab10-retry1-20261117-v3.wcfg` | `/tb_top/soc_lite/cpu/mem_stage/ms_pc` | `0xbfc006f4` | 3,325 ns | 地址 `0xbfaff008`、size=2、wstrb=`f`、wdata=`00000002`；仅提交一次 | `L10-03.png` |
| L10-04 | 异常重定向与旧取指响应 | `report/lab10-11/figures/lab10/04_redirect_stale__s5-full-capture-lab10-retry1-20261117-v3.wcfg` | `/tb_top/soc_lite/cpu/if_stage/restart_pc` | `0xbfc00380` | 12,184,515 ns | redirect 在 12,177,115 ns；旧响应约 7.4 µs 后被丢弃，目标 PC 保持正确 | `L10-04.png` |

L10-03 地址接受与 MEM PC 的同周期显示可能需要稍微向前/后扩展时间轴；锚点是 Store 接受日志时间。L10-04 的 redirect 与 stale-drop 非邻近，时间轴应包含两者或优先围绕 stale-drop 展示 restart PC、旧响应与下一次请求。

## Lab11：AXI3

WDB：`results/lab10_lab11/lab11/s5-full-capture-lab11-fix1-20261117/wave-full.wdb`
WDB SHA-256：`0D9B9238AA5BE51B92CD6F876FC748CC5B5205D94D81169EA426B4E28BC25A81`

| 图 | 主题 | WCFG | 搜索信号 | 搜索值 | 日志锚点 | 核对重点 | PNG |
| --- | --- | --- | --- | --- | ---: | --- | --- |
| L11-01 | AXI3 单拍读事务 | `report/lab10-11/figures/lab11/01_axi_read__s5-full-capture-lab11-fix1-20261117.wcfg` | `/tb_top/soc_lite/cpu_araddr` | `0xbfc00000` | AR 2,045 ns | AR ID=0、ARLEN=0，之后 RVALID/RREADY、RID、RRESP、RLAST 配对 | `L11-01.png` |
| L11-02 | IF/Load 读仲裁 | `report/lab10-11/figures/lab11/02_read_arbitration__s5-full-capture-lab11-fix1-20261117.wcfg` | `/tb_top/soc_lite/u_cpu/mem_stage/ms_pc` | `0xbfc00d64` | Load 74,565 ns | `rd_owner_data=1`、ID=1 的 Load 响应回到 MEM；IF owner 为 ID=0 | `L11-02.png` |
| L11-03 | AW/W/B 写事务 | `report/lab10-11/figures/lab11/03_axi_write__s5-full-capture-lab11-fix1-20261117.wcfg` | `/tb_top/soc_lite/u_cpu/mem_stage/ms_pc` | `0xbfc006f4` | Store 3,285 ns | 地址 `0xbfaff008`、WSTRB=`f`、WDATA=`00000002`；AW/W 分别握手，B 后 MEM 完成 | `L11-03.png` |
| L11-04 | READY 反压 | `report/lab10-11/figures/lab11/04_axi_backpressure__s5-full-capture-lab11-fix1-20261117.wcfg` | `/tb_top/soc_lite/cpu_arvalid` | `1` | AR backpressure 2,035 ns | 同一 AR 地址 `0xbfc00000`、ID=0；下一锚点在 2,045 ns 握手 | `L11-04.png` |
| L11-05 | 异常期间旧读响应丢弃 | `report/lab10-11/figures/lab11/05_redirect_stale__s5-full-capture-lab11-fix1-20261117.wcfg` | `/tb_top/soc_lite/u_cpu/if_stage/restart_pc` | `0xbfc00380` | stale drop 9,304,945 ns | redirect 在 9,304,925 ns；旧 IF 读完成后 stale 丢弃并转到目标 PC | `L11-05.png` |

`L11-04` 的 `search_value=1` 对应 ARVALID；地址与 ID 在该行 `search_context` 的同次 Run 锚点中。用 ARVALID 搜地址值会把信号值和 payload 混淆。

## 观测状态

`wave-capture-log.csv` 当前每图的 `proof_status=PENDING_CAPTURE`。这代表 WCFG 可加载、信号和日志锚点已准备好，但 PNG 尚未由用户在 Vivado 中从该 WDB 实际截图。请勿把 `expected` 当作 `observed`；截图核对后再填写观测值、时间窗并设为 `CAPTURED_VERIFIED`。
