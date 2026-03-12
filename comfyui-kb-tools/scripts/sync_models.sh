#!/bin/bash
# sync_models.sh — sincroniza modelos entre pod y R2
# Lee SYNC_MODE: download | upload | both | dryrun

MODELS_DIR="/workspace/ComfyUI/models"
INPUT_DIR="/workspace/ComfyUI/input"
R2_BUCKET="r2:comfy-models"
MODE="${SYNC_MODE:-download}"

echo "========================================="
echo "  KB Tools - Sync Models [$MODE]"
echo "========================================="

if [ -z "$R2_ACCESS_KEY" ] || [ -z "$R2_SECRET_KEY" ] || [ -z "$R2_ENDPOINT" ]; then
  echo "ERROR: Faltan credenciales R2."
  exit 1
fi

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

FLAGS="--transfers 32 --multi-thread-streams 8 --buffer-size 256M --checkers 64 --fast-list --progress"
EXCLUDES='--exclude "LLM/**" --exclude "*.db"'

download() {
  echo "[↓] Descargando modelos faltantes de R2 → Pod..."
  eval rclone copy "$R2_BUCKET/" "$MODELS_DIR/" $FLAGS $EXCLUDES --ignore-existing
  echo "[↓] Descargando input faltante de R2 → Pod..."
  eval rclone copy "$R2_BUCKET/input/" "$INPUT_DIR/" --transfers 16 --fast-list --ignore-existing --progress
  echo "✅ Download completo."
}

upload() {
  echo "[↑] Subiendo modelos nuevos Pod → R2..."
  eval rclone copy "$MODELS_DIR/" "$R2_BUCKET/" $FLAGS $EXCLUDES --ignore-existing
  echo "[↑] Subiendo input nuevo Pod → R2..."
  eval rclone copy "$INPUT_DIR/" "$R2_BUCKET/input/" --transfers 16 --fast-list --ignore-existing --progress
  echo "✅ Upload completo."
}

dryrun() {
  echo "[?] Modelos en R2 que faltan en el pod:"
  eval rclone copy "$R2_BUCKET/" "$MODELS_DIR/" $EXCLUDES --ignore-existing --dry-run 2>&1 \
    | grep -E "^NOTICE|Skipped" | sed 's/NOTICE: //' || echo "(ninguno)"

  echo ""
  echo "[?] Modelos en el pod que faltan en R2:"
  eval rclone copy "$MODELS_DIR/" "$R2_BUCKET/" $EXCLUDES --ignore-existing --dry-run 2>&1 \
    | grep -E "^NOTICE|Skipped" | sed 's/NOTICE: //' || echo "(ninguno)"
}

case $MODE in
  download) download ;;
  upload)   upload ;;
  both)     download; echo ""; upload ;;
  dryrun)   dryrun ;;
  *)        echo "ERROR: SYNC_MODE inválido: $MODE"; exit 1 ;;
esac
