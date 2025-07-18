#!/usr/bin/env zsh

set -o errexit
set -o nounset
set -o pipefail

autoload -Uz colors && colors

# 🌍 オプション変数
T="${T:-${GITHUB_REPOS:-}}"
DRY_RUN=false
BRANCH=""
ARGS=()

# 📘 オプション解析
while [[ $# -gt 0 ]]; do
    case "$1" in
	--dry-run)
	    DRY_RUN=true
	    shift
	    ;;
	--branch)
	    BRANCH="$2"
	    shift 2
	    ;;
	--help)
	    echo "Usage: $0 [--dry-run] [--branch <name>] <git repo URL>"
	    exit 0
	    ;;
	*)
	    ARGS+=("$1")
	    shift
	    ;;
    esac
done

if [[ ${#ARGS} -ne 1 ]]; then
    echo "${fg[red]}Error:${reset_color} URL を1つだけ指定してください。" >&2
    exit 1
fi

if [[ -z "$T" ]]; then
    echo "${fg[red]}Error:${reset_color} 環境変数 T または GITHUB_REPOS を設定してください。" >&2
    exit 1
fi

typeset -A repo_info
url="${ARGS[1]}"
parsed_url="${url#*://}"
repo_info[host]="${parsed_url%%/*}"
path="${parsed_url#*/}"

IFS='/' read -r repo_info[owner] repo_info[repos] _ <<< "$path"
repo_info[repos]="${repo_info[repos]%.git}"

if [[ -z "${repo_info[owner]}" || -z "${repo_info[repos]}" ]]; then
    echo "${fg[red]}Error:${reset_color} URL からオーナーまたはリポジトリ名が抽出できません。" >&2
    exit 2
fi

echo "${fg[blue]}🌐 URL   ${reset_color}: $url"
echo "${fg[cyan]}👤 Owner ${reset_color}: ${repo_info[owner]}"
echo "${fg[green]}📁 Repo  ${reset_color}: ${repo_info[repos]}"

repo_dir="${T}/${repo_info[host]}/${repo_info[owner]}"
mkdir -p "$repo_dir"
echo "${fg[magenta]}📦 保存先${reset_color}: $repo_dir"

# hub-repos.sh があればリスト出力
if [[ -x "$HOME/.bin/hub-repos.sh" ]]; then
    list_path="${repo_dir}/repos-${repo_info[owner]}.txt"
    "$HOME/.bin/hub-repos.sh" "${repo_info[owner]}" > "$list_path"
    echo "${fg[yellow]}📝 リスト生成${reset_color}: $list_path"
fi

# リポジトリ取得
cd "$repo_dir"

if [[ -d "${repo_info[repos]}" ]]; then
    echo "${fg[cyan]}🔁 既存を更新${reset_color}: ${repo_info[repos]}"
    if $DRY_RUN; then
	echo "[dry-run] cd ${repo_info[repos]} && git pull"
    else
	cd "${repo_info[repos]}"
	git pull
    fi
else
    echo "${fg[green]}📥 クローン開始${reset_color}: ${repo_info[repos]}"
    clone_cmd="git clone --recursive"
    [[ -n "$BRANCH" ]] && clone_cmd+=" --branch $BRANCH"
    clone_cmd+=" \"$url\""

    if $DRY_RUN; then
	echo "[dry-run] $clone_cmd"
    else
	eval "$clone_cmd"
    fi
fi
