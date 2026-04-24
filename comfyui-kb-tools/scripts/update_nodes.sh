#!/bin/bash
# update_nodes.sh — actualiza el Dockerfile en GitHub con los custom nodes actuales
# Solo usar cuando instales o desinstales un custom node

COMFY_DIR="${COMFY_DIR:-/comfyuiworkspace/ComfyUI}"
GITHUB_REPO="rafaboni/comfyui-blackwell"
BRANCH="main"

echo "========================================="
echo "  KB Tools - Update Custom Nodes"
echo "========================================="

# --- Leer GITHUB_TOKEN de R2 ---
rclone copy "r2:comfy-models/config/tokens.txt" "/tmp/" --fast-list 2>/dev/null || true
if [ -f "/tmp/tokens.txt" ]; then
  [ -z "$GITHUB_TOKEN" ] && export GITHUB_TOKEN=$(grep "^GITHUB_TOKEN" /tmp/tokens.txt | cut -d'=' -f2- | tr -d ' \r')
fi

if [ -z "$GITHUB_TOKEN" ]; then
  echo "ERROR: GITHUB_TOKEN no encontrado en R2 config/tokens.txt"
  exit 1
fi

# --- Escanear custom nodes instalados ---
echo "Escaneando custom nodes..."
NODES_DIR="$COMFY_DIR/custom_nodes"
URLS=()
for dir in "$NODES_DIR"/*/; do
  remote_url=$(git -C "$dir" remote get-url origin 2>/dev/null || echo "")
  [ -z "$remote_url" ] && continue
  remote_url="${remote_url%.git}.git"
  echo "  + $(basename $dir)"
  URLS+=("$remote_url")
done

if [ ${#URLS[@]} -eq 0 ]; then
  echo "ERROR: No se encontraron custom nodes con remote git."
  exit 1
fi

# --- Obtener Dockerfile actual de GitHub ---
echo "Obteniendo Dockerfile de GitHub..."
API_URL="https://api.github.com/repos/${GITHUB_REPO}/contents/Dockerfile"
RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" "$API_URL")

FILE_SHA=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['sha'])" 2>/dev/null)
if [ -z "$FILE_SHA" ]; then
  echo "ERROR: No se pudo obtener el Dockerfile de GitHub."
  exit 1
fi

# Decodificar contenido actual a archivo temporal
echo "$RESPONSE" | python3 -c "
import sys, json, base64
d = json.load(sys.stdin)
sys.stdout.buffer.write(base64.b64decode(d['content']))
" > /tmp/current_dockerfile.txt

if [ ! -s /tmp/current_dockerfile.txt ]; then
  echo "ERROR: Dockerfile actual esta vacio o no se pudo decodificar."
  exit 1
fi

# Guardar URLs en archivo temporal (una por linea)
printf '%s\n' "${URLS[@]}" > /tmp/node_urls.txt

# --- Generar nuevo Dockerfile con Python ---
NEW_CONTENT=$(COMFY_DIR="$COMFY_DIR" python3 << 'PYEOF'
import re, os, sys

# Leer URLs desde archivo temporal
with open('/tmp/node_urls.txt', 'r') as f:
    url_list = [u.strip() for u in f.readlines() if u.strip()]

if not url_list:
    print("ERROR: lista de URLs vacia", file=sys.stderr)
    sys.exit(1)

# Generar bloque RUN git clone
lines = []
for i, url in enumerate(url_list):
    if i < len(url_list) - 1:
        lines.append(f"    git clone --depth 1 {url} && \\")
    else:
        lines.append(f"    git clone --depth 1 {url}")

comfy_dir = os.environ.get("COMFY_DIR", "/comfyuiworkspace/ComfyUI")
clone_block = (
    "# --- Custom Nodes ---\n"
    f"WORKDIR {comfy_dir}/custom_nodes\n"
    "RUN " + "\n".join(lines)
)

# Leer Dockerfile actual
with open('/tmp/current_dockerfile.txt', 'r') as f:
    content = f.read()

# Reemplazar seccion Custom Nodes
pattern = r'# --- Custom Nodes ---.*?(?=\n# --- Dependencias)'
replacement = clone_block + "\n"
result = re.sub(pattern, replacement, content, flags=re.DOTALL)

if result == content:
    print("WARN: No se encontro la seccion Custom Nodes en el Dockerfile", file=sys.stderr)

print(result, end='')
PYEOF
)

if [ $? -ne 0 ] || [ -z "$NEW_CONTENT" ]; then
  echo "ERROR: Fallo la generacion del nuevo Dockerfile."
  exit 1
fi

# --- Verificar si cambio ---
CURRENT_CONTENT=$(cat /tmp/current_dockerfile.txt)
if [ "$NEW_CONTENT" = "$CURRENT_CONTENT" ]; then
  echo "Sin cambios en custom nodes — no se necesita rebuild."
  exit 0
fi

# --- Push a GitHub ---
echo "Actualizando Dockerfile en GitHub..."
ENCODED=$(echo "$NEW_CONTENT" | base64 | tr -d '\n')
PUSH_RESPONSE=$(curl -s -X PUT \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "$API_URL" \
  -d "{\"message\": \"chore: sync custom nodes from pod\", \"content\": \"$ENCODED\", \"sha\": \"$FILE_SHA\", \"branch\": \"$BRANCH\"}")

COMMIT=$(echo "$PUSH_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('commit',{}).get('sha','ERROR'))" 2>/dev/null || echo "ERROR")
if [ "$COMMIT" = "ERROR" ]; then
  echo "ERROR: Push fallido."
  echo "$PUSH_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('message','Unknown error'))" 2>/dev/null
  exit 1
fi

echo "Dockerfile actualizado. Commit: ${COMMIT:0:7}"
echo "GitHub Actions esta buildeando la nueva imagen..."
echo "   https://github.com/${GITHUB_REPO}/actions"

# Limpiar archivos temporales
rm -f /tmp/current_dockerfile.txt /tmp/node_urls.txt
