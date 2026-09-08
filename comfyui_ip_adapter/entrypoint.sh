#!/usr/bin/env bash
###############################################################################
# Container entrypoint:
#   1. (optional) start FileBrowser on :8080
#   2. download any missing model weights (config/models.txt)
#   3. exec ComfyUI on :8188
#
# Env knobs:
#   COMFY_HOST / COMFY_PORT      bind address / port     (default 0.0.0.0 / 8188)
#   COMFY_EXTRA_ARGS             extra args appended to `python main.py ...`
#   SKIP_MODEL_DOWNLOAD=1        do not fetch models this start
#   DOWNLOAD_IN_BACKGROUND=1     fetch models in background; start server now
#   FILEBROWSER_ENABLE=1         run FileBrowser (FB_USER / FB_PASS, default admin/admin)
#   JUPYTER_ENABLE=1             run JupyterLab on :8888
#   JUPYTER_TOKEN                access token for JupyterLab (empty = no auth, unsafe)
#   JUPYTER_ROOT                 JupyterLab root dir (default: $COMFYUI_DIR)
#   HF_TOKEN / STRICT_SHA256     passed through to download_models.sh
###############################################################################
set -euo pipefail

: "${COMFYUI_DIR:=/opt/ComfyUI}"
: "${COMFY_HOST:=0.0.0.0}"
: "${COMFY_PORT:=8188}"
ARGS_FILE="$COMFYUI_DIR/comfyui_args.txt"

echo "=================== ComfyUI + FaceID container ==================="
python -c "import torch; print('torch', torch.__version__, '| cuda available:', torch.cuda.is_available())" || true

# seed the reference image(s) shipped with the workflows
cp -n /opt/workflows/*.png "$COMFYUI_DIR/input/" 2>/dev/null || true

# --- 1. FileBrowser (optional) ----------------------------------------
if [ "${FILEBROWSER_ENABLE:-0}" = "1" ]; then
    echo "-- FileBrowser on :8080  (user=${FB_USER:-admin})"
    FBDB=/tmp/filebrowser.db
    filebrowser config init -d "$FBDB"                                   >/dev/null 2>&1 || true
    filebrowser config set  -d "$FBDB" --address 0.0.0.0 --port 8080 \
        --root "$COMFYUI_DIR" --auth.method=json                         >/dev/null 2>&1 || true
    filebrowser users add "${FB_USER:-admin}" "${FB_PASS:-admin}" -d "$FBDB" --perm.admin \
        >/dev/null 2>&1 \
      || filebrowser users update "${FB_USER:-admin}" --password "${FB_PASS:-admin}" -d "$FBDB" \
        >/dev/null 2>&1 || true
    nohup filebrowser -d "$FBDB" >/var/log/filebrowser.log 2>&1 &
fi

# --- 1b. JupyterLab (optional) ------------------------------------------
if [ "${JUPYTER_ENABLE:-0}" = "1" ]; then
    JUPYTER_TOKEN="${JUPYTER_TOKEN:-}"
    if [ -z "$JUPYTER_TOKEN" ]; then
        echo "!! JUPYTER_ENABLE=1 but JUPYTER_TOKEN is empty — JupyterLab will be OPEN to anyone who can reach :8888"
    fi
    echo "-- JupyterLab on :8888  (root=${JUPYTER_ROOT:-$COMFYUI_DIR})"
    nohup jupyter lab \
        --ip=0.0.0.0 --port=8888 --no-browser --allow-root \
        --ServerApp.token="$JUPYTER_TOKEN" \
        --ServerApp.password='' \
        --ServerApp.root_dir="${JUPYTER_ROOT:-$COMFYUI_DIR}" \
        >/var/log/jupyterlab.log 2>&1 &
fi

# --- 2. models ------------------------------------------------------
if [ "${SKIP_MODEL_DOWNLOAD:-0}" = "1" ]; then
    echo "-- SKIP_MODEL_DOWNLOAD=1 — not fetching models"
elif [ "${DOWNLOAD_IN_BACKGROUND:-0}" = "1" ]; then
    echo "-- fetching models in background (server starts immediately;"
    echo "   a run will fail until the weights it needs have landed)"
    nohup /opt/download_models.sh >/var/log/download_models.log 2>&1 &
else
    echo "-- fetching models (first run downloads ~12 GB, be patient)"
    /opt/download_models.sh || echo "!! continuing despite download issues"
fi

# --- 3. seed bundled workflows into the ComfyUI "Workflows" menu -------
# The persistent RunPod volume is mounted at $COMFYUI_DIR/models only, so
# $COMFYUI_DIR/user/default/workflows/ is empty on every fresh pod and must be
# repopulated here, before ComfyUI starts and scans that folder.
#
# Safety: we never clobber a workflow the user created/edited in the UI. A file
# that already exists at the destination is kept as-is; only missing files are
# copied. Every decision is logged so it is visible in the pod boot logs.
WF_SRC=/opt/workflows
WF_DEST="$COMFYUI_DIR/user/default/workflows"
if compgen -G "$WF_SRC/*.json" >/dev/null; then
    mkdir -p "$WF_DEST"
    wf_total=0
    for wf in "$WF_SRC"/*.json; do
        name="$(basename "$wf")"
        wf_total=$((wf_total + 1))
        if [ -e "$WF_DEST/$name" ]; then
            echo "   - kept existing user copy, not overwritten: $name"
        else
            cp "$wf" "$WF_DEST/$name"
            echo "   - copied: $name"
        fi
    done
    echo "-- Loaded $wf_total workflow(s) into ComfyUI menu"
else
    echo "-- no bundled workflows found in $WF_SRC, nothing to load"
fi

# --- 4. ComfyUI ---------------------------------------------------
cd "$COMFYUI_DIR"
EXTRA_ARGS=""
# `|| true`: grep exits 1 when the file is all comments/blank (the default), and
# `set -o pipefail` would otherwise make that abort the whole entrypoint.
if [ -s "$ARGS_FILE" ]; then
    EXTRA_ARGS="$(grep -vE '^\s*#' "$ARGS_FILE" | tr '\n' ' ' || true)"
fi

echo "-- exec: python main.py --listen $COMFY_HOST --port $COMFY_PORT --enable-cors-header $EXTRA_ARGS ${COMFY_EXTRA_ARGS:-}"
echo "================================================================"
exec python main.py --listen "$COMFY_HOST" --port "$COMFY_PORT" --enable-cors-header \
     $EXTRA_ARGS ${COMFY_EXTRA_ARGS:-}
