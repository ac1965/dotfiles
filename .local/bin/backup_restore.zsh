#!/bin/zsh

# バックアップ用のディレクトリ
BACKUP_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/mac_defaults_backup"

# バックアップ
backup_defaults() {
    echo "バックアップディレクトリ: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"

    # 全ての設定をバックアップ
    echo "System Preferences の設定をバックアップ中..."
    defaults read > "$BACKUP_DIR/system_preferences.plist"

    echo "Dock の設定をバックアップ中..."
    defaults read com.apple.dock > "$BACKUP_DIR/com.apple.dock.plist"

    echo "Finder の設定をバックアップ中..."
    defaults read com.apple.finder > "$BACKUP_DIR/com.apple.finder.plist"

    echo "スクリーンショットの設定をバックアップ中..."
    defaults read com.apple.screencapture > "$BACKUP_DIR/com.apple.screencapture.plist"

    echo "バックアップが完了しました！"
}

# リストア
restore_defaults() {
    echo "バックアップディレクトリ: $BACKUP_DIR"
    if [[ ! -d "$BACKUP_DIR" ]]; then
        echo "バックアップディレクトリが見つかりません。バックアップを実行してください。"
        exit 1
    fi

    # 設定をリストア
    echo "System Preferences の設定をリストア中..."
    defaults import "$BACKUP_DIR/system_preferences.plist"

    echo "Dock の設定をリストア中..."
    defaults import com.apple.dock "$BACKUP_DIR/com.apple.dock.plist"
    killall Dock

    echo "Finder の設定をリストア中..."
    defaults import com.apple.finder "$BACKUP_DIR/com.apple.finder.plist"
    killall Finder

    echo "スクリーンショットの設定をリストア中..."
    defaults import com.apple.screencapture "$BACKUP_DIR/com.apple.screencapture.plist"

    echo "リストアが完了しました！"
}

# 機種移行
migrate_to_new_mac() {
    echo "機種移行を実行します。"
    backup_defaults
    echo "バックアップファイルを新しい Mac にコピーしてください。"
    echo "新しい Mac でこのスクリプトを実行し、restore_defaults を使用してください。"
}

# メインメニュー
case "$1" in
    backup)
        backup_defaults
        ;;
    restore)
        restore_defaults
        ;;
    migrate)
        migrate_to_new_mac
        ;;
    *)
        echo "使用方法: $0 {backup|restore|migrate}"
        ;;
esac
