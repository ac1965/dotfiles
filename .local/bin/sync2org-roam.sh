#!/usr/bin/env zsh
#
# 指定した同期元ディレクトリの内容を、org-roam ディレクトリ（デフォルト:
# ~/Documents/org/org-roam）へ追加コピーする。rsync --update を使用し、
# 同期先にしか存在しないファイルは削除しない（安全側の一方向コピー）。
#
# 使い方:
#   sync-to-org-roam.zsh [-n] <同期元ディレクトリ> [同期先ディレクトリ]
#
#   -n, --dry-run   実際にはコピーせず、実行結果のプレビューのみ表示
#   -h, --help      このヘルプを表示
#
# 例:
#   sync-to-org-roam.zsh ~/Downloads/org-notes
#   sync-to-org-roam.zsh -n ~/Downloads/org-notes ~/Documents/org/org-roam

set -euo pipefail

TARGET_DEFAULT="$HOME/Documents/org/org-roam"
SCRIPT_NAME="${0:t}"
DRY_RUN=0

usage() {
  cat >&2 <<EOF
使い方: $SCRIPT_NAME [-n] <同期元ディレクトリ> [同期先ディレクトリ]

  -n, --dry-run   実際にはコピーせず、プレビューのみ表示
  -h, --help      このヘルプを表示

同期先を省略した場合のデフォルト: $TARGET_DEFAULT

挙動: rsync --update による追加コピーのみ。同期先にしか存在しない
      ファイルは削除しない（ミラーリングは行わない）。
EOF
  exit 1
}

args=()
for arg in "$@"; do
  case "$arg" in
    -n|--dry-run) DRY_RUN=1 ;;
    -h|--help) usage ;;
    -*)
      echo "エラー: 不明なオプション: $arg" >&2
      usage
      ;;
    *) args+=("$arg") ;;
  esac
done

(( ${#args[@]} >= 1 )) || usage

SRC="${args[1]}"
DEST="${args[2]:-$TARGET_DEFAULT}"

[[ -d "$SRC" ]] || { echo "エラー: 同期元ディレクトリが存在しません: $SRC" >&2; exit 1; }
[[ -d "$DEST" ]] || { echo "エラー: 同期先ディレクトリが存在しません: $DEST" >&2; exit 1; }

command -v rsync >/dev/null 2>&1 || { echo "エラー: rsync が見つかりません" >&2; exit 1; }

# rsync でディレクトリの中身を同期するため末尾に / を付与する
SRC="${SRC%/}/"
DEST="${DEST%/}/"

RSYNC_OPTS=(-av --update
  --exclude='.git/'
  --exclude='.DS_Store'
  --exclude='__pycache__/'
)
(( DRY_RUN )) && RSYNC_OPTS+=(--dry-run)

echo "同期元: $SRC"
echo "同期先: $DEST"
echo "モード: 追加コピーのみ（削除なし）$([[ $DRY_RUN -eq 1 ]] && echo ' / dry-run')"
echo

rsync "${RSYNC_OPTS[@]}" "$SRC" "$DEST"

echo
if (( DRY_RUN )); then
  echo "dry-run 完了（実際のコピーは行っていません）。"
else
  echo "同期完了。"
fi
