#!/bin/bash

# すべてのドメインを取得
ALL_DOMAINS=$(defaults domains | tr ',' '\n')

# 各ドメインの設定をエクスポート
for DOMAIN in $ALL_DOMAINS; do
# 出力ファイルを設定
OUTPUT_FILE="defaults_$DOMAIN.org"

# Orgモードのテーブルヘッダを書き込み
echo "* Defaults for domain '$DOMAIN'" > "$OUTPUT_FILE"
echo "| Key           | Value         | Type |" >> "$OUTPUT_FILE"
echo "|---------------+---------------+------|" >> "$OUTPUT_FILE"

# ドメインの設定キーと値を取得し、Org形式でテーブルに追加
defaults export "$DOMAIN" - 2>/dev/null | \
plutil -convert json -o - -- - | \
jq -r '. as $parent | to_entries[] | "| \(.key) | \(.value | tostring) | \(.value | type) |"' >> "$OUTPUT_FILE"

# 結果の確認メッセージ
echo "Defaults for domain '$DOMAIN' have been saved to $OUTPUT_FILE"
done
