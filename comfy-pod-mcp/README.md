# comfy-pod MCP

Servidor MCP (SDK oficial `mcp` 2.x, `MCPServer`, Streamable HTTP) que corre **dentro** del contenedor
ComfyUI de RunPod y se usa desde Claude Code en el Mac.

## Herramientas

| Tool | Qué hace |
|---|---|
| `health()` | ComfyUI alcanzable, versión, GPU/VRAM |
| `list_workflows()` | Workflows de `$COMFY_DIR/user/default/workflows` (nombre, tamaño, mtime) |
| `describe_workflow(name)` | Entradas editables (prompts +rol positivo/negativo, seeds, imagen, steps, cfg, width/height, frames) por nodo (id, título, clase) y modelos referenciados (presente/faltante, URL+destino) |
| `missing_models(name)` | Solo los faltantes; sin URL: `"sin URL en el manifiesto"` |
| `download_models(name?, files?, pack?)` | Descargas en segundo plano (3 a la vez); devuelve `job_id` |
| `download_status(job_id)` | bytes/total/estado/error por archivo |
| `run_workflow(name, params)` | UI→API, aplica params, `POST /prompt`; devuelve `prompt_id` |
| `get_job(prompt_id)` | success/error + errores de nodo, o running/pending + posición en cola |
| `get_outputs(prompt_id, include_base64=False)` | Archivos de salida (nombre, subfolder, type, size, URL `/view?...`) |

`params` de `run_workflow`: `{"<node_id>.<input>": valor}` (para nodos de subgrafo el id es `"20:5"`)
más atajos `prompt`, `negative`, `seed` (`-1` = aleatoria; se aplica a **todas** las entradas
`seed`/`noise_seed` literales) e `image` (archivo dentro de `input/`, URL http(s) pública o base64/data URI;
se sube con `POST /upload/image` y se pone en el primer `LoadImage`). La respuesta incluye `applied`
para ver qué se tocó.

## Correr en el pod

```bash
export MCP_TOKEN="$(openssl rand -hex 24)"   # obligatorio; sin él NO arranca
bash /comfyuiworkspace/comfy-pod-mcp/run_mcp.sh   # fondo, log en /var/log/comfy-pod-mcp.log
```

Para que arranque con el pod, agrega en `start.sh` (antes de lanzar ComfyUI en primer plano):

```bash
bash /comfyuiworkspace/comfy-pod-mcp/run_mcp.sh || true
```

y define `MCP_TOKEN` como variable/secret de la plantilla de RunPod. Expón el puerto **8190/http** en la plantilla.
`run_mcp.sh` instala `requirements.txt` solo si faltan las dependencias.

Variables: `MCP_TOKEN` (obligatoria), `MCP_PORT` (8190), `COMFY_DIR` (`/comfyuiworkspace/ComfyUI`),
`COMFY_URL` (`http://127.0.0.1:8188`), `MODELS_MANIFEST` (ruta local que sustituye al manifiesto de R2),
`HF_TOKEN`, `CIVITAI_TOKEN` (si faltan se buscan en `/tmp/kb_models/tokens.txt` y luego en
`r2:comfy-models/config/tokens.txt`, líneas `CLAVE=VALOR`). Los tokens nunca se devuelven ni se registran.

Prueba local sin HTTP: `python3 -m comfy_pod --stdio`.

## Añadir en Claude Code (Mac)

```bash
claude mcp add --transport http comfy-pod https://<podid>-8190.proxy.runpod.net/mcp \
  --header "Authorization: Bearer <token>"
```

Las URLs de `get_outputs` son relativas: se abren en `https://<podid>-8188.proxy.runpod.net` + `url`.

## Manifiesto de modelos

`models_to_download.txt` se baja de R2 (`rclone copy r2:comfy-models/config/models_to_download.txt /tmp/kb_models/`,
caché de 5 min) o se lee de `MODELS_MANIFEST`. Formatos aceptados: `PACK: nombre`, comentarios `#`, y
`<url> <destino>` en una línea **o** URL en una línea y destino en la siguiente (así está el manifiesto real
del repo `comfy-cuda`). El modelo se asocia por *basename*; si no está en el manifiesto se usa el array
`models` del workflow (`{name,url,directory}`, de la raíz o de `properties.models` de cada nodo).

## Seguridad de las descargas

Solo `https`; hosts `huggingface.co`, `*.huggingface.co`, `civitai.com`, `*.civitai.com`. Los redirects se
validan salto a salto y además admiten `*.hf.co` y `civitai-delivery-worker*.r2.cloudflarestorage.com`
(observados con `curl -I` el 2026-10-15). En redirects se descartan el `Authorization` y el token. El destino
se resuelve (incluidos symlinks) y debe quedar dentro de `$COMFY_DIR/models`. Se escribe a `.part`, se reanuda
con `Range`, se verifica el tamaño contra `Content-Length`/`Content-Range` y se renombra al final. No pisa
archivos existentes. Civitai usa `?token=` (único mecanismo implementado), HF usa `Bearer`.

## Conversión UI → API

No existe conversor oficial en el servidor de ComfyUI. Hay un custom node de terceros
(`SethRobinson/comfyui-workflow-to-api-converter-endpoint`, endpoint `/workflow/convert`) y ComfyScript, pero
ninguno es una librería Python offline y mantenida, así que `comfy_pod/convert.py` lo implementa con
`GET /object_info`: orden de widgets, salto del pseudo-widget `control_after_generate` y del botón de subida
de `LoadImage`, widgets convertidos a entrada, Reroute, PrimitiveNode, SetNode/GetNode (KJNodes), omisión de
Note/MarkdownNote/rgthree (Label, Fast Groups/Muter/Bypasser), muted (modo 2) omitido, bypass (modo 4) con
paso directo por tipo, y aplanado de subgrafos (ids `"<instancia>:<nodo>"`). Un workflow ya en formato API
se acepta tal cual.

## Tests

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt && .venv/bin/python -m pytest -q
```

ComfyUI y las descargas se simulan con `httpx.MockTransport`; los tests no usan red, rclone ni R2.

## Limitaciones conocidas

- Nunca probado contra un ComfyUI real ni en el pod (solo mocks + servidor HTTP local sin ComfyUI).
- Conversión: nodos dinámicos/autogrow y *promoted widgets* de subgrafos (valores de widget en la instancia)
  no se convierten; nodos con widgets_values desalineados respecto a `object_info` darán valores corridos;
  un nodo cuya clase no esté en `/object_info` falla con el id y la clase. Un nodo de salida muteado desaparece.
- `describe_workflow` necesita ComfyUI arriba para las entradas editables (usa `/object_info`); los modelos se listan igual.
- La seed `randomize` del UI no se re-sortea: se usa la guardada salvo que pases `seed` (`-1` = aleatoria).
- Detección de modelos por extensión (`.safetensors .ckpt .pt .pth .onnx .gguf .bin`) en cualquier widget;
  "presente" = coincidencia por sufijo de ruta bajo `models/` o aparece en `GET /models/<carpeta>`.
  Carpetas con `extra_model_paths.yaml` fuera de `models/` solo se ven por la API para los loaders conocidos.
- Estado de descargas en memoria: se pierde si el MCP se reinicia (los `.part` sí permiten reanudar).
- `get_outputs` calcula el tamaño leyendo disco o `/view`; con `include_base64` solo imágenes < 2 MB.
