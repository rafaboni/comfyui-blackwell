#!/bin/bash

echo "========================================="
echo "  ComfyUI Blackwell - Rafael Boni"
echo "========================================="

# --- Configurar rclone con R2 ---
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

# --- Filebrowser ---
echo "[1/3] Iniciando FileBrowser..."
mkdir -p /workspace/ComfyUI/output
filebrowser -r /workspace -p 8080 --address 0.0.0.0 --noauth &

# --- Jupyter ---
echo "[2/3] Iniciando Jupyter Lab..."
jupyter lab --allow-root --no-browser --port=8888 --ip=0.0.0.0 \
  --ServerApp.token='' \
  --ServerApp.password='' \
  --ServerApp.allow_origin='*' \
  --ServerApp.allow_remote_access=True \
  --ServerApp.disable_check_xsrf=True &

# --- Bajar modelos en background ---
echo "[3/3] Descargando modelos desde R2 (background)..."
(
  # Workflows primero — excluir DBs para no corromper la de ComfyUI
  rclone copy r2:comfy-models/user/ /workspace/ComfyUI/user/ \
    --transfers 32 \
    --ignore-existing \
    --exclude "*.db"

  # Modelos
  rclone copy r2:comfy-models/ /workspace/ComfyUI/models/ \
    --transfers 32 \
    --multi-thread-streams 8 \
    --buffer-size 256M \
    --checkers 64 \
    --fast-list \
    --ignore-existing \
    --exclude "user/**" \
    --exclude "LLM/**" \
    --exclude "text_encoders/gemma*" \
    --exclude "checkpoints/ltx*" \
    --exclude "loras/ltx*" \
    --exclude "*.db" \
    --progress

  echo "Modelos descargados."
) &

# --- ComfyUI (foreground, mantiene el container vivo) ---
echo "Iniciando ComfyUI..."
cd /workspace/ComfyUI
python main.py --listen 0.0.0.0 --port 8188
