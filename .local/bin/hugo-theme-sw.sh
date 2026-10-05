#!/usr/bin/env zsh
#
# hugo-theme-sw.sh
# Hugo ブログの config/<theme> を config/_default として差し替え、
# public/ を削除した上で `hugo server` を起動する(テーマ切替用)。
#
# 使い方:
#   hugo-theme-sw.sh <theme>        # 例: hugo-theme-sw.sh blowfish
#   hugo-theme-sw.sh -n <theme>     # dry-run: 実行内容を表示するだけ
#   hugo-theme-sw.sh -h
#
# 任意環境変数:
#   HUGO_BLOG_DIR - ブログのルート
#                   (デフォルト: ${HOME}/Documents/devel/repos/hugo-blog)
#
set -o errexit -o nounset -o pipefail

# zsh は関数内で $0 が関数名に化けるため、トップレベルで控えておく
SCRIPT_PATH="$0"
SCRIPT_NAME="${0:t}"
DRYRUN=0

log_error() { print -ru2 -- "❌ [${SCRIPT_NAME}] $*"; }

usage() {
  sed -n '/^# 使い方:/,/^#$/p' "$SCRIPT_PATH"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || { log_error "コマンドが見つかりません: $1"; exit 1; }
}

theme=""
while (( $# > 0 )); do
  case "$1" in
    -h|--help)    usage; exit 0 ;;
    -n|--dry-run) DRYRUN=1; shift ;;
    -*)           log_error "不明なオプション: $1"; usage >&2; exit 1 ;;
    *)            theme="$1"; shift ;;
  esac
done

if [[ -z "$theme" ]]; then
  usage >&2
  exit 1
fi

base="${HUGO_BLOG_DIR:-${HOME}/Documents/devel/repos/hugo-blog}"
target="${base}/config/${theme}"

if [[ ! -d "$target" ]]; then
  log_error "テーマが見つかりません: ${target}"
  exit 1
fi

require_command hugo

print -r -- "${theme} use"
if (( DRYRUN )); then
  print -r -- "would replace ${base}/config/_default with ${target}"
  print -r -- "would remove ${base}/public and run: hugo server --debug --disableFastRender"
  exit 0
fi

cd -- "${base}/config"
rm -rf -- _default
cp -a -- "$theme" _default
cd -- "$base"
rm -rf -- public
exec hugo server --debug --disableFastRender
