# Lab10 类 AXI 与 Lab11 AXI3 接口对照

本文描述两个独立 CPU 工程实际实现的总线子集。Lab10 的 `req/addr_ok/data_ok` 是 CPU 与 SRAM wrapper 之间的类 AXI 请求/完成接口；Lab11 CPU-facing 总线是 AXI3 主设备接口，经过 `axi_wrap`、crossbar 后连接 RAM 与 CONFREG。两者不是同一种总线。

## 接口对照

| 项目 | Lab10 类 AXI SRAM 接口 | Lab11 AXI3 |
| --- | --- | --- |
| 请求结构 | instruction 与 data 两组独立接口 | AR/R 读通道共享；AW/W/B 写通道独立 |
| 地址接受 | `req && addr_ok` 同周期成立才接受 | 每个通道以 `VALID && READY` 接受 |
| 完成条件 | `data_ok` 表示事务完成，读时 `rdata` 有效 | 读等待 R 握手；写必须等 AW、W 都握手并收到 B |
| 事务关联 | 由 IF/MEM 本地状态保存单笔请求 | 单笔 outstanding；IF 读 ID=0，Load/Store ID=1 |
| 地址与数据 | 同一 CPU 请求接口携带地址/写数据；响应另行返回 | 地址、读数据、写地址、写数据、写响应分为五通道 |
| 写请求 | `wr/size/wstrb/addr/wdata` | AW 与 W 可分周期握手；B 成功后才完成 |
| 错误检查 | full-run 计数与 Store 去重；定向测试检查请求/响应时序 | adapter 校验 RID/RRESP/RLAST、BID/BRESP，并锁存 `axi_fault` |
| 实现范围 | 单笔请求等待、请求/完成分离 | 单笔单拍事务、INCR、无锁；不实现突发队列或乱序多 outstanding |

## 事务时序

### Lab10 取指与 Load/Store

```text
req=1, addr=PC ── req && addr_ok ──► 地址被 wrapper 接受
                                      │
                                      └── data_ok, rdata ──► IF/MEM 完成
```

`addr_ok` 单独为高、但 `req=0` 时不是接受事件。请求一旦接受，IF/MEM 保持请求身份并等待 `data_ok`，CPU 不会因等待响应重复提交同一笔事务。Store 完成也等待 `data_ok`，`data_ok` 前 MEM 不前进。

### Lab11 读仲裁与写响应

```text
IF request ─┐
            ├─► 单笔读 owner ─► ARVALID/ARREADY ─► RVALID/RREADY ─► owner 返回
Load req ───┘

Store ─► AWVALID/AWREADY ─┐
        WVALID/WREADY ─────┴─► BVALID/BREADY ─► MEM 完成
```

读状态为 `RD_IDLE → RD_ADDR → RD_DATA`。Load 读优先于同时等待的 IF 读，`rd_owner_data` 锁存响应归属。写状态为 `WR_IDLE → WR_SEND → WR_RESP`；`wr_aw_done`、`wr_w_done` 分别记住两个独立握手，二者都完成后才等待 B。

## 异常和过时取指

重定向清除尚未送入 ID 的旧响应，并更新目标 PC。已被外部接受的旧读不能撤回，IF 会继续消耗其响应并通过 `stale_response` 丢弃，避免把旧路径指令交给 decode。异常提交信号来自 MEM 的 trap/ERET 提交边界；Store 只在有效、无异常的 MEM 项目上发起。

## 实测范围

- Lab10 full-run：94/94 功能点，111,625 条严格 trace 记录；取指 172,457/172,457，Load 4,618/4,618，Store 3,753/3,753，重复 Store=0。
- Lab11 full-run：94/94 功能点，111,625 条严格 trace 记录；AR/R 各 177,511，AW/W/B 各 3,753；Load 4,618/4,618，Store 3,753/3,753，重复 Store=0，AXI protocol faults=0。
- Lab11 实现为单笔单拍子集；full-run 的末尾有一笔 CPU 侧 IF 请求已被 adapter 接受、但尚未进入外部 AR 握手。AR/R 仍完全配对，Load/Store 均无未完成事务。

详细运行来源与可搜索波形锚点见 [`verification-handoff.md`](verification-handoff.md) 和 [`waveform-capture-handoff.md`](waveform-capture-handoff.md)。
