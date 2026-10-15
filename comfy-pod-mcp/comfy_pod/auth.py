"""Middleware ASGI: exige `Authorization: Bearer <MCP_TOKEN>` (comparación en tiempo constante)."""
from __future__ import annotations

import hmac
import json


class BearerAuth:
    def __init__(self, app, token: str):
        if not token:
            raise ValueError("token vacío")
        self.app = app
        self._token = token.encode()

    def _ok(self, scope) -> bool:
        for k, v in scope.get("headers", []):
            if k == b"authorization":
                parts = v.split(None, 1)
                if len(parts) == 2 and parts[0].lower() == b"bearer":
                    return hmac.compare_digest(parts[1].strip(), self._token)
                return False
        return False

    async def __call__(self, scope, receive, send):
        if scope["type"] == "lifespan":
            return await self.app(scope, receive, send)
        if scope["type"] == "http" and self._ok(scope):
            return await self.app(scope, receive, send)
        if scope["type"] == "http":
            body = json.dumps({"error": "unauthorized"}).encode()
            await send({"type": "http.response.start", "status": 401, "headers": [
                (b"content-type", b"application/json"),
                (b"www-authenticate", b"Bearer"),
                (b"content-length", str(len(body)).encode())]})
            await send({"type": "http.response.body", "body": body})
        elif scope["type"] == "websocket":
            await send({"type": "websocket.close", "code": 1008})
