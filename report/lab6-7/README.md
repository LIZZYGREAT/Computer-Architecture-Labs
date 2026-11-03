# Lab6—Lab7 实验报告

## 交付内容

- `main.tex`：按 Lab1 报告模板的封面和章节样式撰写的完整报告。
- `figures/`：Python 生成的结构、握手、退休事件和验收统计图，以及本次采集的 25 张 Vivado 波形截图。13 份 Vivado Wave 配置位于 `figures/waveforms/`，绑定到本次有效重采集 WDB。
- `data/`：由验收结果、匹配后的 trace 和 HI/LO testbench 结果收集的 CSV、图像来源索引，以及逐图波形实测记录表。
- `scripts/build_figures.py`：校验当前结果后，重建 Python PNG 和 CSV 数据表。
- `results/lab6_lab7/`：本次隔离工程重采集的 Lab6、Lab7、DIV/分支定向 WDB 与日志。
- `docs/evidence-index.md`：结论与原始验收证据之间的索引及范围说明。
- `docs/report-data-notes.md`：面向后续报告修改的数据摘要、定向事件值和图表来源。
- `docs/wave-capture-handoff.md`：逐图目标值、信号配置、WDB 来源和采集限制。

## 编译

使用 Codex 内置 LaTeX 编辑器打开此目录并编译 `main.tex`。项目使用 XeLaTeX/CTeX 可用的中文环境；图像路径相对 `main.tex`。

## 重绘插图

从仓库根目录执行：

```powershell
python .\report\lab6-7\scripts\build_figures.py
```

脚本读取累计回归、ALU/DIV/扩展控制转移定向 trace 与 HI/LO 单元结果，先检查 DUT PASS、trace 哈希和参考匹配，再生成 CSV 与 Python 图表。Lab6/Lab7 累计回归和 ALU 定向运行的 WDB 已归档；DIV 与扩展控制转移定向运行没有 WDB，因此相关图是参考 trace 事件图，不是周期级波形。

当前配置位于 `figures/waveforms/`。后续实验请按仓库根目录的 `docs/workflow.md` 建立新的日期目录和配置副本，避免覆盖已有 WCFG。

截图目标、手册预期值和逐图实测字段见 `docs/wave-capture-handoff.md` 与 `data/wave-capture-log.csv`。退休事件图的横轴是 trace 顺序；Vivado Wave 截图应使用对应 `.wdb`，并将实际时间窗和读数写入记录表。
