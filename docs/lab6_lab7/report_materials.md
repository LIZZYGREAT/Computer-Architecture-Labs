# Lab6–Lab7 实验报告材料（当前已验证证据）

## 已有可引用结果

- Lab3 forwarding 基线：23/23，172,599 cycles，0 stalls，独立 trace 匹配。
- Lab4 forwarding 基线：23/23，114,577 cycles，50 stalls，EX/MEM/WB 前递均有覆盖，独立 trace 匹配。
- Lab6 ALU 定向用例：算术/立即数/可变移位边界通过；73 cycles、1 次 load-use stall，EX/MEM/WB forwarding 使用次数为 7/6/3，独立 trace 匹配。
- 累计 Lab6 在 S2 节点到达 n35 `div`，此前 n24–n34 的 34 个功能点通过；该节点之后没有完成 HI/LO 功能。

## 当前 Lab6–Lab7 状态

Lab6 乘除法/HI-LO 与 Lab7 转移/访存 RTL 已加入唯一累计 CPU 工程，但完整 DUT 验证未完成。2026-10-22 Lab7 forwarding 运行在 Xelab 生成 C 编译阶段失败，XSim 未开始执行；因此没有 Lab6/7 的累计功能点、DUT trace 匹配结果或 CPU 波形。详细状态见 [verification.md](verification.md)。

## 波形材料

老师要求的真实波形分析和截图尚未完成。需要先使 Xelab/XSim 正常运行，再按 [waveforms.md](waveforms.md) 导出 8 类代表性 PNG，登记 WDB/WCFG、测试映像哈希和运行结果。当前不可把设计说明或 IP 配置截图作为功能波形证据。

本文件只总结当前实际通过的基线和 S2 结果，不构成 Lab6/Lab7 最终实验结论。
