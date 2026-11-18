# S3：Lab16 Cache 验收报告

**状态：完成**

**分支：** lab12-lab19

## 实现内容

- 在 [cache.v](../../lab16/cache_verify/rtl/cache.v) 实现 Lab16 独立数据 Cache：4 路、256 组、16B/行，总容量 16 KiB。
- 采用 write-back + write-allocate；优先使用无效路，满组后按可复现的轮询指针替换。脏路只会在整行写回握手后进入 refill。
- refill 接受四个 32-bit beat；根据 wstrb 合并写入字节。复位按组同步清除 valid/dirty，不清零数据 RAM；元数据清理完成前不接受请求。
- addr_ok 接受一次 CPU 请求，data_ok 单周期返回完成。内存读写请求在 rdy=0 时保持地址和 payload。
- 官方测试台改为优先报告 replace_wrong 与 cacheres_wrong，防止最后一项错误与结束条件同周期时误报 PASS。runner 要求 256 个 index 00–ff 各完成一次。
- 定向测试台在 [tb_cache_directed.sv](../../lab16/cache_verify/testbench/tb_cache_directed.sv) 验证 miss/hit、连续 word 访问、写命中和写分配、wstrb=0111、干净替换、脏行回写、读写背压 payload 稳定、复位中断与请求记账。

## 验收结果

| 类别 | 最终 RunId | 结果 |
| --- | --- | --- |
| Lab16 官方测试 | [lab16-official-20261118-05](../../results/lab13_19/lab16/lab16-official-20261118-05/result.txt) | PASS；256/256 个 index 各完成一次，Test end! 与 ----PASS!!!；失败标记为 0 |
| Cache 定向检查 | [lab16-directed-20261118-02](../../results/lab13_19/lab16/lab16-directed-20261118-02/result.txt) | PASS；20 项检查，21 次接受、20 次完成、1 次复位取消；16 次读 refill、1 次脏行写回 |

官方仿真结束时间为 265,495 ns。定向仿真结束时间为 7,180 ns。定向仿真对读 miss/hit、干净第五路替换、脏行写回等待、写回后 refill 和复位取消提供了日志时间标记。

两个最终 RunId 均保留 XPR、活动源码清单、Vivado/编译/展开/仿真日志、编译顺序、result.txt、来源 hash 清单和 WDB。source-integrity.txt 均为 PASS，缺失活动工程文件数为 0。

## 波形证据

波形索引：[waveform-index.txt](../../results/lab13_19/lab16/waveform-index.txt)。XSim 开启全信号记录，波形包含 CPU 请求与响应、四路 hit、victim、dirty 元数据、refill 请求与 beat、writeback payload 和 FSM。

- 官方 WDB：4,151,864 字节，SHA-256 59AEB34FF430CE202924058961E2C6056D8591B03D993ACA70A88B51272F6A01。
- 定向 WDB：120,528 字节，SHA-256 D8F728C40948DF18CAF566D86D5D5650F4617235CF032AE523AAA1CA483BB8FB。

WDB 可在 Vivado 中打开检查；另保留了对应场景的仿真日志标记。本阶段未另行导出 GUI 截图。

## 范围说明

Lab16 的 16B/行接口和 128-bit 写回保持独立。后续 Lab17/18 CPU Cache 的 32B/行、8-beat AXI 传输需要单独实现与验收，不能直接把本阶段接口当作最终 CPU 总线协议。
