# GCC / AppContainer 诊断证据

- `gcc62-processstart-*` 与 `gcc62-start-matrix.txt`：Codex PowerShell AppContainer 中的启动失败；隔离 PATH 仍返回 Win32 623。
- `xelab-compiler-command.txt`、`xelab-default-env.log`、`xelab-*-metadata.txt`：Xelab 传给 Vivado GCC 6.2.0 的真实命令、参数、CWD，以及默认/曾注入 GCC 路径的环境对照。
- `gcc-xsim5-compile-*.log`：用 GCC 6.2.0 编译 XSim 生成的 `xsim_5.c`；普通用户 PATH 与隔离 PATH 两种运行均退出 0。
- `appcontainer-lab{3,7}-*`：Xelab 编译 C 内核失败的结果与原始日志；XSim 没有启动。
- `verify-appcontainer-*`：`verify.ps1` 新增的上下文预检在 AppContainer 下提前停止。
- `verify-ordinary-*`：普通 PowerShell 的 token 为 `WINDOWS_APPCONTAINER=False`，Vivado 工程/IP 预检通过。

日志捕获了 PATH、`GCC_SIM_EXE_PATH`、`RDI_MINGW_LIB` 和 Xelab 实际调用路径；未捕获 Windows loader 的 DLL 装载跟踪，无法指认某个冲突 DLL。
