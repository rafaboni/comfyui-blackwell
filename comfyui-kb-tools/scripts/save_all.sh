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

# --- 1. Workflows ---
echo ""
echo "[1/4] 📋 Subiendo workflows..."
rclone copy "$COMFY_DIR/user/" "$R2_BUCKET/user/" \
  --transfers 16 --fast-list --ignore-existing --progress \
  --exclude "*.db"
echo "✅ Workflows salvados."

# --- 2. Loras ---
echo ""
echo "[2/4] 🎨 Subiendo loras..."
rclone copy "$COMFY_DIR/models/loras/" "$R2_BUCKET/loras/" \
  --transfers 16 --fast-list --ignore-existing --progress
echo "✅ Loras salvadas."

# --- 3. Input ---
echo ""
echo "[3/4] 🖼  Subiendo imágenes de input..."
rclone copy "$COMFY_DIR/input/" "$R2_BUCKET/input/" \
  --transfers 16 --fast-list --ignore-existing --progress
echo "✅ Input salvado."

# --- 4. Custom nodes → GitHub ---
echo ""
echo "[4/4] 🧩 Actualizando custom nodes en GitHub..."

if [ -z "$GITHUB_TOKEN" ]; then
  echo "SKIP: GITHUB_TOKEN no configurado."
else
  NODES_DIR="$COMFY_DIR/custom_nodes"
  CLONE_LINES=""
  for dir in "$NODES_DIR"/*/; do
    node_name=$(basename "$dir")
    remote_url=$(git -C "$dir" remote get-url origin 2>/dev/null || echo "")
    [ -z "$remote_url" ] && continue
    remote_url="${remote_url%.git}.git"
    echo "  + $node_name"
    CLONE_LINES="${CLONE_LINES}    git clone --depth 1 ${remote_url} &&\n"
  done
  CLONE_LINES=$(printf "%b" "$CLONE_LINES" | sed '$ s/ &&$//')

  API_URL="https://api.github.com/repos/${GITHUB_REPO}/contents/Dockerfile"
  RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" "$API_URL")
  FILE_SHA=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['sha'])")
  CURRENT_CONTENT=$(echo "$RESPONSE" | python3 -c "
import sys, json, base64
d = json.load(sys.stdin)
print(base64.b64decode(d['content']).decode('utf-8'))
")

  NEW_CONTENT=$(python3 << PYEOF
import re
clone_lines = """$CLONE_LINES"""
new_block = "# --- Custom Nodes ---\nWORKDIR /workspace/ComfyUI/custom_nodes\nRUN " + clone_lines.strip()
content = """$CURRENT_CONTENT"""
pattern = r'# --- Custom Nodes ---.*?(?=# --- Dependencias)'
replacement = new_block + "\n\n"
result = re.sub(pattern, replacement, content, flags=re.DOTALL)
print(result, end='')
PYEOF
)

  ENCODED=$(echo "$NEW_CONTENT" | base64 | tr -d '\n')
  PUSH_RESPONSE=$(curl -s -X PUT \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "$API_URL" \
    -d "{\"message\": \"chore: save_all sync nodes\", \"content\": \"$ENCODED\", \"sha\": \"$FILE_SHA\", \"branch\": \"$BRANCH\"}")

  COMMIT=$(echo "$PUSH_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('commit',{}).get('sha','ERROR'))" 2>/dev/null || echo "ERROR")
  if [ "$COMMIT" = "ERROR" ]; then
    echo "WARN: No se pudo actualizar Dockerfile en GitHub."
  else
    echo "✅ Nodes actualizados. Commit: $COMMIT"
  fi
fi

echo ""
echo "========================================="
echo "✅ TODO SALVADO — sesión segura 🎉"
echo "========================================="
