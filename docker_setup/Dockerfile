# syntax=docker/dockerfile:1.7
###############################################################################
# ComfyUI + IPAdapter-FaceID — fully self-contained image
#
#   * ComfyUI, custom nodes and every Python dependency are baked into the image
#     at pinned versions. No reliance on any pre-populated / persistent volume.
#   * Large model weights are NOT baked in. They are downloaded on container
#     start by /opt/entrypoint.sh from the URLs in config/models.txt.
#
# Build:  docker build -t comfyui-faceid:latest .
# Run:    docker run --gpus all -p 8188:8188 -p 8080:8080 comfyui-faceid:latest
###############################################################################

ARG CUDA_IMAGE=nvidia/cuda:12.8.0-cudnn-runtime-ubuntu24.04
FROM ${CUDA_IMAGE}

# --- pinned versions (match the environment this was captured from) ----------
ARG COMFYUI_REF=b7ac98aafe41c8c8593b9f21238dab58a90424c6      # ComfyUI v0.26.2
ARG TORCH_VERSION=2.10.0
ARG TORCHVISION_VERSION=0.25.0
ARG TORCH_INDEX=https://download.pytorch.org/whl/cu128

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1 \
    COMFYUI_DIR=/opt/ComfyUI \
    VENV_DIR=/opt/venv \
    PATH=/opt/venv/bin:$PATH

# --- OS packages -----------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3.12 python3.12-venv python3.12-dev \
        git curl ca-certificates aria2 unzip \
        ffmpeg libgl1 libglib2.0-0 \
        build-essential \
    && rm -rf /var/lib/apt/lists/*

# --- Python venv + torch (pinned, cu128) --------------------------------
RUN python3.12 -m venv "${VENV_DIR}" \
    && pip install --upgrade pip wheel setuptools \
    && pip install --index-url "${TORCH_INDEX}" \
        "torch==${TORCH_VERSION}" \
        "torchvision==${TORCHVISION_VERSION}" \
        "torchaudio==${TORCH_VERSION}"

# --- ComfyUI + custom nodes -------------------------------------------
COPY scripts/install_comfyui.sh /tmp/install_comfyui.sh
COPY config/custom_nodes.txt    /tmp/custom_nodes.txt
RUN COMFYUI_REF="${COMFYUI_REF}" bash /tmp/install_comfyui.sh /tmp/custom_nodes.txt

# --- FaceID extras (insightface / onnxruntime CPU / ...) ---------------
COPY config/requirements-extra.txt /tmp/requirements-extra.txt
RUN pip install -r /tmp/requirements-extra.txt

# --- FileBrowser (started only when FILEBROWSER_ENABLE=1) --------------
RUN curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash

# --- Claude Code CLI --------------------------------------------------
# Native install (no Node needed); lands in /root/.local/bin. Symlink onto the
# default PATH so `docker exec <container> claude ...` just works. Auth via
# ANTHROPIC_API_KEY (or `claude login` in an interactive exec).
RUN curl -fsSL https://claude.ai/install.sh | bash \
    && ln -sf /root/.local/bin/claude /usr/local/bin/claude \
    && claude --version

# --- app files -------------------------------------------------------
COPY entrypoint.sh            /opt/entrypoint.sh
COPY scripts/download_models.sh /opt/download_models.sh
COPY config/models.txt        /opt/models.txt
COPY config/comfyui_args.txt  ${COMFYUI_DIR}/comfyui_args.txt
COPY workflows/              /opt/workflows/
COPY run_workflow.py         /opt/run_workflow.py
RUN chmod +x /opt/entrypoint.sh /opt/download_models.sh

WORKDIR ${COMFYUI_DIR}
EXPOSE 8188 8080

# No VOLUME is declared on purpose: by default the container is stateless and
# re-downloads weights each start. Mount your own volume at /opt/ComfyUI/models
# (and /opt/ComfyUI/output) if you want to cache them / keep results.

ENTRYPOINT ["/opt/entrypoint.sh"]
