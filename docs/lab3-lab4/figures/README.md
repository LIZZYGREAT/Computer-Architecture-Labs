# 实测波形证据与截图步骤

已保存定向 forwarding 的真实 XSim 波形数据库：[`hazard-directed-forwarding.wdb`](../../../results/lab3_lab4/lab4-20261021T085125Z/hazard-directed-forwarding.wdb)。该文件来自结果轮次 `lab4-20261021T085125Z`，记录命令为 `log_wave -r /tb_top`，大小 297,380 字节，SHA-256 为 `7C6B5DFBEB1649F823B436E2924D060DD7A3BECDC7BC65122C14AA07C20938F4`。同轮 [`result.txt`](../../../results/lab3_lab4/lab4-20261021T085125Z/result.txt) 记录 72 周期、3 stall、定向 MIF/trace 哈希和 `STATUS=PASS`。

当前尚未保存带标注的 GUI 图片。课程报告需要图片时无需重新仿真，按以下步骤从 WDB 导出：

1. 在 Vivado 2025.2 中选择 **File → Open Waveform Database**，打开上述 WDB。
2. 从 `/tb_top` 层次加入 `resetn`、`soc_clk`、`fs_pc`、`ds_pc`、`ds_valid`、`ds_stall`、`ds_to_es_valid`、`es_allowin`、`es_valid`、`ms_valid`、`ws_valid`、`ds_forward_rs_ex/ms/ws`、`ds_forward_rt_ex/ms/ws` 和 `debug_wb_*`。
3. 在 PC `0xbfc00000–0xbfc00018` 附近截取 ALU 连续相关、EX/MEM/WB 前递和最近生产者优先。
4. 在 PC `0xbfc00024–0xbfc00038` 附近截取 store 基址/数据前递及 load-use 停顿与恢复。
5. 在 PC `0xbfc0003c–0xbfc00058` 附近截取 taken/not-taken branch 与 delay slot；在 `0xbfc00060–0xbfc0007c` 附近截取 JR 目标和 delay slot。
6. 图片标题注明 `lab4-20261021T085125Z`、forwarding、定向 MIF、PC 范围和时间范围，保存到本目录。

这些地址来自实际定向程序 listing。FPGA 上板验证尚未执行。
