#!/bin/bash
# start.sh — Vast.ai / Entrypoint startup for ComfyUI Blackwell
set -euo pipefail

echo "========================================="
echo "  ComfyUI Blackwell - Rafael Boni"
echo "========================================="

# ── Directorio base de ComfyUI (dynamico para躲开 RunPod volume mount) ───────
export COMFY_DIR="/comfyuiworkspace/ComfyUI"

# ── SSH ──────────────────────────────────────────────────────────────────────
mkdir -p /run/sshd /root/.ssh
chmod 700 /root/.ssh
echo "root:root" | chpasswd
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config
ssh-keygen -A 2>/dev/null

# SSH key from env var (Vast injects SSH_PUBLIC_KEY as a secret)
if [[ -n "${SSH_PUBLIC_KEY:-}" ]]; then
  echo "$SSH_PUBLIC_KEY" >> /root/.ssh/authorized_keys
  echo "✅ SSH key injected from secret"
fi

# Rafael's Mac key — siempre presente
RAFAEL_PUB='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICqquqVPNxuxQhC7CcaEj9TJcsnK4H7AGkYZtY+xtHbY rafaboni'
if ! grep -q 'qquqVPNxux' /root/.ssh/authorized_keys 2>/dev/null; then
  echo "$RAFAEL_PUB" >> /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
  echo "✅ Rafael's SSH key added"
fi

chown -R root:root /root/.ssh
sshd -t 2>&1
service ssh start 2>/dev/null || true
echo "SSH running: $(ss -tlnp | grep :22 || echo 'check manually')"

# ── Terminal config ────────────────────────────────────────────────────────────
echo 'export TERM=xterm-256color' >> /root/.bashrc
echo 'export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "' >> /root/.bashrc
echo 'bind "set completion-ignore-case on"' >> /root/.bashrc
echo 'bind "set show-all-if-ambiguous on"' >> /root/.bashrc
cp /root/.bashrc /root/.bash_profile 2>/dev/null || true

# ── R2 + rclone sync (background) ─────────────────────────────────────────────
if [[ -n "${R2_ACCESS_KEY:-}" && -n "${R2_SECRET_KEY:-}" && -n "${R2_ENDPOINT:-}" ]]; then
  mkdir -p ~/.config/rclone
  cat > ~/.config/rclone/rclone.conf << 'RCLONE_EOF'
[r2]
type = s3
provider = Other
access_key_id = __R2_ACCESS_KEY__
secret_access_key = __R2_SECRET_KEY__
endpoint = __R2_ENDPOINT__
acl = private
RCLONE_EOF
  sed -i "s/__R2_ACCESS_KEY__/${R2_ACCESS_KEY}/" ~/.config/rclone/rclone.conf
  sed -i "s/__R2_SECRET_KEY__/${R2_SECRET_KEY}/" ~/.config/rclone/rclone.conf
  sed -i "s|__R2_ENDPOINT__|${R2_ENDPOINT}|" ~/.config/rclone/rclone.conf

  mkdir -p /comfyuiworkspace/ComfyUI/output
  (
    echo "→ Workflows desde R2..."
    rclone copy r2:comfy-models/user/ /comfyuiworkspace/ComfyUI/user/ \
      --transfers 16 --fast-list --ignore-existing --exclude "*.db" 2>/dev/null || true
    echo "→ Loras desde R2..."
    rclone copy r2:comfy-models/loras/ /comfyuiworkspace/ComfyUI/models/loras/ \
      --transfers 16 --fast-list --ignore-existing 2>/dev/null || true
    echo "→ Input desde R2..."
    rclone copy r2:comfy-models/input/ /comfyuiworkspace/ComfyUI/input/ \
      --transfers 16 --fast-list --ignore-existing 2>/dev/null || true
    echo "✅ Sync R2 completo"
  ) &
else
  echo "⚠️  R2 credentials no encontradas — skip sync"
fi

# ── FileBrowser ────────────────────────────────────────────────────────────────
echo "[1/3] FileBrowser..."
mkdir -p /comfyuiworkspace/ComfyUI/output
filebrowser -r /comfyuiworkspace -p 8080 --address 0.0.0.0 --noauth &

# ── Jupyter ───────────────────────────────────────────────────────────────────
echo "[2/3] Jupyter Lab..."
cd /comfyuiworkspace && jupyter lab --allow-root --no-browser --port=8888 --ip=0.0.0.0 \
  --ServerApp.token='' \
  --ServerApp.password='' \
  --ServerApp.allow_origin='*' \
  --ServerApp.allow_remote_access=True \
  --ServerApp.disable_check_xsrf=True &

# ── ComfyUI (foreground) ───────────────────────────────────────────────────────
echo "[3/3] Iniciando ComfyUI..."
echo "========================================="
cd /comfyuiworkspace/ComfyUI
python main.py --listen 0.0.0.0 --port 8188
