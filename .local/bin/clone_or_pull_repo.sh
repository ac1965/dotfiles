#!/usr/bin/env zsh
#
# clone_or_pull_repo.sh
# 指定した Git リポジトリ URL を解析し、
#   ${GITHUB_REPOS}/<host>/<owner>/<repo>
# 配下に clone（未取得時）または pull（既取得時）する。
#
# 使い方:
#   GITHUB_REPOS=~/repos ./clone_or_pull_repo.sh https://github.com/org/repo.git
#   T=~/repos            ./clone_or_pull_repo.sh git@github.com:org/repo.git
#   (T は GITHUB_REPOS が未設定の場合のみフォールバックとして使われる)
#
# 必須環境変数（いずれか。GITHUB_REPOS を正式名称として推奨）:
#   GITHUB_REPOS  - リポジトリ保存先ルート（正式名称）
#   T             - 後方互換のための短縮エイリアス（GITHUB_REPOS 未設定時のみ参照）
#
# 任意環境変数:
#   HUB_REPOS_SCRIPT - オーナーのリポジトリ名一覧を取得するスクリプトのパス
#                       （デフォルト: ${HOME}/.bin/hub-repos.sh）
#   GITHUB_TOKEN      - hub-repos.sh 呼び出しに使う GitHub トークン
#                       （未設定の場合、一覧取得ステップは警告を出してスキップ）
#
# hub-repos.sh との連携契約（list_github_repos.sh がこの契約を満たす）:
#   入力: 第1引数にオーナー名（GitHub ユーザー名 / Organization 名）
#   出力: 標準出力にリポジトリ名を1行1件、ヘッダーなしで出力
#   失敗時: 非ゼロ終了コード（本スクリプト側では致命扱いにせず警告のみで継続）
#
# 対応 URL 形式:
#   https://host/owner/repo(.git)
#   http://host/owner/repo(.git)
#   git@host:owner/repo(.git)
#   ssh://git@host/owner/repo(.git)

set -o errexit
set -o nounset
set -o pipefail

# ---------------------------------------------------------------------------
# 定数
# ---------------------------------------------------------------------------
typeset -r SCRIPT_NAME="${0:t}"
typeset -r HUB_REPOS_SCRIPT="${HUB_REPOS_SCRIPT:-${HOME}/.bin/hub-repos.sh}"

# ---------------------------------------------------------------------------
# ユーティリティ
# ---------------------------------------------------------------------------
log_info()  { print -- "→ $*" }
log_error() { print -u2 -- "❌ [${SCRIPT_NAME}] $*" }

usage() {
    print -u2 -- "Usage: ${SCRIPT_NAME} <git repository URL>"
}

require_command() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || {
        log_error "コマンドが見つかりません: ${cmd}"
        exit 127
    }
}

# ---------------------------------------------------------------------------
# 事前チェック
# ---------------------------------------------------------------------------
check_dependencies() {
    require_command git
}

resolve_repo_root() {
    # GITHUB_REPOS を正式名称とし、T は後方互換の短縮エイリアスとして扱う
    local root="${GITHUB_REPOS:-${T:-}}"
    if [[ -z "$root" ]]; then
        log_error "環境変数 GITHUB_REPOS（または T）を設定してください。"
        exit 1
    fi
    print -r -- "$root"
}

check_args() {
    if [[ $# -ne 1 ]]; then
        usage
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# URL 解析
# host / owner / repo を抽出する
# 対応形式:
#   https://host/owner/repo.git
#   http://host/owner/repo.git
#   git@host:owner/repo.git
#   ssh://git@host/owner/repo.git
# ---------------------------------------------------------------------------
parse_git_url() {
    local url="$1"
    local host owner repo path

    if [[ "$url" == git@*:* ]]; then
        # scp形式: git@host:owner/repo.git
        host="${url#git@}"
        host="${host%%:*}"
        path="${url#*:}"
    else
        # https:// http:// ssh:// 形式
        path="${url#*://}"
        # ssh://git@host/... のようにユーザー情報が付く場合を除去
        path="${path#*@}"
        host="${path%%/*}"
        path="${path#*/}"
    fi

    IFS='/' read -r owner repo _ <<< "$path"

    # 末尾の .git を除去
    repo="${repo%.git}"

    if [[ -z "$host" || -z "$owner" || -z "$repo" ]]; then
        log_error "URL からホスト・オーナー・リポジトリ名が抽出できません: ${url}"
        exit 2
    fi

    print -r -- "${host}"$'\t'"${owner}"$'\t'"${repo}"
}

# ---------------------------------------------------------------------------
# オーナーのリポジトリ一覧を保存（付随的な処理のため失敗しても本処理は継続する）
#
# hub-repos.sh の契約: 第1引数=owner、標準出力にリポジトリ名を1行1件出力。
# list_github_repos.sh はこの契約を満たすため、
#   cp list_github_repos.sh ~/.bin/hub-repos.sh && chmod +x ~/.bin/hub-repos.sh
# のように配置すればそのまま利用できる。
# ---------------------------------------------------------------------------
save_owner_repo_list() {
    local owner="$1"
    local dest_dir="$2"
    local out_file="${dest_dir}/repos-${owner}.txt"

    if [[ ! -x "$HUB_REPOS_SCRIPT" ]]; then
        return 0
    fi

    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        log_info "GITHUB_TOKEN 未設定のため、リポジトリ一覧の取得をスキップします。"
        return 0
    fi

    if ! "$HUB_REPOS_SCRIPT" "$owner" > "$out_file"; then
        log_error "hub-repos.sh の実行に失敗しました（一覧取得のみスキップして続行します）: ${owner}"
        rm -f "$out_file"
    fi
}

# ---------------------------------------------------------------------------
# clone または pull を実行
# ---------------------------------------------------------------------------
clone_or_pull() {
    local url="$1"
    local repo="$2"
    local dest_dir="$3"

    if [[ -d "${dest_dir}/${repo}" ]]; then
        log_info "既存のリポジトリを更新: ${repo}"
        git -C "${dest_dir}/${repo}" pull
    else
        log_info "リポジトリをクローン: ${repo}"
        git -C "${dest_dir}" clone --recursive "$url"
    fi
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
    check_dependencies
    check_args "$@"

    local url="$1"
    local repo_root
    repo_root="$(resolve_repo_root)"

    local host owner repo
    IFS=$'\t' read -r host owner repo <<< "$(parse_git_url "$url")"

    print -- "url: ${url}"
    print -- "owner: ${owner}"
    print -- "repo: ${repo}"

    local dest_dir="${repo_root}/${host}/${owner}"
    mkdir -p "$dest_dir"
    print -- "repo_dir: ${dest_dir}"

    save_owner_repo_list "$owner" "$dest_dir"
    clone_or_pull "$url" "$repo" "$dest_dir"
}

main "$@"
