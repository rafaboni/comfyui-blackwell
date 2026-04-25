# ComfyUI Blackwell — RunPod Template

[![RunPod](https://img.shields.io/badge/RunPod-Template-7c3aed?style=for-the-badge&logo=runpod)](https://runpod.io)
[![ComfyUI](https://img.shields.io/badge/ComfyUI-Latest-000000?style=for-the-badge&logo=github)](https://github.com/comfyanonymous/ComfyUI)
[![RTX 5090](https://img.shields.io/badge/GPU-RTX_5090_Blackwell-76b900?style=for-the-badge&logo=nvidia)](https://www.nvidia.com)

Imagen Docker optimizada para **RTX 5090 (Blackwell sm_120)** con ComfyUI, gestión de configuración vía Cloudflare R2 y herramientas de administración integradas.

---

## 🚀 Puertos

| Puerto | Servicio | Descripción |
|--------|----------|-------------|
| **8188** | ComfyUI | Interfaz principal de generación de imágenes y video |
| **8888** | Jupyter Lab | Terminal y explorador de archivos avanzado |
| **8080** | File Browser | Explorador de archivos visual para subir/bajar archivos |

---

## 🔐 Variables de entorno requeridas

Configurar como **RunPod Secrets** (no como variables normales):

| Variable | Descripción |
|----------|-------------|
| `R2_ACCESS_KEY` | Clave de acceso de Cloudflare R2 |
| `R2_SECRET_KEY` | Clave secreta de Cloudflare R2 |
| `R2_ENDPOINT` | URL del bucket R2 (ej: `https://xxx.r2.cloudflarestorage.com`) |

---

## ⚡ Al arrancar el pod

El contenedor sincroniza automáticamente en background desde R2:

- ✅ Workflows guardados (`user/`)
- - ✅ LoRAs (`models/loras/`)
  - - ✅ Imágenes de input (`input/`)
   
    - ComfyUI está disponible en ~30 segundos.
   
    - ⚠️ Los modelos grandes **NO** se descargan automáticamente. Se descargan bajo demanda desde el panel RB Tools usando URLs directas con streaming.
   
    - ---

    ## 🧩 Custom Nodes instalados

    | Custom Node | Descripción | Workflows |
    |-------------|-------------|-----------|
    | [ComfyUI-Manager](https://github.com/ltdrdata/ComfyUI-Manager) | Gestor de custom nodes e instalación | Todos |
    | [ComfyUI-KJNodes](https://github.com/kijai/ComfyUI-KJNodes) | Nodos de utilidad de Kijai (Resize Image v2, Width, Height, Set nodes) | Wan 2.2 Animate |
    | [ComfyUI-WanVideoWrapper](https://github.com/kijai/ComfyUI-WanVideoWrapper) | WanVideo Model Loader, VAE Loader, Sampler, Torch Compile Settings | Wan 2.2 Animate |
    | [ComfyUI-VideoHelperSuite](https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite) | Load Video (Upload), Video Combine | Wan 2.2 Animate |
    | [ComfyUI-segment-anything-2](https://github.com/kijai/ComfyUI-segment-anything-2) | Sam2Segmentation, Download SAM2Model | Wan 2.2 Animate (preprocesado) |
    | [ComfyUI-Impact-Pack](https://github.com/ltdrdata/ComfyUI-Impact-Pack) | Detección de sujetos, segmentación YOLO | Wan 2.2 Animate (preprocesado) |
    | [ComfyUI-Easy-Use](https://github.com/yolain/ComfyUI-Easy-Use) | Nodos simplificados para flujos de trabajo comunes | General |
    | [ComfyUI-Custom-Scripts](https://github.com/pythongosssss/ComfyUI-Custom-Scripts) | Scripts de UI y utilidades de interfaz | General |
    | [rgthree-comfy](https://github.com/rgthree/rgthree-comfy) | Nodos avanzados de organización y contexto | General |
    | [efficiency-nodes-comfyui](https://github.com/jags111/efficiency-nodes-comfyui) | Nodos de eficiencia para pipelines SDXL/SD | General |
    | [ComfyUI_UltimateSDUpscale](https://github.com/ssitu/ComfyUI_UltimateSDUpscale) | Upscaling avanzado con SD | General |
    | [ComfyUI-QwenVL](https://github.com/1038lab/ComfyUI-QwenVL) | Vision-Language model Qwen para captioning | General |
    | [ComfyUI-QwenVL-Mod](https://github.com/huchukato/ComfyUI-QwenVL-Mod) | Versión modificada de QwenVL | General |
    | [Civicomfy](https://github.com/MoonGoblinDev/Civicomfy) | Descarga de modelos desde CivitAI directamente | General |
    | [ComfyUI-RunpodDirect](https://github.com/MadiatorLabs/ComfyUI-RunpodDirect) | Integración directa con RunPod API | General |
    | [comfyui-kb-tools](https://github.com/rafaboni/comfyui-blackwell) | Panel RB Tools (propio): descarga modelos, sync R2, update Dockerfile | Todos |

    ### 🎬 Workflow: Wan 2.2 Animate (Character Swap + Lip-sync)

    Basado en el workflow de [Kijai](https://github.com/kijai), modificado por MDMZ. Descarga disponible en [Patreon de MDMZ](https://www.patreon.com/posts/wan-2-2-animate-140792860).

    **Nodos clave usados:**

    | Nodo | Custom Node pack |
    |------|-----------------|
    | `WanVideo Model Loader` | ComfyUI-WanVideoWrapper |
    | `WanVideo VAE Loader` | ComfyUI-WanVideoWrapper |
    | `WanVideo Torch Compile Settings` | ComfyUI-WanVideoWrapper |
    | `WanVideo Animate Embeds` | ComfyUI-WanVideoWrapper |
    | `WanAnimate Preprocess` | ComfyUI-WanVideoWrapper |
    | `Resize Image v2` | ComfyUI-KJNodes |
    | `Load Video (Upload)` | ComfyUI-VideoHelperSuite |
    | `Video Combine` | ComfyUI-VideoHelperSuite |
    | `Sam2Segmentation` | ComfyUI-segment-anything-2 |
    | `DownLoad SAM2Model` | ComfyUI-segment-anything-2 |
    | `ONNX Detection Model Loader` | ComfyUI-Impact-Pack |
    | `Grow Mask With Blur` | ComfyUI nativo |

    **Modelos requeridos:**
    - `Wan2_2-Animate-14B_fp8_scaled_e4m3fn_KJ_v2.safetensors` → `models/checkpoints/`
    - - `wan_2.1_vae.safetensors` → `models/vae/`
      - - Text encoder fp16 → `models/text_encoders/`
        - - LoRAs Wan 2.2 → `models/loras/`
         
          - ---

          ## 🧰 RB Tools (Panel de Administración)

          Panel integrado en el sidebar de ComfyUI. Accede desde el ícono 🔧 en la barra lateral.

          ### 💾 SALVAR TODO

          Sube a R2 todo lo nuevo de la sesión:
          - Workflows modificados
          - - LoRAs nuevas
            - - Imágenes de input
             
              - Usar siempre al terminar la sesión antes de apagar el pod.
             
              - ### 📥 Descargar Modelos (Streaming + Paralelo)
             
              - Descarga modelos grandes desde URLs directas configuradas en `models_to_download.txt`.
             
              - Características:
              - - ✅ Descargas paralelas con threading para mayor velocidad
                - - ✅ Barras de progreso en tiempo real (MB/s)
                  - - ✅ Soporte automático para tokens de HuggingFace y Civitai
                    - - ✅ Botón ❌ Cancelar que limpia archivos parciales
                      - - ✅ Reanuda descargas interrumpidas si el archivo está incompleto
                       
                        - Packs disponibles:
                       
                        - | Pack | Descripción |
                        - |------|-------------|
                        - | Klein 9B | FLUX.2 Klein para generación de imágenes de alta calidad |
                        - | Klein Base 9B fp8 | Versión base optimizada para entrenamiento de LoRAs |
                        - | WAN 2.2 Animate | Animación de personajes y movimiento |
                        - | WAN 2.2 I2V | Image-to-Video: convierte imágenes en videos cortos |
                        - | WAN 2.2 T2V | Text-to-Video: genera videos desde prompts de texto |
                       
                        - ### 🖼 Imágenes de Input ↔ R2
                       
                        - Sincroniza imágenes de referencia usadas en nodos `Load Image` con R2. Ideal para mantener tus assets disponibles entre sesiones.
                       
                        - ### 🧩 Update Nodes → Dockerfile → GitHub
                       
                        - Actualiza el Dockerfile cuando instales nuevos custom nodes vía ComfyUI Manager. Dispara un nuevo build automáticamente en GitHub Actions.
                       
                        - ⚠️ Solo usar cuando instales o desinstales un custom node.
                       
                        - ### ✏️ Agregar Pack de Modelos
                       
                        - Formulario para agregar nuevos packs al archivo de configuración en R2.
                       
                        - Requiere:
                        - - URL directa del modelo principal (checkpoint)
                          - - URL del text encoder (opcional)
                            - - URL del VAE (opcional)
                             
                              - ### 🔑 Configuración de tokens
                             
                              - Subir el archivo `tokens.txt` a `R2/config/tokens.txt`:
                             
                              - ```
                                HF_TOKEN=hf_xxxxxxxxxxxx
                                CIVITAI_TOKEN=xxxxxxxxxxxx
                                GITHUB_TOKEN=ghp_xxxxxxxxxxxx
                                ```

                                RB Tools lee este archivo automáticamente para:
                                - Descargas autenticadas de HuggingFace (`Authorization: Bearer`)
                                - - Descargas de Civitai (`?token=` en la URL)
                                  - - Updates del Dockerfile en GitHub vía API
                                   
                                    - ---

                                    ## ⚙️ Configuración de modelos descargables

                                    El archivo `R2/config/models_to_download.txt` define los packs disponibles.

                                    Formato:

                                    ```
                                    PACK: Klein 9B
                                    https://huggingface.co/rafaboni/flux2-klein/resolve/main/klein_9b.safetensors
                                    models/checkpoints/klein_9b.safetensors
                                    https://huggingface.co/rafaboni/flux2-klein/resolve/main/encoder.safetensors
                                    models/text_encoders/encoder.safetensors
                                    https://huggingface.co/rafaboni/flux2-klein/resolve/main/vae.safetensors
                                    models/vae/vae.safetensors

                                    PACK: WAN 2.2 Animate
                                    https://huggingface.co/rafaboni/wan22/resolve/main/wan_animate.safetensors
                                    models/checkpoints/wan_animate.safetensors
                                    ```

                                    📌 **Importante:**
                                    - Las URLs deben ser enlaces directos de descarga (no páginas HTML)
                                    - - Usa `/resolve/` en HuggingFace, no `/blob/`
                                      - - RB Tools usa `requests.get(stream=True)` para descargar eficientemente
                                       
                                        - ---

                                        ## 🏗️ Arquitectura

                                        ```
                                        RunPod Pod (RTX 5090 Blackwell)
                                        │
                                        ├── 🌐 Servicios
                                        │   ├── ComfyUI        :8188
                                        │   ├── Jupyter Lab    :8888
                                        │   └── File Browser   :8080
                                        │
                                        ├── 📁 /workspace/ComfyUI/
                                        │   ├── models/
                                        │   │   ├── checkpoints/    ← Modelos (descarga bajo demanda vía HTTP streaming)
                                        │   │   ├── loras/          ← LoRAs (sync con R2 al arrancar)
                                        │   │   ├── text_encoders/  ← Encoders (descarga bajo demanda)
                                        │   │   └── vae/            ← VAEs (descarga bajo demanda)
                                        │   ├── input/              ← Imágenes de input (sync con R2 al arrancar)
                                        │   ├── output/             ← Imágenes y videos generados
                                        │   └── user/               ← Workflows (sync con R2 al arrancar)
                                        │
                                        └── 🔧 custom_nodes/comfyui-kb-tools/
                                            └── Panel RB Tools integrado en ComfyUI

                                        Cloudflare R2 (bucket: comfy-models/)
                                        │
                                        ├── loras/      ← LoRAs persistentes
                                        ├── input/      ← Imágenes de input persistentes
                                        ├── user/       ← Workflows persistentes
                                        └── config/
                                            ├── tokens.txt               ← Tokens para descargas autenticadas
                                            └── models_to_download.txt   ← URLs directas HTTP/HTTPS de modelos
                                        ```

                                        ---

                                        ## 🐳 Registry Auth (Recomendado)

                                        Para evitar rate limiting de Docker Hub al iniciar el pod:

                                        1. Genera un Access Token en Docker Hub Settings
                                        2. 2. En RunPod → Pod Template → Advanced → Registry Auth:
                                           3.    - Registry: `docker.io`
                                                 -    - Username: `rafaboni`
                                                      -    - Password: `<tu_access_token>`
                                                       
                                                           - ---

                                                           ## 🔄 Flujo de trabajo recomendado

                                                           ```
                                                           Iniciar Pod → Sync R2 (LoRAs, Workflows, Input) → ComfyUI listo :8188
                                                           → Descargar modelos vía RB Tools → Generar / Trabajar
                                                           → 💾 SALVAR TODO en RB Tools → Apagar Pod
                                                           ```

                                                           ---

                                                           ## 🛠️ Troubleshooting

                                                           | Problema | Solución |
                                                           |----------|----------|
                                                           | Descarga de modelo falla | Verificar que la URL sea directa (usa `/resolve/` en HF) |
                                                           | Token no funciona | Revisar formato en `tokens.txt` y permisos del token |
                                                           | RB Tools no aparece | Reiniciar ComfyUI o verificar que `comfyui-kb-tools` está en `custom_nodes/` |
                                                           | Sync con R2 lento | Verificar conexión y credenciales R2 en RunPod Secrets |
                                                           | Modelo ya descargado pero no aparece | Verificar que la ruta de destino en `models_to_download.txt` es correcta |
                                                           | Error en nodos WanVideo | Instalar `ComfyUI-WanVideoWrapper` y `ComfyUI-segment-anything-2` vía Manager |

                                                           ---

                                                           ## 📄 Licencia

                                                           MIT License. Ver archivo LICENSE para detalles.
