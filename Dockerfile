FROM nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1
ENV PIP_BREAK_SYSTEM_PACKAGES=1

# --- System deps ---
RUN apt-get update && apt-get install -y --no-install-recommends     python3 python3-pip python3-dev     git git-lfs wget curl ffmpeg     libgl1 libglib2.0-0 libsm6 libxext6 libxrender-dev     openssh-server     rclone     && ln -sf /usr/bin/python3 /usr/bin/python     && ln -sf /usr/bin/pip3 /usr/bin/pip     && rm -rf /var/lib/apt/lists/*

# --- Filebrowser ---
RUN curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash

# --- Jupyter ---
RUN pip install jupyterlab

# --- PyTorch nightly cu128 (Blackwell sm_120 support) ---
RUN pip install --pre torch torchvision torchaudio     --index-url https://download.pytorch.org/whl/nightly/cu128

# --- ComfyUI ---
ARG CACHE_DATE
WORKDIR /workspace
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git
WORKDIR /workspace/ComfyUI
RUN pip install -r requirements.txt

# --- Custom Nodes ---
WORKDIR /workspace/ComfyUI/custom_nodes
RUN git clone --depth 1 https://github.com/MoonGoblinDev/Civicomfy.git &&
    git clone --depth 1 https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git &&
    git clone --depth 1 https://github.com/yolain/ComfyUI-Easy-Use.git &&
    git clone --depth 1 https://github.com/kijai/ComfyUI-Florence2.git &&
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Impact-Pack.git &&
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Inspire-Pack.git &&
    git clone --depth 1 https://github.com/kijai/ComfyUI-KJNodes.git &&
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git &&
    git clone --depth 1 https://github.com/huchukato/ComfyUI-QwenVL-Mod.git &&
    git clone --depth 1 https://github.com/1038lab/ComfyUI-QwenVL.git &&
    git clone --depth 1 https://github.com/MadiatorLabs/ComfyUI-RunpodDirect.git &&
    git clone --depth 1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git &&
    git clone --depth 1 https://github.com/kijai/ComfyUI-segment-anything-2.git &&
    git clone --depth 1 https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes.git &&
    git clone --depth 1 https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git &&
    git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git &&
    git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git &&
    git clone --depth 1 https://github.com/Fannovel16/comfyui_controlnet_aux.git &&
    git clone --depth 1 https://github.com/jags111/efficiency-nodes-comfyui.git &&
    git clone --depth 1 https://github.com/rgthree/rgthree-comfy.git &&
    git clone --depth 1 https://github.com/WASasquatch/was-node-suite-comfyui.git

# --- Dependencias de custom nodes ---
RUN for dir in /workspace/ComfyUI/custom_nodes/*/; do         [ -f "$dir/requirements.txt" ] &&         pip install -r "$dir/requirements.txt" || true;     done

# --- KB Tools custom node ---
COPY comfyui-kb-tools/ /workspace/ComfyUI/custom_nodes/comfyui-kb-tools/
RUN chmod +x /workspace/ComfyUI/custom_nodes/comfyui-kb-tools/scripts/*.sh

# --- Script de inicio ---
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 8188 8888 8080
CMD ["/start.sh"]
