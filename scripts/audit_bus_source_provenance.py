#!/usr/bin/env python3
"""Correlate preserved Lab10/Lab11 run manifests with Git without rewriting history."""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import io
import subprocess
from pathlib import Path


FIELDS = [
    "case", "run_id", "suite", "source_commit", "source_dirty", "source_diff_sha256",
    "historical_manifest", "historical_manifest_sha256", "path", "role",
    "hash_basis", "historical_sha256", "source_commit_sha256", "target_head_sha256",
    "current_worktree_sha256", "git_relation", "path_status", "run_provenance_status",
    "audit_basis",
]


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def read_kv(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if path.is_file():
        for line in path.read_text(encoding="utf-8-sig", errors="replace").splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                values[key.strip()] = value.strip()
    return values


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        return []
    with path.open("r", newline="", encoding="utf-8-sig", errors="replace") as stream:
        return list(csv.DictReader(stream))


def git_bytes(repo: Path, spec: str) -> bytes | None:
    result = subprocess.run(
        ["git", "-C", str(repo), "show", spec],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False,
    )
    return result.stdout if result.returncode == 0 else None


def repository_path(repo: Path, raw_path: str) -> tuple[Path | None, str | None]:
    candidate = Path(raw_path)
    if not candidate.is_absolute():
        candidate = repo / candidate
    candidate = candidate.resolve(strict=False)
    try:
        relative = candidate.relative_to(repo.resolve()).as_posix()
    except ValueError:
        return candidate, None
    return candidate, relative


def git_relation(repo: Path, source_commit: str, target_head: str,
                 git_path: str | None) -> tuple[str, str | None, str | None]:
    if not git_path or not source_commit:
        return "MISSING_INPUT", None, None
    before = git_bytes(repo, f"{source_commit}:{git_path}")
    target = git_bytes(repo, f"{target_head}:{git_path}")
    if before is None:
        return "MISSING_INPUT", None, sha256_bytes(target) if target is not None else None
    before_hash = sha256_bytes(before)
    target_hash = sha256_bytes(target) if target is not None else None
    return ("COMMITTED_UNCHANGED" if target_hash == before_hash else "MODIFIED_SINCE_RUN",
            before_hash, target_hash)


def audit_one_path(repo: Path, target_head: str, run: dict[str, str], row: dict[str, str],
                   manifest: Path, manifest_hash: str) -> dict[str, str]:
    source_commit = run.get("SOURCE_COMMIT", "")
    source_dirty = run.get("SOURCE_DIRTY", "").lower() == "true"
    raw_path = row.get("path", "").strip()
    current_path, git_path = repository_path(repo, raw_path) if raw_path else (None, None)
    relation, commit_hash, head_hash = git_relation(repo, source_commit, target_head, git_path)
    current_hash = sha256_file(current_path) if current_path and current_path.is_file() else "MISSING"
    historical_hash = row.get("sha256", "").strip().upper()

    if not raw_path or relation == "MISSING_INPUT":
        path_status = (
            "RUN_ARTIFACT_UNTRACKED" if current_hash != "MISSING" and git_path and git_path.startswith("results/")
            else "MISSING_INPUT" if current_hash == "MISSING" else "UNTRACKED_INPUT"
        )
    elif current_hash == "MISSING":
        path_status = "MISSING_INPUT"
    elif relation == "MODIFIED_SINCE_RUN" or (head_hash and current_hash != head_hash):
        path_status = "MODIFIED_SINCE_RUN"
    elif historical_hash and historical_hash not in {"MISSING", "NONE"} and historical_hash != commit_hash:
        # The historical five-column table was read at run setup, but it did not
        # preserve a dirty working-tree snapshot that could explain this delta.
        path_status = "MODIFIED_SINCE_RUN"
    else:
        path_status = "COMMITTED_UNCHANGED"

    effective_status = run.get("EFFECTIVE_MANIFEST_STATUS", "")
    if effective_status == "PASS":
        run_status = "EFFECTIVE_MANIFEST_RECORDED"
    elif effective_status == "FAIL":
        run_status = "EFFECTIVE_MANIFEST_INTEGRITY_FAIL"
    else:
        run_status = "HISTORICAL_DIRTY_UNPROVEN" if source_dirty else path_status
    if not source_commit:
        run_status = "MISSING_INPUT"
    if row.get("source_phase") == "PRE_SIM":
        basis = "EFFECTIVE_PRE_SIM_SOURCE_MANIFEST"
    else:
        basis = "LEGACY_SOURCE_MANIFEST" if row.get("role") else "INPUT_MANIFEST_REFERENCE"
    return {
        "case": run.get("CASE", ""), "run_id": run.get("RUN_ID", ""),
        "suite": run.get("SUITE", ""), "source_commit": source_commit,
        "source_dirty": str(source_dirty).lower(),
        "source_diff_sha256": run.get("SOURCE_DIFF_SHA256", ""),
        "historical_manifest": manifest.resolve().as_posix() if manifest.is_file() else "MISSING",
        "historical_manifest_sha256": manifest_hash,
        "path": git_path or raw_path, "role": row.get("role", "reference_input"),
        "hash_basis": row.get("hash_basis", "FILE_CONTENT" if row.get("role") else "INPUT_REFERENCE"),
        "historical_sha256": historical_hash,
        "source_commit_sha256": commit_hash or "MISSING",
        "target_head_sha256": head_hash or "MISSING",
        "current_worktree_sha256": current_hash,
        "git_relation": relation, "path_status": path_status,
        "run_provenance_status": run_status, "audit_basis": basis,
    }


def run_directories(repo: Path) -> list[Path]:
    root = repo / "results/lab10_lab11"
    if not root.is_dir():
        return []
    return sorted((path.parent for path in root.rglob("result.txt")), key=lambda path: path.as_posix().lower())


def audit_run(repo: Path, target_head: str, run_dir: Path) -> tuple[list[dict[str, str]], dict[str, str]]:
    info = read_kv(run_dir / "result.txt")
    case = info.get("CASE", run_dir.parent.name)
    if case not in {"lab10", "lab11"}:
        return [], info
    info.setdefault("CASE", case)
    info.setdefault("RUN_ID", run_dir.name)
    input_rows = read_csv(run_dir / "input_manifest.csv") or read_csv(run_dir / "input-manifest.csv")
    input_row = next((row for row in input_rows if row.get("case") == case), {})
    for key in ("SOURCE_COMMIT", "SOURCE_DIRTY", "SOURCE_DIFF_SHA256"):
        fallback = {"SOURCE_COMMIT": "source_commit", "SOURCE_DIRTY": "source_dirty",
                    "SOURCE_DIFF_SHA256": "source_diff_sha256"}[key]
        if not info.get(key):
            info[key] = input_row.get(fallback, "")

    effective_manifest = run_dir / "effective-source-manifest.csv"
    legacy_manifest = run_dir / "source-manifest.csv"
    manifest = effective_manifest if effective_manifest.is_file() else legacy_manifest
    manifest_hash = sha256_file(manifest) if manifest.is_file() else "MISSING"
    rows = read_csv(manifest)
    if manifest == effective_manifest:
        phases = {row.get("source_phase", "") for row in rows}
        integrity = info.get("SOURCE_INTEGRITY", "") or read_kv(run_dir / "source-integrity.txt").get("SOURCE_INTEGRITY", "")
        info["EFFECTIVE_MANIFEST_STATUS"] = (
            "PASS" if integrity == "PASS" and {"PRE_SIM", "POST_SIM"}.issubset(phases) else
            "FAIL" if integrity == "FAIL" else "INCOMPLETE"
        )
        rows = [row for row in rows if row.get("source_phase") == "PRE_SIM"]
    # Ensure that configured run inputs remain visible even when the old table
    # omitted them or recorded only a subset of the actual compiler inputs.
    known_paths = {row.get("path", "").replace("\\", "/").lower() for row in rows}
    input_references = []
    for key, role in (("xpr", "project_input"), ("coe_path", "instruction_coe"),
                      ("mif_path", "instruction_mif"), ("trace_path", "reference_trace")):
        value = input_row.get(key, "").strip()
        if value and value.replace("\\", "/").lower() not in known_paths:
            input_references.append({"path": value, "role": role, "sha256": ""})
    if not rows:
        rows = input_references
    else:
        rows.extend(input_references)
    if not rows:
        rows = [{"path": "", "role": "", "sha256": ""}]
    info["SOURCE_COMMIT"] = info.get("SOURCE_COMMIT", "")
    return [audit_one_path(repo, target_head, info, row, manifest, manifest_hash) for row in rows], info


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--target-head", default="HEAD")
    parser.add_argument("--output-csv", type=Path)
    parser.add_argument("--output-doc", type=Path)
    args = parser.parse_args()
    repo = args.repo_root.resolve()
    target_head = subprocess.run(["git", "-C", str(repo), "rev-parse", args.target_head],
                                 check=True, capture_output=True, text=True).stdout.strip()
    branch = subprocess.run(["git", "-C", str(repo), "branch", "--show-current"],
                            check=True, capture_output=True, text=True).stdout.strip()
    output_csv = args.output_csv or repo / "report/lab10-11/data/source-correlation-audit.csv"
    output_doc = args.output_doc or repo / "report/lab10-11/docs/source-provenance-audit.md"
    all_rows: list[dict[str, str]] = []
    run_summaries: list[tuple[str, str, str, int]] = []
    for run_dir in run_directories(repo):
        rows, info = audit_run(repo, target_head, run_dir)
        if not rows:
            continue
        dirty = info.get("SOURCE_DIRTY", "").lower() == "true"
        path_statuses = {row["path_status"] for row in rows}
        effective_status = info.get("EFFECTIVE_MANIFEST_STATUS", "")
        if effective_status == "PASS":
            overall = "EFFECTIVE_MANIFEST_RECORDED"
        elif effective_status == "FAIL":
            overall = "EFFECTIVE_MANIFEST_INTEGRITY_FAIL"
        elif dirty:
            overall = "HISTORICAL_DIRTY_UNPROVEN"
        else:
            overall = (
                "MISSING_INPUT" if "MISSING_INPUT" in path_statuses else
                "MODIFIED_SINCE_RUN" if "MODIFIED_SINCE_RUN" in path_statuses else
                "COMMITTED_UNCHANGED"
            )
        run_summaries.append((info.get("CASE", ""), info.get("RUN_ID", run_dir.name), overall, len(rows)))
        all_rows.extend(rows)

    output_csv.parent.mkdir(parents=True, exist_ok=True)
    buffer = io.StringIO(newline="")
    writer = csv.DictWriter(buffer, fieldnames=FIELDS, lineterminator="\n")
    writer.writeheader()
    writer.writerows(all_rows)
    output_csv.write_text(buffer.getvalue(), encoding="utf-8-sig")

    status_names = (
        "COMMITTED_UNCHANGED", "MODIFIED_SINCE_RUN", "HISTORICAL_DIRTY_UNPROVEN",
        "EFFECTIVE_MANIFEST_RECORDED", "EFFECTIVE_MANIFEST_INTEGRITY_FAIL", "MISSING_INPUT",
    )
    counts = {name: sum(status == name for _, _, status, _ in run_summaries) for name in status_names}
    timestamp = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    lines = [
        "# Lab10 / Lab11 历史源码关联性审计", "",
        f"- 生成时间：`{timestamp}`", f"- 当前分支：`{branch}`", f"- 对照目标：`{target_head}`",
        f"- 审计 Run 数：{len(run_summaries)}；路径记录数：{len(all_rows)}。",
        f"- Run 状态计数：`COMMITTED_UNCHANGED={counts['COMMITTED_UNCHANGED']}`、"
        f"`MODIFIED_SINCE_RUN={counts['MODIFIED_SINCE_RUN']}`、"
        f"`HISTORICAL_DIRTY_UNPROVEN={counts['HISTORICAL_DIRTY_UNPROVEN']}`、"
        f"`EFFECTIVE_MANIFEST_RECORDED={counts['EFFECTIVE_MANIFEST_RECORDED']}`、"
        f"`EFFECTIVE_MANIFEST_INTEGRITY_FAIL={counts['EFFECTIVE_MANIFEST_INTEGRITY_FAIL']}`、"
        f"`MISSING_INPUT={counts['MISSING_INPUT']}`。", "",
        "## 口径", "",
        "本审计读取 Run 的 `result.txt`、`input_manifest.csv` 和 Git 对象；若存在"
        "`effective-source-manifest.csv`，优先使用其 `PRE_SIM` 行，否则回退到旧 `source-manifest.csv`。"
        "逐路径比较 Run 记录的提交对象、目标提交对象、当前工作区文件哈希，以及清单保存的 SHA-256；"
        "输出写入独立审计 CSV，不回写运行文件。`COMMITTED_UNCHANGED` 只表示可访问文件在提交链与当前"
        "工作区中未发现变化。", "",
        "旧 Run 若 `SOURCE_DIRTY=true` 且没有精确有效源码清单，标为 `HISTORICAL_DIRTY_UNPROVEN`；旧清单"
        "没有保存未提交内容的逐文件快照，不能证明运行时使用了提交对象中的版本。若 Run 具有 PRE/POST"
        "有效清单且 `SOURCE_INTEGRITY=PASS`，则标为 `EFFECTIVE_MANIFEST_RECORDED`：实际文件集和哈希均已记录，"
        "并证明运行期间未变化。`source_dirty` 与逐路径相对 Git/当前工作区的关系仍分别保留。", "",
        "旧五列 `source-manifest.csv` 不完整，可能未覆盖活动 CPU RTL、头文件、实际 sim top、私有 IP 配置"
        "或验证脚本；其 SHA-256 只证明该 CSV 文件内容，不能代表完整历史源码快照。", "",
        f"逐路径结果见 [`source-correlation-audit.csv`](../data/{output_csv.name})。", "",
        "## Run 明细", "",
        "| Case | Run ID | Run 状态 | 路径记录数 |", "| --- | --- | --- | ---: |",
    ]
    lines.extend(f"| {case} | `{run_id}` | `{status}` | {count} |" for case, run_id, status, count in run_summaries)
    output_doc.parent.mkdir(parents=True, exist_ok=True)
    output_doc.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"SOURCE_CORRELATION_AUDIT={output_csv}")
    print(f"SOURCE_PROVENANCE_AUDIT={output_doc}")
    print(f"AUDITED_RUNS={len(run_summaries)}")
    print(f"AUDITED_PATHS={len(all_rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
