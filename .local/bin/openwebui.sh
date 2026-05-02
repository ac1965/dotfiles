#!/bin/bash

set -e

# ===== 設定 =====
OPENWEBUI_IMAGE="ghcr.io/open-webui/open-webui:main"
CONTAINER_NAME="open-webui"
BACKUP_DIR="$HOME/Documents/${CONTAINER_NAME}/openwebui_backup_$(date +%Y%m%d_%H%M%S)"
DATA_VOLUME="openwebui_data"   # docker-compose.yml で指定している volume 名

echo "=== Open WebUI アップデート開始 ==="

# 1. 現在稼働中のコンテナ確認
if docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
    echo "[1/5] コンテナ停止中..."
    docker stop "$CONTAINER_NAME"
else
    echo "[1/5] 既存コンテナは見つかりません。新規インストールモードになります。"
fi

# 2. データバックアップ
if docker volume ls --format '{{.Name}}' | grep -q "^$DATA_VOLUME$"; then
    echo "[2/5] データバックアップ中 → $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    docker run --rm -v "$DATA_VOLUME":/data -v "$BACKUP_DIR":/backup alpine \
        tar czf /backup/openwebui_data.tar.gz -C /data .
    echo "バックアップ完了: $BACKUP_DIR/openwebui_data.tar.gz"
else
    echo "[2/5] データボリュームが存在しません。スキップします。"
fi

# 3. 最新イメージ取得
echo "[3/5] Open WebUI イメージを取得中..."
docker pull "$OPENWEBUI_IMAGE"

# 4. 古いコンテナ削除
if docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
    echo "[4/5] 古いコンテナ削除中..."
    docker rm "$CONTAINER_NAME"
fi

# 5. 新しいコンテナ起動
# docker run -d -p 3000:8080 --add-host=host.docker.internal:host-gateway -v open-webui:/app/backend/data --name open-webui --restart always ghcr.io/open-webui/open-webui:main
echo "[5/5] 新しいコンテナ起動中..."
docker run -d -p 3000:8080 --add-host=host.docker.internal:host-gateway -v ${DATA_VOLUME}:/app/backend/data --name ${CONTAINER_NAME} --restart always ${OPENWEBUI_IMAGE}

echo "=== アップデート完了 ==="
echo "✅ OpenWebUI のアップデートと再起動が完了しました"
echo "ブラウザで http://localhost:3000 にアクセスしてください。"
