#!/usr/bin/env python3
"""
1_extract_diffs.py

対象リポジトリの全コミット(または --since 指定範囲)を走査し、
各コミットのハッシュ・現メッセージ・diff を JSONL 形式で書き出す。

使い方:
    cd /path/to/your/repo
    python3 1_extract_diffs.py --out diffs.jsonl
    python3 1_extract_diffs.py --out diffs.jsonl --since HEAD~50  # 直近50件のみ
    python3 1_extract_diffs.py --out diffs.jsonl --max-diff-chars 4000  # diffを切り詰め
"""

import argparse
import json
import subprocess
import sys


def run(cmd):
    # text=True だとUTF-8として不正なバイト列(バイナリ差分やShift-JISファイル名混入等)で
    # UnicodeDecodeError を起こして落ちるため、bytesで受け取ってerrors="replace"で手動デコードする
    result = subprocess.run(cmd, capture_output=True)
    stdout = result.stdout.decode("utf-8", errors="replace")
    stderr = result.stderr.decode("utf-8", errors="replace")
    if result.returncode != 0:
        print(f"[ERROR] command failed: {' '.join(cmd)}\n{stderr}", file=sys.stderr)
        sys.exit(1)
    return stdout


def get_commit_list(since):
    rev_range = since if since else "--all"
    # 親コミットが複数(マージコミット)は対象外にする(--no-merges)
    out = run(["git", "log", "--no-merges", "--reverse", "--pretty=format:%H", rev_range])
    return [h for h in out.splitlines() if h.strip()]


def has_parent(commit_hash):
    result = subprocess.run(
        ["git", "rev-parse", "--verify", "-q", f"{commit_hash}~1"],
        capture_output=True, text=True,
    )
    return result.returncode == 0


def get_commit_info(commit_hash, max_diff_chars):
    msg = run(["git", "log", "-1", "--pretty=format:%s%n%b", commit_hash]).strip()
    files = run(["git", "diff-tree", "--no-commit-id", "--name-status", "-r", commit_hash]).strip()
    if has_parent(commit_hash):
        diff = run(["git", "diff", f"{commit_hash}~1", commit_hash])
    else:
        # 根本コミット(親なし): 空ツリーとの差分 = 全ファイルが追加された状態
        diff = run(["git", "diff-tree", "--root", "-p", commit_hash])
    truncated = False
    if max_diff_chars and len(diff) > max_diff_chars:
        diff = diff[:max_diff_chars]
        truncated = True
    return {
        "hash": commit_hash,
        "old_message": msg,
        "files_changed": files,
        "diff": diff,
        "diff_truncated": truncated,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, help="出力先 JSONL ファイル")
    ap.add_argument("--since", default=None, help="git log に渡すrev-range (例: HEAD~50)。省略時は全履歴")
    ap.add_argument("--max-diff-chars", type=int, default=6000, help="diffの最大文字数(トークン節約用)")
    args = ap.parse_args()

    commits = get_commit_list(args.since)
    print(f"[INFO] {len(commits)} commits found (merge commits excluded).")

    with open(args.out, "w", encoding="utf-8") as f:
        for i, h in enumerate(commits, 1):
            info = get_commit_info(h, args.max_diff_chars)
            f.write(json.dumps(info, ensure_ascii=False) + "\n")
            if i % 50 == 0:
                print(f"[INFO] {i}/{len(commits)} processed")

    print(f"[DONE] wrote {args.out}")


if __name__ == "__main__":
    main()
