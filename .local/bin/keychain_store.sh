#!/usr/bin/env zsh
# keychain_store.sh — パスフレーズをmacOS Keychainに登録
# 初回セットアップ時のみ実行する
# -g/--generate: 対話入力の代わりにランダムなパスフレーズを自動生成
# -f/--force:    既存エントリがあっても確認なしで上書き
#
# 素の `security` コマンドで登録する(自前バイナリでのアクセス制限は
# ビルドのたびに信頼関係が壊れ無人実行がハングする問題があったため撤回
# 済み。詳細は encrypt 冒頭のコメントを参照)。
set -euo pipefail

SERVICE="com.encrypt.aes256gcm"

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
LABEL="dotfiles encrypt/decrypt (${ACCOUNT})"

if (( ! force )) && security find-generic-password -s "$SERVICE" -a "$ACCOUNT" -w >/dev/null 2>&1; then
  echo "⚠️  Keychainに既存エントリがあります (service=$SERVICE, account=$ACCOUNT)。" >&2
  echo "   上書きすると、このパスフレーズで暗号化済みのファイルが復号できなくなります。" >&2
  echo "   上書きする場合は -f/--force を付けて再実行してください。" >&2
  exit 1
fi

if (( generate )); then
  pp=$(openssl rand -base64 32)
else
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
fi

# Keychainに保存（既存エントリは上書き）
security add-generic-password \
  -s "$SERVICE" \
  -a "$ACCOUNT" \
  -l "$LABEL" \
  -w "$pp" \
  -U                             # -U: update if exists

if (( generate )); then
  echo "⚠️  このパスフレーズはこのMacにしか存在しません(iCloud同期なし)。今のうちにパスワードマネージャーへ保存してください:" >&2
  echo "    $pp" >&2
fi

# メモリクリア
pp=$(openssl rand -base64 20)
pp2="$pp"
unset pp pp2

echo "✅ Stored in Keychain: service=${SERVICE}, account=${ACCOUNT}" >&2
