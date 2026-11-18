# S2：Lab14 CP0/TLB 验收报告

**状态：完成**

**分支：** `lab12-lab19`

**实现提交：** `ce1cd75`

**验收脚本提交：** `fc34199`、`985f64f`

## 实现内容

- 在独立目录 [lab14/cpu_tlb](../../lab14/cpu_tlb) 中实现 Lab14 CPU 副本，Lab11 已验收源码保持不变。
- CP0 增加 Index、Random、Wired、EntryHi、EntryLo0/1；Index miss 位、寄存器写掩码和 TLBR 回写按 Lab14 方案处理。
- ID 阶段识别 TLBR、TLBWI、TLBWR、TLBP；3 位 TLB 操作侧带进入流水线，在 MEM 提交点单次生效，并阻止年轻指令越过序列化操作。
- CPU 使用 Lab13 的双查找端口 TLB。KSEG0/KSEG1 直映到低 29 位物理地址；映射段使用 `{PFN, VA[11:0]}`。miss、无效页和不可写页会屏蔽总线请求，物理地址没有回退到 VA。
- `addr_translate.v` 输出 `cacheable`：KSEG0 可缓存、KSEG1 不可缓存，映射页以 C=3 标记为可缓存，供后续 Cache 阶段连接。
- Vivado 把旧版 XCI 标记为 locked。回归脚本将 XCI 复制到每次运行的结果目录，替换该副本的 COE 路径并在那里升级/生成 IP；仓库中的 XCI 与 Lab11 源码保持干净。

## 验收结果

| 类别 | 最终 RunId | 结果 |
| --- | --- | --- |
| Lab14 官方 n1–n6 | [lab14-n1-n6-official-20261118-05](../../results/lab13-lab19/lab14/lab14-n1-n6-official-20261118-05/result.txt) | PASS，6/6，4,705 周期 |
| 地址转换定向检查 | [lab14-translate-directed-20261118-02](../../results/lab13-lab19/lab14/lab14-translate-directed-20261118-02/result.txt) | PASS，11/11 |
| Lab11 AXI3 定向回归 | [lab11-axi3-directed-20261118-02](../../results/lab13-lab19/lab14/lab11-axi3-directed-20261118-02/result.txt) | PASS，读写握手、AW/W 独立延迟、重定向取指、错误响应检查均通过 |
| Lab11 CPU golden-trace 回归 | [lab11-cpu-golden-20261118-03](../../results/lab13-lab19/lab14/lab11-cpu-golden-20261118-03/result.txt) | PASS，94/94 功能点，111,625 条 trace 记录耗尽 |

每个最终 RunId 均保留 `result.txt`、Vivado 日志、仿真日志、编译顺序、工程文件、活动源码清单和来源/输入 hash 清单；四个 `source-integrity.txt` 均为 PASS，缺失活动文件数为 0。保存的 WDB 另有 SHA-256 记录：

- 官方 n1–n6：8,298,059 字节，SHA-256 `02EFA22A684345CF52B561E1A44616E472A0F4D24D1CFA2DDC0C8F42F07417E4`。
- 地址转换定向检查：44,020 字节，SHA-256 `69170EB6AE71E3FB0DE1FD2EA7944D9815149179DD2FD70692C5F4EEA1561A9B`。
- AXI3 定向回归：64,406 字节，SHA-256 `A0B253031311995938DDCA543BC0409546A54374EF9E724393319C76322C93C0`。
- Lab11 golden-trace 全信号波形超过 995 MB；最终记录保留完整仿真日志、94 点结果、trace 与总线统计，不保留该超大 WDB。

Lab14 COE/MIF 的 SHA-256 分别为 `FDA79739A58F14DAF500320220DD12FF37B2EED35A3E2A1763B8147AE0F16275` 和 `A043D97CD71CD18817114B5960E36AB924D3D8877417C425AB5BBD20059DE076`。Lab11 golden-trace 输入及 Lab9 COE/MIF 的 hash 均记录在对应 `input_manifest.csv`。

## 定向覆盖与总线指标

11 项地址转换检查覆盖 KSEG0/1 物理别名、映射偶页/奇页、ASID miss、Global 命中、V=0、D=0 的 load/store 行为，以及 TLB miss 时请求被屏蔽且无 VA 直通。

Lab11 golden-trace 回归的总线指标：1,067,615 个流水周期；3,753 次 store 的 AW、W、B 握手各 3,753 次；重复 store 为 0；协议断言错误为 0；丢弃旧取指响应 687 次。trace 共 111,625 条记录，其中 111,583 条有效写回，尾部检查通过。

## 范围与边界

- 本阶段按方案验证 n1–n6。TLB refill/invalid 的专用异常处理属于后续 Lab15 范围；当前 miss/invalid 采取阻断总线请求的行为，相关保护已通过定向检查。
- Lab11 golden-trace 回归覆盖原有 MIPS 功能、异常重定向和总线行为，不代表已实现 TLB refill 异常。
- WDB 已保存并校验 hash；未生成 GUI 截图或手工波形读数记录，因此截图型证据仍标记为待采集。
- 最终只保留每类一个有效 RunId；失败尝试和已被最终记录替代的运行均已清理。
