# Lab6—Lab7 实验报告

## 交付内容

- `main.tex`：按 Lab1 报告模板的封面和章节样式撰写的完整报告。
- `figures/`：Python 生成的 CPU 结构、HI/LO 握手、定向分支流程和功能点汇总图。它们是说明图/统计图，不是 Vivado 波形截图。
- `scripts/build_figures.py`：从仓库验收结果读取数据并重建上述 PNG。
- `docs/evidence-index.md`：结论与原始验收证据之间的索引及范围说明。

## 编译

使用 Codex 内置 LaTeX 编辑器打开此目录并编译 `main.tex`。项目使用 XeLaTeX/CTeX 可用的中文环境；图像路径相对 `main.tex`。

## 重绘插图

从仓库根目录执行：

```powershell
python .\report\lab6-7\scripts\build_figures.py
```

脚本读取 `results/lab6_lab7/lab6-20261022T062908Z/result.txt` 与 `lab7-20261022T063433Z/result.txt`，确认两轮功能点完整通过后才生成汇总图。
