#!/bin/bash

echo "========================================="
echo "  ComfyUI Blackwell - Rafael Boni"
echo "========================================="

# --- SSH ---
mkdir -p /run/sshd
echo "root:root" | chpasswd
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
service ssh start

# --- Terminal config ---
echo 'export TERM=xterm-256color' >> /root/.bashrc
echo 'export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "' >> /root/.bashrc
echo 'bind "set completion-ignore-case on"' >> /root/.bashrc
echo 'bind "set show-all-if-ambiguous on"' >> /root/.bashrc
cp /root/.bashrc /root/.bash_profile

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

# --- FileBrowser ---
echo "[1/3] Iniciando FileBrowser..."
mkdir -p /workspace/ComfyUI/output
filebrowser -r /workspace -p 8080 --address 0.0.0.0 --noauth &

# --- Jupyter ---
echo "[2/3] Iniciando Jupyter Lab..."
cd /workspace && jupyter lab --allow-root --no-browser --port=8888 --ip=0.0.0.0 \
  --ServerApp.token='' \
  --ServerApp.password='' \
  --ServerApp.allow_origin='*' \
  --ServerApp.allow_remote_access=True \
  --ServerApp.disable_check_xsrf=True &

# --- Descarga inicial en background ---
echo "[3/3] Descargando workflows, loras e input desde R2 (background)..."
(
  echo "→ Workflows..."
  rclone copy r2:comfy-models/user/ /workspace/ComfyUI/user/ \
    --transfers 16 --fast-list --ignore-existing \
    --exclude "*.db"

  echo "→ Loras..."
  rclone copy r2:comfy-models/loras/ /workspace/ComfyUI/models/loras/ \
    --transfers 16 --fast-list --ignore-existing

  echo "→ Input..."
  rclone copy r2:comfy-models/input/ /workspace/ComfyUI/input/ \
    --transfers 16 --fast-list --ignore-existing

  echo "✅ Listo para trabajar."
) &

# --- ComfyUI (foreground) ---
echo "Iniciando ComfyUI..."
cd /workspace/ComfyUI
python main.py --listen 0.0.0.0 --port 8188
