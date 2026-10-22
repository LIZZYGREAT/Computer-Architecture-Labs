# 历史验收记录说明

早期验证曾在 Xelab 编译阶段报 `XSIM 43-3409`，XSim 未启动。当时把 PowerShell 的 Win32 错误 623 误判为 GCC 本身无法启动。后续复查区分出执行上下文：Codex 受限 PowerShell 使用 AppContainer token，在该上下文 GCC 子进程无法启动；普通 Windows PowerShell（非 AppContainer）下 GCC 6.2 与完整 XSim 验收通过。

早期结果曾显示 0 个功能点和 0 周期；这些数字表示仿真未运行，不是 CPU 功能结果。脚本现会在 AppContainer 下提前返回 `ENVIRONMENT_ERROR`，并写出 token 上下文，避免将类似环境问题误记为功能失败或零周期。

旧的重复失败重试目录已从 `results` 清理。当前可用于报告的 PASS 运行、独立 trace、阶段日志、WDB 与 GCC 诊断证据统一见 [`verification-final.md`](verification-final.md)、[`delivery-manifest.md`](delivery-manifest.md) 和 [`gcc-startup-incident.md`](gcc-startup-incident.md)。
