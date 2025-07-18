#!/bin/zsh

# 保存ディレクトリ（環境変数優先）
BACKUP_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/mac_defaults_backup"

# ヘルプ表示
function show_help() {
    cat <<EOF
Usage: $0 [backup|restore|migrate] <domain>

  保存先 : $BACKUP_DIR

  backup   : 指定したドメインの設定をバックアップします
  restore  : バックアップした設定をリストアします
  migrate  : バックアップを別の Mac に SCP で移行します
  domain   : 対象のドメイン名（例: com.apple.finder）

EOF
    exit 1
}

# バックアップ関数
function backup() {
    local domain=$1
    local backup_file="${BACKUP_DIR}/${domain}.plist"

    mkdir -p "$BACKUP_DIR"
    echo "📦 バックアップ中: ${domain} → ${backup_file}"
    if defaults export "$domain" "$backup_file"; then
        echo "✅ バックアップ完了: ${backup_file}"
    else
        echo "❌ バックアップ失敗"
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
        else
            echo "❌ リストア失敗"
        fi
    else
        echo "⚠️ バックアップファイルが見つかりません: ${backup_file}"
    fi
}

# 移行関数
function migrate() {
    local domain=$1
    local backup_file="${BACKUP_DIR}/${domain}.plist"
    local remote_host="user@remote-mac.local"

    if [[ -f "$backup_file" ]]; then
        echo "🚚 移行中: ${backup_file} → ${remote_host}:${BACKUP_DIR}/"
        if scp "$backup_file" "${remote_host}:${BACKUP_DIR}/"; then
            echo "✅ 移行完了"
        else
            echo "❌ 移行失敗"
        fi
    else
        echo "⚠️ バックアップファイルが見つかりません: ${backup_file}"
    fi
}

# メインロジック
if [[ $# -ne 2 ]]; then
    show_help
fi

action=$1
domain=$2

case "$action" in
    backup)  backup "$domain" ;;
    restore) restore "$domain" ;;
    migrate) migrate "$domain" ;;
    *)       show_help ;;
esac
