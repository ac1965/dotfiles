#!/usr/bin/env zsh
#
# list_github_repos.sh
# 指定した GitHub ユーザーのリポジトリ名一覧を取得する
#
# 使い方:
#   GITHUB_TOKEN=xxxx ./list_github_repos.sh [username]
#   環境変数 SNS_USERNAME でユーザー名を指定することも可能
#
# 必須環境変数:
#   GITHUB_TOKEN   - GitHub Personal Access Token
#
# 任意環境変数:
#   GITHUB_APIURL  - GitHub API のベースURL（デフォルト: https://api.github.com）
#   SNS_USERNAME   - 引数省略時に使うユーザー名
#   REPO_TYPE      - all | owner | member (デフォルト: owner)
#                    private repo も含めたい場合の絞り込み条件
#
# hub-repos.sh としての配置（clone_or_pull_repo.sh 連携用）:
#   本スクリプトは「第1引数=owner、標準出力にリポジトリ名を1行1件出力」
#   という契約を満たすため、そのまま hub-repos.sh として使える。
#     mkdir -p ~/.bin
#     cp list_github_repos.sh ~/.bin/hub-repos.sh
#     chmod +x ~/.bin/hub-repos.sh
#   clone_or_pull_repo.sh は GITHUB_TOKEN が設定されている場合のみ
#   ~/.bin/hub-repos.sh（または $HUB_REPOS_SCRIPT）を自動的に呼び出す。

set -o errexit
set -o nounset
set -o pipefail

# ---------------------------------------------------------------------------
# 定数
# ---------------------------------------------------------------------------
typeset -r SCRIPT_NAME="${0:t}"
typeset -r PER_PAGE=100
typeset -r GITHUB_APIURL="${GITHUB_APIURL:-https://api.github.com}"
typeset -r REPO_TYPE="${REPO_TYPE:-owner}"

# ---------------------------------------------------------------------------
# ユーティリティ
# ---------------------------------------------------------------------------
log_error() {
    print -u2 -- "❌ [${SCRIPT_NAME}] $*"
}

require_command() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || {
        log_error "コマンドが見つかりません: ${cmd}（インストールしてください）"
        exit 127
    }
}

# ---------------------------------------------------------------------------
# 事前チェック
# ---------------------------------------------------------------------------
check_dependencies() {
    require_command curl
    require_command jq
}

check_token() {
    : "${GITHUB_TOKEN:?❌ Error: GITHUB_TOKEN is required}"
}

resolve_username() {
    local username="${1:-${SNS_USERNAME:-}}"
    if [[ -z "$username" ]]; then
        log_error "GitHub username is not specified（引数または SNS_USERNAME を指定してください）"
        exit 1
    fi
    print -r -- "$username"
}

# ---------------------------------------------------------------------------
# API 呼び出し（ページネーション対応）
# ---------------------------------------------------------------------------
fetch_all_repo_names() {
    local username="$1"
    local page=1
    local http_status
    local body
    local tmp_response
    local endpoint

    tmp_response="$(mktemp)"
    trap 'rm -f "$tmp_response"' EXIT

    while true; do
        endpoint="${GITHUB_APIURL}/users/${username}/repos?per_page=${PER_PAGE}&page=${page}&type=${REPO_TYPE}"

        http_status="$(
            curl -sS \
                -u ":${GITHUB_TOKEN}" \
                -H "Accept: application/vnd.github+json" \
                -o "$tmp_response" \
                -w '%{http_code}' \
                "$endpoint"
        )" || {
            log_error "API 呼び出し自体に失敗しました（ネットワーク/TLS等）: ${endpoint}"
            exit 2
        }

        if [[ "$http_status" != "200" ]]; then
            log_error "API 呼び出しに失敗しました（HTTP ${http_status}）。ユーザー名またはトークンを確認してください。"
            log_error "レスポンス: $(cat "$tmp_response")"
            exit 2
        fi

        body="$(cat "$tmp_response")"

        # 配列が空になったらページング終了
        if [[ "$(echo "$body" | jq 'length')" -eq 0 ]]; then
            break
        fi

        echo "$body" | jq -r '.[].name'

        # per_page 未満の件数しか返らなければ最終ページ
        if [[ "$(echo "$body" | jq 'length')" -lt "$PER_PAGE" ]]; then
            break
        fi

        (( page++ ))
    done
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
    check_dependencies
    check_token

    local username
    username="$(resolve_username "${1:-}")"

    fetch_all_repo_names "$username"
}

main "$@"
