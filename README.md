
# ComfyUI Blackwell — RunPod Template

Imagen Docker optimizada para RTX 5090 (Blackwell sm_120) con ComfyUI, gestión de configuración via Cloudflare R2 y herramientas de administración integradas.

* * *

## Puertos

| Puerto | Servicio | Descripción |
|--------|----------|-------------|
| **8188** | ComfyUI | Interfaz principal de generación de imágenes y video |
| **8888** | Jupyter Lab | Terminal y explorador de archivos avanzado |
| **8080** | File Browser | Explorador de archivos visual para subir/bajar archivos |

* * *

## Variables de entorno requeridas

Configurar como **RunPod Secrets** (no como variables normales):

| Variable | Descripción |
|----------|-------------|
| `R2_ACCESS_KEY` | Clave de acceso de Cloudflare R2 |
| `R2_SECRET_KEY` | Clave secreta de Cloudflare R2 |
| `R2_ENDPOINT` | URL del bucket R2 (ej: `https://xxx.r2.cloudflarestorage.com`) |

* * *

## Al arrancar el pod

El container automáticamente sincroniza en background desde R2:

- ✅ Workflows guardados (`user/`)
- ✅ LoRAs (`models/loras/`)
- ✅ Imágenes de input (`input/`)

ComfyUI está disponible en ~30 segundos. 

> ⚠️ **Los modelos grandes NO se descargan automáticamente**. Se descargan bajo demanda desde el panel **RB Tools** usando URLs directas con streaming.

* * *

## RB Tools (antes KB Tools) 🔧

Panel integrado en el sidebar de ComfyUI. Contiene:

### 💾 SALVAR TODO
Sube a R2 todo lo nuevo de la sesión:
- Workflows modificados
- LoRAs nuevas  
- Imágenes de input

> **Usar siempre al terminar la sesión antes de apagar el pod.**

### 📥 Descargar Modelos (Streaming + Paralelo)
Descarga modelos grandes desde **URLs directas** configuradas en `models_to_download.txt`. 

**Características:**
- ✅ Descargas paralelas con threading
- ✅ Barras de progreso en tiempo real (MB/s)
- ✅ Soporte para tokens de HuggingFace y Civitai
- ✅ Botón **❌ Cancelar** que limpia archivos parciales
- ✅ Reanuda si el archivo está incompleto

**Packs disponibles:**
- **Klein 9B** — FLUX.2 Klein para generación de imágenes
- **Klein Base 9B fp8** — versión base para entrenamiento de LoRAs
- **WAN 2.2 Animate** — animación de personajes
- **WAN 2.2 I2V** — imagen a video
- **WAN 2.2 T2V** — texto a video

### 🖼 Imágenes de Input ↔ R2
Sincroniza imágenes de referencia usadas en nodos `Load Image` con R2.

### 🧩 Update Nodes → Dockerfile → GitHub
Actualizar el Dockerfile cuando se instalen nuevos custom nodes via ComfyUI Manager. Dispara un nuevo build automáticamente.

> Solo usar cuando instales o desinstales un custom node.

### ✏️ Agregar Pack de Modelos
Formulario para agregar nuevos packs al archivo de configuración en R2. Requiere URL directa del modelo, text encoder y VAE.

* * *

## Configuración de tokens

Subir el archivo `tokens.txt` a `R2/config/tokens.txt`:

```
HF_TOKEN=hf_xxxxxxxxxxxx
CIVITAI_TOKEN=xxxxxxxxxxxx
GITHUB_TOKEN=ghp_xxxxxxxxxxxx
```

RB Tools lee este archivo automáticamente para:
- Descargas autenticadas de HuggingFace (`Authorization: Bearer`)
- Descargas de Civitai (`?token=` en la URL)
- Updates del Dockerfile en GitHub

* * *

## Configuración de modelos descargables

El archivo `R2/config/models_to_download.txt` define los packs. Formato:

```txt
PACK: Nombre del pack
https://huggingface.co/.../model.safetensors models/checkpoints/model.safetensors
https://civitai.com/.../encoder.safetensors models/text_encoders/encoder.safetensors
https://.../vae.safetensors models/vae/vae.safetensors
```

> 📌 **Importante**: Las URLs deben ser enlaces directos de descarga (no páginas HTML). RB Tools usa `requests.get(stream=True)` para descargar.

* * *

## Arquitectura

```
RunPod Pod (RTX 5090)
├── ComfyUI :8188
│   └── custom_nodes/comfyui-kb-tools/   ← Panel RB Tools
├── Jupyter Lab :8888
├── File Browser :8080
└── /workspace/ComfyUI/
    ├── models/              ← Modelos (descarga bajo demanda vía HTTP streaming)
    ├── models/loras/        ← LoRAs (sync con R2 al arrancar)
    ├── input/               ← Imágenes (sync con R2 al arrancar)
    ├── output/              ← Imágenes generadas
    └── user/                ← Workflows (sync con R2 al arrancar)

Cloudflare R2 (comfy-models/)
├── loras/                   ← LoRAs persistentes
├── input/                   ← Imágenes de input persistentes
├── user/                    ← Workflows persistentes
└── config/
    ├── tokens.txt           ← Tokens para descargas autenticadas
    └── models_to_download.txt  ← URLs directas de modelos (NO archivos R2)
```

* * *

## Registry Auth (recomendado)

Para evitar throttling de Docker Hub al iniciar el pod:
- **Registry**: `docker.io`
- **Username**: `rafaboni`
- **Password**: Docker Hub Access Token
```

---

## 🔄 Cambios clave que apliqué:

| Sección | Antes | Ahora |
|---------|-------|-------|
| Nombre del panel | KB Tools | **RB Tools** |
| Descarga de modelos | Via R2/rclone | **HTTP streaming con `requests`** |
| Progreso de descarga | No especificado | **Barras en tiempo real + MB/s** |
| Cancelación | No mencionada | **Botón Cancelar + limpieza de parciales** |
| Autenticación | Genérica | **Tokens HF/Civitai aplicados automáticamente** |
| Configuración de modelos | URLs de R2 | **URLs directas HTTP/HTTPS** |

¿Quieres que te genere el archivo `README.md` listo para copiar/pegar o necesitas ajustar algo más? 🚀
