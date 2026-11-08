#!/usr/bin/env zsh
#
# collect_commit_msg.sh
#
# 元リポジトリを別ディレクトリへクローンし、diff抽出 -> コミットメッセージ生成
# -> filter-repo によるメッセージ書き換え、までを一括実行する。
#
# 使い方:
#   ./collect_commit_msg.sh <元リポジトリのパス> [出力先ディレクトリ] [オプション]
#
# オプション:
#   --ollama            Claude API の代わりにローカル Ollama でメッセージ生成する
#   --model MODEL        メッセージ生成に使うモデル名を指定する
#                         (--ollama 未指定時は claude-sonnet-4-6、指定時は qwen2.5-coder:14b がデフォルト)
#   -h, --help            このヘルプを表示する
#
# 注意:
#   git filter-repo は書き換え後にリモート(origin等)を安全のため自動的に
#   削除する。書き換え後に `git remote -v` が空でも異常ではない。

# 対話シェル(.zshrc)の設定に影響されないよう、実行前にデフォルト状態へ戻す
emulate -LR zsh
set -euo pipefail

# 未作成のディレクトリを想定しない安全策として、意図しないファイル名展開は避ける
setopt no_nomatch

SCRIPT_PATH="${0:A}"
SCRIPT_DIR="${SCRIPT_PATH:h}"

# 注意: zshは関数内で $0 が関数名に変わる(bashと異なる)ため、
#       スクリプト自身のパスは上で保存した SCRIPT_PATH を使う。
usage() {
    sed -n '2,19p' "$SCRIPT_PATH" | sed 's/^# \{0,1\}//'
}

fail() {
    print -ru2 -- "[ERROR] $1"
    exit 1
}

# --- 引数解析 -----------------------------------------------------------
# zparseopts は環境によってモジュール未整備で読み込めないことがあるため
# (実機で確認済み)、可搬性を優先して手動でパースする。
USE_OLLAMA=0
MODEL=""
typeset -a POSITIONAL
POSITIONAL=()

while (( $# > 0 )); do
    case "$1" in
        --ollama)
            USE_OLLAMA=1
            shift
            ;;
        --model)
            (( $# >= 2 )) || fail "--model にはモデル名が必要です"
            MODEL="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            POSITIONAL+=("$@")
            break
            ;;
        -*)
            print -ru2 -- "[ERROR] 不明なオプション: $1"
            usage >&2
            exit 1
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

(( ${#POSITIONAL[@]} >= 1 )) || {
    print -ru2 -- "[ERROR] 使い方: $SCRIPT_PATH <元リポジトリのパス> [出力先ディレクトリ] [--ollama] [--model MODEL]"
    exit 1
}

SRC="${POSITIONAL[1]}"
DEST="${POSITIONAL[2]:-}"

if [[ -z "$SRC" ]]; then
    fail "元リポジトリのパスが空です"
fi
[[ -e "$SRC" ]] || fail "元リポジトリ '$SRC' が存在しません"
SRC_ABS="${SRC:A}"
git -C "$SRC_ABS" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || fail "'$SRC' はgitリポジトリではありません"

REPO_NAME="${SRC_ABS:t}"
DEST="${DEST:-${REPO_NAME}-backup-$(date +%Y%m%d)}"
[[ -n "$DEST" ]] || fail "出力先ディレクトリ名が空です"

if [[ "$USE_OLLAMA" -eq 1 ]]; then
    GENERATE_SCRIPT="$SCRIPT_DIR/2_generate_messages_ollama.py"
    MODEL="${MODEL:-qwen2.5-coder:14b}"
else
    GENERATE_SCRIPT="$SCRIPT_DIR/2_generate_messages.py"
    MODEL="${MODEL:-claude-sonnet-4-6}"
fi
[[ -f "$GENERATE_SCRIPT" ]] || fail "生成スクリプトが見つかりません: $GENERATE_SCRIPT"

# 各ステップの実行後に埋まる(NEXT STEPSの案内・再実行判定で使う)
DEST_ABS=""
CURRENT_BRANCH=""
PUBLISH_URL=""
DONE_MARKER=""

# --- 事前チェック ---------------------------------------------------------

check_dependencies() {
    # fail()は即exitするため、for内で呼ぶと最初の1件しか報告できず
    # 手戻りが増える。不足分をすべて集めてからまとめて報告する。
    local cmd
    typeset -a missing
    missing=()
    for cmd in git python3 git-filter-repo; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    (( ${#missing[@]} == 0 )) || fail "コマンドが見つかりません: ${(j:, :)missing}"
}

check_safety() {
    # DEST が SRC 自身(またはその内部)を指していないか確認する。
    # クローン先を誤って元リポジトリ内に作ると復旧が困難なため。
    local dest_parent dest_abs
    dest_parent="${DEST:h}"
    [[ -d "$dest_parent" ]] || fail "出力先の親ディレクトリが存在しません: $dest_parent"
    dest_abs="${dest_parent:A}/${DEST:t}"

    if [[ "$dest_abs" == "$SRC_ABS" || "$dest_abs" == "$SRC_ABS"/* ]]; then
        fail "出力先 '$DEST' が元リポジトリ '$SRC_ABS' の内部を指しています"
    fi
    # DEST が既に存在する場合の可否は clone_repo() 側で判定する
    # (gitリポジトリなら前回の続きから再開、そうでなければ失敗させる)。
}

# --- 各ステップ -----------------------------------------------------------

clone_repo() {
    if [[ -e "$DEST" ]]; then
        git -C "$DEST" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
            || fail "出力先 '$DEST' は既に存在しますが、gitリポジトリではありません。内容を確認するか、別名を指定/削除してください。"

        print -r -- "[INFO] 出力先 '$DEST' は既存のgitリポジトリです。前回の続きから再開します。"
        cd -- "$DEST"
        DEST_ABS="$(pwd)"
    else
        print -r -- "[INFO] クローン中: $SRC_ABS -> $DEST"
        git clone --no-hardlinks -- "$SRC_ABS" "$DEST"
        cd -- "$DEST"
        DEST_ABS="$(pwd)"
    fi

    # filter-repoによる書き換えが既に完了しているかの判定に使う
    # (.git/ 配下なのでcommitやworking treeには一切影響しない)
    DONE_MARKER="$DEST_ABS/.git/collect_commit_msg.done"

    print -r -- "[INFO] カレントディレクトリ: $DEST_ABS"
    print -r -- "[INFO] コミット数: $(git rev-list --count HEAD)"
    print -r -- "[INFO] ブランチ一覧:"
    git branch -vv
}

extract_diffs() {
    print -r -- "[STEP] diff抽出中..."
    python3 "$SCRIPT_DIR/1_extract_diffs.py" --out diffs.jsonl
}

generate_messages() {
    print -r -- "[STEP] コミットメッセージ生成中 (model: $MODEL)..."
    # 未処理分(=前回rewriteでハッシュが変わった分)だけ生成される(レジューム)
    python3 "$GENERATE_SCRIPT" --in diffs.jsonl --out messages.json --model "$MODEL"
}

rewrite_history() {
    print -r -- "[STEP] filter-repo でメッセージ書き換え中..."
    REWRITE_MESSAGES_JSON="$(pwd)/messages.json" \
        git filter-repo --force --commit-callback "$(cat -- "$SCRIPT_DIR/3_rewrite_messages.py")"

    # filter-repoは安全のためoriginを自動削除するが、書き換え前後の比較用に
    # クローン元(SRC、ローカルの退避元)を指すoriginとして復元しておく。
    # 実際の公開先(GitHub等)ではない点に注意。
    git remote add origin "$SRC_ABS"

    # main/master等ブランチ名はプロジェクトごとに異なるため決め打ちしない
    CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo master)"

    # 完了マーカー。再実行時にdiff抽出・メッセージ生成・filter-repoを
    # スキップするかどうかの判定に使う(書き換え後はハッシュが変わり
    # messages.jsonのキーと一致しなくなるため、無条件で再実行するとAPIが
    # 全コミット分無駄に呼ばれてしまう)。
    : > "$DONE_MARKER"
}

# push等の外部リモートに影響する操作はしないが、fetch/ローカルブランチ作成/diff
# はこのDEST内で完結する読み取り専用の確認作業なので自動実行する。
compare_with_original() {
    print -r -- "[STEP] 書き換え前の履歴と比較中..."
    git fetch origin
    git branch -f real-original-history "origin/${CURRENT_BRANCH}"
    print -r -- "[INFO] 書き換え前後の差分(メッセージのみ変更されファイル内容は不変のはず):"
    git diff "$CURRENT_BRANCH" real-original-history --stat
}

# remoteの追加とfetchはローカル操作でリモートには影響しないため自動実行する。
# 実際にリモートへ反映するpushだけは副作用が大きいため手動確認に残す。
setup_publish_remote() {
    PUBLISH_URL="$(git -C "$SRC_ABS" remote get-url origin 2>/dev/null || true)"
    if [[ -z "$PUBLISH_URL" ]]; then
        print -r -- "[WARN] クローン元 '$SRC_ABS' にoriginリモートが見つからないため、publishリモートの自動設定をスキップします。"
        return
    fi

    print -r -- "[STEP] 公開用リモート 'publish' (${PUBLISH_URL}) を設定中..."
    # 前回の実行で既にpublishリモートが存在する場合にaddが失敗しないよう、
    # 存在すればURLを合わせるだけにする(冪等)。
    if git remote get-url publish >/dev/null 2>&1; then
        git remote set-url publish "$PUBLISH_URL"
    else
        git remote add publish "$PUBLISH_URL"
    fi
    # --force-with-lease はローカルが把握しているpublish/<branch>の状態を
    # 手がかりに安全性を検証するため、pushの前に必ずfetchしておく。
    git fetch publish
}

print_summary() {
    print -r -- "[INFO] 書き換え後 HEAD: $(git rev-parse HEAD)"
    print -r -- "[INFO] 直近20件:"
    git log --oneline | head -20
    local unresolved
    unresolved="$(git log --oneline | grep -c '^\S* Update$' || true)"
    print -r -- "[INFO] 未解決('Update'のままの)コミット数: $unresolved"
    print -r -- "[INFO] リモート一覧 (originは比較用にクローン元 '$SRC_ABS' を指すよう復元済み):"
    git remote -v

    print -r -- ""
    print -r -- "[!!!] 以下は必ずこのディレクトリで実行してください: $DEST_ABS"
    print -r -- "[!!!] 元リポジトリ '$SRC_ABS' はまだ書き換えられていません。"
    print -r -- "[!!!] そちらで push すると古いメッセージのまま反映されてしまいます。"
    print -r -- ""
    print -r -- "[NEXT STEPS] (リモートへの force-push は副作用が大きいため、このスクリプトは自動実行しません)"
    print -r -- "  cd $DEST_ABS"
    print -r -- ""
    if [[ -n "$PUBLISH_URL" ]]; then
        print -r -- "  # publishリモート($PUBLISH_URL)は設定・fetch済みです。反映する場合:"
        print -r -- "  git push --force-with-lease publish $CURRENT_BRANCH"
    else
        print -r -- "  # 実際のリモートへ反映する場合(公開先URLはクローン元に見つかりませんでした):"
        print -r -- "  git remote add publish <実際のリモートURL>"
        print -r -- "  git fetch publish"
        print -r -- "  git push --force-with-lease publish $CURRENT_BRANCH"
    fi
    print -r -- ""
    print -r -- "  # pushが成功したら、元リポジトリ側 ($SRC_ABS) もこの新しい履歴に合わせる場合:"
    print -r -- "  # (書き換えでコミットハッシュが変わっているため、pullではなくresetが必要。"
    print -r -- "  #  reset --hard は未コミットの変更を破棄するので、必ずgit statusで確認してから)"
    print -r -- "  cd $SRC_ABS"
    print -r -- "  git status"
    print -r -- "  git fetch origin"
    print -r -- "  git reset --hard origin/$CURRENT_BRANCH"
}

on_error() {
    local exit_code=$?
    print -ru2 -- "[ERROR] 失敗しました (行 ${LINENO})。出力先: ${DEST:-<未作成>}"
    print -ru2 -- "[ERROR] diffs.jsonl / messages.json が残っていれば、再実行時に未処理分から再開されます。"
    exit "$exit_code"
}
trap on_error ERR

check_dependencies
check_safety
clone_repo

if [[ -f "$DONE_MARKER" ]]; then
    print -r -- "[INFO] 書き換え完了マーカーを検出しました。diff抽出・メッセージ生成・filter-repoはスキップします。"
    print -r -- "[INFO] (やり直したい場合はこのDESTを削除して再実行してください)"
    CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo master)"
else
    extract_diffs
    generate_messages
    rewrite_history
fi

compare_with_original
setup_publish_remote
print_summary
