#!/usr/bin/env zsh
#
# hub-repos.sh
# 指定した GitHub ユーザーのリポジトリ一覧を JSON 配列で取得する
#
# 使い方:
#   ./hub-repos.sh [username]
#   ./hub-repos.sh [https://github.com/username ...]  （URL 指定も可、owner 部分のみ抽出）
#   環境変数 SNS_USERNAME でユーザー名を指定することも可能
#
# 出力:
#   標準出力に JSON 配列を1つ出力する。各要素は
#   {owner, repo, url} を持つオブジェクト（favorite-repos.json の
#   repos[].repos[] 要素と同じ形。clone-favorite-repos.sh --import-* に
#   そのまま渡せる）。
#
# 認証:
#   GitHub CLI (gh) の認証情報を利用する。
#   事前に `gh auth login` を実行しておくこと
#   （macOS ではトークンが Keychain に安全に保存される）。
#
# 任意環境変数:
#   GH_HOST        - github.com 以外（GitHub Enterprise 等）を対象にする場合に指定
#                     （gh CLI 標準の環境変数。詳細は `gh help environment` 参照）
#   SNS_USERNAME   - 引数省略時に使うユーザー名
#   REPO_TYPE      - all | owner | member (デフォルト: owner)
#                    private repo も含めたい場合の絞り込み条件
#   INCLUDE_FORKS  - 1 を指定すると fork リポジトリも含める（デフォルト: 除外）

set -o errexit
set -o nounset
set -o pipefail

# ---------------------------------------------------------------------------
# 定数
# ---------------------------------------------------------------------------
typeset -r SCRIPT_NAME="${0:t}"
typeset -r PER_PAGE=100
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
    require_command gh
    require_command jq
}

check_gh_auth() {
    if ! gh auth status >/dev/null 2>&1; then
        log_error "gh が認証されていません。'gh auth login' を実行してください。"
        exit 1
    fi
}

resolve_username() {
    local input="${1:-${SNS_USERNAME:-}}"
    if [[ -z "$input" ]]; then
        log_error "GitHub username is not specified（引数または SNS_USERNAME を指定してください）"
        exit 1
    fi
    extract_owner "$input"
}

# ---------------------------------------------------------------------------
# 引数がプレーンなユーザー名ではなく GitHub の URL
# （https://host/owner, https://host/owner/repo, git@host:owner/repo 等）
# で渡された場合に、owner 部分だけを取り出す
# ---------------------------------------------------------------------------
extract_owner() {
    local input="$1" path owner

    if [[ "$input" == git@*:* ]]; then
        path="${input#*:}"
    elif [[ "$input" == *://* ]]; then
        path="${input#*://}"
        path="${path#*@}"  # ssh://git@host/... のユーザー情報を除去
        path="${path#*/}"  # host を除去
    else
        print -r -- "$input"
        return
    fi

    owner="${path%%/*}"
    if [[ -z "$owner" ]]; then
        log_error "URL からユーザー名（owner）を抽出できません: ${input}"
        exit 2
    fi
    print -r -- "$owner"
}

# ---------------------------------------------------------------------------
# API 呼び出し（gh api --paginate によりページネーションを自動処理）
# ---------------------------------------------------------------------------
fetch_all_repo_names() {
    local username="$1"
    local tmp_err jq_program

    tmp_err="$(mktemp)"

    if [[ "${INCLUDE_FORKS:-0}" == "1" ]]; then
        jq_program='.[] | {owner: (.full_name | split("/")[0]), repo: .name, url: (.html_url + ".git")}'
    else
        jq_program='.[] | select(.fork == false) | {owner: (.full_name | split("/")[0]), repo: .name, url: (.html_url + ".git")}'
    fi

    # `trap ... EXIT` はスクリプト全体の終了時に発火するため、この関数の
    # local 変数（tmp_err）はその時点で既にスコープ外になり nounset エラー
    # で落ちる（＝成功時も呼び出し元に失敗と誤認される）。
    # 同じ関数スコープ内で確実にクリーンアップするため always ブロックを使う。
    {
        if ! gh api --paginate \
                --method GET \
                "users/${username}/repos" \
                -f "per_page=${PER_PAGE}" \
                -f "type=${REPO_TYPE}" \
                --jq "$jq_program" \
                2>"$tmp_err" \
            | jq -s '.'
        then
            log_error "GitHub API 呼び出しに失敗しました（gh api）。認証状態・ユーザー名を確認してください。"
            log_error "詳細: $(cat "$tmp_err")"
            exit 2
        fi
    } always {
        rm -f "$tmp_err"
    }
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
    check_dependencies
    check_gh_auth

    local username
    username="$(resolve_username "${1:-}")"

    fetch_all_repo_names "$username"
}

main "$@"
