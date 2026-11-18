# S4 Lab17 ICache 验收报告

## 实现

- 在 `lab17/cpu_icache` 建立独立 CPU/SoC 副本，Lab14 的 CPU 与工程文件没有修改。
- 新增 4 路 × 128 组 × 32B ICache（16KiB），物理 Tag 比较，按物理地址的 `[11:5]` 组索引和 `[4:2]` 字选择。
- Cacheable 取指整行回填 8 个 32-bit beat；KSEG1 与关闭缓存的取指共用原有 CPU `addr_ok/data_ok` 完成语义，走 AXI3 单拍读取。
- 新增统一 `cache_axi3_bridge`：I refill `ARLEN=7`、Uncache `ARLEN=0`，锁存 AXI payload，按 owner 返回响应，检查 RID/RRESP/RLAST/BID/BRESP。CPU 原有 IF 重定向和 `stale_response` 排空逻辑保留在隔离副本内。
- `run_soc.tcl` 支持 Lab17 缓存版和关闭 ICache 的同镜像基线；`run_unit.tcl` 支持独立 ICache/AXI 定向验收。
- 新增 `scripts/tlb_cache/verify.ps1` 统一入口，生成独立 RunId 目录并在通过后采集 active-source 与镜像 SHA-256 清单。

## 验收结果

独立定向验收通过 24 项检查，覆盖 8 拍 refill 与并发 I/D 读仲裁、同一行命中、KSEG1 单拍旁路、8 拍脏行写回、AW/W 独立握手和 RID 错误锁存。正常请求完成计数为 IF 4/4、D 2/2、写回 1/1；故意注入 RID 错误的 IF 请求单独记录为 1 accepted、0 completed、1 expected pending，且 `axi_fault=1`。

同一份 `lab17/func_all94/obj/inst_ram.coe` 在缓存版和无缓存版均通过 94/94 测试点，最终 `num_data=0x5e00005e`，LED RG0/RG1 均为通过值。两个运行的 94 个评分点逐项相同，3,752 个 Store 均完成一次，没有重复 Store 或 AXI/cache fault。

| 指标 | ICache 开启 | ICache 关闭 |
|---|---:|---:|
| 周期数 | 1,038,101 | 1,402,080 |
| ICache hit / miss / refill | 134,535 / 21,571 / 21,571 | 0 / 0 / 0 |
| ICache Uncache 取指 | 16,919 | 172,900 |
| AXI AR 事务 | 43,108 | 177,518 |
| AXI R beat | 194,105 | 177,518 |
| AW / W / B | 3,752 / 3,752 / 3,752 | 3,752 / 3,752 / 3,752 |

按本次固定 100MHz 仿真时钟计算，ICache 版周期约为无缓存版的 **1.3506×**；AR 事务减少 **75.72%**。缓存版 R beat 数较大是预期现象：每次 refill 需传 8 beat，不能把 R beat 数当作 AR 事务数比较。

## 证据与运行

- 定向 run：[lab17-bridge-directed-20261118-06](../../results/lab13_19/lab17/lab17-bridge-directed-20261118-06/result.txt)，24 项通过，含完整 WDB。
- ICache 功能 run：[lab17-icache-functional-20261118-02](../../results/lab13_19/lab17/lab17-icache-functional-20261118-02/result.txt)，94/94 通过。
- 无缓存基线：[lab17-baseline-functional-20261118-01](../../results/lab13_19/lab17/lab17-baseline-functional-20261118-01/result.txt)，94/94 通过。
- [波形索引](../../results/lab13_19/lab17/waveform-index.txt)；[功能对照 CSV](../../results/lab13_19/lab17/functional-comparison.csv)。
- 三个最终 run 的 `source-integrity.txt` 均为 PASS；两个 SoC run 的 COE 镜像 SHA-256 均为 `D2FE2D064B2611237805DCB502A273329C8DE5FACF5C8368F55DE1326D3C2244`。
- 每个类别只保留一个最终有效 run；本阶段的失败和被替代目录已清理。

## 复现入口

```powershell
vivado -mode batch -source scripts/tlb_cache/run_unit.tcl -tclargs lab17 directed <repo-root> <run-dir>
vivado -mode batch -source scripts/tlb_cache/run_soc.tcl -tclargs <repo-root> <run-dir> lab17
vivado -mode batch -source scripts/tlb_cache/run_soc.tcl -tclargs <repo-root> <run-dir> lab17_baseline
# 或者使用统一入口：
.\scripts\tlb_cache\verify.ps1 -Case lab17 -Suite functional -RunId lab17-icache-94-02
```
