#!/usr/bin/env zsh
#
# hub-repos.sh
# 指定した GitHub ユーザーのリポジトリ一覧を JSON 配列で取得する
#
# 使い方:
#   GITHUB_TOKEN=xxxx ./hub-repos.sh [username]
#   環境変数 SNS_USERNAME でユーザー名を指定することも可能
#
# 出力:
#   標準出力に JSON 配列を1つ出力する。各要素は
#   {name, full_name, html_url, private, fork} を持つオブジェクト。
#
# 必須環境変数:
#   GITHUB_TOKEN   - GitHub Personal Access Token
#
# 任意環境変数:
#   GITHUB_APIURL  - GitHub API のベースURL（デフォルト: https://api.github.com）
#   SNS_USERNAME   - 引数省略時に使うユーザー名
#   REPO_TYPE      - all | owner | member (デフォルト: owner)
#                    private repo も含めたい場合の絞り込み条件

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
    local tmp_response
    local tmp_buffer
    local endpoint

    tmp_response="$(mktemp)"
    tmp_buffer="$(mktemp)"

    # `trap ... EXIT` はスクリプト全体の終了時に発火するため、この関数の
    # local 変数（tmp_response/tmp_buffer）はその時点で既にスコープ外になり
    # nounset エラーで落ちる（＝成功時も呼び出し元に失敗と誤認される）。
    # 同じ関数スコープ内で確実にクリーンアップするため always ブロックを使う。
    {
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

            # jq には $tmp_response を直接読ませる（echo/変数経由だと、zsh の
            # 組み込み echo がデフォルトで \n 等をバックスラッシュ解釈してしまい、
            # レスポンス中の JSON エスケープを破壊して jq のパースが壊れるため）。

            # 配列が空になったらページング終了
            if [[ "$(jq 'length' "$tmp_response")" -eq 0 ]]; then
                break
            fi

            # 必要なフィールドだけに絞り込み、ページごとに NDJSON として貯める
            jq -c '.[] | {name, full_name, html_url, private, fork}' "$tmp_response" >> "$tmp_buffer"

            # per_page 未満の件数しか返らなければ最終ページ
            if [[ "$(jq 'length' "$tmp_response")" -lt "$PER_PAGE" ]]; then
                break
            fi

            (( page++ ))
        done

        # 貯めた NDJSON を1つの JSON 配列にまとめて標準出力へ
        jq -s '.' "$tmp_buffer"
    } always {
        rm -f "$tmp_response" "$tmp_buffer"
    }
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
