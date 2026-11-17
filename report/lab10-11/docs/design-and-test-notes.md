# Lab10/Lab11 设计与测试记录

## 目标与工程隔离

Lab10、Lab11 各有一份独立的 `rtl/myCPU/`，分别连接课程 SRAM wrapper/bridge 与 AXI3 wrapper/crossbar。Lab3 CPU RTL 保持不变；Lab3 原工程 XPR 有用户本地改动，未纳入本任务提交。课程提供的 SoC、bridge、wrapper、CONFREG 与 IP 未为本次功能修改。

两套验证输入均来自各自 Lab9 COE/MIF 与 golden trace。当前 full-run 记录的 COE SHA-256 为 `978140EC69D63A6F264FA6A95A2D28210D9D8A50E2AB105766A1429AA1CE888E`，MIF 为 `392C6386B57F4780536A54F1F5AF34E7749E9AF61CB2DB5703685C4C04CFEB01`，golden trace 为 `8AEE862561B79A7020E1753590B25E37DBB4ECC379E9B75B234F9FA6212F30CF`。

## Lab10 IF 与 MEM

- IF 的状态包括 `IF_REQUEST`、`IF_WAIT_DATA`、`IF_HOLD`。请求锁存 `request_pc`；地址接受后等待返回；响应进入缓冲，ID 阻塞时保持有效。
- trap/ERET/分支重定向清除尚未交付的旧响应。外部已接受的旧取指仍会被消费，并标为 stale 后丢弃。
- MEM 以 `data_sram_req && data_sram_addr_ok` 记录接受，等待 `data_sram_data_ok` 后才允许阶段前进。Load 数据先锁存；Store 完成后才清除本笔事务。
- `store_wstrb/store_wdata` 按字节、半字、字及 LWL/LWR、SWL/SWR 规则生成；访存异常时不发出外部请求。

## Lab11 AXI3 adapter

- `axi3_cpu_bus` 只有一笔读事务：`RD_IDLE/RD_ADDR/RD_DATA`。IF 与 Load 共用 AR/R；`rd_owner_data` 区分归属，ID 0 表示 IF，ID 1 表示数据读。
- 写状态为 `WR_IDLE/WR_SEND/WR_RESP`。AW/W 独立有效并分别锁存完成；B 响应成功后向 MEM 返回完成。
- 事务采用单拍、INCR、normal unlocked；检查 RID/RRESP/RLAST 与 BID/BRESP，错误锁存到 `axi_fault`。
- IF 的 stale 响应处理与 Lab10 同样保留；full-run 中 trap/ERET redirect、stale drop 均有日志锚点。

## 验收结果

| 测试 | 实际结果 | 重点计数/判定 |
| --- | --- | --- |
| Lab10 directed `s4-directed-authorized-lab10-20261117` | PASS | IF 接受/响应 4/4；MEM 11/11；Store 5、Load 6；重复 Store 0 |
| Lab10 full `s5-full-capture-lab10-retry1-20261117` | PASS | 功能 94/94；trace 111,625；取指、Load、Store 接受/完成均配对；stale fetch 丢弃 128 |
| Lab11 directed `s4-directed-authorized-lab11-20261117` | PASS | 读 2、写 2；AW-first/W-first 各覆盖；RID/RRESP/RLAST/BID/BRESP 与 IF redirect 用例通过 |
| Lab11 full `s5-full-capture-lab11-fix1-20261117` | PASS | 功能 94/94；trace 111,625；AR/R 177,511/177,511；AW/W/B 各 3,753；protocol fault 0 |

Lab10 full-run 的 `protocol_assertions_failed` 字段没有由该 testbench 输出，故摘要表记为 `N/A`；本次实际计数显示 Load/Store 接受与完成平衡、重复 Store=0，Lab10 的显式时序定向检查另有 PASS 结果。Lab11 testbench 输出了 `protocol_assertions_failed=0`。

Lab11 full-run 结束时 `inst_req_accept=172894`、`inst_data_complete=172893`。CPU 侧接受数比完成数多 1；将 Load 数加上后，AR 与 R 各 177,511 次且完全配对。该差额表示仿真结束时有一笔末尾 IF 请求已进入 adapter、尚未走到外部 AR；它不是一个未返回的 R 响应。Load 与 Store 均无尾项。

## 原 CPU 异常/中断回归复核

本任务未修改 `lab3/CPU_CDE/mycpu_verify/rtl/myCPU/`。复核仓库已有结果：CP0 unit test 62 条断言 PASS；precise-store test 6 条断言、trap/ERET 各 1 次 PASS；IP7 interrupt test 10 条断言、trap/ERET/Store 各 1 次，masked-then-taken PASS；software timer IRQ test 13 条断言 PASS。结果目录分别在 `results/lab8_lab9/cp0-unit-20261109T141303Z/`、`precise-store-20261110T/`、`interrupt-ip7-20261110T-retry/`、`software-timer-20261110T035119Z/`。这些既有回归本次只读复核，没有在被用户改动的 Lab3 XPR 上重新启动工程。

第八章实践任务三的完整随机延迟压力测试不在本次交付范围；Lab11 的 directed 测试和 full-run 已实际覆盖 READY=0、独立 AW/W 与响应等待。
