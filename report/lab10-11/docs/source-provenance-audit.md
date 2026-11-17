# Lab10 / Lab11 历史源码关联性审计

- 生成时间：`2026-11-17T17:59:13Z`
- 当前分支：`lab10-lab11`
- 对照目标：`fdf438ad8fb0b9bc42972ea9436b54c8e47220cc`
- 审计 Run 数：7；路径记录数：247。
- Run 状态计数：`COMMITTED_UNCHANGED=0`、`MODIFIED_SINCE_RUN=0`、`HISTORICAL_DIRTY_UNPROVEN=6`、`EFFECTIVE_MANIFEST_RECORDED=1`、`EFFECTIVE_MANIFEST_INTEGRITY_FAIL=0`、`MISSING_INPUT=0`。

## 口径

本审计读取 Run 的 `result.txt`、`input_manifest.csv` 和 Git 对象；若存在`effective-source-manifest.csv`，优先使用其 `PRE_SIM` 行，否则回退到旧 `source-manifest.csv`。逐路径比较 Run 记录的提交对象、目标提交对象、当前工作区文件哈希，以及清单保存的 SHA-256；输出写入独立审计 CSV，不回写运行文件。`COMMITTED_UNCHANGED` 只表示可访问文件在提交链与当前工作区中未发现变化。

旧 Run 若 `SOURCE_DIRTY=true` 且没有精确有效源码清单，标为 `HISTORICAL_DIRTY_UNPROVEN`；旧清单没有保存未提交内容的逐文件快照，不能证明运行时使用了提交对象中的版本。若 Run 具有 PRE/POST有效清单且 `SOURCE_INTEGRITY=PASS`，则标为 `EFFECTIVE_MANIFEST_RECORDED`：实际文件集和哈希均已记录，并证明运行期间未变化。`source_dirty` 与逐路径相对 Git/当前工作区的关系仍分别保留。

旧五列 `source-manifest.csv` 不完整，可能未覆盖活动 CPU RTL、头文件、实际 sim top、私有 IP 配置或验证脚本；其 SHA-256 只证明该 CSV 文件内容，不能代表完整历史源码快照。

逐路径结果见 [`source-correlation-audit.csv`](../data/source-correlation-audit.csv)。

## Run 明细

| Case | Run ID | Run 状态 | 路径记录数 |
| --- | --- | --- | ---: |
| lab10 | `s4-directed-authorized-lab10-20261117` | `HISTORICAL_DIRTY_UNPROVEN` | 39 |
| lab10 | `s5-full-capture-lab10-retry1-20261117` | `HISTORICAL_DIRTY_UNPROVEN` | 39 |
| lab11 | `lab11-prot-fix-full-20261117-01` | `HISTORICAL_DIRTY_UNPROVEN` | 39 |
| lab11 | `lab11-source-provenance-directed-20261118-03` | `EFFECTIVE_MANIFEST_RECORDED` | 48 |
| lab11 | `preflight-stage-separation-20261118-02` | `HISTORICAL_DIRTY_UNPROVEN` | 4 |
| lab11 | `s4-directed-authorized-lab11-20261117` | `HISTORICAL_DIRTY_UNPROVEN` | 39 |
| lab11 | `s5-full-capture-lab11-fix1-20261117` | `HISTORICAL_DIRTY_UNPROVEN` | 39 |
