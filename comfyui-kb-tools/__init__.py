import subprocess
import threading
import os
from aiohttp import web
from server import PromptServer

# Rutas de los scripts
SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
UPDATE_NODES_SCRIPT = os.path.join(SCRIPTS_DIR, "scripts", "update_nodes.sh")
SYNC_MODELS_SCRIPT  = os.path.join(SCRIPTS_DIR, "scripts", "sync_models.sh")

# Buffer de output por proceso
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

@routes.post("/kb_tools/update_nodes")
async def update_nodes(request):
    import uuid
    job_id = str(uuid.uuid4())
    thread = threading.Thread(
        target=run_script,
        args=(UPDATE_NODES_SCRIPT, job_id),
        daemon=True
    )
    thread.start()
    return web.json_response({"job_id": job_id})

SAVE_ALL_SCRIPT = os.path.join(SCRIPTS_DIR, "scripts", "save_all.sh")

@routes.post("/kb_tools/save_all")
async def save_all(request):
    import uuid
    job_id = str(uuid.uuid4())
    thread = threading.Thread(
        target=run_script,
        args=(SAVE_ALL_SCRIPT, job_id),
        daemon=True
    )
    thread.start()
    return web.json_response({"job_id": job_id})

@routes.post("/kb_tools/sync_models")
async def sync_models(request):
    import uuid
    data = await request.json()
    mode = data.get("mode", "download")  # download | upload | both | dryrun
    job_id = str(uuid.uuid4())
    thread = threading.Thread(
        target=run_script,
        args=(SYNC_MODELS_SCRIPT, job_id, {"SYNC_MODE": mode}),
        daemon=True
    )
    thread.start()
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
