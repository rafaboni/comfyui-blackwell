"""Cliente HTTP async de la API de ComfyUI."""
from __future__ import annotations

from typing import Any

import httpx

from . import config

# Inyectable en tests (httpx.MockTransport).
TRANSPORT: httpx.AsyncBaseTransport | None = None


class ComfyError(Exception):
    def __init__(self, msg: str, detail: Any = None):
        super().__init__(msg)
        self.detail = detail


class ComfyClient:
    def __init__(self, base: str | None = None, timeout: float = 30.0):
        self.base = (base or config.comfy_url()).rstrip("/")
        self.timeout = timeout

    def _client(self) -> httpx.AsyncClient:
        return httpx.AsyncClient(base_url=self.base, timeout=self.timeout, transport=TRANSPORT)

    async def get_json(self, path: str, params: dict | None = None) -> Any:
        async with self._client() as c:
            try:
                r = await c.get(path, params=params)
            except httpx.HTTPError as e:
                raise ComfyError(f"ComfyUI no responde en {self.base}: {type(e).__name__}") from e
            if r.status_code >= 400:
                raise ComfyError(f"GET {path} -> HTTP {r.status_code}", r.text[:500])
            return r.json()

    async def post_prompt(self, api_prompt: dict, client_id: str) -> dict:
        async with self._client() as c:
            try:
                r = await c.post("/prompt", json={"prompt": api_prompt, "client_id": client_id})
            except httpx.HTTPError as e:
                raise ComfyError(f"ComfyUI no responde: {type(e).__name__}") from e
            try:
                body = r.json()
            except ValueError:
                body = {"raw": r.text[:500]}
            if r.status_code >= 400:
                raise ComfyError(f"POST /prompt rechazado (HTTP {r.status_code})", body)
            return body

    async def upload_image(self, data: bytes, filename: str) -> dict:
        async with self._client() as c:
            r = await c.post("/upload/image", files={"image": (filename, data)},
                             data={"type": "input", "overwrite": "true"})
            if r.status_code >= 400:
                raise ComfyError(f"POST /upload/image -> HTTP {r.status_code}", r.text[:300])
            return r.json()

    async def view(self, filename: str, subfolder: str, type_: str) -> bytes:
        async with self._client() as c:
            r = await c.get("/view", params={"filename": filename, "subfolder": subfolder, "type": type_})
            if r.status_code >= 400:
                raise ComfyError(f"GET /view -> HTTP {r.status_code}")
            return r.content

    async def view_size(self, filename: str, subfolder: str, type_: str) -> int | None:
        async with self._client() as c:
            try:
                r = await c.get("/view", params={"filename": filename, "subfolder": subfolder, "type": type_})
            except httpx.HTTPError:
                return None
            return len(r.content) if r.status_code == 200 else None
