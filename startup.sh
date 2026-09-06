#!/bin/bash

set -e

COMFY="/workspace/runpod-slim/ComfyUI"

echo ""
echo "=========================================="
echo " ComfyUI RunPod environment"
echo "=========================================="
echo ""

cd "$COMFY"


# ============================================================
# GPU / PyTorch diagnostic
# ============================================================

echo "Python:"
python3 --version

echo ""
echo "PyTorch / CUDA:"

python3 - <<'PY'
import torch

print("PyTorch:", torch.__version__)
print("CUDA compiled:", torch.version.cuda)
print("CUDA available:", torch.cuda.is_available())

if torch.cuda.is_available():
    print("GPU:", torch.cuda.get_device_name(0))
    print(
        "VRAM:",
        round(torch.cuda.get_device_properties(0).total_memory / 1024**3, 2),
        "GB"
    )
PY


# ============================================================
# InsightFace diagnostic
# ============================================================

echo ""
echo "InsightFace:"

python3 - <<'PY'
import insightface
import onnxruntime

print("InsightFace:", insightface.__version__)
print("ONNX Runtime:", onnxruntime.__version__)
print(
    "ONNX providers:",
    onnxruntime.get_available_providers()
)
PY


# ============================================================
# Download models if necessary
# ============================================================

/download_models.sh


# ============================================================
# Final environment check
# ============================================================

echo ""
echo "=========================================="
echo " Environment ready"
echo "=========================================="
echo ""

echo "ComfyUI:"
echo "$COMFY"

echo ""
echo "IPAdapter:"
ls -lh "$COMFY/models/ipadapter"

echo ""
echo "LoRA:"
ls -lh "$COMFY/models/loras"

echo ""
echo "CLIP Vision:"
ls -lh "$COMFY/models/clip_vision"

echo ""
echo "Checkpoint:"
ls -lh "$COMFY/models/checkpoints"

echo ""
echo "InsightFace:"
find "$COMFY/models/insightface/buffalo_l" \
    -maxdepth 1 \
    -type f \
    -printf "%f\n" \
    2>/dev/null || true


# ============================================================
# Start ComfyUI
# ============================================================

echo ""
echo "=========================================="
echo " Starting ComfyUI"
echo "=========================================="
echo ""

exec python3 main.py \
    --listen 0.0.0.0 \
    --port 8188

