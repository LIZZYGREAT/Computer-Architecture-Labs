# Lab8 / Lab9 implementation baseline

检查日期：2026-11-09（Asia/Shanghai）
仓库：`lab` 内层 Git 仓库
分支：`lab8-lab9`
基线提交：`abc727449319ba8fdd5a7ba717fdcc2d57309eae`

## 基线验收

Vivado 工程和 IP 只读 preflight 于 `lab7-20261109T135309Z` 通过。preflight 检查了 `sources_1`、`sim_1`、`soc_lite_top` / `tb_top` 顶层、引用文件和 5 个必需 IP，均无缺失、锁定或非 Up-to-date 项。该运行记录保存在 `results/lab6_lab7/lab7-20261109T135309Z/`。

变更前 Lab7 forwarding 回归于 `lab7-20261109T135423Z` 通过：

| 项目 | 实测值 |
|---|---:|
| 功能点 | 68 / 68 |
| Reference GPR trace | 全量匹配 |
| 流水周期 | 166,330 |
| 停顿周期 | 926 |
| EX / MEM / WB 前递 | 49,970 / 12,229 / 15,454 |
| Zero-register 写入尝试 | 0 |
| 依赖副作用检查 | PASS |
| XSim 退出码 / 最终状态 | 0 / PASS |

Run ID、工具输出和哈希记录位于 `results/lab6_lab7/lab7-20261109T135423Z/`。该次输入为 `results/lab6_lab7/golden/lab7/golden_trace.txt`（SHA-256 `23ADD75B2BADFDABF98B1863A89896DFC60B4B351CC49321B22BEB22035991C3`）和 `lab7/func_lab7/obj/inst_ram.mif`（SHA-256 `8EBF314084B3B06BF40A9F4DF2B402E74BE5D1F705A75F7ADFC858868B9B75BE`）。仿真运行后 Vivado 递增了 XPR 中的 launch counter；检查并仅还原该字段后，原工程文件与基线一致。运行日志和 WDB 保留在结果目录，未纳入 Git。

## Lab8 / Lab9 原始映像

以下输入未修改。两份课程 COE 与 MIF 均通过 `scripts/check_instruction_image.py` 检查，与 `inst_ram.xci` 的 262,144-word 深度相符，且 COE/MIF 解码后的全部 word 一致。

| 用例 | Word 数 | COE SHA-256 | MIF SHA-256 | 解码内容 SHA-256 |
|---|---:|---|---|---|
| Lab8 | 167,147 | `2DD81A38B94683B91C66B6F812A8AE375712E2832A4441D471CA81624D507D20` | `D611D547FFDC000F003673B1B9276D1BA813C15008BE071EE6B639DE278ABF51` | `D0A482FF3651CBD400EFB2973F9591A5A1AE8EC950A9A27DFE686070B92E8796` |
| Lab9 | 171,587 | `978140EC69D63A6F264FA6A95A2D28210D9D8A50E2AB105766A1429AA1CE888E` | `392C6386B57F4780536A54F1F5AF34E7749E9AF61CB2DB5703685C4C04CFEB01` | `B6A5737AB6696D52906B9AB45D98E0BE1DF28FB5F8A687E694259297C6F2503` |

## RTL 结构与例外风险

| 路径 / 通道 | 当前结构 | 对 Lab8 / Lab9 的影响 |
|---|---|---|
| `rtl/myCPU/mycpu.h` | `FS_TO_DS=64`、`DS_TO_ES=154`、`ES_TO_MS=114`、`MS_TO_WS=70` | 尚无异常、延迟槽或 CP0 元数据字段；修改总线时需同步更新生产与消费端。 |
| IF → ID | `{inst[31:0], pc[31:0]}` | IF 仅选择分支目标或顺序 PC；没有 AdEL 检测、异常向量选择或旧取指响应丢弃状态。复位取指地址为 `0xBFC00000`。 |
| ID → EX | `HILO_OP[7:0]`, `ALU_OP[11:0]`, `MEM_OP[11:0]`, 控制、寄存器值、立即数、PC | ID 有分支/跳转控制但不携带 `is_delay_slot`。没有 `syscall`、`break`、RI、`mfc0`、`mtc0` 或 `eret` 译码。 |
| EX → MEM | `MEM_OP[11:0]`, GPR 写控制/目的寄存器、结果、旧 RT、PC | EX 计算地址并在该级发出 SRAM 请求；当前 `data_sram_en` 受 valid/ready 控制，但没有地址错误或更老 trap 的 kill 条件。 |
| MEM → WB | GPR 写控制/目的寄存器、结果、PC | MEM 没有异常提交点或 CP0 读写；WB 只按当前 `ws_valid` 和目的寄存器控制 GPR 写回。 |
| HI/LO | `hilo_unit` 内部乘除完成时直接更新 `hi_reg` / `lo_reg`；MTHI/MTLO 也在 EX 接受时写入 | 尚无被更老异常冲刷时的取消/提交协议，必须增加精确 kill 语义。 |
| CPU / SoC 接口 | `mycpu_top` 无中断输入；`soc_lite_top` 无 `ext_int` 来源 | 外部中断需新增明确端口，并由 SoC testbench 控制；普通 Lab3/4/6/7 回归必须驱动零。 |

流水线总线当前字段范围：

```text
FS_TO_DS  [63:32] inst, [31:0] pc
DS_TO_ES [153:146] hilo_op, [145:134] alu_op, [133:122] mem_op,
         [121:118] operand/control select, [117] gr_we, [116:112] dest,
         [111:96] imm, [95:64] rs, [63:32] rt, [31:0] pc
ES_TO_MS [113:102] mem_op, [101] gr_we, [100:96] dest,
         [95:64] result, [63:32] old_rt, [31:0] pc
MS_TO_WS [69] gr_we, [68:64] dest, [63:32] result, [31:0] pc
```

采用方案指定的统一提交模型：异常与 `eret` 在 MEM 对最老有效指令裁决；`mtc0` 在有效 MEM 提交沿更新 CP0；`mfc0` 在 MEM 读取并作为普通写回数据前递；PC 重定向优先级为 trap、eret、分支、顺序取指。实现时需同时抑制 EX 级较年轻 store、HI/LO 和 CP0 副作用。

## 参考模型与验证边界

CPU132 源码中存在 `mfc0`、`mtc0`、`eret` 译码及 Count、Compare、Status、Cause、EPC 寄存器逻辑。它可作为课程 Lab8/Lab9 GPR reference trace 候选；Lab8/Lab9 trace 生成尚未运行，需在 P8/P9 扩展生成器并分别实测，不能用源码存在代替行为验证。现有 `generate_reference_trace.ps1`、`verify.ps1`、`run_behavioral_sim.tcl` 和 `cases.json` 只接受 lab3/lab4/lab6/lab7。CPU132 SoC 没有被测 DUT 的外部中断注入，硬件中断必须用独立、可控的 SoC/testbench 断言。

## 阶段结论

S0 的工程/IP preflight、Lab7 变更前有效回归和原始课程镜像完整性检查均通过。此记录只证明基线条件，不表示 CP0、例外、Lab8/Lab9 回归或硬件中断已经实现或通过。后续各阶段按实施方案逐项验收并提交。
