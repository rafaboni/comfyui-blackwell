"""Parser y carga del manifiesto de modelos (models_to_download.txt)."""
from __future__ import annotations

import os
import shutil
import subprocess
import time
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import urlparse

from . import config


@dataclass(frozen=True)
class Entry:
    url: str
    dest: str  # relativo a COMFY_DIR, p.ej. models/vae/a.safetensors
    pack: str = ""

    @property
    def basename(self) -> str:
        return self.dest.replace("\\", "/").rsplit("/", 1)[-1]


@dataclass
class Manifest:
    entries: list[Entry] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    source: str = ""

    def by_basename(self, name: str) -> Entry | None:
        base = name.replace("\\", "/").rsplit("/", 1)[-1]
        for e in self.entries:
            if e.basename == base:
                return e
        low = base.casefold()
        for e in self.entries:
            if e.basename.casefold() == low:
                return e
        for e in self.entries:  # último recurso: nombre al final de la URL
            if urlparse(e.url).path.rsplit("/", 1)[-1].casefold() == low:
                return e
        return None

    def by_dest(self, dest: str) -> Entry | None:
        d = dest.replace("\\", "/").lstrip("./")
        for e in self.entries:
            if e.dest == d:
                return e
        return None

    def packs(self) -> dict[str, list[Entry]]:
        out: dict[str, list[Entry]] = {}
        for e in self.entries:
            out.setdefault(e.pack, []).append(e)
        return out


def _is_url(tok: str) -> bool:
    return tok.startswith(("http://", "https://"))


def parse_manifest(text: str, source: str = "") -> Manifest:
    """Acepta dos formatos:
    - `<url> <dest>` en la misma línea (formato pedido);
    - `<url>` y en la línea siguiente `<dest>` (formato real del repo comfy-cuda).
    Líneas `PACK: nombre`, comentarios `#` y líneas en blanco."""
    m = Manifest(source=source)
    pack = ""
    pending_url: str | None = None
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.upper().startswith("PACK:"):
            if pending_url:
                m.warnings.append(f"línea {n}: URL sin destino antes de PACK: {pending_url}")
                pending_url = None
            pack = line.split(":", 1)[1].strip()
            continue
        if _is_url(line.split(None, 1)[0]):
            if pending_url:
                m.warnings.append(f"línea {n}: URL sin destino: {pending_url}")
                pending_url = None
            parts = line.split(None, 1)
            if len(parts) == 2:
                m.entries.append(Entry(parts[0], parts[1].strip(), pack))
            else:
                pending_url = parts[0]
            continue
        if pending_url:
            m.entries.append(Entry(pending_url, line, pack))
            pending_url = None
        else:
            m.warnings.append(f"línea {n}: no reconocida: {line[:80]}")
    if pending_url:
        m.warnings.append(f"URL sin destino al final: {pending_url}")
    return m


_cache: dict = {"t": 0.0, "m": None}
TTL = 300.0


def _rclone_has_r2() -> bool:
    if not shutil.which("rclone"):
        return False
    try:
        r = subprocess.run(["rclone", "listremotes"], capture_output=True, text=True, timeout=15)
        return "r2:" in r.stdout
    except Exception:
        return False


def fetch_from_r2(remote_path: str) -> str | None:
    """rclone copy <remote_path> a /tmp/kb_models/. Devuelve error o None."""
    if not _rclone_has_r2():
        return "rclone sin remote r2"
    config.KB_DIR.mkdir(parents=True, exist_ok=True)
    try:
        r = subprocess.run(["rclone", "copy", remote_path, str(config.KB_DIR) + "/"],
                           capture_output=True, text=True, timeout=90)
    except Exception as e:  # noqa: BLE001
        return f"rclone falló: {type(e).__name__}"
    if r.returncode != 0:
        return f"rclone código {r.returncode}"
    return None


def load_manifest(force: bool = False) -> Manifest:
    """MODELS_MANIFEST (si existe) manda; si no, R2 -> /tmp/kb_models (caché 5 min)."""
    override = os.environ.get("MODELS_MANIFEST")
    if override:
        p = Path(override)
        if not p.is_file():
            m = Manifest(source=str(p))
            m.warnings.append(f"MODELS_MANIFEST no existe: {p}")
            return m
        return parse_manifest(p.read_text(encoding="utf-8", errors="replace"), str(p))
    now = time.time()
    if not force and _cache["m"] is not None and now - _cache["t"] < TTL:
        return _cache["m"]
    err = fetch_from_r2(config.R2_MANIFEST)
    local = config.KB_DIR / "models_to_download.txt"
    if local.is_file():
        m = parse_manifest(local.read_text(encoding="utf-8", errors="replace"), str(local))
        if err:
            m.warnings.append(f"no se pudo refrescar desde R2 ({err}); se usa copia local")
    else:
        m = Manifest(source="(ninguno)")
        m.warnings.append(f"sin manifiesto: {err or 'archivo ausente'}")
    _cache.update(t=now, m=m)
    return m
