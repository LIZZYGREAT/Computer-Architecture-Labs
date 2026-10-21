# Lab3 / Lab4 正确启动与运行流程

> 本文只记录工程启动、测试映像更新和仿真运行步骤。以下流程依据仓库中的 Vivado 工程、IP 配置和 testbench 整理；本机尚未实际运行 Vivado，因此不表示仿真已经通过。

## 1. 先确认要运行哪套测试

- **Lab3 基线测试**：使用 `lab3/CPU_CDE/soft/func_lab3/obj/` 中随附的预编译映像。
- **Lab4 紧凑测试**：使用 `lab4/func_lab4/` 中的测试源和映像。Lab4 只有测试程序，没有独立 Vivado 工程；运行时仍使用 Lab3 的 CPU 验证工程。
- 如果测试程序改变，reference 和 DUT 必须加载同一份新映像，并重新生成参考 trace。

启动 DUT Vivado 工程需要 Vivado。重新编译测试程序还需要 Linux/WSL、`make`、主机 GCC 和 MIPS little-endian 交叉编译工具链。

## 2. 运行 Lab3 默认映像

若没有修改测试程序，且工程中的 `inst_ram` 初始化映像与现有 `golden_trace.txt` 对应，可直接运行 DUT 仿真，跳到第 4 节。若映像不确定，按 Lab4 的完整流程执行第 3、4 节。

DUT 工程：

`lab3/CPU_CDE/mycpu_verify/run_vivado/mycpu_prj1/mycpu_prj1.xpr`

## 3. 运行 Lab4 测试映像

### 3.1 编译测试程序

在 WSL/Linux 终端中运行：

```bash
cd /mnt/c/Users/lenovo/Desktop/Projects/FPGA/lab/docs/lab4/func_lab4
command -v mipsel-linux-gcc
command -v mipsel-linux-ld
command -v mipsel-linux-objcopy
make clean
make
```

默认工具链前缀是 `mipsel-linux-`。如果工具链命令带 `gnu`，例如 `mipsel-linux-gnu-gcc`，执行：

```bash
make CROSS_COMPILE=mipsel-linux-gnu-
```

确认 `obj/` 下已经生成最新的 `inst_ram.coe` 和 `inst_ram.mif`。`make clean` 会清除 Lab4 当前的 `obj/` 编译结果。

### 3.2 先用参考 CPU 生成 trace

Reference 工程：

`lab3/CPU_CDE/cpu132_gettrace/run_vivado/cpu132_gettrace/cpu132_gettrace.xpr`

1. 在 Vivado 打开上述 `.xpr`。
2. 在 Sources 中找到 `inst_ram`，右键选择 **Re-customize IP**。
3. 在 IP 配置中加载 Lab4 新生成的 `lab4/func_lab4/obj/inst_ram.coe`，确认后生成 Output Products。
4. 启动 **Run Behavioral Simulation**，进入仿真后选择 **Run All**，等待仿真结束。
5. 确认 `lab3/CPU_CDE/cpu132_gettrace/golden_trace.txt` 已更新且非空。必须等 reference 仿真结束后再打开 DUT 工程。

### 3.3 在 DUT 工程装载同一映像

1. 打开 DUT 工程 `lab3/CPU_CDE/mycpu_verify/run_vivado/mycpu_prj1/mycpu_prj1.xpr`。
2. 对 DUT 工程中的 `inst_ram` 执行同样的 **Re-customize IP** 操作，加载同一个 `lab4/func_lab4/obj/inst_ram.coe`，再生成 Output Products。
3. 确认 reference 和 DUT 使用的是同一版测试程序。若只替换了仿真目录中的 `.mif`，要在 Vivado 中点 **Restart** 后再运行仿真。

## 4. 启动 DUT 行为仿真

1. 在 Flow Navigator 选择 **Run Simulation > Run Behavioral Simulation**。
2. 确认仿真顶层为 `tb_top`。SoC 综合顶层是 `soc_lite_top`，不要将 `mycpu_top` 单独作为 SoC 顶层。
3. 仿真窗口打开后选择 **Run All**。
4. 等 testbench 自行运行到结束，不要在生成 trace 或功能点测试完成前停止。
5. 查看 Transcript 输出：通过时应到达 `0xbfc00100`，出现 `Test end!` 和 `PASS!!!`，且没有 `Error!!!`、trace mismatch 或功能点错误。

若 testbench 在结束前报告 mismatch，先确认 reference 与 DUT 的指令 RAM 映像相同，并确认 golden trace 是由当前映像重新生成的。

## 5. 可选：下载到 FPGA 板

只在行为仿真通过后进行：

1. 确认实验板与工程约束相符。工程目标器件为 `xc7a200tfbg676-2`，时钟约束为 10 ns；其他板卡不能直接沿用此 `.xdc`。
2. 在 DUT 工程依次运行 **Run Synthesis**、**Run Implementation** 和 **Generate Bitstream**。
3. 打开 **Hardware Manager**，连接 FPGA 板并下载生成的 bitstream。

没有匹配的实体板卡时，跳过上板步骤，完成行为仿真即可。

## 工程路径速查

- Reference trace 工程：`lab3/CPU_CDE/cpu132_gettrace/run_vivado/cpu132_gettrace/cpu132_gettrace.xpr`
- DUT 验证工程：`lab3/CPU_CDE/mycpu_verify/run_vivado/mycpu_prj1/mycpu_prj1.xpr`
- Lab3 测试映像：`lab3/CPU_CDE/soft/func_lab3/obj/`
- Lab4 测试映像：`lab4/func_lab4/obj/`
- DUT testbench：`lab3/CPU_CDE/mycpu_verify/testbench/mycpu_tb.v`
