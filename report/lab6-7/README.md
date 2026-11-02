# Lab6—Lab7 实验报告

## 交付内容

- `main.tex`：按 Lab1 报告模板的封面和章节样式撰写的完整报告。
- `figures/`：Python 生成的结构、握手、退休事件和验收统计图。本版不包含 Vivado 波形截图。
- `data/`：由验收结果、匹配后的 trace 和 HI/LO testbench 结果收集的 CSV，以及图像来源索引。
- `scripts/build_figures.py`：校验当前结果后，重建 Python PNG 和 CSV 数据表。
- `docs/evidence-index.md`：结论与原始验收证据之间的索引及范围说明。
- `docs/report-data-notes.md`：面向后续报告修改的数据摘要、定向事件值和图表来源。

## 编译

使用 Codex 内置 LaTeX 编辑器打开此目录并编译 `main.tex`。项目使用 XeLaTeX/CTeX 可用的中文环境；图像路径相对 `main.tex`。

## 重绘插图

从仓库根目录执行：

```powershell
python .\report\lab6-7\scripts\build_figures.py
```

脚本读取累计回归、ALU/DIV/扩展控制转移定向 trace 与 HI/LO 单元结果，先检查 DUT PASS、trace 哈希和参考匹配，再生成 CSV 与 Python 图表。Lab6/Lab7 累计回归和 ALU 定向运行的 WDB 已归档；DIV 与扩展控制转移定向运行没有 WDB，因此相关图是参考 trace 事件图，不是周期级波形。本版没有嵌入 Vivado 截图。
