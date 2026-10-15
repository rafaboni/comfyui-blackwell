FROM nvidia/cuda:13.0.2-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1
ENV PIP_BREAK_SYSTEM_PACKAGES=1
# Repo al que "Update Nodes" (kb-tools) escribe el Dockerfile: el de ESTA imagen
ENV GITHUB_REPO=rafaboni/comfyui-blackwell

# --- Fix apt mirrors (use us.archive.ubuntu.com + retry on transient failures) ---
RUN sed -i 's|http://archive.ubuntu.com|https://us.archive.ubuntu.com|g' /etc/apt/sources.list && \
    echo "Acquire::Retries 5;" > /etc/apt/apt.conf.d/80retry

# --- System deps ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-dev \
    git git-lfs wget curl ffmpeg bc \
    libgl1 libglib2.0-0 libsm6 libxext6 libxrender-dev \
    openssh-server \
    rclone \
    && ln -sf /usr/bin/python3 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /root/.ssh \
    && chmod 700 /root/.ssh

# --- SSH public keys (Rafael's key for remote access) ---
COPY authorized_keys /root/.ssh/authorized_keys
RUN chmod 600 /root/.ssh/authorized_keys

# --- Filebrowser ---
RUN curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash || true

# --- Jupyter ---
RUN pip install jupyterlab

# --- PyTorch 2.14.1 estable cu130 (Blackwell sm_120: RTX 5090, RTX PRO; driver >= 580) ---
# Crear pods con --min-cuda-version 13.0.
# Se congela torch en /tmp/constraints.txt para que ningun requirements.txt lo cambie.
RUN pip install torch==2.14.1 torchvision torchaudio \
    --index-url https://download.pytorch.org/whl/cu130 && \
    pip freeze | grep -E '^(torch|torchvision|torchaudio)==' > /tmp/constraints.txt && \
    cat /tmp/constraints.txt
ENV PIP_CONSTRAINT=/tmp/constraints.txt

# --- ComfyUI (version fijada: H3 pide >=0.30, los workflows 10sorlabs usan nodos core de 0.35) ---
ARG CACHE_DATE
ARG COMFYUI_REF=v0.40.0
WORKDIR /comfyuiworkspace
RUN git clone --depth 1 --branch ${COMFYUI_REF} https://github.com/Comfy-Org/ComfyUI.git && \
    test -f ComfyUI/main.py || (echo "FATAL: ComfyUI/main.py not found!" && exit 1)
WORKDIR /comfyuiworkspace/ComfyUI
RUN pip install -r requirements.txt

# --- Custom Nodes ---
WORKDIR /comfyuiworkspace/ComfyUI/custom_nodes
RUN git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone --depth 1 https://github.com/MoonGoblinDev/Civicomfy.git && \
    git clone --depth 1 https://github.com/kijai/ComfyUI-KJNodes.git && \
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Impact-Pack.git && \
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Impact-Subpack.git && \
    git clone --depth 1 https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git && \
    git clone --depth 1 https://github.com/yolain/ComfyUI-Easy-Use.git && \
    git clone --depth 1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && \
    git clone --depth 1 https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git && \
    git clone --depth 1 https://github.com/jags111/efficiency-nodes-comfyui.git && \
    git clone --depth 1 https://github.com/rgthree/rgthree-comfy.git && \
    git clone --depth 1 https://github.com/1038lab/ComfyUI-QwenVL.git && \
    git clone --depth 1 https://github.com/huchukato/ComfyUI-QwenVL-Mod.git && \
    git clone --depth 1 https://github.com/MadiatorLabs/ComfyUI-RunpodDirect.git && \
    git clone --depth 1 https://github.com/kijai/ComfyUI-WanVideoWrapper.git && \
    git clone --depth 1 https://github.com/kijai/ComfyUI-segment-anything-2.git && \
    git clone --depth 1 https://github.com/kijai/ComfyUI-WanAnimatePreprocess.git && \
    git clone --depth 1 https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes.git && \
    git clone --depth 1 https://github.com/lbouaraba/comfyui-krea2edit.git && \
    git clone --depth 1 https://github.com/theUpsider/ComfyUI-Logic.git && \
    git clone --depth 1 https://github.com/Comfy-Org/Nvidia_RTX_Nodes_ComfyUI.git && \
    git clone --depth 1 https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git && \
    git clone --depth 1 https://github.com/evanspearman/ComfyMath.git
# --- Dependencias de custom nodes ---
# Bajo PIP_CONSTRAINT (torch congelado). Los fallos quedan en /comfyuiworkspace/node_deps_failed.txt.
# Reintento sin aislamiento de build: sam2 (Impact-Pack) choca con el constraint de torch dentro del entorno aislado.
# nvidia-vfx (Nvidia_RTX_Nodes) vive en pypi.nvidia.com.
RUN for dir in /comfyuiworkspace/ComfyUI/custom_nodes/*/; do \
    [ -f "$dir/requirements.txt" ] || continue; \
    pip install --extra-index-url https://pypi.nvidia.com -r "$dir/requirements.txt" \
      || pip install --no-build-isolation --extra-index-url https://pypi.nvidia.com -r "$dir/requirements.txt" \
      || echo "$dir" >> /comfyuiworkspace/node_deps_failed.txt; \
    done; \
    pip uninstall -y onnxruntime || true; \
    pip install onnxruntime-gpu || echo "onnxruntime-gpu" >> /comfyuiworkspace/node_deps_failed.txt; \
    python -c "import torch; print('torch', torch.__version__, 'cuda', torch.version.cuda)"; \
    cat /comfyuiworkspace/node_deps_failed.txt 2>/dev/null || echo "deps de nodes: sin fallos"

# --- rgthree: su parche de ejecucion recursiva rompe con ComfyUI 0.40 (execution.recursive_output_delete_if_changed ya no existe) ---
RUN printf '{\n  "patch_recursive_execution": false\n}\n' > /comfyuiworkspace/ComfyUI/custom_nodes/rgthree-comfy/rgthree_config.json

# --- MCP comfy-pod (:8190, lo arranca start.sh si hay MCP_TOKEN) ---
COPY comfy-pod-mcp/ /opt/comfy-pod-mcp/
RUN pip install -r /opt/comfy-pod-mcp/requirements.txt && chmod +x /opt/comfy-pod-mcp/run_mcp.sh

# --- KB Tools custom node ---
COPY comfyui-kb-tools/ /comfyuiworkspace/ComfyUI/custom_nodes/comfyui-kb-tools/
RUN chmod +x /comfyuiworkspace/ComfyUI/custom_nodes/comfyui-kb-tools/scripts/*.sh

# --- Script de inicio ---
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 8188 8888 8080 8190
CMD ["/start.sh"]
