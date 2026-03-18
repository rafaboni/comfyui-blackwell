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

  if echo "$url" | grep -q "huggingface.co" && [ -n "$HF_TOKEN" ]; then
    curl -L --progress-bar -o "$dest_abs" \
      -H "Authorization: Bearer $HF_TOKEN" "$url" 2>&1 || { echo "  ❌ Error"; rm -f "$dest_abs"; }
  elif echo "$url" | grep -q "civitai.com" && [ -n "$CIVITAI_TOKEN" ]; then
    curl -L --progress-bar -o "$dest_abs" \
      "${url}?token=${CIVITAI_TOKEN}" 2>&1 || { echo "  ❌ Error"; rm -f "$dest_abs"; }
  else
    curl -L --progress-bar -o "$dest_abs" "$url" 2>&1 || { echo "  ❌ Error"; rm -f "$dest_abs"; }
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
