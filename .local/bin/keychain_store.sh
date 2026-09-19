#!/usr/bin/env zsh
# keychain_store.sh — パスフレーズをmacOS Keychainに登録
# 初回セットアップ時のみ実行する
# -g/--generate: 対話入力の代わりにランダムなパスフレーズを自動生成
# -f/--force:    既存エントリがあっても確認なしで上書き
#
# 実際の登録・上書き判定は keychain-helper に委譲する。helper はアイテム
# 作成時に自分自身だけを信頼アプリとして登録するため(security add-generic-
# password では実現できない)、素の `security` コマンドや他プロセスからの
# 読み出しはKeychainの確認ダイアログの対象になる。詳細は
# keychain-helper.swift 冒頭のコメントを参照。
set -euo pipefail

SERVICE="com.encrypt.aes256gcm"
BINDIR="${0:A:h}"
HELPER="${BINDIR}/keychain-helper"

usage() {
  echo "Usage: $0 [-g|--generate] [-f|--force] [account]" >&2
  exit 1
}

generate=0
force=0
account=""
for a in "$@"; do
  case "$a" in
    -g|--generate) generate=1 ;;
    -f|--force) force=1 ;;
    -h|--help) usage ;;
    -*) echo "Unknown option: $a" >&2; usage ;;
    *) account="$a" ;;
  esac
done
ACCOUNT="${account:-private-archive}"    # 複数ファイル管理する場合のラベル

if [ ! -x "$HELPER" ]; then
  swiftc "${BINDIR}/keychain-helper.swift" -o "$HELPER"
fi

if (( ! force )) && "$HELPER" get "$ACCOUNT" >/dev/null 2>&1; then
  echo "⚠️  Keychainに既存エントリがあります (service=$SERVICE, account=$ACCOUNT)。" >&2
  echo "   上書きすると、このパスフレーズで暗号化済みのファイルが復号できなくなります。" >&2
  echo "   上書きする場合は -f/--force を付けて再実行してください。" >&2
  exit 1
fi

if (( generate )); then
  "$HELPER" generate -f "$ACCOUNT"
  exit 0
fi

# パスフレーズ入力（非表示）
# zsh の `read -p` は bash と異なりコプロセスからの読み込みを意味するため、
# プロンプト表示には `read name?prompt` 構文を使う。
read -r -s "pp?Passphrase to store (≥20 chars): "; echo >&2
if [ ${#pp} -lt 20 ]; then
  echo "❌ Too short" >&2; exit 1
fi
read -r -s "pp2?Confirm: "; echo >&2
if [ "$pp" != "$pp2" ]; then
  echo "❌ Mismatch" >&2; exit 1
fi

printf '%s\n' "$pp" | "$HELPER" set -f "$ACCOUNT"

# メモリクリア
pp=$(openssl rand -base64 20)
pp2="$pp"
unset pp pp2
