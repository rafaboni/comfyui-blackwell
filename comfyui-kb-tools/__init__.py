import subprocess
import threading
import os
from aiohttp import web
from server import PromptServer

SCRIPTS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "scripts")

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

@routes.post("/kb_tools/save_all")
async def save_all(request):
    import uuid
    job_id = str(uuid.uuid4())
    threading.Thread(
        target=run_script,
        args=(os.path.join(SCRIPTS_DIR, "save_all.sh"), job_id),
        daemon=True
    ).start()
    return web.json_response({"job_id": job_id})

@routes.post("/kb_tools/update_nodes")
async def update_nodes(request):
    import uuid
    job_id = str(uuid.uuid4())
    threading.Thread(
        target=run_script,
        args=(os.path.join(SCRIPTS_DIR, "save_all.sh"), job_id),
        daemon=True
    ).start()
    return web.json_response({"job_id": job_id})

@routes.get("/kb_tools/models_list")
async def models_list(request):
    """Lee models_to_download.txt de R2 y devuelve la lista parseada."""
    import subprocess, tempfile, os
    tmp = tempfile.mkdtemp()
    try:
        result = subprocess.run(
            ["rclone", "copy", "r2:comfy-models/config/models_to_download.txt", tmp],
            capture_output=True, text=True, timeout=30
        )
        txt_path = os.path.join(tmp, "models_to_download.txt")
        if not os.path.exists(txt_path):
            return web.json_response({"models": [], "error": "models_to_download.txt no encontrado en R2"})

        models = []
        with open(txt_path) as f:
            for i, line in enumerate(f):
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.split()
                if len(parts) >= 2:
                    url, dest = parts[0], parts[1]
                    name = os.path.basename(dest)
                    models.append({"index": i, "name": name, "url": url, "dest": dest})

        return web.json_response({"models": models})
    except Exception as e:
        return web.json_response({"models": [], "error": str(e)})
    finally:
        import shutil
        shutil.rmtree(tmp, ignore_errors=True)

@routes.post("/kb_tools/download_models")
async def download_models(request):
    import uuid
    data = await request.json()
    indices = data.get("indices", "ALL")
    if isinstance(indices, list):
        indices = ",".join(str(i) for i in indices)
    job_id = str(uuid.uuid4())
    threading.Thread(
        target=run_script,
        args=(os.path.join(SCRIPTS_DIR, "download_models.sh"), job_id, {"SELECTED_MODELS": str(indices)}),
        daemon=True
    ).start()
    return web.json_response({"job_id": job_id})

@routes.post("/kb_tools/sync_input")
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

@routes.get("/kb_tools/output/{job_id}")
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
WEB_DIRECTORY = "./web"

__all__ = ["NODE_CLASS_MAPPINGS", "NODE_DISPLAY_NAME_MAPPINGS", "WEB_DIRECTORY"]
