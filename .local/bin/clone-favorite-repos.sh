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
#   # favorite-repos.json への取り込み（hub-repos.sh の出力を利用）
#   ./clone-favorite-repos.sh --import-owner d12frosted              # カテゴリは owner 名になる
#   ./clone-favorite-repos.sh --import-owner d12frosted -c emacs     # カテゴリを指定
#   ./clone-favorite-repos.sh --import-json repos-d12frosted.json -c emacs
#   ./clone-favorite-repos.sh --import-owner d12frosted -n           # dry-run（取り込み内容の表示のみ）
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
#   HUB_REPOS_SCRIPT    - --import-owner でリポジトリ一覧を取得するスクリプトのパス
#                         （デフォルト: このスクリプトと同じディレクトリの hub-repos.sh）

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
       ${SCRIPT_NAME} --import-owner OWNER [-c category] [-n] [-j favorite-repos.json]
       ${SCRIPT_NAME} --import-json PATH [-c category] [-n] [-j favorite-repos.json]

  -c, --category NAME   [通常モード] このカテゴリのみ対象にする（複数指定可）
                        [import モード] 取り込み先のカテゴリ（省略時は owner 名）
  -j, --json PATH       favorite-repos.json のパスを指定する
  -n, --dry-run         [通常モード] clone/pull を実行せず対象を表示するのみ
                        [import モード] favorite-repos.json を書き換えず取り込み内容を表示するのみ
      --list-categories 利用可能なカテゴリ一覧を表示して終了する
      --import-owner OWNER  hub-repos.sh で OWNER のリポジトリ一覧を取得し favorite-repos.json に取り込む
      --import-json PATH    hub-repos.sh 形式（{owner,repo,url}の配列）の JSON ファイルを取り込む
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

resolve_hub_repos_script() {
    local script="${HUB_REPOS_SCRIPT:-${SCRIPT_DIR}/hub-repos.sh}"
    if [[ ! -x "$script" ]]; then
        log_error "hub-repos.sh が見つかりません、または実行できません: ${script}"
        exit 1
    fi
    print -r -- "$script"
}

list_categories() {
    local json_file="$1"
    jq -r '.repos[].category' "$json_file"
}

# ---------------------------------------------------------------------------
# hub-repos.sh の出力（{owner,repo,url} の配列）を favorite-repos.json の
# 指定カテゴリに反映する。
#
# 単純な url 和集合ではなく、「インポート対象に含まれる owner 分だけ」を
# 最新状態に置き換える（＝その owner が GitHub 上で削除/リネームしたリポジトリは
# favorite-repos.json 側からも削除される）。同じカテゴリ内に他 owner の
# エントリが混在していても、それらは一切変更しない。
# ---------------------------------------------------------------------------
import_repos() {
    local owner="$1" json_path="$2" category="$3" favorite_json="$4" dryrun="$5"
    local import_data

    if [[ -n "$owner" ]]; then
        local hub_repos_script
        hub_repos_script="$(resolve_hub_repos_script)"
        log_info "hub-repos.sh でリポジトリ一覧を取得: ${owner}"
        import_data="$("$hub_repos_script" "$owner")"
    else
        [[ -f "$json_path" ]] || { log_error "ファイルが存在しません: ${json_path}"; exit 1; }
        import_data="$(cat "$json_path")"
    fi

    local count
    count="$(jq 'length' <<< "$import_data")"
    if [[ "$count" -eq 0 ]]; then
        log_error "インポート対象のリポジトリがありません。"
        exit 1
    fi

    if [[ -z "$category" ]]; then
        category="$(jq -r '.[0].owner' <<< "$import_data")"
    fi

    # 追加/削除される予定のエントリを算出する（dry-run 表示・通常ログ共通）
    # add:      新規取得データのうち、既存カテゴリにまだ無い url
    # remove:   既存カテゴリのうち、インポート対象 owner に属していて、
    #           今回の取得結果に url が見当たらなくなったもの（＝ owner が
    #           GitHub 上で削除/リネームしたリポジトリ）
    # existing: 既存カテゴリの現在件数（ログ表示用）
    local diff
    diff="$(jq --argjson new "$import_data" --arg cat "$category" '
        ((.repos[] | select(.category == $cat) | .repos) // []) as $existing
        | ($new | map(.owner) | unique) as $owners
        | ($new | map(.url)) as $newUrls
        | ($existing | map(.url)) as $existingUrls
        | {
            existing: ($existing | length),
            add: ($new | map(select(
                . as $item | ($existingUrls | index($item.url) | not)
            ))),
            remove: ($existing | map(select(
                . as $item
                | ($owners | index($item.owner))
                  and ($newUrls | index($item.url) | not)
            )))
          }
    ' "$favorite_json")"

    local existing_count add_count remove_count
    existing_count="$(jq '.existing' <<< "$diff")"
    add_count="$(jq '.add | length' <<< "$diff")"
    remove_count="$(jq '.remove | length' <<< "$diff")"

    if (( dryrun )); then
        log_info "[dry-run] カテゴリ「${category}」（現在 ${existing_count} 件）"
        log_info "[dry-run] 追加予定: ${add_count} 件"
        jq -r '.add[] | "  + \(.owner)/\(.repo) (\(.url))"' <<< "$diff"
        log_info "[dry-run] 削除予定: ${remove_count} 件（GitHub 側で見当たらなくなったもの）"
        jq -r '.remove[] | "  - \(.owner)/\(.repo) (\(.url))"' <<< "$diff"
        return
    fi

    log_info "カテゴリ「${category}」: 追加 ${add_count} 件 / 削除 ${remove_count} 件 → ${favorite_json}"

    local tmp
    tmp="$(mktemp)"
    {
        jq --argjson new "$import_data" --arg cat "$category" '
            ($new | map(.owner) | unique) as $owners
            | ($new | map(.url)) as $newUrls
            | if (.repos | any(.category == $cat)) then
                .repos |= map(
                    if .category == $cat then
                        .repos = (
                            (
                                (.repos | map(select(
                                    . as $item
                                    | ($owners | index($item.owner) | not)
                                      or ($newUrls | index($item.url))
                                )))
                                + $new
                            ) | unique_by(.url)
                        )
                    else . end
                )
              else
                .repos += [{category: $cat, repos: ($new | unique_by(.url))}]
              end
        ' "$favorite_json" > "$tmp"
        mv "$tmp" "$favorite_json"
    } always {
        rm -f "$tmp"
    }

    log_info "完了: ${favorite_json}"
}

main() {
    check_dependencies

    local json_file=""
    local -a categories=()
    local -i dryrun=0
    local -i list_only=0
    local import_owner=""
    local import_json=""

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
            --import-owner)
                [[ $# -ge 2 ]] || { usage; exit 1; }
                import_owner="$2"
                shift 2
                ;;
            --import-json)
                [[ $# -ge 2 ]] || { usage; exit 1; }
                import_json="$2"
                shift 2
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

    if [[ -n "$import_owner" || -n "$import_json" ]]; then
        if [[ -n "$import_owner" && -n "$import_json" ]]; then
            log_error "--import-owner と --import-json は同時に指定できません。"
            exit 1
        fi
        if (( ${#categories[@]} > 1 )); then
            log_error "import モードでは -c/--category は1つだけ指定してください。"
            exit 1
        fi
        import_repos "$import_owner" "$import_json" "${categories[1]:-}" "$json_file" "$dryrun"
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
