#!/bin/bash
# download_models.sh — usa Python para descargas paralelas robustas

COMFY_DIR="/workspace/ComfyUI"
R2_BUCKET="r2:comfy-models"
TMP_DIR="/tmp/kb_models"

mkdir -p "$TMP_DIR"

echo "========================================="
echo "  RB Tools - Descargar Modelos"
echo "========================================="

# Configurar rclone
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

# Bajar config
echo "→ Leyendo config desde R2..."
rclone copy "$R2_BUCKET/config/tokens.txt" "$TMP_DIR/" --fast-list 2>/dev/null || true
rclone copy "$R2_BUCKET/config/models_to_download.txt" "$TMP_DIR/" --fast-list

if [ ! -f "$TMP_DIR/models_to_download.txt" ]; then
  echo "ERROR: No se encontró models_to_download.txt en R2."
  exit 1
fi

# Delegar todo a Python
python3 << PYEOF
import os, sys, threading, subprocess, time

COMFY_DIR = "$COMFY_DIR"
TMP_DIR = "$TMP_DIR"
SELECTED = os.environ.get("SELECTED_PACKS", "ALL")

# Leer tokens
hf_token = ""
civitai_token = ""
tokens_file = f"{TMP_DIR}/tokens.txt"
if os.path.exists(tokens_file):
    for line in open(tokens_file):
        line = line.strip()
        if line.startswith("HF_TOKEN="):
            hf_token = line.split("=", 1)[1]
        elif line.startswith("CIVITAI_TOKEN="):
            civitai_token = line.split("=", 1)[1]

# Parsear packs
files = []  # (url, dest_abs, fname)
current_pack = None
in_pack = False

for line in open(f"{TMP_DIR}/models_to_download.txt"):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    if line.startswith("PACK:"):
        current_pack = line[5:].strip()
        in_pack = (SELECTED == "ALL" or current_pack in SELECTED)
        if in_pack:
            print(f"📦 Pack: {current_pack}", flush=True)
        continue
    if in_pack:
        parts = line.split()
        if len(parts) >= 2:
            url, dest_rel = parts[0], parts[1]
            dest_abs = os.path.join(COMFY_DIR, dest_rel)
            fname = os.path.basename(dest_abs)
            files.append((url, dest_abs, fname))

if not files:
    print("No hay archivos para descargar.")
    sys.exit(0)

print(f"\n⏳ Descargando {len(files)} archivos en paralelo...", flush=True)

# Guardar PIDs para cancel
pids_file = f"{TMP_DIR}/download_pids.txt"
partial_file = f"{TMP_DIR}/partial_files.txt"
open(pids_file, 'w').close()
open(partial_file, 'w').close()

def get_remote_size(url, headers):
    cmd = ["curl", "-sI"] + headers + [url]
    try:
        out = subprocess.check_output(cmd, timeout=15).decode()
        for line in out.splitlines():
            if line.lower().startswith("content-length:"):
                return int(line.split(":", 1)[1].strip())
    except:
        pass
    return 0

def download_file(url, dest, fname):
    # Build headers
    headers = []
    final_url = url
    if "huggingface.co" in url and hf_token:
        headers = ["-H", f"Authorization: Bearer {hf_token}"]
    elif "civitai.com" in url and civitai_token:
        final_url = f"{url}?token={civitai_token}"

    total = get_remote_size(final_url, headers)

    # Check if already complete
    if os.path.exists(dest) and total > 0:
        existing = os.path.getsize(dest)
        if existing >= total:
            print(f"PROGRESS:{fname}:100:0", flush=True)
            print(f"  ✓ Ya existe: {fname}", flush=True)
            return
        else:
            print(f"  ⚠ Incompleto ({existing}/{total} bytes), re-descargando: {fname}", flush=True)
            os.remove(dest)

    os.makedirs(os.path.dirname(dest), exist_ok=True)

    with open(partial_file, 'a') as f:
        f.write(dest + "\n")

    cmd = ["curl", "-L", "--no-progress-meter"] + headers + ["-o", dest, final_url]
    proc = subprocess.Popen(cmd)

    with open(pids_file, 'a') as f:
        f.write(str(proc.pid) + "\n")

    start = time.time()
    while proc.poll() is None:
        time.sleep(1)
        if os.path.exists(dest) and total > 0:
            current = os.path.getsize(dest)
            pct = min(99, int(current * 100 / total))
            elapsed = time.time() - start
            speed = round(current / 1048576 / elapsed, 1) if elapsed > 0 else 0
            print(f"PROGRESS:{fname}:{pct}:{speed}", flush=True)

    code = proc.returncode
    if code != 0 or not os.path.exists(dest) or os.path.getsize(dest) == 0:
        print(f"PROGRESS:{fname}:ERROR:0", flush=True)
        print(f"  ❌ Error: {fname}", flush=True)
        if os.path.exists(dest):
            os.remove(dest)
    else:
        elapsed = time.time() - start
        size_mb = round(os.path.getsize(dest) / 1048576, 1)
        avg = round(size_mb / elapsed, 1) if elapsed > 0 else 0
        print(f"PROGRESS:{fname}:100:{avg}", flush=True)
        print(f"  ✅ {fname} — {size_mb}MB @ {avg} MB/s", flush=True)

    # Limpiar partial
    try:
        lines = open(partial_file).readlines()
        open(partial_file, 'w').writelines(l for l in lines if dest not in l)
    except:
        pass

threads = []
for url, dest, fname in files:
    t = threading.Thread(target=download_file, args=(url, dest, fname))
    t.start()
    threads.append(t)

for t in threads:
    t.join()

print("\n✅ Descarga completa.", flush=True)
PYEOF
