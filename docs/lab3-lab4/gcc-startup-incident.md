# Vivado GCC / Xelab 启动故障排查

记录日期：2026-10-22。此记录区分 Vivado 自带 GCC 的实际行为与运行它的 PowerShell 安全上下文。

## 结论

问题的可复现边界是 **Windows AppContainer 执行上下文**，不是已证实的 GCC 安装损坏或某一个 DLL 冲突：Codex 的受限 PowerShell token 为 AppContainer；从该进程启动 Vivado GCC 6.2.0 会抛 Win32 错误 623，即使把 `PATH` 隔离为 `C:\Windows\System32;C:\Windows` 也一样。普通 Windows PowerShell（`TokenIsAppContainer=0`）中，GCC 6.2.0 可以运行 `--version` 并编译 XSim 生成的 C 文件；在该上下文启动 `verify.ps1` 后，Vivado/XSim 全流程通过。

因此，原先“GCC 6.2 本身无法启动”以及“只要删除 GCC 路径覆盖就解决了”的结论都不准确。Vivado 使用其默认工具配置时确实调用内置 GCC 6.2.0；能否启动取决于启动 Vivado 的进程安全上下文。当前 `verify.ps1` 会先检查 `TokenIsAppContainer`，处于 AppContainer 时返回 `ENVIRONMENT_ERROR`，并在结果目录写出 `host-context.txt`，避免把环境启动限制误报成 DUT 的零周期结果。

## Xelab 的实际调用

详细日志中的 GCC 可执行文件和 `xsim_2.c` 编译参数如下：

```text
D:\Verilog\2025.2\Vivado\data\..\tps\mingw\6.2.0\win64.o\nt\bin\gcc.exe -fPIC -c -Wa,-W -I"D:\Verilog\2025.2\Vivado\data/xsim/include" "xsim.dir/tb_top_verbose/obj/xsim_2.c" -O1 -o "xsim.dir/tb_top_verbose/obj/xsim_2.win64.obj" -DXILINX_SIMULATOR
CWD=C:\Users\lenovo\Desktop\Projects\FPGA\lab\lab3\CPU_CDE\mycpu_verify\run_vivado\mycpu_prj1\mycpu_prj1.sim\sim_1\behav\xsim
```

Xelab 也用同一 GCC 6.2.0 链接 `xsimk.exe`、`xsim_0/1/2.win64.obj` 与 Vivado XSim kernel。原始命令和环境元数据在 [`gcc-diagnostic-20261022`](../../results/lab3_lab4/gcc-diagnostic-20261022/)；其中保留默认配置和注入路径对照、实际启动失败记录及 XSim C 编译复现。

本轮 Lab7/Lab3 的失败日志记录 `xsim_5.c` 和 `XSIM 43-3409`。这表示 Xelab 的 C 内核构建阶段失败，XSim 没有启动；该轮 0 个功能点、0 周期是“未执行”，不能写成仿真测得零周期。失败轮的 `result.txt`、`simulation-vivado.log` 与 `xsim-elaborate.log` 已收拢到同一诊断目录。

## PATH、环境变量与 DLL 搜索

| 对照 | GCC 环境 | 结果 |
|---|---|---|
| Codex 受限 PowerShell | `TokenIsAppContainer=1`；默认 PATH 或仅 `C:\Windows\System32;C:\Windows` | `Process.Start(gcc.exe --version)` 返回 Win32 623，未启动 |
| 普通 Windows PowerShell | `TokenIsAppContainer=0`；当前 Windows 用户 PATH | GCC 6.2.0 `--version` 退出 0；实际 XSim C 编译退出 0 |
| 普通 Windows PowerShell，隔离 PATH | `TokenIsAppContainer=0`；PATH 仅含 Windows System32/Windows | GCC 6.2.0 启动和实际 XSim C 编译均退出 0 |

环境元数据还比较了 `GCC_SIM_EXE_PATH`、`RDI_MINGW_LIB` 和 PATH：Vivado 默认 `RDI_MINGW_LIB` 指向 GCC 6.2.0 的 `bin`/`libexec`；旧诊断把 GCC 9.5.0/10.0.0 路径放在 PATH 与 `RDI_MINGW_LIB` 前部，但 Xelab 日志仍显式调用 GCC 6.2.0。`verify.ps1` 与 `run_behavioral_sim.tcl` 当前不改写这些变量，也不设置额外 GCC 路径；Vivado 继承启动它的 PowerShell 环境。

错误 623 的 Windows 定义描述 DLL 占用了系统 DLL 保留的地址范围，但错误文本没有给出本次冲突 DLL 名称。[Microsoft 的 Win32 错误码 623 文档](https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--500-999-)说明了错误含义。我们记录了进程 PATH 和 Vivado GCC 变量，没有取得 Windows loader 的模块搜索/装载跟踪，因此**不能**把错误归因到某个 DLL，也不能推断 GCC 文件损坏。

## 最小处理与复核结果

- 在普通 Windows PowerShell（不是 AppContainer 终端）中从仓库根目录运行 `verify.ps1`。工具启动后会记录 `WINDOWS_APPCONTAINER=False`；若该值为 `True`，脚本会提前停止并提示换到普通 PowerShell。
- Vivado 保持默认编译器配置；没有替换系统 DLL、没有重装 Vivado、没有重写 CPU。
- 普通上下文下 Lab3 forwarding、Lab4 blocking/forwarding、定向 blocking/forwarding 均通过；Lab7 累计 forwarding 也通过 68/68。当前结果入口见 [`verification-final.md`](verification-final.md) 和 [`docs/lab6_lab7/verification.md`](../lab6_lab7/verification.md)。

Codex AppContainer 复现和普通上下文预检的精简记录在 [`gcc-diagnostic-20261022`](../../results/lab3_lab4/gcc-diagnostic-20261022/)。
