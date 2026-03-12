#!/bin/bash
# update_nodes.sh — escanea custom nodes y actualiza Dockerfile en GitHub
set -e

GITHUB_REPO="rafaboni/comfyui-blackwell"
NODES_DIR="/workspace/ComfyUI/custom_nodes"
BRANCH="main"

echo "========================================="
echo "  KB Tools - Update Nodes"
echo "========================================="

if [ -z "$GITHUB_TOKEN" ]; then
  echo "ERROR: GITHUB_TOKEN no encontrado. Agrégalo como RunPod secret."
  exit 1
fi

echo "[1/4] Escaneando custom nodes instalados..."
CLONE_LINES=""
for dir in "$NODES_DIR"/*/; do
  node_name=$(basename "$dir")
  remote_url=$(git -C "$dir" remote get-url origin 2>/dev/null || echo "")
  if [ -z "$remote_url" ]; then
    echo "  SKIP $node_name (sin remote git)"
    continue
  fi
  remote_url="${remote_url%.git}.git"
  echo "  + $node_name → $remote_url"
  CLONE_LINES="${CLONE_LINES}    git clone --depth 1 ${remote_url} &&\n"
done

# Quitar último &&
CLONE_LINES=$(printf "%b" "$CLONE_LINES" | sed '$ s/ &&$//')

if [ -z "$CLONE_LINES" ]; then
  echo "ERROR: No se encontraron custom nodes."
  exit 1
fi

echo "[2/4] Obteniendo Dockerfile de GitHub..."
API_URL="https://api.github.com/repos/${GITHUB_REPO}/contents/Dockerfile"
RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" "$API_URL")

FILE_SHA=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['sha'])")
CURRENT_CONTENT=$(echo "$RESPONSE" | python3 -c "
import sys, json, base64
d = json.load(sys.stdin)
print(base64.b64decode(d['content']).decode('utf-8'))
")

if [ -z "$FILE_SHA" ]; then
  echo "ERROR: No se pudo obtener el Dockerfile."
  exit 1
fi

echo "[3/4] Generando nuevo bloque de custom nodes..."
NEW_CONTENT=$(python3 << PYEOF
import re, sys

clone_lines = """$CLONE_LINES"""
new_block = "# --- Custom Nodes ---\nWORKDIR /workspace/ComfyUI/custom_nodes\nRUN " + clone_lines.strip()

content = """$CURRENT_CONTENT"""
pattern = r'# --- Custom Nodes ---.*?(?=# --- Dependencias)'
replacement = new_block + "\n\n"
result = re.sub(pattern, replacement, content, flags=re.DOTALL)
print(result, end='')
PYEOF
)

echo "[4/4] Pusheando a GitHub..."
ENCODED=$(echo "$NEW_CONTENT" | base64 | tr -d '\n')
PUSH_RESPONSE=$(curl -s -X PUT \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "$API_URL" \
  -d "{\"message\": \"chore: sync custom nodes from pod\", \"content\": \"$ENCODED\", \"sha\": \"$FILE_SHA\", \"branch\": \"$BRANCH\"}")

COMMIT=$(echo "$PUSH_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('commit',{}).get('sha','ERROR'))" 2>/dev/null || echo "ERROR")

if [ "$COMMIT" = "ERROR" ]; then
  echo "ERROR: Push fallido."
  echo "$PUSH_RESPONSE"
  exit 1
fi

echo ""
echo "✅ Dockerfile actualizado. Commit: $COMMIT"
echo "🔨 GitHub Actions buildeando nueva imagen..."
echo "   https://github.com/${GITHUB_REPO}/actions"
