#!/bin/bash

# Orgファイルを指定
ORG_FILE=$1

# ファイルが指定されていない場合のエラーメッセージ
if [ -z "$ORG_FILE" ]; then
echo "Usage: $0 <org_file>"
exit 1
fi

# Orgファイルが存在しない場合のエラーメッセージ
if [ ! -f "$ORG_FILE" ]; then
echo "File '$ORG_FILE' not found!"
exit 1
fi

# ドメインを格納する変数
CURRENT_DOMAIN=""

# Orgファイルを1行ずつ読み込む
while IFS= read -r line; do
# ドメイン行を検出
if [[ $line == *"Defaults for domain"* ]]; then
# ドメイン名を抽出
CURRENT_DOMAIN=$(echo "$line" | sed -E "s/\* Defaults for domain '(.*)'/\1/")
echo "Setting defaults for domain: $CURRENT_DOMAIN"
elif [[ $line == "|"* && $line != *"Key"* ]]; then
# キー、値、タイプを抽出
KEY=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')
           VALUE=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3}')
                        TYPE=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $4); print $4}')

                                    # タイプに応じて値を適切な形式で設定
                                    case "$TYPE" in
                                    "boolean")
                        # booleanをtrue/falseで設定
                        if [ "$VALUE" == "true" ]; then
                        defaults write "$CURRENT_DOMAIN" "$KEY" -bool true
                        else
                        defaults write "$CURRENT_DOMAIN" "$KEY" -bool false
                        fi
                        ;;
                        "integer")
           # 整数を設定
           defaults write "$CURRENT_DOMAIN" "$KEY" -int "$VALUE"
           ;;
           "float")
# 浮動小数点数を設定
defaults write "$CURRENT_DOMAIN" "$KEY" -float "$VALUE"
;;
"string")
# 文字列を設定
defaults write "$CURRENT_DOMAIN" "$KEY" -string "$VALUE"
;;
"array")
# 配列として設定 (カンマ区切りのリストを配列に変換)
IFS=',' read -ra ARRAY_VALUES <<< "$VALUE"
defaults write "$CURRENT_DOMAIN" "$KEY" -array "${ARRAY_VALUES[@]}"
;;
"dict")
# 辞書型はサポートが複雑なので、追加の工夫が必要です
echo "Dictionary type not supported directly."
;;
*)
echo "Unknown type '$TYPE' for key '$KEY'. Skipping..."
;;
esac

echo "Set $CURRENT_DOMAIN $KEY to $VALUE (type: $TYPE)"
fi
done < "$ORG_FILE"

echo "Settings from '$ORG_FILE' have been applied."
# apply_org_defaults.sh
