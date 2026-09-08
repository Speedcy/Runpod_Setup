#!/usr/bin/env bash
###############################################################################
# Build-time helper: clone ComfyUI at a pinned commit, install its
# requirements, then clone + install every custom node from custom_nodes.txt.
###############################################################################
set -euo pipefail

: "${COMFYUI_DIR:=/opt/ComfyUI}"
: "${COMFYUI_REF:?set COMFYUI_REF (a ComfyUI git commit or tag)}"
NODES_FILE="${1:-/tmp/custom_nodes.txt}"

echo ">> ComfyUI $COMFYUI_REF -> $COMFYUI_DIR"
git clone --filter=blob:none https://github.com/comfyanonymous/ComfyUI.git "$COMFYUI_DIR"
git -C "$COMFYUI_DIR" checkout --detach "$COMFYUI_REF"
pip install -r "$COMFYUI_DIR/requirements.txt"

mkdir -p "$COMFYUI_DIR/custom_nodes"
cd "$COMFYUI_DIR/custom_nodes"

while IFS='|' read -r url ref || [ -n "${url:-}" ]; do
    url="$(echo "${url:-}" | xargs)"
    ref="$(echo "${ref:-}" | xargs)"
    [ -z "$url" ] && continue
    case "$url" in \#*) continue ;; esac

    name="$(basename "$url" .git)"
    echo ">> custom node: $name @ ${ref:-HEAD}"
    git clone --filter=blob:none "$url" "$name"
    if [ -n "$ref" ]; then
        git -C "$name" checkout --detach "$ref"
    fi
    if [ -f "$name/requirements.txt" ]; then
        pip install -r "$name/requirements.txt"
    fi
done < "$NODES_FILE"

# Model / IO folders the workflow expects (download_models.sh fills these).
mkdir -p \
    "$COMFYUI_DIR"/models/checkpoints \
    "$COMFYUI_DIR"/models/loras \
    "$COMFYUI_DIR"/models/vae \
    "$COMFYUI_DIR"/models/clip_vision \
    "$COMFYUI_DIR"/models/ipadapter \
    "$COMFYUI_DIR"/models/controlnet \
    "$COMFYUI_DIR"/models/insightface/models \
    "$COMFYUI_DIR"/input \
    "$COMFYUI_DIR"/output

echo ">> install_comfyui.sh done"
