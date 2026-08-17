#!/usr/bin/env bash
#
# 0_backup_clone.sh
#
# filter-repo等の履歴書き換え作業用に、別ディレクトリへの独立クローンを作る。
# 同一リポジトリ内のブランチはfilter-repoの書き換え対象から逃げられないため、
# 必ず別ディレクトリのクローンとして退避する。
#
# 使い方:
#   ./0_backup_clone.sh /path/to/original-repo
#   ./0_backup_clone.sh /path/to/original-repo /path/to/dest-dir   # 出力先を指定する場合

set -euo pipefail

SRC="${1:?使い方: $0 <元リポジトリのパス> [出力先ディレクトリ]}"
REPO_NAME="$(basename "$SRC")"
DEST="${2:-${REPO_NAME}-backup-$(date +%Y%m%d)}"

if [ -e "$DEST" ]; then
    echo "[ERROR] 出力先 '$DEST' は既に存在します。別名を指定するか削除してください。" >&2
    exit 1
fi

echo "[INFO] クローン中: $SRC -> $DEST"
git clone --no-hardlinks "$SRC" "$DEST"

cd "$DEST"
echo "[INFO] クローン完了。カレントディレクトリ: $(pwd)"
echo "[INFO] コミット数: $(git rev-list --count HEAD)"
echo "[INFO] ブランチ一覧:"
git branch -vv

echo ""
echo "[DONE] 以降の作業はこのディレクトリ内で行ってください: $DEST"
