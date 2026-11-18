# S5 Lab18 DCache 验收报告

## 实现

- 在 `lab18/cpu_dcache` 建立独立的 Lab14/Lab17 派生 CPU/SoC，Lab17 ICache 工程保持不变。
- 新增 4 路 × 128 组 × 32B 的 16KiB DCache，使用物理 Tag、写分配与写回；Store hit 按 `MEM_stage` 提供的 byte strobe 合并，Store miss 先回填再合并。
- Dirty victim 通过现有统一 AXI3 bridge 写出 8 个 W beat，并等待匹配的 B 响应后才开始 refill。桥接请求的地址和数据在未接收期间保持稳定。
- KSEG1 和非缓存 TLB 页绕过 DCache，通过 bridge 的单拍 Load/Store 路径访问，外设写等 B 响应后才完成。没有在 Uncache 访问时隐式冲刷 Cache。
- 保留 `MEM_stage` 的一请求/一完成接口与 LB/LH/LWL/LWR 读取提取逻辑；DCache 接收 SB/SH/SWL/SWR 已对齐的 byte strobe 和 write data。
- 扩展 `verify.ps1`、`run_unit.tcl` 和 `run_soc.tcl`，为 Lab18 生成唯一 RunId、参数记录、输入/工程预检、源码与 COE 哈希、编译/仿真日志和 WDB。

## 验收结果

定向 DCache 测试 9/9 通过：首次 miss 收到 8 beat；同一行再次访问没有增加 AR；Store 后 Load 读回新值；SB/SH/SWL/SWR 保持 byte lane；第 5 个同 index Tag 触发脏替换，并验证写回数据 `0x3344aa11`。在 B 响应到达前没有发出 refill。Uncache Store/Load 没有分配 Cache 行，Uncache 写恰好完成一次。

单独的 MEM 定向测试确认异常路径中的 SW 不会发出数据请求；有效 SW 在地址反压期间保持地址、掩码和数据稳定，并恰好接受、完成一次。另一组并发测试让 ICache 和 DCache 同时 miss，统一桥正确分配两笔 AR 的 owner/ID，并向双方各返回 8 个 R beat；`axi_fault=0`。

同一份 Lab17 `func_all94` 镜像完成 94/94，最终 `num_data=0x5e00005e`，运行 1,041,981 个仿真周期。3,752 个 CPU Store 全部一一完成；NUM 寄存器共 95 次写事务，其中启动清零 1 次、94 个评分点各 1 次，写入值按预期顺序逐笔检查。

| 指标 | 结果 |
|---|---:|
| DCache hit / miss | 6,937 / 950 |
| 脏行写回 / Uncache 请求 | 446 / 483 |
| ICache hit / miss / refill / Uncache 取指 | 134,525 / 21,571 / 21,571 / 16,920 |
| AXI AR / R beat | 39,684 / 197,331 |
| AXI AW / W beat / B | 685 / 3,807 / 685 |
| CPU Store accepted / completed | 3,752 / 3,752 |
| NUM 外设写 accepted / completed | 95 / 95 |

W beat 数包含脏行写回的 8 拍突发；446 次整行写回贡献 3,568 个 beat，其余是单拍 Uncache 写。AW 与 B 数相等，CPU Store 与外设写计数均无重复。

## 证据

- [DCache 定向 run](../../results/lab13-lab19/lab18/lab18-dcache-directed-20261118-01/result.txt)：9 项检查通过，含 WDB。
- [I/D 并发 miss run](../../results/lab13-lab19/lab18/lab18-cache-arbitration-20261118-02/result.txt)：owner/ID 正确，两行共 16 个 R beat，含 WDB。
- [MEM 异常/提交 run](../../results/lab13-lab19/lab18/lab18-mem-exception-20261118-02/result.txt)：异常 Store 被阻止，有效 Store 完成一次，含 WDB。
- [94 项功能 run](../../results/lab13-lab19/lab18/lab18-dcache-functional-20261118-02/result.txt)：94/94、源码完整性 PASS；长仿真不保留全量 WDB。
- [波形索引](../../results/lab13-lab19/lab18/waveform-index.txt)记录三个 WDB 的大小、SHA-256 和事件锚点；Vivado 截图/WCFG 人工复核待后续捕获。
- 功能镜像 COE SHA-256：`D2FE2D064B2611237805DCB502A273329C8DE5FACF5C8368F55DE1326D3C2244`。
- 每个验收类别只保留一个最终有效 run；失败的计数判定与 Vivado xelab 启动尝试已清理。

## 复现

```powershell
.\scripts\tlb_cache\verify.ps1 -Case lab18 -Suite directed -RunId lab18-dcache-directed-<run-id>
.\scripts\tlb_cache\verify.ps1 -Case lab18 -Suite arbitration -RunId lab18-cache-arbitration-<run-id>
.\scripts\tlb_cache\verify.ps1 -Case lab18 -Suite mem-exception -RunId lab18-mem-exception-<run-id>
.\scripts\tlb_cache\verify.ps1 -Case lab18 -Suite functional -RunId lab18-dcache-functional-<run-id>
```
