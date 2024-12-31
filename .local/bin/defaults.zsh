#!/bin/zsh

# バックアップ用のディレクトリ
BACKUP_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/mac_defaults_backup"

# ヘルプメッセージ
function show_help() {
    echo "Usage: $0 [backup|restore|migrate] [domain]"
    echo "  保存先: $BACKUP_DIR"
    echo "  backup  : 指定したドメインの設定をバックアップします"
    echo "  restore : 指定したドメインの設定をリストアします"
    echo "  migrate : バックアップを別のMacに移行してリストアします"
    echo "  domain  : バックアップまたはリストア対象のドメイン（例: com.apple.finder）"
    exit 1
}

# バックアップ処理
function backup() {
    local domain=$1
    mkdir -p "$BACKUP_DIR"
    local backup_file="${BACKUP_DIR}/${domain}.plist"
    echo "Backing up domain '${domain}' to '${backup_file}'..."
    defaults export "$domain" "$backup_file" && echo "Backup completed: ${backup_file}" || echo "Backup failed"
}

# リストア処理
function restore() {
    local domain=$1
    local backup_file="${BACKUP_DIR}/${domain}.plist"
    if [[ -f "$backup_file" ]]; then
        echo "Restoring domain '${domain}' from '${backup_file}'..."
        defaults import "$domain" "$backup_file" && echo "Restore completed" || echo "Restore failed"
    else
        echo "Backup file '${backup_file}' not found. Restore aborted."
    fi
}

# 移行処理（別Macに移行）
function migrate() {
    local domain=$1
    local backup_file="${BACKUP_DIR}/${domain}.plist"
    if [[ -f "$backup_file" ]]; then
        echo "Migrating domain '${domain}'..."
        scp "$backup_file" user@remote-mac.local:"$BACKUP_DIR/" && echo "Migration completed" || echo "Migration failed"
    else
        echo "Backup file '${backup_file}' not found. Migration aborted."
    fi
}

# メインロジック
if [[ $# -lt 2 ]]; then
    show_help
fi

action=$1
domain=$2

case "$action" in
    backup)
        backup "$domain"
        ;;
    restore)
        restore "$domain"
        ;;
    migrate)
        migrate "$domain"
        ;;
    *)
        show_help
        ;;
esac
