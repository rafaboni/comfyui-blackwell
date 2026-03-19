#!/bin/bash
# download_models.sh — descarga paralela con progreso real usando Python requests

COMFY_DIR="/workspace/ComfyUI"
R2_BUCKET="r2:comfy-models"
TMP_DIR="/tmp/kb_models"

mkdir -p "$TMP_DIR"

echo "========================================="
echo "  RB Tools - Descargar Modelos"
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

echo "→ Leyendo config desde R2..."
rclone copy "$R2_BUCKET/config/tokens.txt" "$TMP_DIR/" --fast-list 2>/dev/null || true
rclone copy "$R2_BUCKET/config/models_to_download.txt" "$TMP_DIR/" --fast-list

if [ ! -f "$TMP_DIR/models_to_download.txt" ]; then
  echo "ERROR: No se encontró models_to_download.txt en R2."
  exit 1
fi

SELECTED_PACKS="${SELECTED_PACKS}" python3 << 'PYEOF'
import os, sys, threading, time, requests

COMFY_DIR = "/workspace/ComfyUI"
TMP_DIR = "/tmp/kb_models"
SELECTED = os.environ.get("SELECTED_PACKS", "ALL")
PIDS_FILE = f"{TMP_DIR}/download_pids.txt"
PARTIAL_FILE = f"{TMP_DIR}/partial_files.txt"

open(PIDS_FILE, 'w').close()
open(PARTIAL_FILE, 'w').close()

# Leer tokens
hf_token = civitai_token = ""
if os.path.exists(f"{TMP_DIR}/tokens.txt"):
    for line in open(f"{TMP_DIR}/tokens.txt"):
        if line.startswith("HF_TOKEN="):
            hf_token = line.split("=",1)[1].strip()
        elif line.startswith("CIVITAI_TOKEN="):
            civitai_token = line.split("=",1)[1].strip()

# Parsear packs
files = []
in_pack = False
for line in open(f"{TMP_DIR}/models_to_download.txt"):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    if line.startswith("PACK:"):
        pack = line[5:].strip()
        in_pack = (SELECTED == "ALL" or pack in SELECTED)
        if in_pack:
            print(f"📦 Pack: {pack}", flush=True)
        continue
    if in_pack:
        parts = line.split()
        if len(parts) >= 2:
            url, dest_rel = parts[0], parts[1]
            dest = os.path.join(COMFY_DIR, dest_rel)
            fname = os.path.basename(dest)
            files.append((url, dest, fname))

if not files:
    print("No hay archivos para descargar.")
    sys.exit(0)

print(f"\n⏳ Descargando {len(files)} archivos en paralelo...", flush=True)

def download_file(url, dest, fname):
    # Build headers and URL
    headers = {}
    final_url = url
    if "huggingface.co" in url and hf_token:
        headers["Authorization"] = f"Bearer {hf_token}"
    elif "civitai.com" in url and civitai_token:
        final_url = f"{url}?token={civitai_token}"

    try:
        # Stream request — get content-length immediately
        resp = requests.get(final_url, headers=headers, stream=True, timeout=30)
        resp.raise_for_status()
        total = int(resp.headers.get("content-length", 0))

        # Check if already complete
        if os.path.exists(dest) and total > 0:
            existing = os.path.getsize(dest)
            if existing >= total:
                print(f"PROGRESS:{fname}:100:0", flush=True)
                print(f"  ✓ Ya existe: {fname}", flush=True)
                return
            else:
                print(f"  ⚠ Incompleto, re-descargando: {fname}", flush=True)
                os.remove(dest)

        os.makedirs(os.path.dirname(dest), exist_ok=True)

        with open(PARTIAL_FILE, 'a') as f:
            f.write(dest + "\n")

        start = time.time()
        downloaded = 0
        chunk_size = 1024 * 1024  # 1MB chunks

        with open(dest, 'wb') as f:
            for chunk in resp.iter_content(chunk_size=chunk_size):
                if chunk:
                    f.write(chunk)
                    downloaded += len(chunk)
                    if total > 0:
                        pct = min(99, int(downloaded * 100 / total))
                        elapsed = time.time() - start
                        speed = round(downloaded / 1048576 / elapsed, 1) if elapsed > 0 else 0
                        print(f"PROGRESS:{fname}:{pct}:{speed}", flush=True)

        elapsed = time.time() - start
        size_mb = round(os.path.getsize(dest) / 1048576, 1)
        avg = round(size_mb / elapsed, 1) if elapsed > 0 else 0
        print(f"PROGRESS:{fname}:100:{avg}", flush=True)
        print(f"  ✅ {fname} — {size_mb}MB @ {avg} MB/s", flush=True)

    except Exception as e:
        print(f"PROGRESS:{fname}:ERROR:0", flush=True)
        print(f"  ❌ Error: {fname} — {e}", flush=True)
        if os.path.exists(dest):
            os.remove(dest)

    # Limpiar partial
    try:
        lines = open(PARTIAL_FILE).readlines()
        open(PARTIAL_FILE, 'w').writelines(l for l in lines if dest not in l)
    except:
        pass

threads = []
for url, dest, fname in files:
    t = threading.Thread(target=download_file, args=(url, dest, fname), daemon=True)
    t.start()
    threads.append(t)
    # Registrar thread id como PID aproximado
    with open(PIDS_FILE, 'a') as f:
        f.write(str(t.ident or 0) + "\n")

for t in threads:
    t.join()

print("\n✅ Descarga completa.", flush=True)
PYEOF
