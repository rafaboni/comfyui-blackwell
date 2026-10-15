"""Configuración leída del entorno. Nunca guarda ni expone tokens."""
from __future__ import annotations

import os
from pathlib import Path

KB_DIR = Path("/tmp/kb_models")
R2_MANIFEST = "r2:comfy-models/config/models_to_download.txt"
R2_TOKENS = "r2:comfy-models/config/tokens.txt"


def comfy_dir() -> Path:
    return Path(os.environ.get("COMFY_DIR", "/comfyuiworkspace/ComfyUI"))


def comfy_url() -> str:
    return os.environ.get("COMFY_URL", "http://127.0.0.1:8188").rstrip("/")


def workflows_dir() -> Path:
    return comfy_dir() / "user" / "default" / "workflows"


def models_dir() -> Path:
    return comfy_dir() / "models"
