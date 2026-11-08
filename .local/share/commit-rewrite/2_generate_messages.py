#!/usr/bin/env python3
"""
2_generate_messages.py

1_extract_diffs.py の出力(diffs.jsonl)を読み、各コミットについて
Conventional Commits 形式のメッセージを Claude API で生成する。

事前準備:
    pip install anthropic --break-system-packages
    export ANTHROPIC_API_KEY=sk-ant-...

使い方(まずドライランで数件だけ確認):
    python3 2_generate_messages.py --in diffs.jsonl --out messages.json --dry-run --limit 5

問題なければ本番実行(全件):
    python3 2_generate_messages.py --in diffs.jsonl --out messages.json
"""

import argparse
import json
import os
import sys
import time

try:
    import anthropic
except ImportError:
    print("[ERROR] pip install anthropic --break-system-packages を先に実行してください", file=sys.stderr)
    sys.exit(1)


SYSTEM_PROMPT = """あなたはgitコミット履歴の整理を行うアシスタントです。
与えられたdiffと変更ファイル一覧から、Conventional Commits形式の
コミットメッセージを1つだけ生成してください。

ルール:
- 形式: <type>(<scope>): <summary>
  - type は feat, fix, docs, style, refactor, test, chore, perf のいずれか
  - scope は変更の主対象(ディレクトリ名やモジュール名など)。不明なら省略可
  - summary は日本語で50文字以内、命令形または体言止め
- 本文(1行空けて詳細)は、diffから読み取れる「何を変更したか」を箇条書き2〜4行で。
  「なぜ」変更したかはdiffから読み取れないため、推測で書かないこと。
- 出力はコミットメッセージ本文のみ。前置き・後書き・Markdown装飾は一切不要。
"""


def build_user_prompt(entry):
    return f"""変更ファイル:
{entry['files_changed']}

diff:
{entry['diff']}
{'(diffは長いため途中で切り詰めています)' if entry.get('diff_truncated') else ''}

元のメッセージ(参考、意味がないものが多い): {entry['old_message']!r}
"""


def generate_one(client, entry, model="claude-sonnet-4-6"):
    resp = client.messages.create(
        model=model,
        max_tokens=500,
        system=SYSTEM_PROMPT,
        messages=[{"role": "user", "content": build_user_prompt(entry)}],
    )
    text_blocks = [b.text for b in resp.content if b.type == "text"]
    return "".join(text_blocks).strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="infile", required=True)
    ap.add_argument("--out", dest="outfile", required=True, help="hash -> new message の JSON")
    ap.add_argument("--dry-run", action="store_true", help="ファイルに保存せず、標準出力に表示するのみ")
    ap.add_argument("--limit", type=int, default=None, help="処理件数を制限(ドライラン確認用)")
    ap.add_argument("--model", default="claude-sonnet-4-6")
    ap.add_argument(
        "--fresh", action="store_true",
        help="既存の --out ファイルを無視して全件を最初から生成し直す(デフォルトは未処理分のみのレジューム)",
    )
    args = ap.parse_args()

    with open(args.infile, encoding="utf-8") as f:
        entries = [json.loads(line) for line in f if line.strip()]

    # 既存の messages.json があれば読み込み、すでに成功済みのハッシュはスキップする
    # (= 前回APIエラーでスキップされたコミットだけが対象になる)
    results = {}
    if not args.dry_run and not args.fresh and os.path.exists(args.outfile):
        with open(args.outfile, encoding="utf-8") as f:
            results = json.load(f)
        before = len(entries)
        entries = [e for e in entries if e["hash"] not in results]
        print(
            f"[INFO] resume mode: {args.outfile} に既存 {len(results)} 件を検出。"
            f"未処理 {len(entries)}/{before} 件のみ再試行します。"
            f" (全件やり直す場合は --fresh を指定)",
            file=sys.stderr,
        )

    if args.limit:
        entries = entries[: args.limit]

    if not entries:
        print("[INFO] 未処理のコミットはありません。すべて処理済みです。")
        return

    client = anthropic.Anthropic()  # ANTHROPIC_API_KEY を環境変数から読む
    failed = []

    for i, entry in enumerate(entries, 1):
        h = entry["hash"]
        try:
            new_msg = generate_one(client, entry, model=args.model)
        except Exception as e:
            print(f"[WARN] {h[:8]} failed: {e} -- skip (元のメッセージを維持)", file=sys.stderr)
            failed.append(h)
            continue

        if args.dry_run:
            print("=" * 60)
            print(f"commit {h[:8]}")
            print(f"  旧: {entry['old_message']!r}")
            print(f"  新:\n{new_msg}")
        else:
            results[h] = new_msg

        if i % 10 == 0:
            print(f"[INFO] {i}/{len(entries)} generated", file=sys.stderr)
            if not args.dry_run:
                # 途中経過をこまめに保存(長時間実行中のクラッシュ対策)
                with open(args.outfile, "w", encoding="utf-8") as f:
                    json.dump(results, f, ensure_ascii=False, indent=2)

        time.sleep(0.3)  # レート制限対策(必要に応じ調整)

    if not args.dry_run:
        with open(args.outfile, "w", encoding="utf-8") as f:
            json.dump(results, f, ensure_ascii=False, indent=2)
        print(f"[DONE] wrote {args.outfile} ({len(results)} messages total)")
        if failed:
            print(f"[INFO] {len(failed)} 件が今回も失敗しました。同じコマンドを再実行すれば再試行されます。", file=sys.stderr)
    else:
        print(f"\n[DONE] dry-run complete ({len(entries)} entries). ファイルには保存していません。")


if __name__ == "__main__":
    main()
