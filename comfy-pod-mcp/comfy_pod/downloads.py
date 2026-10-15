"""Descargas de modelos: validación de host/destino, reanudación, verificación de tamaño."""
from __future__ import annotations

import os
import re
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.parse import urljoin, urlparse

import httpx

from . import config
from .manifest import Entry, fetch_from_r2

# Inyectable en tests (httpx.BaseTransport).
TRANSPORT: httpx.BaseTransport | None = None
MAX_HOPS = 5
CHUNK = 1024 * 1024
_REDIRECT = (301, 302, 303, 307, 308)


class DownloadError(Exception):
    pass


def host_allowed(host: str) -> bool:
    h = (host or "").lower().rstrip(".")
    return h in ("huggingface.co", "civitai.com") or h.endswith((".huggingface.co", ".civitai.com"))


def redirect_host_allowed(host: str) -> bool:
    """Hosts permitidos SOLO como destino de redirect. Observados el 2026-10-15:
    HF -> us.aws.cdn.hf.co ; Civitai -> civitai-delivery-worker-prod.<hash>.r2.cloudflarestorage.com"""
    h = (host or "").lower().rstrip(".")
    return (host_allowed(h) or h == "hf.co" or h.endswith(".hf.co")
            or (h.startswith("civitai-delivery-worker") and h.endswith(".r2.cloudflarestorage.com")))


def validate_url(url: str, redirect: bool = False):
    u = urlparse(url)
    if u.scheme != "https":
        raise DownloadError("solo se permite https")
    if u.username or u.password:
        raise DownloadError("URL con credenciales no permitida")
    if u.port not in (None, 443):
        raise DownloadError("puerto no permitido")
    ok = redirect_host_allowed(u.hostname or "") if redirect else host_allowed(u.hostname or "")
    if not ok:
        raise DownloadError(f"host no permitido: {u.hostname}")
    return u


def validate_dest(dest: str) -> Path:
    """`dest` relativo a COMFY_DIR; debe quedar dentro de COMFY_DIR/models (tras resolver symlinks)."""
    if not dest or "\x00" in dest:
        raise DownloadError("destino vacío o inválido")
    d = dest.replace("\\", "/")
    if d.startswith("/") or re.match(r"^[A-Za-z]:", d):
        raise DownloadError("destino absoluto no permitido")
    if any(p == ".." for p in d.split("/")):
        raise DownloadError("destino con '..' no permitido")
    if d.endswith("/") or d.endswith(".part"):
        raise DownloadError("destino debe ser un archivo")
    root = config.comfy_dir().resolve()
    models = config.models_dir().resolve()
    full = (root / d).resolve()
    if models not in full.parents:
        raise DownloadError("el destino debe quedar dentro de models/")
    return full


# ---- tokens ---------------------------------------------------------------------
_tok_state = {"last_fetch": 0.0}


def _parse_tokens(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    try:
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                out[k.strip()] = v.strip().strip("'\"")
    except OSError:
        pass
    return out


def get_token(key: str) -> str | None:
    v = os.environ.get(key)
    if v:
        return v
    f = config.KB_DIR / "tokens.txt"
    t = _parse_tokens(f).get(key)
    if t:
        return t
    if time.time() - _tok_state["last_fetch"] > 60:
        _tok_state["last_fetch"] = time.time()
        if fetch_from_r2(config.R2_TOKENS) is None:
            try:
                os.chmod(f, 0o600)
            except OSError:
                pass
            return _parse_tokens(f).get(key)
    return None


def redact(text: str, secrets: list[str | None]) -> str:
    for s in secrets:
        if s:
            text = text.replace(s, "***")
    return re.sub(r"(?i)((?:access_)?token|api_?key|authorization)=[^&\s'\"]+", r"\1=***", text)


# ---- descarga de un archivo -------------------------------------------------------
def download_one(entry: Entry, rec: dict, hf_token: str | None, civ_token: str | None) -> None:
    """Descarga síncrona (se ejecuta en hilo). Actualiza `rec` (bytes/total/state/error)."""
    secrets = [hf_token, civ_token]
    try:
        _download(entry, rec, hf_token, civ_token)
    except DownloadError as e:
        rec.update(state="error", error=redact(str(e), secrets))
    except httpx.HTTPError as e:
        rec.update(state="error", error=redact(f"{type(e).__name__}: {e}", secrets)[:300])
    except OSError as e:
        rec.update(state="error", error=f"E/S: {e.strerror or type(e).__name__}")


def _parse_range_total(cr: str | None) -> int | None:
    m = re.match(r"bytes\s+(?:\d+-\d+|\*)/(\d+)", cr or "")
    return int(m.group(1)) if m else None


def _download(entry: Entry, rec: dict, hf_token: str | None, civ_token: str | None) -> None:
    final = validate_dest(entry.dest)
    u0 = validate_url(entry.url)
    final.parent.mkdir(parents=True, exist_ok=True)
    if final.exists() and final.stat().st_size > 0:
        rec.update(state="skipped", bytes=final.stat().st_size, total=final.stat().st_size,
                   error=None, note="ya existe")
        return
    part = final.with_name(final.name + ".part")
    host = (u0.hostname or "").lower()
    base_headers = {"Accept-Encoding": "identity", "User-Agent": "comfy-pod-mcp"}
    first_url = entry.url
    if host.endswith("huggingface.co") and hf_token:
        base_headers["Authorization"] = f"Bearer {hf_token}"
    if host.endswith("civitai.com") and civ_token:
        sep = "&" if "?" in first_url else "?"
        first_url = f"{first_url}{sep}token={civ_token}"
    offset = part.stat().st_size if part.exists() else 0
    rec.update(state="downloading", bytes=offset, error=None)
    with httpx.Client(timeout=httpx.Timeout(30.0, read=120.0), follow_redirects=False, transport=TRANSPORT) as c:
        cur, headers = first_url, dict(base_headers)
        for hop in range(MAX_HOPS + 1):
            h = dict(headers)
            if offset:
                h["Range"] = f"bytes={offset}-"
            with c.stream("GET", cur, headers=h) as r:
                if r.status_code in _REDIRECT:
                    loc = r.headers.get("location")
                    if not loc:
                        raise DownloadError("redirect sin Location")
                    nxt = urljoin(cur, loc)
                    validate_url(nxt, redirect=True)
                    cur = nxt
                    headers = {k: v for k, v in base_headers.items() if k != "Authorization"}
                    continue
                _consume(r, rec, part, final, offset)
                return
        raise DownloadError("demasiados redirects")


def _consume(r: httpx.Response, rec: dict, part: Path, final: Path, offset: int) -> None:
    sc = r.status_code
    if sc in (401, 403):
        raise DownloadError(f"HTTP {sc}: acceso denegado (revisa HF_TOKEN / CIVITAI_TOKEN y la licencia del modelo)")
    if sc == 416:
        total = _parse_range_total(r.headers.get("content-range"))
        if offset and total == offset:
            os.replace(part, final)
            rec.update(state="done", bytes=total, total=total)
            return
        part.unlink(missing_ok=True)
        raise DownloadError("416: .part inconsistente, se borró; reintenta")
    if sc not in (200, 206):
        raise DownloadError(f"HTTP {sc}")
    if sc == 206:
        total = _parse_range_total(r.headers.get("content-range"))
        mode = "ab"
    else:
        cl = r.headers.get("content-length")
        total = int(cl) if cl and cl.isdigit() else None
        mode, offset = "wb", 0
    rec["total"] = total
    done = offset
    with open(part, mode) as f:
        for chunk in r.iter_bytes(CHUNK):
            f.write(chunk)
            done += len(chunk)
            rec["bytes"] = done
    size = part.stat().st_size
    if total is not None and size != total:
        if size > total:
            part.unlink(missing_ok=True)
        raise DownloadError(f"tamaño final {size} distinto del esperado {total}; se conserva .part para reanudar" if size < total
                            else f"tamaño final {size} mayor que el esperado {total}; se borró .part")
    os.replace(part, final)
    rec.update(state="done", bytes=size, total=total if total is not None else size,
               note=None if total is not None else "sin Content-Length: tamaño no verificado")


# ---- gestor de trabajos -----------------------------------------------------------
class DownloadManager:
    def __init__(self, workers: int = 3):
        self._pool = ThreadPoolExecutor(max_workers=workers, thread_name_prefix="dl")
        self._jobs: dict[str, dict] = {}
        self._lock = threading.Lock()

    def start(self, entries: list[Entry]) -> str:
        job_id = uuid.uuid4().hex[:12]
        files = []
        for e in entries:
            rec = {"dest": e.dest, "url": e.url.split("?")[0], "state": "queued", "bytes": 0,
                   "total": None, "error": None}
            # validar antes de encolar: el error queda visible en el estado
            try:
                validate_url(e.url)
                validate_dest(e.dest)
            except DownloadError as ex:
                rec.update(state="error", error=str(ex))
            files.append((e, rec))
        with self._lock:
            self._jobs[job_id] = {"created": time.time(), "files": [r for _, r in files]}
        for e, rec in files:
            if rec["state"] == "queued":
                self._pool.submit(self._run, e, rec)
        return job_id

    def _run(self, e: Entry, rec: dict) -> None:
        try:
            download_one(e, rec, get_token("HF_TOKEN"), get_token("CIVITAI_TOKEN"))
        except Exception as ex:  # noqa: BLE001  (nunca dejar un hilo sin estado final)
            rec.update(state="error", error=f"{type(ex).__name__}")

    def status(self, job_id: str) -> dict | None:
        with self._lock:
            j = self._jobs.get(job_id)
        if j is None:
            return None
        files = [dict(f) for f in j["files"]]
        states = {f["state"] for f in files}
        overall = ("running" if states & {"queued", "downloading"}
                   else "error" if "error" in states else "done")
        return {"job_id": job_id, "state": overall, "files": files}


MANAGER = DownloadManager()
