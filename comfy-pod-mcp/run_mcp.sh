#!/usr/bin/env bash
# Lanza comfy-pod MCP en segundo plano. Llamar desde start.sh:
#   bash /comfyuiworkspace/comfy-pod-mcp/run_mcp.sh
# Requiere MCP_TOKEN en el entorno del pod (secreto de RunPod). Log: /var/log/comfy-pod-mcp.log
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG=/var/log/comfy-pod-mcp.log
export COMFY_DIR="${COMFY_DIR:-/comfyuiworkspace/ComfyUI}"
export MCP_PORT="${MCP_PORT:-8190}"
export PIP_BREAK_SYSTEM_PACKAGES=1

if [[ -z "${MCP_TOKEN:-}" ]]; then
  echo "comfy-pod-mcp: MCP_TOKEN no definido; no se arranca." | tee -a "$LOG" >&2
  exit 2
fi
if pgrep -f "comfy_pod" >/dev/null 2>&1; then
  echo "comfy-pod-mcp: ya está corriendo." | tee -a "$LOG"
  exit 0
fi
# Dependencias solo si faltan (idempotente, rápido si ya están)
if ! python3 -c "import mcp, httpx, uvicorn" >/dev/null 2>&1; then
  python3 -m pip install -q -r "$DIR/requirements.txt" >>"$LOG" 2>&1 || {
    echo "comfy-pod-mcp: pip install falló, ver $LOG" >&2; exit 3; }
fi
cd "$DIR"
nohup python3 -m comfy_pod >>"$LOG" 2>&1 &
echo "comfy-pod-mcp: lanzado (pid $!, puerto $MCP_PORT, log $LOG)"
