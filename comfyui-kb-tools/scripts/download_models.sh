#!/bin/bash
# download_models.sh — descarga packs en paralelo con progreso
# SELECTED_PACKS env var: nombres separados por | o "ALL"

COMFY_DIR="/workspace/ComfyUI"
R2_BUCKET="r2:comfy-models"
TMP_DIR="/tmp/kb_models"
TMP_TXT="$TMP_DIR/models_to_download.txt"
TMP_TOKENS="$TMP_DIR/tokens.txt"
PIDS_FILE="$TMP_DIR/download_pids.txt"
PARTIAL_FILE="$TMP_DIR/partial_files.txt"

mkdir -p "$TMP_DIR"
> "$PIDS_FILE"
> "$PARTIAL_FILE"

echo "========================================="
echo "  KB Tools - Descargar Modelos"
echo "========================================="

# --- Configurar rclone ---
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

# --- Leer config de R2 ---
echo "→ Leyendo config desde R2..."
rclone copy "$R2_BUCKET/config/tokens.txt" "$TMP_DIR/" --fast-list 2>/dev/null || true
rclone copy "$R2_BUCKET/config/models_to_download.txt" "$TMP_DIR/" --fast-list

if [ ! -f "$TMP_TXT" ]; then
  echo "ERROR: No se encontró models_to_download.txt en R2."
  exit 1
fi

# --- Leer tokens ---
HF_TOKEN=""
CIVITAI_TOKEN=""
if [ -f "$TMP_TOKENS" ]; then
  HF_TOKEN=$(grep "^HF_TOKEN" "$TMP_TOKENS" | cut -d'=' -f2- | tr -d ' \r')
  CIVITAI_TOKEN=$(grep "^CIVITAI_TOKEN" "$TMP_TOKENS" | cut -d'=' -f2- | tr -d ' \r')
fi

# --- Parsear archivos a descargar ---
declare -a URLS
declare -a DESTS
current_pack=""
in_selected_pack=false

while IFS= read -r line; do
  line="${line%$'\r'}"
  [[ -z "$line" || "$line" =~ ^# ]] && continue

  if [[ "$line" =~ ^PACK:\ (.*) ]]; then
    current_pack="${BASH_REMATCH[1]}"
    if [ "$SELECTED_PACKS" = "ALL" ] || echo "$SELECTED_PACKS" | grep -qF "$current_pack"; then
      in_selected_pack=true
      echo "📦 Pack: $current_pack"
    else
      in_selected_pack=false
    fi
    continue
  fi

  if [ "$in_selected_pack" = true ]; then
    url=$(echo "$line" | awk '{print $1}')
    dest=$(echo "$line" | awk '{print $2}')
    [ -z "$url" ] || [ -z "$dest" ] && continue
    URLS+=("$url")
    DESTS+=("$COMFY_DIR/$dest")
  fi
done < "$TMP_TXT"

if [ ${#URLS[@]} -eq 0 ]; then
  echo "No hay archivos para descargar."
  exit 0
fi

echo ""
echo "⏳ Descargando ${#URLS[@]} archivos en paralelo..."

# --- Descargar cada archivo en background independiente ---
for i in "${!URLS[@]}"; do
  url="${URLS[$i]}"
  dest="${DESTS[$i]}"
  fname=$(basename "$dest")

  # Skip si ya existe
  if [ -f "$dest" ]; then
    echo "PROGRESS:${fname}:100:0"
    echo "  ✓ Ya existe: $fname"
    continue
  fi

  mkdir -p "$(dirname "$dest")"
  echo "$dest" >> "$PARTIAL_FILE"

  # Construir headers
  auth_header=""
  final_url="$url"
  if echo "$url" | grep -q "huggingface.co" && [ -n "$HF_TOKEN" ]; then
    auth_header="-H \"Authorization: Bearer $HF_TOKEN\""
  elif echo "$url" | grep -q "civitai.com" && [ -n "$CIVITAI_TOKEN" ]; then
    final_url="${url}?token=${CIVITAI_TOKEN}"
  fi

  # Lanzar descarga + monitor como proceso completamente independiente
  (
    START=$(date +%s)
    TOTAL=$(eval curl -sI $auth_header "$final_url" 2>/dev/null | grep -i content-length | awk '{print $2}' | tr -d '\r')
    [ -z "$TOTAL" ] && TOTAL=0

    eval curl -L --no-progress-meter $auth_header -o "$dest" "$final_url" 2>/dev/null &
    CURL_PID=$!

    while kill -0 $CURL_PID 2>/dev/null; do
      sleep 1
      if [ -f "$dest" ] && [ "$TOTAL" -gt 0 ]; then
        CURRENT=$(stat -c%s "$dest" 2>/dev/null || echo 0)
        PCT=$(python3 -c "print(min(99, int($CURRENT * 100 / $TOTAL)))")
        ELAPSED=$(( $(date +%s) - START ))
        SPEED=0
        [ "$ELAPSED" -gt 0 ] && SPEED=$(python3 -c "print(round($CURRENT/1048576/$ELAPSED,1))")
        echo "PROGRESS:${fname}:${PCT}:${SPEED}"
      fi
    done

    wait $CURL_PID
    CODE=$?
    if [ $CODE -ne 0 ] || [ ! -s "$dest" ]; then
      echo "PROGRESS:${fname}:ERROR:0"
      echo "  ❌ Error: $fname"
      rm -f "$dest"
    else
      ELAPSED=$(( $(date +%s) - START ))
      SIZE=$(python3 -c "print(round($(stat -c%s "$dest")/1048576,1))")
      AVG=0
      [ "$ELAPSED" -gt 0 ] && AVG=$(python3 -c "print(round($SIZE/$ELAPSED,1))")
      echo "PROGRESS:${fname}:100:${AVG}"
      echo "  ✅ ${fname} — ${SIZE}MB @ ${AVG} MB/s"
    fi
    sed -i "\|$dest|d" "$PARTIAL_FILE" 2>/dev/null
  ) &
  echo $! >> "$PIDS_FILE"
done

# Esperar a que terminen todos
wait

echo ""
echo "✅ Descarga completa."
rm -f "$PIDS_FILE" "$PARTIAL_FILE"
