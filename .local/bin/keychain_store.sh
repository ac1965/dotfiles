#!/bin/bash
# keychain_store.sh — パスフレーズをmacOS Keychainに登録
# 初回セットアップ時のみ実行する
set -euo pipefail

SERVICE="com.encrypt.aes256gcm"
ACCOUNT="${1:-default}"          # 複数ファイル管理する場合のラベル

# パスフレーズ入力（非表示）
read -r -s -p "Passphrase to store (≥20 chars): " pp; echo >&2
if [ ${#pp} -lt 20 ]; then
  echo "❌ Too short" >&2; exit 1
fi
read -r -s -p "Confirm: " pp2; echo >&2
if [ "$pp" != "$pp2" ]; then
  echo "❌ Mismatch" >&2; exit 1
fi

# Keychainに保存（既存エントリは上書き）
security add-generic-password \
  -s "$SERVICE" \
  -a "$ACCOUNT" \
  -w "$pp" \
  -U                             # -U: update if exists

# メモリクリア
pp=$(openssl rand -base64 20)
pp2="$pp"
unset pp pp2

echo "✅ Stored in Keychain: service=${SERVICE}, account=${ACCOUNT}" >&2
