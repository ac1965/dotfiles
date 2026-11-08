#!/usr/bin/env zsh

# 厳格モード(zsh): 未定義変数とパイプ失敗は検出するが、errexit は意図的に付けない。
# 複数ドメインの backup/restore で 1 件失敗しても残りを続行し、失敗件数を集計して
# 終了コードに反映する設計のため(各関数が明示的に return コードを返す)。
set -o nounset -o pipefail

# zsh は関数内で $0 が関数名に化ける(FUNCTION_ARGZERO)ため、スクリプト名
# はトップレベルで一度だけ変数に控えておく。
SCRIPT_NAME="${0:t}"

# 保存ディレクトリ(環境変数優先)。
# ~/.cache ではなく ~/.local/state 配下に置くのは、private/dotfiles.zsh の
# HOME_FILES 経由で private アーカイブに取り込まれ、暗号化された状態で
# 永続化・別マシンへの移行対象になるようにするため(.cache は揮発性ディレ
# クトリという扱いで同期対象に含めていない)。
BACKUP_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mac-defaults-backup"

# backup-all / restore-all が対象にするドメイン一覧ファイル。
# dotfiles.zsh 経由で公開リポジトリの .config/macos-defaults/domains.txt
# から配置される(ドメイン名のみで実データは含まない)。
DOMAINS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/macos-defaults/domains.txt"

# ヘルプ表示
# 終了コード: -h/--help は 99、引数エラーは 1
function show_help() {
    local code="${1:-1}"
    cat <<EOF
Usage: $SCRIPT_NAME [backup|restore|migrate] <domain>
       $SCRIPT_NAME [backup-all|restore-all]

  保存先     : $BACKUP_DIR
  ドメイン一覧: $DOMAINS_FILE

  backup      : 指定したドメインの設定をバックアップします
  restore     : バックアップした設定をリストアします
  migrate     : バックアップを別の Mac に SCP で移行します(宛先は環境変数 MIGRATE_HOST=user@host で指定)
  backup-all  : ドメイン一覧ファイルに列挙された全ドメインをバックアップします
  restore-all : ドメイン一覧ファイルに列挙された全ドメインをリストアし、関連プロセスを再起動します
  domain      : 対象のドメイン名（例: com.apple.finder）

EOF
    exit "$code"
}

# バックアップ関数
#
# ドメイン名に '/' を含むもの(例: com.apple.LaunchServices/com.apple.
# launchservices.secure)は出力ファイルパスにもそのまま '/' が入り、
# サブディレクトリが必要になる。`defaults export` はその親ディレクトリが
# 無いと exit code 0 のまま何も書き込まずに黙って失敗する(エラー扱いに
# ならない既知の挙動)ため、ここで (1) 親ディレクトリを都度作成し、
# (2) 実際にファイルが生成されたかを exit code とは別に検証する。
function backup() {
    local domain=$1
    local backup_file="${BACKUP_DIR}/${domain}.plist"

    mkdir -p -- "${backup_file:h}"
    echo "📦 バックアップ中: ${domain} → ${backup_file}"
    # `defaults export` は存在しない/読めないドメインでも終了コード 0 で「空の plist(42バイト)」を
    # 書いてしまう。サンドボックス化アプリ(例: com.apple.Safari)は実体がコンテナ内にあり、
    # 通常は読めないため、事前に読み取れるかを確認して空のバックアップを作らない。
    if ! defaults read "$domain" >/dev/null 2>&1; then
        echo "❌ ドメインを読み取れません(存在しない、またはサンドボックス/権限により参照不可): ${domain}"
        rm -f -- "$backup_file"
        return 1
    fi
    if defaults export "$domain" "$backup_file" && [[ -f "$backup_file" ]]; then
        echo "✅ バックアップ完了: ${backup_file}"
        return 0
    else
        echo "❌ バックアップ失敗"
        return 1
    fi
}

# リストア関数
function restore() {
    local domain=$1
    local backup_file="${BACKUP_DIR}/${domain}.plist"

    if [[ -f "$backup_file" ]]; then
        echo "♻️ リストア中: ${domain} ← ${backup_file}"
        if defaults import "$domain" "$backup_file"; then
            echo "✅ リストア完了"
            return 0
        else
            echo "❌ リストア失敗"
            return 1
        fi
    else
        echo "⚠️ バックアップファイルが見つかりません: ${backup_file}"
        return 1
    fi
}

# ドメイン一覧ファイルを読み、コメント('#')・空行を除いたドメイン名を
# 順に読み込み専用配列変数 domains_out に格納する。
function read_domains() {
    domains_out=()
    if [[ ! -f "$DOMAINS_FILE" ]]; then
        echo "❌ ドメイン一覧ファイルが見つかりません: ${DOMAINS_FILE}" >&2
        return 1
    fi
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        domains_out+=("$line")
    done < "$DOMAINS_FILE"
    return 0
}

# ドメイン一覧を一括バックアップ
function backup_all() {
    local -a domains_out
    read_domains || exit 1
    local domain
    local -i ok=0 ng=0
    for domain in "${domains_out[@]}"; do
        if backup "$domain"; then (( ++ok )); else (( ++ng )); fi
    done
    echo "📊 バックアップ: 成功 ${ok} 件 / 失敗 ${ng} 件"
    (( ng == 0 ))
}

# ドメイン一覧を一括リストアし、反映のため関連プロセスを再起動する
function restore_all() {
    local -a domains_out
    read_domains || exit 1
    local domain
    local -i restored=0 failed=0
    for domain in "${domains_out[@]}"; do
        if restore "$domain"; then (( ++restored )); else (( ++failed )); fi
    done
    if (( restored > 0 )); then
        echo "🔄 反映のため関連プロセスを再起動します(Dock/Finder/SystemUIServer/cfprefsd)..."
        killall Dock Finder SystemUIServer cfprefsd 2>/dev/null
        echo "✅ ${restored} 件のドメインをリストアしました(失敗 ${failed} 件)"
    else
        echo "⚠️ リストアされたドメインはありませんでした(失敗 ${failed} 件)"
    fi
    (( failed == 0 ))
}

# 移行関数
function migrate() {
    local domain=$1
    local backup_file="${BACKUP_DIR}/${domain}.plist"
    local remote_host="${MIGRATE_HOST:-}"

    if [[ -z "$remote_host" ]]; then
        echo "❌ 移行先が未指定です。MIGRATE_HOST=user@host を指定してください" >&2
        return 1
    fi
    if [[ ! -f "$backup_file" ]]; then
        echo "⚠️ バックアップファイルが見つかりません: ${backup_file}"
        return 1
    fi
    local remote_file="${BACKUP_DIR}/${domain}.plist"
    echo "🚚 移行中: ${backup_file} → ${remote_host}:${remote_file}"
    # 宛先ディレクトリが無いと scp が失敗する(ドメイン名に / を含む場合は階層も必要)
    if ssh "$remote_host" mkdir -p -- "${remote_file:h}" && scp "$backup_file" "${remote_host}:${remote_file}"; then
        echo "✅ 移行完了"
    else
        echo "❌ 移行失敗"
        return 1
    fi
}

# メインロジック
if [[ $# -eq 1 ]]; then
    case "$1" in
        backup-all)  backup_all;  exit $? ;;
        restore-all) restore_all; exit $? ;;
        -h|--help)   show_help 99 ;;
        *)           show_help ;;
    esac
fi

if [[ $# -ne 2 ]]; then
    show_help
fi

action=$1
domain=$2

case "$action" in
    backup)  backup "$domain"; exit $? ;;
    restore) restore "$domain"; exit $? ;;
    migrate) migrate "$domain"; exit $? ;;
    *)       show_help ;;
esac
