"""Lectura de workflows guardados y detección de modelos referenciados."""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any, Iterator

from . import config
from .manifest import Manifest

MODEL_EXTS = (".safetensors", ".ckpt", ".pt", ".pth", ".onnx", ".gguf", ".bin")

# class_type -> (carpeta de ComfyUI para GET /models/<carpeta>, o None si no hay endpoint claro)
LOADER_FOLDERS: dict[str, str | None] = {
    "CheckpointLoaderSimple": "checkpoints",
    "CheckpointLoader": "checkpoints",
    "unCLIPCheckpointLoader": "checkpoints",
    "ImageOnlyCheckpointLoader": "checkpoints",
    "UNETLoader": "diffusion_models",
    "UnetLoaderGGUF": "diffusion_models",
    "CLIPLoader": "text_encoders",
    "CLIPLoaderGGUF": "text_encoders",
    "DualCLIPLoader": "text_encoders",
    "TripleCLIPLoader": "text_encoders",
    "VAELoader": "vae",
    "LoraLoader": "loras",
    "LoraLoaderModelOnly": "loras",
    "CLIPVisionLoader": "clip_vision",
    "UpscaleModelLoader": "upscale_models",
    "ControlNetLoader": "controlnet",
    "StyleModelLoader": "style_models",
    "UltralyticsDetectorProvider": None,
    "SAMLoader": "sams",
}

_safe_cache: dict[str, Any] = {}


def resolve_workflow_path(name: str) -> Path:
    """Resuelve `name` dentro de la carpeta de workflows; rechaza escapes."""
    base = config.workflows_dir().resolve()
    n = name.strip().replace("\\", "/")
    if not n or "\x00" in n or n.startswith("/"):
        raise ValueError(f"nombre de workflow inválido: {name!r}")
    for cand in ([n] if n.endswith(".json") else [n + ".json", n]):
        p = (base / cand).resolve()
        if base in p.parents and p.is_file():
            return p
    raise FileNotFoundError(f"workflow no encontrado: {name!r} (en {base})")


def list_workflows() -> list[dict]:
    base = config.workflows_dir()
    out = []
    if not base.is_dir():
        return out
    for root, _dirs, files in os.walk(base):
        for f in files:
            if f.endswith(".json"):
                p = Path(root) / f
                st = p.stat()
                out.append({
                    "name": str(p.relative_to(base)),
                    "size": st.st_size,
                    "mtime": st.st_mtime,
                })
    out.sort(key=lambda d: d["mtime"], reverse=True)
    return out


def load_workflow(name: str) -> dict:
    p = resolve_workflow_path(name)
    return json.loads(p.read_text(encoding="utf-8"))


def is_api_format(wf: dict) -> bool:
    """Formato API: dict id -> {class_type, inputs}. UI: tiene 'nodes'."""
    if "nodes" in wf and isinstance(wf["nodes"], list):
        return False
    return bool(wf) and all(isinstance(v, dict) and "class_type" in v for v in wf.values())


def iter_ui_nodes(wf: dict) -> Iterator[tuple[str, dict]]:
    """Nodos de la raíz y de cada subgrafo: (ruta_legible, nodo)."""
    for n in wf.get("nodes", []):
        yield str(n.get("id")), n
    for sg in (wf.get("definitions") or {}).get("subgraphs", []) or []:
        for n in sg.get("nodes", []):
            yield f"{sg.get('name') or sg.get('id')}/{n.get('id')}", n


def _strings(v: Any) -> Iterator[str]:
    if isinstance(v, str):
        yield v
    elif isinstance(v, list):
        for x in v:
            yield from _strings(x)
    elif isinstance(v, dict):
        for x in v.values():
            yield from _strings(x)


def looks_like_model(s: str) -> bool:
    if not s or len(s) > 300 or "\n" in s or "://" in s:
        return False
    return s.strip().lower().endswith(MODEL_EXTS)


def referenced_models(wf: dict) -> list[dict]:
    """Modelos referenciados: [{name, class_type, node, folder, embedded:{url,directory}|None}]."""
    embedded: dict[str, dict] = {}
    for m in wf.get("models", []) or []:
        if isinstance(m, dict) and m.get("name"):
            embedded[m["name"]] = {"url": m.get("url"), "directory": m.get("directory")}
    found: dict[str, dict] = {}

    def add(value: str, cls: str, node_ref: str) -> None:
        key = value.replace("\\", "/")
        if key in found:
            found[key]["nodes"].append(node_ref)
            return
        base = key.rsplit("/", 1)[-1]
        found[key] = {
            "name": key,
            "class_type": cls,
            "nodes": [node_ref],
            "folder": LOADER_FOLDERS.get(cls),
            "embedded": embedded.get(base) or embedded.get(key),
        }

    if is_api_format(wf):
        for nid, node in wf.items():
            for v in (node.get("inputs") or {}).values():
                if isinstance(v, str) and looks_like_model(v):
                    add(v, node.get("class_type", "?"), nid)
        return list(found.values())

    for ref, node in iter_ui_nodes(wf):
        cls = node.get("type", "?")
        if node.get("mode") == 2:  # muteado: no se ejecuta, no se exige
            continue
        wv = node.get("widgets_values")
        for s in _strings(wv):
            if looks_like_model(s):
                add(s, cls, ref)
        for m in (node.get("properties") or {}).get("models", []) or []:
            if isinstance(m, dict) and m.get("name"):
                embedded.setdefault(m["name"], {"url": m.get("url"), "directory": m.get("directory")})
    # segunda pasada: los `properties.models` por nodo pueden llegar después del add
    for key, rec in found.items():
        if rec["embedded"] is None:
            rec["embedded"] = embedded.get(key.rsplit("/", 1)[-1]) or embedded.get(key)
    return list(found.values())


def index_models_fs() -> list[str]:
    """Rutas relativas (con '/') de todos los archivos bajo models/."""
    base = config.models_dir()
    out: list[str] = []
    if not base.is_dir():
        return out
    for root, _d, files in os.walk(base, followlinks=False):
        for f in files:
            if f.endswith(".part"):
                continue
            out.append(str((Path(root) / f).relative_to(base)).replace(os.sep, "/"))
    return out


def present_in_fs(name: str, index: list[str]) -> str | None:
    """Coincidencia por sufijo de ruta (insensible a mayúsculas). Devuelve la ruta hallada."""
    suf = name.replace("\\", "/").lstrip("/").casefold()
    for rel in index:
        r = rel.casefold()
        if r == suf or r.endswith("/" + suf):
            return rel
    return None


def resolve_model(rec: dict, manifest: Manifest) -> dict | None:
    """URL+destino: primero el manifiesto (por basename), luego el workflow."""
    e = manifest.by_basename(rec["name"])
    if e:
        return {"url": e.url, "dest": e.dest, "source": "manifest", "pack": e.pack}
    emb = rec.get("embedded")
    if emb and emb.get("url") and emb.get("directory"):
        base = rec["name"].replace("\\", "/").rsplit("/", 1)[-1]
        return {"url": emb["url"], "dest": f"models/{emb['directory']}/{base}", "source": "workflow", "pack": ""}
    return None
