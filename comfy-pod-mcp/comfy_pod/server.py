"""Servidor MCP comfy-pod (SDK oficial `mcp` 2.x: MCPServer, antes FastMCP)."""
from __future__ import annotations

import argparse
import asyncio
import base64
import os
import sys
import uuid
from pathlib import Path
from urllib.parse import urlencode

from mcp.server.mcpserver import MCPServer
from mcp.server.transport_security import TransportSecuritySettings

from . import __version__, config
from .auth import BearerAuth
from .comfy import ComfyClient, ComfyError
from .convert import ConversionError, convert_ui_to_api
from .downloads import MANAGER
from .manifest import Entry, load_manifest
from .params import ParamError, apply_params, editable_inputs
from . import workflows as wfm

IMG_EXTS = (".png", ".jpg", ".jpeg", ".webp", ".gif")
B64_MAX = 2 * 1024 * 1024

mcp = MCPServer(
    "comfy-pod",
    instructions=("Controla el ComfyUI de este pod: listar/describir workflows, descargar modelos faltantes, "
                  "ejecutar workflows y recoger resultados."),
)


def _client() -> ComfyClient:
    return ComfyClient()


# ---------------------------------------------------------------- health
@mcp.tool()
async def health() -> dict:
    """Estado de ComfyUI (alcanzable, versión) y GPU/VRAM."""
    try:
        s = await _client().get_json("/system_stats")
    except ComfyError as e:
        return {"comfyui_reachable": False, "error": str(e), "comfy_pod_version": __version__}
    sysinfo = s.get("system", {})
    return {
        "comfyui_reachable": True,
        "comfyui_version": sysinfo.get("comfyui_version"),
        "python_version": sysinfo.get("python_version"),
        "pytorch_version": sysinfo.get("pytorch_version"),
        "gpus": [{"name": d.get("name"), "type": d.get("type"), "vram_total": d.get("vram_total"),
                  "vram_free": d.get("vram_free")} for d in s.get("devices", [])],
        "comfy_pod_version": __version__,
    }


# ---------------------------------------------------------------- workflows
@mcp.tool()
async def list_workflows() -> list[dict]:
    """Workflows guardados por la UI (nombre, tamaño en bytes, mtime epoch), más recientes primero."""
    return await asyncio.to_thread(wfm.list_workflows)


async def _models_report(wf: dict) -> dict:
    manifest = await asyncio.to_thread(load_manifest)
    index = await asyncio.to_thread(wfm.index_models_fs)
    recs = wfm.referenced_models(wf)
    api_lists: dict[str, set[str]] = {}
    for folder in {r["folder"] for r in recs if r["folder"]}:
        try:
            names = await _client().get_json(f"/models/{folder}")
            api_lists[folder] = {n.replace("\\", "/") for n in names}
        except ComfyError:
            pass
    models = []
    for r in recs:
        fs_hit = wfm.present_in_fs(r["name"], index)
        api_hit = r["folder"] in api_lists and r["name"] in api_lists[r["folder"]]
        res = wfm.resolve_model(r, manifest)
        models.append({
            "name": r["name"], "class_type": r["class_type"], "nodes": r["nodes"],
            "present": bool(fs_hit or api_hit),
            "found_at": ("models/" + fs_hit) if fs_hit else None,
            "resolution": res if res else "sin URL en el manifiesto",
        })
    return {"models": models, "manifest_source": manifest.source, "manifest_warnings": manifest.warnings}


async def _api_for(wf: dict) -> tuple[dict, list[str]]:
    if wfm.is_api_format(wf):
        return wf, []
    oi = await _client().get_json("/object_info")
    return await asyncio.to_thread(convert_ui_to_api, wf, oi)


@mcp.tool()
async def describe_workflow(name: str) -> dict:
    """Entradas editables (prompts, seeds, imagen, steps, cfg, width/height, frames) por nodo
    (id+título+clase) y modelos referenciados (presente/faltante + URL/destino resueltos)."""
    wf = await asyncio.to_thread(wfm.load_workflow, name)
    out: dict = {"name": name, "format": "api" if wfm.is_api_format(wf) else "ui"}
    try:
        api, warns = await _api_for(wf)
        out["editable_inputs"] = editable_inputs(api)
        out["conversion_warnings"] = warns
    except (ComfyError, ConversionError) as e:
        out["editable_inputs"] = None
        out["editable_inputs_error"] = f"no se pudo convertir a API ({e}); los modelos sí se listan"
    out.update(await _models_report(wf))
    return out


@mcp.tool()
async def missing_models(name: str) -> dict:
    """Solo los modelos que faltan, con URL/destino del manifiesto o 'sin URL en el manifiesto'."""
    wf = await asyncio.to_thread(wfm.load_workflow, name)
    rep = await _models_report(wf)
    miss = [m for m in rep["models"] if not m["present"]]
    return {"name": name, "missing": miss, "missing_count": len(miss),
            "manifest_source": rep["manifest_source"], "manifest_warnings": rep["manifest_warnings"]}


# ---------------------------------------------------------------- descargas
@mcp.tool()
async def download_models(name: str | None = None, files: list[str] | None = None,
                          pack: str | None = None) -> dict:
    """Inicia descargas en segundo plano (máx. 3 a la vez) y devuelve job_id.
    name: faltantes de ese workflow con URL resuelta. files: basenames, destinos 'models/...' o 'URL DESTINO'
    (se buscan en el manifiesto). pack: todos los archivos del PACK (sin distinguir mayúsculas)."""
    if not (name or files or pack):
        raise ValueError("indica name, files o pack")
    manifest = await asyncio.to_thread(load_manifest)
    chosen: dict[str, Entry] = {}
    unresolved: list[str] = []
    if name:
        rep = await _models_report(await asyncio.to_thread(wfm.load_workflow, name))
        for m in rep["models"]:
            if m["present"]:
                continue
            res = m["resolution"]
            if isinstance(res, dict):
                chosen[res["dest"]] = Entry(res["url"], res["dest"], res.get("pack", ""))
            else:
                unresolved.append(m["name"])
    for f in files or []:
        f = f.strip()
        parts = f.split(None, 1)
        e: Entry | None = None
        if len(parts) == 2 and parts[0].startswith("https://"):
            e = Entry(parts[0], parts[1].strip())
        else:
            e = manifest.by_dest(f) or manifest.by_basename(f)
        if e:
            chosen[e.dest] = e
        else:
            unresolved.append(f)
    if pack:
        hits = [e for p, es in manifest.packs().items() if p.casefold() == pack.strip().casefold() for e in es]
        if not hits:
            unresolved.append(f"PACK: {pack}")
        for e in hits:
            chosen[e.dest] = e
    if not chosen:
        return {"job_id": None, "started": 0, "unresolved": unresolved,
                "note": "nada que descargar"}
    job_id = MANAGER.start(list(chosen.values()))
    return {"job_id": job_id, "started": len(chosen), "unresolved": unresolved,
            "files": [{"dest": e.dest} for e in chosen.values()]}


@mcp.tool()
async def download_status(job_id: str) -> dict:
    """Estado por archivo: bytes, total, state (queued/downloading/done/skipped/error), error."""
    s = MANAGER.status(job_id)
    if s is None:
        raise ValueError(f"job_id desconocido: {job_id}")
    return s


# ---------------------------------------------------------------- ejecución
@mcp.tool()
async def run_workflow(name: str, params: dict | None = None) -> dict:
    """Convierte (UI->API si hace falta), aplica params y encola en ComfyUI. Devuelve prompt_id.
    params: {"<node_id>.<input>": valor} y atajos "prompt", "negative", "seed" (-1 = aleatoria), "image"
    (archivo en input/, URL http(s) o base64)."""
    wf = await asyncio.to_thread(wfm.load_workflow, name)
    client = _client()
    try:
        api, warns = await _api_for(wf)
        api = {k: {**v, "inputs": dict(v.get("inputs", {}))} for k, v in api.items()}  # copia
        applied = await apply_params(api, params or {}, client)
    except (ConversionError, ParamError, ValueError) as e:
        raise ValueError(str(e)) from e
    try:
        res = await client.post_prompt(api, uuid.uuid4().hex)
    except ComfyError as e:
        raise ValueError(f"{e}: {e.detail}") from e
    return {"prompt_id": res.get("prompt_id"), "number": res.get("number"),
            "node_errors": res.get("node_errors") or {}, "applied": applied, "warnings": warns}


@mcp.tool()
async def get_job(prompt_id: str) -> dict:
    """Estado del trabajo: historial (success/error + errores de nodos) o posición en cola."""
    c = _client()
    hist = await c.get_json(f"/history/{prompt_id}")
    if prompt_id in hist:
        h = hist[prompt_id]
        st = h.get("status", {})
        errors = [m[1] for m in st.get("messages", []) if m and m[0] == "execution_error"]
        state = "error" if st.get("status_str") == "error" else ("success" if st.get("completed") else "unknown")
        return {"prompt_id": prompt_id, "state": state, "status": st.get("status_str"),
                "completed": st.get("completed"), "execution_errors": errors,
                "output_nodes": list((h.get("outputs") or {}).keys())}
    q = await c.get_json("/queue")
    for i, item in enumerate(q.get("queue_running", [])):
        if item[1] == prompt_id:
            return {"prompt_id": prompt_id, "state": "running", "queue_position": 0}
    for i, item in enumerate(q.get("queue_pending", [])):
        if item[1] == prompt_id:
            return {"prompt_id": prompt_id, "state": "pending",
                    "queue_position": len(q.get("queue_running", [])) + i + 1}
    return {"prompt_id": prompt_id, "state": "not_found",
            "note": "ni en historial ni en cola (id inexistente o historial limpiado)"}


def _local_path(type_: str, sub: str, fn: str) -> Path | None:
    root = {"output": "output", "temp": "temp", "input": "input"}.get(type_)
    if not root:
        return None
    base = (config.comfy_dir() / root).resolve()
    p = (base / sub / fn).resolve()
    return p if base in p.parents and p.is_file() else None


@mcp.tool()
async def get_outputs(prompt_id: str, include_base64: bool = False) -> dict:
    """Archivos de salida (filename, subfolder, type, size) y URL relativa `/view?...` del proxy de ComfyUI
    (https://<podid>-8188.proxy.runpod.net + url). Con include_base64, imágenes < 2 MB en base64."""
    c = _client()
    hist = await c.get_json(f"/history/{prompt_id}")
    if prompt_id not in hist:
        return {"prompt_id": prompt_id, "files": [], "note": "aún sin historial (¿en cola o sin terminar?)"}
    files = []
    for node_id, out in (hist[prompt_id].get("outputs") or {}).items():
        for kind, items in out.items():
            if not isinstance(items, list):
                continue
            for it in items:
                if not (isinstance(it, dict) and it.get("filename")):
                    continue
                fn, sub, typ = it["filename"], it.get("subfolder", ""), it.get("type", "output")
                lp = _local_path(typ, sub, fn)
                size = lp.stat().st_size if lp else await c.view_size(fn, sub, typ)
                rec = {"node_id": node_id, "kind": kind, "filename": fn, "subfolder": sub, "type": typ,
                       "size": size, "url": "/view?" + urlencode({"filename": fn, "subfolder": sub, "type": typ})}
                if include_base64 and fn.lower().endswith(IMG_EXTS) and size is not None and size < B64_MAX:
                    data = lp.read_bytes() if lp else await c.view(fn, sub, typ)
                    rec["base64"] = base64.b64encode(data).decode()
                files.append(rec)
    return {"prompt_id": prompt_id, "files": files}


# ---------------------------------------------------------------- arranque
def build_http_app(token: str):
    inner = mcp.streamable_http_app(
        host="0.0.0.0", streamable_http_path="/mcp",
        transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False),
    )
    return BearerAuth(inner, token), inner


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="comfy-pod-mcp")
    ap.add_argument("--stdio", action="store_true", help="transporte stdio (pruebas locales; no pide MCP_TOKEN)")
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=int(os.environ.get("MCP_PORT", "8190")))
    a = ap.parse_args(argv)
    if a.stdio:
        mcp.run("stdio")
        return 0
    token = os.environ.get("MCP_TOKEN", "")
    if not token:
        print("ERROR: MCP_TOKEN no está definido. Exporta MCP_TOKEN=<secreto largo> y reintenta; "
              "sin token el servidor no arranca.", file=sys.stderr)
        return 2
    import uvicorn
    app, _ = build_http_app(token)
    uvicorn.run(app, host=a.host, port=a.port, log_level="info")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
