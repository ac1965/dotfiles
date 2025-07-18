i#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# リポジトリ保存先（環境変数 T または GITHUB_REPOS）
T="${T:-${GITHUB_REPOS:-}}"
if [[ -z "$T" ]]; then
    echo "Error: 環境変数 T または GITHUB_REPOS を設定してください。" >&2
    exit 1
fi

# 引数チェック
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <git repository URL>"
    exit 1
fi

url="$1"

# URL からホスト・オーナー・リポジトリ名を抽出
# 例: https://github.com/org/repo.git → github.com / org / repo
parsed_url="${url#*://}"  # プロトコル削除
host="${parsed_url%%/*}"
path="${parsed_url#*/}"

IFS='/' read -r owner repos _ <<< "$path"

if [[ -z "$owner" || -z "$repos" ]]; then
    echo "Error: URL からオーナーまたはリポジトリ名が抽出できません。" >&2
    exit 2
fi

echo "url: $url"
echo "owner: $owner"
echo "repo: $repos"

# 保存先ディレクトリの作成
repo_dir="${T}/${host}/${owner}"
mkdir -p "$repo_dir"
echo "repo_dir: $repo_dir"

# hub-repos.sh が存在すれば、所有者のリポジトリ一覧を取得
if [[ -x "$HOME/.bin/hub-repos.sh" ]]; then
    "$HOME/.bin/hub-repos.sh" "$owner" > "${repo_dir}/repos-${owner}.txt"
fi

# リポジトリが指定されていればクローンまたは pull
(
    cd "$repo_dir"
    if [[ -d "$repos" ]]; then
        echo "→ 既存のリポジトリを更新: $repos"
        cd "$repos"
        git pull
    else
        echo "→ リポジトリをクローン: $repos"
        git clone --recursive "$url"
    fi
)

