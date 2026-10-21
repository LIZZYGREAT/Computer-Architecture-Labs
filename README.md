# MIPS 五级流水线实验仓库（Lab3–Lab7）

## 唯一 CPU 工程

`lab3/CPU_CDE/mycpu_verify/` 是从 Lab3 开始、逐阶段累积修改的唯一 CPU 与 Vivado 工程。目录名保留历史路径，不表示它只用于 Lab3。`lab3/CPU_CDE/cpu132_gettrace/` 是生成独立参考轨迹的参考 CPU。Lab6 和 Lab7 不复制 CPU 工程或 `.xpr`。

## 实验材料

- Lab3 基础材料：`lab3/CPU_CDE/soft/func_lab3/`
- Lab4 累积功能测试：`lab4/func_lab4/`
- Lab5 沿用 Lab4 的 CPU 状态；验收节点由 Git 标签 `lab5-forwarding-verified` 记录，不另建一份 CPU 工程。
- Lab6 累计功能测试：`lab6/func_lab6/`；乘除法模块级教学 testbench 参考位于 `lab6/乘法器模块级验证顶层/`。
- Lab7 累计功能测试：`lab7/func_lab7/`
- Lab6/Lab7 原始任务要求和实施方案：`docs/lab6_lab7/`

Lab6/7 目录目前保存课程测试资源和 ROM 映像；CPU 指令扩展、对应验收脚本与波形报告尚未实施。`scripts/verify.ps1` 当前用于 Lab3/Lab4 验证。

## 已记录的基线结果

Lab3/Lab4 的验收记录和复现材料见 `docs/lab3-lab4/verification-final.md`，原始结果见 `results/lab3_lab4/`。该记录报告 Lab3 与 Lab4 功能测试通过，Lab4 forwarding 也有定向冒险测试证据。本仓库初始化时没有重新运行这些测试。

Lab6/Lab7 的 `obj/inst_ram.mif`、`inst_ram.coe`、`data_ram.mif` 和 `data_ram.coe` 是课程仿真映像，保留在仓库。`.elf`、`.bin`、`.data`、生成的 `test.s`、Vivado 缓存和未归档日志由 `.gitignore` 排除，可按课程 Makefile 或 Vivado 工程重新生成。

`docs/lab6_lab7/requirements.txt` 是课程实验要求原文，不是软件包依赖清单。
