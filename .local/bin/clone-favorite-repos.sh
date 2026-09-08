#!/usr/bin/env zsh
#
# clone-favorite-repos.sh
# favorite-repos.json に列挙されたリポジトリを一括で clone / pull する。
# 実処理は hub-clone.sh（clone_or_pull_repo.sh）に委譲する。
#
# 使い方:
#   GITHUB_REPOS=~/repos ./clone-favorite-repos.sh
#   GITHUB_REPOS=~/repos ./clone-favorite-repos.sh -c emacs
#   GITHUB_REPOS=~/repos ./clone-favorite-repos.sh -c security-pentest -c reverse-engineering
#   ./clone-favorite-repos.sh --list-categories
#   ./clone-favorite-repos.sh -n            # dry-run
#
# 必須環境変数（いずれか。hub-clone.sh に準拠）:
#   GITHUB_REPOS  - リポジトリ保存先ルート（正式名称）
#   T             - 後方互換のための短縮エイリアス
#
# 任意環境変数:
#   FAVORITE_REPOS_JSON - favorite-repos.json のパス
#                         （デフォルト: ${XDG_DATA_HOME:-~/.local/share}/favorite-repos.json、
#                          次点で ./favorite-repos.json）
#   HUB_CLONE_SCRIPT    - clone/pull を行うスクリプトのパス
#                         （デフォルト: このスクリプトと同じディレクトリの hub-clone.sh）

set -o errexit
set -o nounset
set -o pipefail

typeset -r SCRIPT_NAME="${0:t}"
typeset -r SCRIPT_DIR="${0:A:h}"

log_info()  { print -- "→ $*" }
log_error() { print -u2 -- "❌ [${SCRIPT_NAME}] $*" }

usage() {
    cat <<EOF >&2
Usage: ${SCRIPT_NAME} [-c category ...] [-n] [-j favorite-repos.json]
       ${SCRIPT_NAME} --list-categories

  -c, --category NAME   このカテゴリのリポジトリのみ対象にする（複数指定可）
  -j, --json PATH       favorite-repos.json のパスを指定する
  -n, --dry-run         clone/pull を実行せず対象を表示するのみ
      --list-categories 利用可能なカテゴリ一覧を表示して終了する
  -h, --help            このヘルプを表示する
EOF
}

require_command() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || {
        log_error "コマンドが見つかりません: ${cmd}"
        exit 127
    }
}

check_dependencies() {
    require_command jq
}

resolve_json_path() {
    if [[ -n "${FAVORITE_REPOS_JSON:-}" ]]; then
        print -r -- "$FAVORITE_REPOS_JSON"
        return
    fi
    # ${SCRIPT_DIR} は通常 .../.local/bin なので、その兄弟ディレクトリ
    # .../.local/share を見る（リポジトリ内でも deploy 後の $HOME でも成立する）。
    if [[ -f "${SCRIPT_DIR}/../share/favorite-repos.json" ]]; then
        print -r -- "${SCRIPT_DIR}/../share/favorite-repos.json"
        return
    fi
    local xdg_data_home="${XDG_DATA_HOME:-${HOME}/.local/share}"
    if [[ -f "${xdg_data_home}/favorite-repos.json" ]]; then
        print -r -- "${xdg_data_home}/favorite-repos.json"
        return
    fi
    if [[ -f "./favorite-repos.json" ]]; then
        print -r -- "./favorite-repos.json"
        return
    fi
    log_error "favorite-repos.json が見つかりません。FAVORITE_REPOS_JSON か -j で指定してください。"
    exit 1
}

resolve_hub_clone_script() {
    local script="${HUB_CLONE_SCRIPT:-${SCRIPT_DIR}/hub-clone.sh}"
    if [[ ! -x "$script" ]]; then
        log_error "hub-clone.sh が見つかりません、または実行できません: ${script}"
        exit 1
    fi
    print -r -- "$script"
}

list_categories() {
    local json_file="$1"
    jq -r '.repos[].category' "$json_file"
}

main() {
    check_dependencies

    local json_file=""
    local -a categories=()
    local -i dryrun=0
    local -i list_only=0

    while (( $# > 0 )); do
        case "$1" in
            -c|--category)
                [[ $# -ge 2 ]] || { usage; exit 1; }
                categories+=("$2")
                shift 2
                ;;
            -j|--json)
                [[ $# -ge 2 ]] || { usage; exit 1; }
                json_file="$2"
                shift 2
                ;;
            -n|--dry-run)
                dryrun=1
                shift
                ;;
            --list-categories)
                list_only=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "不明な引数です: $1"
                usage
                exit 1
                ;;
        esac
    done

    [[ -n "$json_file" ]] || json_file="$(resolve_json_path)"
    [[ -f "$json_file" ]] || { log_error "ファイルが存在しません: ${json_file}"; exit 1; }

    if (( list_only )); then
        list_categories "$json_file"
        return
    fi

    local hub_clone_script
    hub_clone_script="$(resolve_hub_clone_script)"

    local category_filter=".repos[]"
    if (( ${#categories[@]} > 0 )); then
        local jq_categories
        jq_categories="$(printf '%s\n' "${categories[@]}" | jq -R . | jq -s .)"
        category_filter=".repos[] | select(.category as \$c | ${jq_categories} | index(\$c))"
    fi

    local -a urls
    urls=("${(@f)$(jq -r "${category_filter} | .repos[].url" "$json_file")}")

    if [[ ${#urls[@]} -eq 0 ]]; then
        log_error "対象リポジトリが見つかりません（カテゴリ指定を確認してください）。"
        exit 1
    fi

    log_info "対象リポジトリ数: ${#urls[@]}"

    local url
    for url in "${urls[@]}"; do
        if (( dryrun )); then
            log_info "[dry-run] ${url}"
            continue
        fi
        log_info "処理中: ${url}"
        "$hub_clone_script" "$url"
    done
}

main "$@"
