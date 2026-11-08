#!/usr/bin/env python3
"""
2_generate_messages_ollama.py

1_extract_diffs.py の出力(diffs.jsonl)を読み、各コミットについて
Conventional Commits 形式のメッセージを Ollama(ローカルLLM)で生成する。

Claude API版(2_generate_messages.py)との違いは、生成バックエンドが
ローカルの Ollama サーバー(デフォルト http://localhost:11434)になっている点のみ。
resume(未処理分のみ再試行)・dry-run・途中保存の仕様は同じ。

事前準備:
    # Ollamaをインストールし、コード向けモデルをpullしておく
    #   brew install ollama            (macOSの場合)
    #   ollama serve                   (サーバー起動。常駐させておく)
    #   ollama pull qwen2.5-coder:14b  (モデル取得。7B以下だと精度が落ちやすい)

    pip install requests --break-system-packages

使い方(まずドライランで数件だけ確認):
    python3 2_generate_messages_ollama.py --in diffs.jsonl --out messages.json --dry-run --limit 5

問題なければ本番実行(全件。既存messages.jsonがあれば未処理分のみ再試行):
    python3 2_generate_messages_ollama.py --in diffs.jsonl --out messages.json

モデルやホストを変える場合:
    python3 2_generate_messages_ollama.py --in diffs.jsonl --out messages.json \
        --model deepseek-coder-v2:16b --host http://localhost:11434
"""

import argparse
import json
import os
import sys
import time

try:
    import requests
except ImportError:
    print(
        "[ERROR] pip install requests --break-system-packages を先に実行してください",
        file=sys.stderr,
    )
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
- 出力はコミットメッセージ本文のみ。前置き・後書き・Markdown装飾・```などの
  コードフェンスは一切不要。説明や確認の言葉("承知しました"等)も付けないこと。
"""


def build_user_prompt(entry):
    return f"""変更ファイル:
{entry["files_changed"]}

diff:
{entry["diff"]}
{"(diffは長いため途中で切り詰めています)" if entry.get("diff_truncated") else ""}

元のメッセージ(参考、意味がないものが多い): {entry["old_message"]!r}
"""


def strip_code_fence(text):
    """モデルが ```...``` で囲って返してくることがあるため、あれば剥がす。"""
    text = text.strip()
    if text.startswith("```"):
        lines = text.split("\n")
        if lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        text = "\n".join(lines).strip()
    return text


def generate_one(entry, host, model, timeout):
    resp = requests.post(
        f"{host}/api/generate",
        json={
            "model": model,
            "system": SYSTEM_PROMPT,
            "prompt": build_user_prompt(entry),
            "stream": False,
            "options": {
                "temperature": 0.2,  # コミットメッセージ生成なので低めにして安定させる
            },
        },
        timeout=timeout,
    )
    resp.raise_for_status()
    data = resp.json()
    return strip_code_fence(data.get("response", ""))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="infile", required=True)
    ap.add_argument(
        "--out", dest="outfile", required=True, help="hash -> new message の JSON"
    )
    ap.add_argument(
        "--dry-run",
        action="store_true",
        help="ファイルに保存せず、標準出力に表示するのみ",
    )
    ap.add_argument(
        "--limit", type=int, default=None, help="処理件数を制限(ドライラン確認用)"
    )
    ap.add_argument(
        "--model",
        default="qwen3-coder:latest",
        help="Ollamaのモデル名(事前にpull済みであること)",
    )
    ap.add_argument(
        "--host", default="http://localhost:11434", help="OllamaサーバーのURL"
    )
    ap.add_argument(
        "--timeout", type=int, default=120, help="1リクエストあたりのタイムアウト秒数"
    )
    ap.add_argument(
        "--fresh",
        action="store_true",
        help="既存の --out ファイルを無視して全件を最初から生成し直す(デフォルトは未処理分のみのレジューム)",
    )
    args = ap.parse_args()

    # Ollamaサーバーが起動しているか事前チェック
    try:
        requests.get(f"{args.host}/api/tags", timeout=5)
    except requests.exceptions.ConnectionError:
        print(
            f"[ERROR] {args.host} に接続できません。"
            f" `ollama serve` でサーバーが起動しているか確認してください。",
            file=sys.stderr,
        )
        sys.exit(1)

    with open(args.infile, encoding="utf-8") as f:
        entries = [json.loads(line) for line in f if line.strip()]

    # 既存の messages.json があれば読み込み、すでに成功済みのハッシュはスキップする
    # (= 前回失敗(タイムアウト等)でスキップされたコミットだけが対象になる)
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

    print(
        f"[INFO] model={args.model} host={args.host} 対象={len(entries)}件",
        file=sys.stderr,
    )

    failed = []
    t_start = time.time()

    for i, entry in enumerate(entries, 1):
        h = entry["hash"]
        try:
            new_msg = generate_one(entry, args.host, args.model, args.timeout)
            if not new_msg:
                raise ValueError("空の応答が返されました")
        except Exception as e:
            print(
                f"[WARN] {h[:8]} failed: {e} -- skip (元のメッセージを維持)",
                file=sys.stderr,
            )
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
            elapsed = time.time() - t_start
            avg = elapsed / i
            remain = avg * (len(entries) - i)
            print(
                f"[INFO] {i}/{len(entries)} generated"
                f" (avg {avg:.1f}s/commit, 残り約{remain / 60:.1f}分)",
                file=sys.stderr,
            )
            if not args.dry_run:
                # 途中経過をこまめに保存(長時間実行中のクラッシュ対策)
                with open(args.outfile, "w", encoding="utf-8") as f:
                    json.dump(results, f, ensure_ascii=False, indent=2)

    if not args.dry_run:
        with open(args.outfile, "w", encoding="utf-8") as f:
            json.dump(results, f, ensure_ascii=False, indent=2)
        print(f"[DONE] wrote {args.outfile} ({len(results)} messages total)")
        if failed:
            print(
                f"[INFO] {len(failed)} 件が今回も失敗しました。同じコマンドを再実行すれば再試行されます。",
                file=sys.stderr,
            )
    else:
        print(
            f"\n[DONE] dry-run complete ({len(entries)} entries). ファイルには保存していません。"
        )


if __name__ == "__main__":
    main()
