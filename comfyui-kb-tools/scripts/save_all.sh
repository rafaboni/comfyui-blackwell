#!/bin/bash
# save_all.sh — sube workflows + loras + input + actualiza nodes en GitHub
set -e

COMFY_DIR="/workspace/ComfyUI"
R2_BUCKET="r2:comfy-models"
GITHUB_REPO="rafaboni/comfyui-blackwell"
BRANCH="main"

echo "========================================="
echo "  KB Tools - SALVAR TODO"
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

# --- Leer tokens de R2 ---
rclone copy "r2:comfy-models/config/tokens.txt" "/tmp/" --fast-list 2>/dev/null || true
if [ -f "/tmp/tokens.txt" ]; then
  [ -z "$GITHUB_TOKEN" ]   && export GITHUB_TOKEN=$(grep   "^GITHUB_TOKEN"   /tmp/tokens.txt | cut -d'=' -f2- | tr -d ' \r')
  [ -z "$HF_TOKEN" ]       && export HF_TOKEN=$(grep       "^HF_TOKEN"       /tmp/tokens.txt | cut -d'=' -f2- | tr -d ' \r')
  [ -z "$CIVITAI_TOKEN" ]  && export CIVITAI_TOKEN=$(grep  "^CIVITAI_TOKEN"  /tmp/tokens.txt | cut -d'=' -f2- | tr -d ' \r')
fi

# --- 1. Workflows (--update sube solo si es más nuevo) ---
echo ""
echo "[1/4] 📋 Subiendo workflows..."
rclone copy "$COMFY_DIR/user/" "$R2_BUCKET/user/" \
  --transfers 16 --fast-list --update \
  --exclude "*.db"
echo "✅ Workflows salvados."

# --- 2. Loras ---
echo ""
echo "[2/4] 🎨 Subiendo loras..."
rclone copy "$COMFY_DIR/models/loras/" "$R2_BUCKET/loras/" \
  --transfers 16 --fast-list --update
echo "✅ Loras salvadas."

# --- 3. Input ---
echo ""
echo "[3/4] 🖼  Subiendo imágenes de input..."
rclone copy "$COMFY_DIR/input/" "$R2_BUCKET/input/" \
  --transfers 16 --fast-list --update
echo "✅ Input salvado."

# --- 4. Custom nodes ---
echo ""
echo "[4/4] 🧩 Custom nodes..."
echo "  Usa el botón 'Update Nodes' en KB Tools si instalaste nuevos nodes."

echo ""
echo "========================================="
echo "✅ TODO SALVADO — sesión segura 🎉"
echo "========================================="
