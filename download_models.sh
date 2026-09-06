#!/bin/bash

set -e

COMFY="/workspace/runpod-slim/ComfyUI"

CHECKPOINT_DIR="$COMFY/models/checkpoints"
IPADAPTER_DIR="$COMFY/models/ipadapter"
LORA_DIR="$COMFY/models/loras"
CLIP_DIR="$COMFY/models/clip_vision"
INSIGHTFACE_DIR="$COMFY/models/insightface"

mkdir -p \
    "$CHECKPOINT_DIR" \
    "$IPADAPTER_DIR" \
    "$LORA_DIR" \
    "$CLIP_DIR" \
    "$INSIGHTFACE_DIR"

echo ""
echo "=========================================="
echo " Downloading ComfyUI models"
echo "=========================================="
echo ""

# ============================================================
# Helper
# ============================================================

download_file() {

    URL="$1"
    DEST="$2"

    if [ -f "$DEST" ]; then
        echo "[OK] Already present:"
        echo "     $DEST"
        return 0
    fi

    TMP="${DEST}.download"

    echo ""
    echo "[DOWNLOAD]"
    echo "$URL"
    echo "-> $DEST"
    echo ""

    wget \
        -c \
        --show-progress \
        --tries=5 \
        --timeout=30 \
        -O "$TMP" \
        "$URL"

    mv "$TMP" "$DEST"

    echo "[OK] Downloaded:"
    echo "$DEST"
}

# ============================================================
# 1. Juggernaut XL v9
# ============================================================

download_file \
"https://huggingface.co/RunDiffusion/Juggernaut-XL-v9/resolve/main/Juggernaut-XL_v9_RunDiffusionPhoto_v2.safetensors?download=true" \
"$CHECKPOINT_DIR/Juggernaut-XL_v9_RunDiffusionPhoto_v2.safetensors"


# ============================================================
# 2. IP-Adapter FaceID PlusV2 SDXL
# ============================================================

download_file \
"https://huggingface.co/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sdxl.bin?download=true" \
"$IPADAPTER_DIR/ip-adapter-faceid-plusv2_sdxl.bin"


# ============================================================
# 3. FaceID PlusV2 SDXL LoRA
# ============================================================

download_file \
"https://huggingface.co/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sdxl_lora.safetensors?download=true" \
"$LORA_DIR/ip-adapter-faceid-plusv2_sdxl_lora.safetensors"


# ============================================================
# 4. CLIP Vision ViT-H
# ============================================================

download_file \
"https://huggingface.co/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors?download=true" \
"$CLIP_DIR/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors"


# ============================================================
# 5. InsightFace buffalo_l
# ============================================================

BUFFALO_DIR="$INSIGHTFACE_DIR/buffalo_l"
BUFFALO_ZIP="$INSIGHTFACE_DIR/buffalo_l.zip"

if [ -d "$BUFFALO_DIR" ] && [ -f "$BUFFALO_DIR/det_10g.onnx" ]; then

    echo ""
    echo "[OK] InsightFace buffalo_l already installed."

else

    echo ""
    echo "=========================================="
    echo " Downloading InsightFace buffalo_l"
    echo "=========================================="

    rm -rf "$BUFFALO_DIR"

    wget \
        -c \
        --show-progress \
        --tries=5 \
        --timeout=30 \
        -O "$BUFFALO_ZIP" \
        "https://github.com/deepinsight/insightface/releases/download/v0.7/buffalo_l.zip"

    mkdir -p "$INSIGHTFACE_DIR"

    unzip -o "$BUFFALO_ZIP" \
        -d "$INSIGHTFACE_DIR"

    rm -f "$BUFFALO_ZIP"

fi


# ============================================================
# Final verification
# ============================================================

echo ""
echo "=========================================="
echo " Model verification"
echo "=========================================="
echo ""

REQUIRED_FILES=(

"$CHECKPOINT_DIR/Juggernaut-XL_v9_RunDiffusionPhoto_v2.safetensors"

"$IPADAPTER_DIR/ip-adapter-faceid-plusv2_sdxl.bin"

"$LORA_DIR/ip-adapter-faceid-plusv2_sdxl_lora.safetensors"

"$CLIP_DIR/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors"

"$INSIGHTFACE_DIR/buffalo_l/det_10g.onnx"

)

for FILE in "${REQUIRED_FILES[@]}"; do

    if [ ! -f "$FILE" ]; then
        echo "[ERROR] Missing:"
        echo "$FILE"
        exit 1
    fi

    SIZE=$(du -h "$FILE" | cut -f1)

    echo "[OK] $SIZE  $FILE"

done

echo ""
echo "All required models are available."
echo ""
