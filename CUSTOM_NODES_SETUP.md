# Custom Nodes Setup - ComfyUI Blackwell

Documentación de la instalación de custom nodes para WAN 2.2 Animate sin SageAttention.

## Custom Nodes Instalados (Dockerfile)

✅ **Ya incluidos en el Dockerfile:**

1. **ComfyUI-Manager** - Gestor de custom nodes e instalación
2. 2. **ComfyUI-KJNodes** - Nodos de utilidad de Kijai (Resize Image v2, Width, Height, Set nodes)
   3. 3. **ComfyUI-WanVideoWrapper** - WanVideo Model Loader, VAE Loader, Sampler, Torch Compile Settings
      4. 4. **ComfyUI-VideoHelperSuite** - Load Video (Upload), Video Combine
         5. 5. **ComfyUI-segment-anything-2** - Sam2Segmentation, Download SAM2Model
            6. 6. **ComfyUI-Impact-Pack** - Detección de sujetos, segmentación YOLO
               7. 7. **ComfyUI-Easy-Use** - Nodos simplificados para flujos de trabajo comunes
                  8. 8. **ComfyUI-Custom-Scripts** - Scripts de UI y utilidades de interfaz
                     9. 9. **rgthree-comfy** - Nodos avanzados de organización y contexto
                        10. 10. **efficiency-nodes-comfyui** - Nodos de eficiencia para pipelines SDXL/SD
                            11. 11. **ComfyUI_UltimateSDUpscale** - Upscaling avanzado con SD
                                12. 12. **ComfyUI-QwenVL** - Vision-Language model Qwen para captioning
                                    13. 13. **ComfyUI-QwenVL-Mod** - Versión modificada de QwenVL
                                        14. 14. **Civicomfy** - Descarga de modelos desde CivitAI directamente
                                            15. 15. **ComfyUI-RunpodDirect** - Integración directa con RunPod API
                                                16. 16. **comfyui-kb-tools** - Panel RB Tools (propio)
                                                   
                                                    17. ## ⚠️ Custom Node AGREGADO RECIENTEMENTE
                                                   
                                                    18. **ComfyUI-WanAnimatePreprocess** (Línea 64 del Dockerfile)
                                                    19. - Repositorio: https://github.com/kijai/ComfyUI-WanAnimatePreprocess
                                                        - - Propósito: Nodos de preprocesamiento para WAN 2.2 Animate (pose, face, detection)
                                                          - - Necesario para: Preprocesar videos antes de la animación
                                                           
                                                            - ## Configuración de Modelos
                                                           
                                                            - ### URLs de Descarga (models_to_download.txt)
                                                           
                                                            - El archivo `models_to_download.txt` en la raíz del repositorio contiene las URLs directas para descargar:
                                                           
                                                            - **PACK: WAN 2.2 Animate**
                                                           
                                                            - - **Diffusion Model**: `Wan2_2-Animate-14B_fp8_scaled_e4m3fn_KJ_v2.safetensors`
                                                              -   - Destino: `models/checkpoints/`
                                                                  -   - URL: HuggingFace Kijai WanVideo_comfy_fp8_scaled
                                                                   
                                                                      - - **Text Encoder**: `umt5-xxl-enc-fp8_e4m3fn.safetensors`
                                                                        -   - Destino: `models/text_encoders/`
                                                                            -   - URL: HuggingFace Kijai WanVideo_comfy
                                                                             
                                                                                - - **VAE**: `Wan2_1_VAE_bf16.safetensors`
                                                                                  -   - Destino: `models/vae/`
                                                                                      -   - URL: HuggingFace Kijai WanVideo_comfy
                                                                                       
                                                                                          - - **Detection Model**: `yolov10m.onnx`
                                                                                            -   - Destino: `models/detection/`
                                                                                                -   - URL: HuggingFace Wan-AI Wan2.2-Animate-14B
                                                                                                 
                                                                                                    - ## Estructura de Carpetas en custom_nodes/
                                                                                                 
                                                                                                    - ```
                                                                                                      custom_nodes/
                                                                                                      ├── ComfyUI-Manager/
                                                                                                      ├── ComfyUI-KJNodes/
                                                                                                      ├── ComfyUI-WanVideoWrapper/          ← WAN 2.2 Animate model loading
                                                                                                      ├── ComfyUI-WanAnimatePreprocess/     ← NEW! Preprocesamiento (pose, face, detection)
                                                                                                      ├── ComfyUI-VideoHelperSuite/
                                                                                                      ├── ComfyUI-segment-anything-2/       ← Segmentación de objetos
                                                                                                      ├── ComfyUI-Impact-Pack/              ← YOLO detection
                                                                                                      ├── ComfyUI-Easy-Use/
                                                                                                      ├── ComfyUI-Custom-Scripts/
                                                                                                      ├── rgthree-comfy/
                                                                                                      ├── efficiency-nodes-comfyui/
                                                                                                      ├── ComfyUI_UltimateSDUpscale/
                                                                                                      ├── ComfyUI-QwenVL/
                                                                                                      ├── ComfyUI-QwenVL-Mod/
                                                                                                      ├── Civicomfy/
                                                                                                      ├── ComfyUI-RunpodDirect/
                                                                                                      └── comfyui-kb-tools/                 ← RB Tools panel
                                                                                                      ```
                                                                                                      
                                                                                                      ## Sin SageAttention
                                                                                                      
                                                                                                      ⚠️ **Importante**: Se REMOVIÓ la instalación de SageAttention debido a incompatibilidades con:
                                                                                                      - PyTorch 2.12 dev
                                                                                                      - - RTX 5090 (Blackwell sm_120)
                                                                                                       
                                                                                                        - **Alternativa recomendada:**
                                                                                                        - Usar `attention_mode: sdpa` en el WanVideo Sampler
                                                                                                        - - ✅ Funciona correctamente
                                                                                                          - - ✅ Calidad idéntica a SageAttention
                                                                                                            - - ✅ Solo un 5-10% más lento
                                                                                                             
                                                                                                              - ## Workflow: WAN 2.2 Animate
                                                                                                             
                                                                                                              - El workflow usa estos custom nodes:
                                                                                                             
                                                                                                              - | Nodo | Custom Node Pack |
                                                                                                              - |------|------------------|
                                                                                                              - | WanVideo Model Loader | ComfyUI-WanVideoWrapper |
                                                                                                              - | WanVideo VAE Loader | ComfyUI-WanVideoWrapper |
                                                                                                              - | WanVideo Torch Compile Settings | ComfyUI-WanVideoWrapper |
                                                                                                              - | WanVideo Animate Embeds | ComfyUI-WanVideoWrapper |
                                                                                                              - | WanAnimate Preprocess | **ComfyUI-WanAnimatePreprocess** |
                                                                                                              - | Resize Image v2 | ComfyUI-KJNodes |
                                                                                                              - | Load Video (Upload) | ComfyUI-VideoHelperSuite |
                                                                                                              - | Video Combine | ComfyUI-VideoHelperSuite |
                                                                                                              - | Sam2Segmentation | ComfyUI-segment-anything-2 |
                                                                                                              - | DownLoad SAM2Model | ComfyUI-segment-anything-2 |
                                                                                                              - | ONNX Detection Model Loader | ComfyUI-Impact-Pack |
                                                                                                              - | Grow Mask With Blur | ComfyUI nativo |
                                                                                                              - 
