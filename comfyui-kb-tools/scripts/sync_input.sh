#!/bin/bash
# sync_input.sh — sube o baja la carpeta input
# MODE env var: upload | download

INPUT_DIR="/workspace/ComfyUI/input"
R2_BUCKET="r2:comfy-models"
MODE="${MODE:-upload}"

echo "========================================="
echo "  KB Tools - Sync Input [$MODE]"
echo "========================================="

mkdir -p ~/.config/rclone
cat > ~/.config/rclone/rclone.conf << EOF
[r2]
type = s3
provider = Other
access_key_id = ${R2_ACCESS_KEY}
secret_access_key = ${R2_SECRET_KEY}
endpoint = ${R2_ENDPOINT}
acl = private
EOF

FLAGS="--transfers 16 --fast-list --ignore-existing --progress"

case $MODE in
  upload)
    echo "[↑] Subiendo input → R2..."
    eval rclone copy "$INPUT_DIR/" "$R2_BUCKET/input/" $FLAGS
    echo "✅ Input subido."
    ;;
  download)
    echo "[↓] Bajando input ← R2..."
    eval rclone copy "$R2_BUCKET/input/" "$INPUT_DIR/" $FLAGS
    echo "✅ Input descargado."
    ;;
  *)
    echo "ERROR: MODE inválido: $MODE"
    exit 1
    ;;
esac
