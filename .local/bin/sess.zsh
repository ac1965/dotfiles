#!/usr/bin/env zsh
#
# sess.zsh - ファイルを指定単位ごとにディレクトリへ振り分ける
#
# 元のファイル名は変更せず、count個ごとに 001, 002, ... という
# 連番ディレクトリを作成して移動するのみ。
#
# Usage: ./sess.zsh [group_size]
#   group_size : 1ディレクトリあたりのファイル数（デフォルト: 20）

# 厳格モード(zsh): 失敗したら止める。mv の失敗で処理を続けない。
set -o errexit -o nounset -o pipefail
setopt nullglob

group_size=${1:-20}

if (( group_size <= 0 )); then
    echo "Error: group_size must be a positive integer" >&2
    exit 1
fi

count=0

for f in *(.N); do
    # ((count++)) は count が 0 のとき終了ステータス 1 になり errexit で落ちるため、
    # 評価値が常に非ゼロになる前置インクリメントを使う。
    (( ++count ))
    group=$(( (count - 1) / group_size + 1 ))
    dir=$(printf '%03d' $group)
    mkdir -p "$dir"
    mv -- "$f" "$dir/$f"
done

echo "Done: ${count} files moved into $(( (count - 1) / group_size + 1 )) directories (group size: ${group_size})"
