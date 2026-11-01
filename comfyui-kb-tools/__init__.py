import subprocess
import threading
import os
from aiohttp import web
from server import PromptServer

SCRIPTS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "scripts")
WEB_DIRECTORY = "./web"

_output_buffers = {}
_output_lock = threading.Lock()

def run_script(script_path, job_id, env_extra=None):
    env = os.environ.copy()
    if env_extra:
        env.update(env_extra)
    try:
        process = subprocess.Popen(
            ["bash", script_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env=env,
            bufsize=1
        )
        with _output_lock:
            _output_buffers[job_id] = {"lines": [], "done": False}

        for line in process.stdout:
            with _output_lock:
                _output_buffers[job_id]["lines"].append(line.rstrip())

        process.wait()
        with _output_lock:
            _output_buffers[job_id]["done"] = True
            _output_buffers[job_id]["returncode"] = process.returncode
    except Exception as e:
        with _output_lock:
            _output_buffers[job_id]["lines"].append(f"ERROR: {str(e)}")
            _output_buffers[job_id]["done"] = True
            _output_buffers[job_id]["returncode"] = 1


routes = PromptServer.instance.routes

@routes.post("/rb_tools/save_all")
async def save_all(request):
    import uuid
    job_id = str(uuid.uuid4())
    threading.Thread(
        target=run_script,
        args=(os.path.join(SCRIPTS_DIR, "save_all.sh"), job_id),
        daemon=True
    ).start()
    return web.json_response({"job_id": job_id})

@routes.post("/rb_tools/update_nodes")
async def update_nodes(request):
    import uuid
    job_id = str(uuid.uuid4())
    threading.Thread(
        target=run_script,
        args=(os.path.join(SCRIPTS_DIR, "update_nodes.sh"), job_id),
        daemon=True
    ).start()
    return web.json_response({"job_id": job_id})

@routes.get("/rb_tools/models_list")
async def models_list(request):
    """Lee models_to_download.txt de R2 y devuelve packs parseados."""
    import subprocess, tempfile, os
    tmp = tempfile.mkdtemp()
    try:
        subprocess.run(
            ["rclone", "copy", "r2:comfy-models/config/models_to_download.txt", tmp],
            capture_output=True, text=True, timeout=30
        )
        txt_path = os.path.join(tmp, "models_to_download.txt")
        if not os.path.exists(txt_path):
            return web.json_response({"packs": [], "error": "models_to_download.txt no encontrado en R2"})

        packs = []
        current_pack = None
        with open(txt_path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith("PACK:"):
                    current_pack = {"name": line[5:].strip(), "files": []}
                    packs.append(current_pack)
                elif current_pack is not None:
                    parts = line.split()
                    if len(parts) >= 2:
                        current_pack["files"].append({
                            "url": parts[0],
                            "dest": parts[1],
                            "name": os.path.basename(parts[1])
                        })

        return web.json_response({"packs": packs})
    except Exception as e:
        return web.json_response({"packs": [], "error": str(e)})
    finally:
        import shutil
        shutil.rmtree(tmp, ignore_errors=True)

@routes.post("/rb_tools/download_models")
async def download_models(request):
    import uuid
    data = await request.json()
    packs = data.get("packs", "ALL")
    if isinstance(packs, list):
        packs = "|".join(packs)
    job_id = str(uuid.uuid4())
    threading.Thread(
        target=run_script,
        args=(os.path.join(SCRIPTS_DIR, "download_models.sh"), job_id, {"SELECTED_PACKS": str(packs)}),
        daemon=True
    ).start()
    return web.json_response({"job_id": job_id})

@routes.post("/rb_tools/cancel_download")
async def cancel_download(request):
    """Mata todos los procesos de descarga y limpia archivos parciales."""
    import subprocess
    try:
        # Matar procesos listados en pids file
        pids_file = "/tmp/kb_models/download_pids.txt"
        partial_file = "/tmp/kb_models/partial_files.txt"

        killed = 0
        if os.path.exists(pids_file):
            with open(pids_file) as f:
                for pid in f.read().splitlines():
                    try:
                        subprocess.run(["kill", "-9", pid.strip()], capture_output=True)
                        killed += 1
                    except:
                        pass

        # Borrar archivos parciales
        cleaned = 0
        if os.path.exists(partial_file):
            with open(partial_file) as f:
                for path in f.read().splitlines():
                    path = path.strip()
                    if path and os.path.exists(path):
                        os.remove(path)
                        cleaned += 1

        # Limpiar tmp
        subprocess.run(["rm", "-f", pids_file, partial_file], capture_output=True)

        return web.json_response({"ok": True, "killed": killed, "cleaned": cleaned})
    except Exception as e:
        return web.json_response({"ok": False, "error": str(e)})

@routes.post("/rb_tools/sync_input")
async def sync_input(request):
    import uuid
    data = await request.json()
    mode = data.get("mode", "upload")
    job_id = str(uuid.uuid4())
    threading.Thread(
        target=run_script,
        args=(os.path.join(SCRIPTS_DIR, "sync_input.sh"), job_id, {"MODE": mode}),
        daemon=True
    ).start()
    return web.json_response({"job_id": job_id})

@routes.get("/rb_tools/models_txt")
async def get_models_txt(request):
    """Lee models_to_download.txt de R2 y lo devuelve como texto."""
    import subprocess, tempfile, os
    tmp = tempfile.mkdtemp()
    try:
        subprocess.run(
            ["rclone", "copy", "r2:comfy-models/config/models_to_download.txt", tmp],
            capture_output=True, text=True, timeout=30
        )
        txt_path = os.path.join(tmp, "models_to_download.txt")
        if not os.path.exists(txt_path):
            return web.json_response({"content": "", "error": "models_to_download.txt no encontrado en R2"})
        with open(txt_path) as f:
            content = f.read()
        return web.json_response({"content": content})
    except Exception as e:
        return web.json_response({"content": "", "error": str(e)})
    finally:
        import shutil
        shutil.rmtree(tmp, ignore_errors=True)

@routes.post("/rb_tools/save_models_txt")
async def save_models_txt(request):
    """Guarda models_to_download.txt en R2."""
    import subprocess, tempfile, os
    data = await request.json()
    content = data.get("content", "")
    tmp = tempfile.mkdtemp()
    try:
        txt_path = os.path.join(tmp, "models_to_download.txt")
        with open(txt_path, "w") as f:
            f.write(content)
        result = subprocess.run(
            ["rclone", "copy", txt_path, "r2:comfy-models/config/"],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode != 0:
            return web.json_response({"ok": False, "error": result.stderr})
        return web.json_response({"ok": True})
    except Exception as e:
        return web.json_response({"ok": False, "error": str(e)})
    finally:
        import shutil
        shutil.rmtree(tmp, ignore_errors=True)

@routes.get("/rb_tools/output/{job_id}")
async def get_output(request):
    job_id = request.match_info["job_id"]
    with _output_lock:
        buf = _output_buffers.get(job_id)
        if not buf:
            return web.json_response({"error": "job not found"}, status=404)
        return web.json_response({
            "lines": buf["lines"],
            "done": buf["done"],
            "returncode": buf.get("returncode")
        })


NODE_CLASS_MAPPINGS = {}
NODE_DISPLAY_NAME_MAPPINGS = {}

__all__ = ["NODE_CLASS_MAPPINGS", "NODE_DISPLAY_NAME_MAPPINGS", "WEB_DIRECTORY"]
