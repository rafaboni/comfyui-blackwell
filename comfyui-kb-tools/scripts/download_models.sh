#!/bin/bash
# download_models.sh
# Lee config/models_to_download.txt de R2, descarga los modelos seleccionados.
# SELECTED_MODELS env var: índices separados por coma (ej: "0,2,5")
# Si SELECTED_MODELS="ALL" descarga todo.

COMFY_DIR="/workspace/ComfyUI"
R2_BUCKET="r2:comfy-models"
TMP_TXT="/tmp/models_to_download.txt"
TMP_TOKENS="/tmp/tokens.txt"

echo "========================================="
echo "  KB Tools - Descargar Modelos"
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

# --- Bajar tokens ---
echo "→ Leyendo tokens..."
rclone copy "$R2_BUCKET/config/tokens.txt" /tmp/ --fast-list 2>/dev/null || true

HF_TOKEN=""
CIVITAI_TOKEN=""
if [ -f "$TMP_TOKENS" ]; then
  HF_TOKEN=$(grep "HF_TOKEN" "$TMP_TOKENS" | cut -d'=' -f2 | tr -d ' \r')
  CIVITAI_TOKEN=$(grep "CIVITAI_TOKEN" "$TMP_TOKENS" | cut -d'=' -f2 | tr -d ' \r')
fi

# --- Bajar lista de modelos ---
echo "→ Leyendo lista de modelos..."
rclone copy "$R2_BUCKET/config/models_to_download.txt" /tmp/ --fast-list

if [ ! -f "$TMP_TXT" ]; then
  echo "ERROR: No se encontró config/models_to_download.txt en R2."
  exit 1
fi

# Parsear líneas válidas (no vacías, no comentarios)
mapfile -t LINES < <(grep -v '^\s*#' "$TMP_TXT" | grep -v '^\s*$')

if [ ${#LINES[@]} -eq 0 ]; then
  echo "ERROR: La lista de modelos está vacía."
  exit 1
fi

# Selección de modelos
IFS=',' read -ra INDICES <<< "${SELECTED_MODELS:-ALL}"

for i in "${!LINES[@]}"; do
  line="${LINES[$i]}"

  # Verificar si este índice está seleccionado
  if [ "${SELECTED_MODELS}" != "ALL" ]; then
    selected=false
    for idx in "${INDICES[@]}"; do
      [ "$idx" = "$i" ] && selected=true && break
    done
    [ "$selected" = false ] && continue
  fi

  # Parsear línea: URL DESTINO_RELATIVO
  url=$(echo "$line" | awk '{print $1}')
  dest_rel=$(echo "$line" | awk '{print $2}')

  if [ -z "$url" ] || [ -z "$dest_rel" ]; then
    echo "SKIP línea $i: formato inválido — '$line'"
    continue
  fi

  dest_abs="$COMFY_DIR/$dest_rel"
  mkdir -p "$(dirname "$dest_abs")"
  filename=$(basename "$dest_abs")

  echo ""
  echo "→ Descargando: $filename"
  echo "  URL: $url"
  echo "  Destino: $dest_abs"

  # Determinar headers según dominio
  if echo "$url" | grep -q "huggingface.co"; then
    if [ -n "$HF_TOKEN" ]; then
      wget -q --show-progress -O "$dest_abs" \
        --header="Authorization: Bearer $HF_TOKEN" "$url"
    else
      wget -q --show-progress -O "$dest_abs" "$url"
    fi
  elif echo "$url" | grep -q "civitai.com"; then
    if [ -n "$CIVITAI_TOKEN" ]; then
      wget -q --show-progress -O "$dest_abs" \
        "${url}?token=${CIVITAI_TOKEN}"
    else
      wget -q --show-progress -O "$dest_abs" "$url"
    fi
  else
    wget -q --show-progress -O "$dest_abs" "$url"
  fi

  if [ $? -eq 0 ]; then
    echo "  ✅ $filename descargado."
  else
    echo "  ❌ Error descargando $filename."
    rm -f "$dest_abs"
  fi
done

echo ""
echo "✅ Descarga completa."
