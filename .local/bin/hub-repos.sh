#!/usr/bin/env zsh

set -o errexit
set -o nounset
set -o pipefail

# 🔐 必須トークンチェック
: "${GITHUB_TOKEN:?❌ Error: GITHUB_TOKEN is required}"

# 🌐 API URL 設定
GITHUB_APIURL="${GITHUB_APIURL:-https://api.github.com}"

# 👤 ユーザー名取得（引数または環境変数から）
USERNAME="${1:-${SNS_USERNAME:-}}"

if [[ -z "$USERNAME" ]]; then
    print -u2 "❌ Error: GitHub username is not specified (引数または SNS_USERNAME を指定してください)"
    exit 1
fi

# 🔗 API エンドポイント組み立て
API_ENDPOINT="${GITHUB_APIURL}/users/${USERNAME}/repos?per_page=100"

# 📡 リクエスト実行（失敗時メッセージ付き）
response="$(curl -sf -u ":${GITHUB_TOKEN}" "$API_ENDPOINT")" || {
    print -u2 "❌ Error: API 呼び出しに失敗しました。ユーザー名またはトークンを確認してください。"
    exit 2
}

# 📋 リポジトリ名一覧を抽出
echo "$response" | jq -r '.[].name'
