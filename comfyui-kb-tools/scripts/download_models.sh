#!/bin/bash
# download_models.sh
# Descarga packs seleccionados desde models_to_download.txt en R2
# SELECTED_PACKS env var: nombres de packs separados por | (ej: "Klein 9B fp8|WAN 2.2 I2V")
# Si SELECTED_PACKS="ALL" descarga todos los packs

COMFY_DIR="/workspace/ComfyUI"
R2_BUCKET="r2:comfy-models"
TMP_DIR="/tmp/kb_models"
TMP_TXT="$TMP_DIR/models_to_download.txt"
TMP_TOKENS="$TMP_DIR/tokens.txt"

mkdir -p "$TMP_DIR"

echo "========================================="
echo "  KB Tools - Descargar Modelos"
echo "========================================="

# --- Bajar config de R2 ---
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
  HF_TOKEN=$(grep "HF_TOKEN" "$TMP_TOKENS" | cut -d'=' -f2 | tr -d ' \r')
  CIVITAI_TOKEN=$(grep "CIVITAI_TOKEN" "$TMP_TOKENS" | cut -d'=' -f2 | tr -d ' \r')
fi

# --- Parsear y descargar packs seleccionados ---
current_pack=""
in_selected_pack=false

download_file() {
  local url="$1"
  local dest_rel="$2"
  local dest_abs="$COMFY_DIR/$dest_rel"

  # Skip si ya existe
  if [ -f "$dest_abs" ]; then
    echo "  ✓ Ya existe: $(basename $dest_abs)"
    return
  fi

  mkdir -p "$(dirname "$dest_abs")"
  echo "  ↓ Descargando: $(basename $dest_abs)"

  local auth_header=""
  local final_url="$url"
  if echo "$url" | grep -q "huggingface.co" && [ -n "$HF_TOKEN" ]; then
    auth_header="-H \"Authorization: Bearer $HF_TOKEN\""
  elif echo "$url" | grep -q "civitai.com" && [ -n "$CIVITAI_TOKEN" ]; then
    final_url="${url}?token=${CIVITAI_TOKEN}"
  fi

  # Obtener tamaño total primero
  local total_bytes=$(eval curl -sI $auth_header "$final_url" 2>/dev/null | grep -i content-length | awk '{print $2}' | tr -d '\r')
  [ -z "$total_bytes" ] && total_bytes=0

  # Descargar en background silencioso y monitorear tamaño
  eval curl -L --no-progress-meter $auth_header -o "$dest_abs" "$final_url" 2>/dev/null &
  local curl_pid=$!
  local last_pct=0
  local start_time=$(date +%s)

  while kill -0 $curl_pid 2>/dev/null; do
    sleep 1
    if [ -f "$dest_abs" ] && [ "$total_bytes" -gt 0 ]; then
      local current=$(stat -c%s "$dest_abs" 2>/dev/null || echo 0)
      local pct=$(( current * 100 / total_bytes ))
      local elapsed=$(( $(date +%s) - start_time ))
      local speed_mb=0
      [ "$elapsed" -gt 0 ] && speed_mb=$(python3 -c "print(round($current / 1048576 / $elapsed, 1))")
      echo "PROGRESS:$(basename $dest_abs):${pct}:${speed_mb}"
    fi
  done

  wait $curl_pid
  local exit_code=$?

  if [ $exit_code -ne 0 ] || [ ! -s "$dest_abs" ]; then
    echo "  ❌ Error descargando $(basename $dest_abs)"
    rm -f "$dest_abs"
  else
    local elapsed=$(( $(date +%s) - start_time ))
    local size_mb=$(python3 -c "print(round($(stat -c%s "$dest_abs") / 1048576, 1))")
    local avg_speed=0
    [ "$elapsed" -gt 0 ] && avg_speed=$(python3 -c "print(round($size_mb / $elapsed, 1))")
    echo "  ✅ $(basename $dest_abs) — ${size_mb}MB en ${elapsed}s @ ${avg_speed} MB/s"
  fi
}

while IFS= read -r line; do
  line="${line%$'\r'}"
  [[ -z "$line" || "$line" =~ ^# ]] && continue

  if [[ "$line" =~ ^PACK:\ (.*) ]]; then
    current_pack="${BASH_REMATCH[1]}"
    if [ "$SELECTED_PACKS" = "ALL" ]; then
      in_selected_pack=true
    else
      # Verificar si este pack está en la lista seleccionada
      if echo "$SELECTED_PACKS" | grep -qF "$current_pack"; then
        in_selected_pack=true
        echo ""
        echo "📦 Pack: $current_pack"
      else
        in_selected_pack=false
      fi
    fi
    if [ "$in_selected_pack" = true ] && [ "$SELECTED_PACKS" = "ALL" ]; then
      echo ""
      echo "📦 Pack: $current_pack"
    fi
    continue
  fi

  if [ "$in_selected_pack" = true ]; then
    url=$(echo "$line" | awk '{print $1}')
    dest=$(echo "$line" | awk '{print $2}')
    [ -n "$url" ] && [ -n "$dest" ] && download_file "$url" "$dest"
  fi

done < "$TMP_TXT"

echo ""
echo "✅ Descarga completa."
