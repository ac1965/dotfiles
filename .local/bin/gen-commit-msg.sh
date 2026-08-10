#!/usr/bin/env bash
#
# gen-commit-msg.sh
#
# ステージ済みの git diff (git diff --cached) を Ollama に渡し、
# Conventional Commits 形式のコミットメッセージを生成する。
#
# 事前準備:
#   ollama serve                    (別ターミナルで起動しておく)
#   ollama pull qwen2.5-coder:14b   (初回のみ)
#
# 使い方:
#   git add -A
#   ./gen-commit-msg.sh                     # メッセージを表示するだけ
#   ./gen-commit-msg.sh --commit            # 生成したメッセージでそのままコミット
#   ./gen-commit-msg.sh --commit --edit     # 生成後、エディタで確認・編集してからコミット
#   ./gen-commit-msg.sh --model deepseek-coder-v2:16b
#   ./gen-commit-msg.sh --host http://localhost:11434
#
set -euo pipefail

MODEL="qwen3-coder:latest"
HOST="http://localhost:11434"
DO_COMMIT=0
DO_EDIT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)  MODEL="$2"; shift 2 ;;
    --host)   HOST="$2"; shift 2 ;;
    --commit) DO_COMMIT=1; shift ;;
    --edit)   DO_EDIT=1; shift ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *)
      echo "[ERROR] unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# --- 前提チェック -----------------------------------------------------

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[ERROR] gitリポジトリの中で実行してください" >&2
  exit 1
fi

DIFF="$(git diff --cached)"
if [[ -z "$DIFF" ]]; then
  echo "[ERROR] ステージされた変更がありません。先に 'git add' してください" >&2
  exit 1
fi

if ! curl -s -o /dev/null -w '%{http_code}' "$HOST/api/tags" | grep -q '^200$'; then
  echo "[ERROR] $HOST に接続できません。'ollama serve' が起動しているか確認してください" >&2
  exit 1
fi

FILES_CHANGED="$(git diff --cached --name-status)"

# --- プロンプト組み立て ------------------------------------------------

SYSTEM_PROMPT='あなたはgitコミット履歴の整理を行うアシスタントです。
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
  コードフェンスは一切不要。説明や確認の言葉("承知しました"等)も付けないこと。'

# diffが巨大すぎるとコンテキスト長を超えるため、上限を設けて切り詰める
MAX_DIFF_CHARS=8000
if [[ ${#DIFF} -gt $MAX_DIFF_CHARS ]]; then
  DIFF="${DIFF:0:$MAX_DIFF_CHARS}
(diffは長いため途中で切り詰めています)"
fi

USER_PROMPT="変更ファイル:
${FILES_CHANGED}

diff:
${DIFF}"

# --- Ollama呼び出し -----------------------------------------------------
# jqへの依存を避けるため、リクエストJSONの組み立て・レスポンスのパースは python3 で行う

REQUEST_JSON="$(
  MODEL="$MODEL" SYSTEM_PROMPT="$SYSTEM_PROMPT" USER_PROMPT="$USER_PROMPT" python3 -c '
import json, os
print(json.dumps({
    "model": os.environ["MODEL"],
    "system": os.environ["SYSTEM_PROMPT"],
    "prompt": os.environ["USER_PROMPT"],
    "stream": False,
    "options": {"temperature": 0.2},
}))
'
)"

echo "[INFO] model=$MODEL host=$HOST でメッセージを生成中..." >&2

RESPONSE="$(curl -s -X POST "$HOST/api/generate" -d "$REQUEST_JSON")"

COMMIT_MSG="$(
  echo "$RESPONSE" | python3 -c '
import json, sys
data = json.load(sys.stdin)
text = data.get("response", "").strip()
# モデルが ```...``` で囲って返すことがあるため剥がす
if text.startswith("```"):
    lines = text.split("\n")
    if lines[0].startswith("```"):
        lines = lines[1:]
    if lines and lines[-1].strip() == "```":
        lines = lines[:-1]
    text = "\n".join(lines).strip()
print(text)
'
)"

if [[ -z "$COMMIT_MSG" ]]; then
  echo "[ERROR] メッセージの生成に失敗しました。Ollamaの応答:" >&2
  echo "$RESPONSE" >&2
  exit 1
fi

echo "----------------------------------------"
echo "$COMMIT_MSG"
echo "----------------------------------------"

# --- コミット実行(任意) -------------------------------------------------

if [[ $DO_COMMIT -eq 1 ]]; then
  if [[ $DO_EDIT -eq 1 ]]; then
    git commit -e -m "$COMMIT_MSG"
  else
    git commit -m "$COMMIT_MSG"
  fi
else
  echo "[INFO] --commit を付けると、このメッセージでそのままコミットします" >&2
fi
