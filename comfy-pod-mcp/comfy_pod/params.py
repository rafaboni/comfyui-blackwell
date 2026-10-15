"""Entradas editables de un prompt API y aplicación de parámetros."""
from __future__ import annotations

import base64
import binascii
import ipaddress
import random
import re
import socket
from pathlib import Path
from urllib.parse import urlparse

import httpx

from . import config

KIND = {
    "seed": "seed", "noise_seed": "seed", "steps": "steps", "cfg": "cfg", "width": "width",
    "height": "height", "length": "length", "frames": "length", "num_frames": "length",
    "video_frames": "length", "frame_count": "length", "batch_size": "batch_size", "denoise": "denoise",
}
TEXT_NAMES = {"text", "prompt", "positive_prompt", "negative_prompt", "string"}
SKIP_TEXT_CLASSES = ("Preview", "Show", "SaveText", "Note")
MAX_TEXT = 2000
MAX_UPLOAD = 50 * 1024 * 1024


def is_link(v) -> bool:
    return isinstance(v, list) and len(v) == 2 and isinstance(v[0], str) and isinstance(v[1], int)


def _is_text_input(cls: str, name: str, v) -> bool:
    return name in TEXT_NAMES and isinstance(v, str) and not cls.startswith(SKIP_TEXT_CLASSES)


def _roles(api: dict) -> dict[str, str]:
    """nodo de texto -> 'positive'/'negative' rastreando hacia atrás desde sampler.positive/negative."""
    roles: dict[str, str] = {}
    for node in api.values():
        for role in ("positive", "negative"):
            v = node.get("inputs", {}).get(role)
            if not is_link(v):
                continue
            stack, seen = [v[0]], set()
            while stack:
                nid = stack.pop()
                if nid in seen or nid not in api:
                    continue
                seen.add(nid)
                n = api[nid]
                if any(_is_text_input(n["class_type"], k, x) for k, x in n.get("inputs", {}).items()):
                    roles.setdefault(nid, role)
                    continue
                stack.extend(x[0] for x in n.get("inputs", {}).values() if is_link(x))
    for nid, n in api.items():  # respaldo por título
        if nid in roles:
            continue
        title = (n.get("_meta", {}).get("title") or "").lower()
        if any(_is_text_input(n["class_type"], k, x) for k, x in n.get("inputs", {}).items()):
            if "negative" in title or "negativ" in title:
                roles[nid] = "negative"
            elif "positive" in title or "positiv" in title:
                roles[nid] = "positive"
    return roles


def _sort_key(nid: str):
    return [int(p) if p.isdigit() else 0 for p in re.split(r"[:]", nid)]


def editable_inputs(api: dict) -> list[dict]:
    roles = _roles(api)
    out = []
    for nid in sorted(api, key=_sort_key):
        n = api[nid]
        cls = n["class_type"]
        title = n.get("_meta", {}).get("title", cls)
        for name, v in n.get("inputs", {}).items():
            if is_link(v):
                continue
            kind = None
            if _is_text_input(cls, name, v):
                kind = "prompt"
            elif name == "image" and cls.startswith("LoadImage") and isinstance(v, str):
                kind = "image"
            elif name in KIND and isinstance(v, (int, float)) and not isinstance(v, bool):
                kind = KIND[name]
            if kind is None:
                continue
            item = {"node_id": nid, "title": title, "class_type": cls, "input": name,
                    "key": f"{nid}.{name}", "kind": kind,
                    "value": v if not isinstance(v, str) else v[:MAX_TEXT]}
            if kind == "prompt" and nid in roles:
                item["role"] = roles[nid]
            out.append(item)
    return out


# ---- imágenes -------------------------------------------------------------------
def _sniff_ext(data: bytes) -> str:
    if data.startswith(b"\x89PNG"):
        return ".png"
    if data.startswith(b"\xff\xd8"):
        return ".jpg"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return ".webp"
    if data[:3] == b"GIF":
        return ".gif"
    return ".png"


def _check_public_url(url: str) -> None:
    u = urlparse(url)
    if u.scheme not in ("http", "https") or not u.hostname:
        raise ValueError("URL de imagen inválida (solo http/https)")
    try:
        infos = socket.getaddrinfo(u.hostname, u.port or (443 if u.scheme == "https" else 80))
    except socket.gaierror as e:
        raise ValueError(f"no se resuelve el host de la imagen: {u.hostname}") from e
    for info in infos:
        ip = ipaddress.ip_address(info[4][0])
        if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved:
            raise ValueError("la URL de la imagen apunta a una red privada; no permitido")


async def image_to_input_name(value: str, client, transport=None) -> str:
    """Devuelve el nombre para LoadImage.image. Acepta: archivo ya en input/, URL http(s), base64/data URI."""
    import hashlib
    v = value.strip()
    if v.startswith(("http://", "https://")):
        _check_public_url(v)
        async with httpx.AsyncClient(timeout=60, follow_redirects=False, transport=transport) as c:
            r = await c.get(v)
        if r.status_code != 200:
            raise ValueError(f"no se pudo bajar la imagen (HTTP {r.status_code})")
        data = r.content
    elif v.startswith("data:") or (len(v) > 256 and re.fullmatch(r"[A-Za-z0-9+/=\s]+", v)):
        b64 = v.split(",", 1)[1] if v.startswith("data:") else v
        try:
            data = base64.b64decode(b64, validate=False)
        except (binascii.Error, ValueError) as e:
            raise ValueError("base64 de imagen inválido") from e
    else:
        inp = (config.comfy_dir() / "input").resolve()
        p = (inp / v.replace("\\", "/").lstrip("/")).resolve() if not Path(v).is_absolute() else Path(v).resolve()
        if inp not in p.parents or not p.is_file():
            raise ValueError(f"imagen no encontrada en input/: {v!r} (solo se aceptan rutas dentro de input/)")
        return str(p.relative_to(inp)).replace("\\", "/")
    if not data or len(data) > MAX_UPLOAD:
        raise ValueError("imagen vacía o mayor de 50 MB")
    name = f"mcp_{hashlib.sha1(data).hexdigest()[:12]}{_sniff_ext(data)}"
    res = await client.upload_image(data, name)
    sub = res.get("subfolder") or ""
    return f"{sub}/{res['name']}" if sub else res["name"]


# ---- aplicar parámetros ---------------------------------------------------------
class ParamError(ValueError):
    pass


async def apply_params(api: dict, params: dict, client, transport=None) -> list[str]:
    """Modifica `api` in place. Devuelve lista legible de lo aplicado."""
    applied: list[str] = []
    params = dict(params or {})
    edit = editable_inputs(api)
    roles = {e["node_id"]: e.get("role") for e in edit if e["kind"] == "prompt"}

    def set_in(nid: str, name: str, value) -> None:
        api[nid]["inputs"][name] = value
        applied.append(f"{nid}.{name}")

    def text_targets(role: str) -> list[dict]:
        t = [e for e in edit if e["kind"] == "prompt" and e.get("role") == role]
        if not t and role == "positive":
            allp = [e for e in edit if e["kind"] == "prompt" and e.get("role") != "negative"]
            t = allp[:1]
        return t

    if "prompt" in params:
        t = text_targets("positive")
        if not t:
            raise ParamError("no se encontró un nodo de prompt positivo; usa '<id>.text'")
        for e in t:
            set_in(e["node_id"], e["input"], str(params["prompt"]))
        params.pop("prompt")
    if "negative" in params:
        t = text_targets("negative")
        if not t:
            raise ParamError("no se encontró un nodo de prompt negativo; usa '<id>.text'")
        for e in t:
            set_in(e["node_id"], e["input"], str(params["negative"]))
        params.pop("negative")
    if "seed" in params:
        s = params.pop("seed")
        if s == -1:
            s = random.randint(0, 2**53 - 1)
        t = [e for e in edit if e["kind"] == "seed"]
        if not t:
            raise ParamError("el workflow no tiene entradas seed/noise_seed literales")
        for e in t:
            set_in(e["node_id"], e["input"], int(s))
    if "image" in params:
        t = [e for e in edit if e["kind"] == "image"]
        if not t:
            raise ParamError("el workflow no tiene nodo LoadImage; usa '<id>.<input>'")
        name = await image_to_input_name(str(params.pop("image")), client, transport)
        set_in(t[0]["node_id"], t[0]["input"], name)
    for key, value in params.items():
        if "." not in key:
            raise ParamError(f"parámetro desconocido {key!r}: use prompt/negative/seed/image o '<node_id>.<input>'")
        nid, name = key.rsplit(".", 1)
        if nid not in api:
            raise ParamError(f"el nodo {nid!r} no existe en el prompt API (ids: {sorted(api, key=_sort_key)[:30]})")
        set_in(nid, name, value)
    return applied
