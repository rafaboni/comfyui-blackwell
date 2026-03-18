# ComfyUI Blackwell — RunPod Template

Imagen Docker optimizada para RTX 5090 (Blackwell sm_120) con ComfyUI, gestión de modelos via Cloudflare R2 y herramientas de administración integradas.

---

## Puertos

| Puerto | Servicio | Descripción |
|--------|----------|-------------|
| **8188** | ComfyUI | Interfaz principal de generación de imágenes y video |
| **8888** | Jupyter Lab | Terminal y explorador de archivos avanzado |
| **8080** | File Browser | Explorador de archivos visual para subir/bajar archivos |

---

## Variables de entorno requeridas

Configurar como **RunPod Secrets** (no como variables normales):

| Variable | Descripción |
|----------|-------------|
| `R2_ACCESS_KEY` | Clave de acceso de Cloudflare R2 |
| `R2_SECRET_KEY` | Clave secreta de Cloudflare R2 |
| `R2_ENDPOINT` | URL del bucket R2 (ej: `https://xxx.r2.cloudflarestorage.com`) |

---

## Al arrancar el pod

El container automáticamente descarga en background desde R2:
- ✅ Workflows guardados
- ✅ LoRAs
- ✅ Imágenes de input

ComfyUI está disponible en ~30 segundos. Los modelos grandes **no** se descargan automáticamente — se descargan bajo demanda desde KB Tools.

---

## KB Tools

Panel integrado en el sidebar de ComfyUI (ícono 🔧). Contiene:

### 💾 SALVAR TODO
Sube a R2 todo lo nuevo de la sesión:
- Workflows modificados
- LoRAs nuevas
- Imágenes de input
> **Usar siempre al terminar la sesión antes de apagar el pod.**

### 📥 Descargar Modelos
Descarga modelos grandes desde URLs configuradas en R2. Selecciona los packs que necesitas para la sesión:
- **Klein 9B** — FLUX.2 Klein para generación de imágenes
- **Klein Base 9B fp8** — versión base para entrenamiento de LoRAs
- **WAN 2.2 Animate** — animación de personajes
- **WAN 2.2 I2V** — imagen a video
- **WAN 2.2 T2V** — texto a video

Muestra barras de progreso en tiempo real con velocidad de descarga. Incluye botón **❌ Cancelar** que limpia los archivos parciales.

### 🖼 Imágenes de Input ↔ R2
Sube o baja imágenes de referencia usadas en nodos `Load Image`.

### 🧩 Update Nodes → Dockerfile → GitHub
Actualizar el Dockerfile cuando se instalen nuevos custom nodes via ComfyUI Manager. Dispara un nuevo build automáticamente.
> Solo usar cuando instales o desinstales un custom node.

### ✏️ Agregar Pack de Modelos
Formulario para agregar nuevos packs al archivo de configuración de modelos en R2. Requiere URL del modelo, text encoder y VAE.

---

## Configuración de tokens (R2)

Subir el archivo `tokens.txt` a `R2/config/tokens.txt` con el siguiente formato:

```
HF_TOKEN=hf_xxxxxxxxxxxx
CIVITAI_TOKEN=xxxxxxxxxxxx
GITHUB_TOKEN=ghp_xxxxxxxxxxxx
```

KB Tools lee este archivo automáticamente para descargas autenticadas de HuggingFace y Civitai, y para updates del Dockerfile en GitHub.

---

## Modelos disponibles en R2

El archivo `R2/config/models_to_download.txt` define los packs descargables. Formato:

```
PACK: Nombre del pack
https://url-del-modelo models/carpeta/archivo.safetensors
https://url-del-encoder models/text_encoders/archivo.safetensors
https://url-del-vae models/vae/archivo.safetensors
```

---

## Arquitectura

```
RunPod Pod (RTX 5090)
├── ComfyUI :8188
│   └── custom_nodes/comfyui-kb-tools/   ← Panel de administración
├── Jupyter Lab :8888
├── File Browser :8080
└── /workspace/ComfyUI/
    ├── models/         ← Modelos (descarga bajo demanda)
    ├── models/loras/   ← LoRAs (sincronizadas al arrancar)
    ├── input/          ← Imágenes de referencia (sincronizadas al arrancar)
    ├── output/         ← Imágenes generadas
    └── user/           ← Workflows (sincronizados al arrancar)

Cloudflare R2 (comfy-models/)
├── loras/              ← LoRAs persistentes
├── input/              ← Imágenes de input persistentes
├── user/               ← Workflows persistentes
└── config/
    ├── tokens.txt      ← HF, Civitai, GitHub tokens
    └── models_to_download.txt  ← Lista de packs de modelos
```

---

## Registry Auth (recomendado)

Para evitar throttling de Docker Hub al iniciar el pod, configurar en el template:
- **Registry**: `docker.io`
- **Username**: `rafaboni`
- **Password**: Docker Hub Access Token
