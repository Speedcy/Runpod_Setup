# ============================================================
# ComfyUI + IPAdapter FaceID + InsightFace
# RunPod / RTX 2000 Ada / CUDA 12.8
# ============================================================

FROM runpod/comfyui:1.4.7-cuda12.8

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

WORKDIR /workspace/runpod-slim/ComfyUI

# ------------------------------------------------------------
# System dependencies
# ------------------------------------------------------------

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    wget \
    ca-certificates \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------
# Python dependencies
# ------------------------------------------------------------

RUN pip install --no-cache-dir \
    insightface==1.0.1 \
    onnxruntime==1.29.0

# ------------------------------------------------------------
# IPAdapter Plus
# ------------------------------------------------------------

RUN rm -rf custom_nodes/ComfyUI_IPAdapter_plus && \
    git clone --depth 1 \
    https://github.com/cubiq/ComfyUI_IPAdapter_plus.git \
    custom_nodes/ComfyUI_IPAdapter_plus

# Install custom-node-specific requirements if present
RUN if [ -f custom_nodes/ComfyUI_IPAdapter_plus/requirements.txt ]; then \
        pip install --no-cache-dir \
        -r custom_nodes/ComfyUI_IPAdapter_plus/requirements.txt; \
    fi

# ------------------------------------------------------------
# Required directories
# ------------------------------------------------------------

RUN mkdir -p \
    models/checkpoints \
    models/ipadapter \
    models/loras \
    models/clip_vision \
    models/insightface \
    input \
    output \
    user/default/workflows

# ------------------------------------------------------------
# Startup script
# ------------------------------------------------------------

COPY download_models.sh /download_models.sh
COPY startup.sh /startup.sh

RUN chmod +x /download_models.sh /startup.sh

# ------------------------------------------------------------
# Start
# ------------------------------------------------------------

ENTRYPOINT ["/startup.sh"]
