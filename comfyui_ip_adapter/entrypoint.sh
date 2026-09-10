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
#   JUPYTER_TOKEN                access token for JupyterLab (recommended). With a
#                               token, RunPod's "Connect" badge for :8888 stays
#                               on "Initializing" by design (its readiness probe
#                               wants a 200 on `/`, JupyterLab redirects to a
#                               login) — this is cosmetic, the port works: open
#                               the printed https://<pod>-8888...&/lab?token=URL.
#                               Empty = no auth (badge goes green, but anyone
#                               with the proxy URL gets a root shell).
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
    JUPYTER_ROOT="${JUPYTER_ROOT:-$COMFYUI_DIR}"
    mkdir -p "$JUPYTER_ROOT"

    # Auth mode vs. RunPod's port-readiness probe (see the header comment):
    #   token set  -> `GET /` redirects to the login page; RunPod's probe wants a
    #                 200 there, so the :8888 "Connect" badge stays "Initializing".
    #                 Cosmetic — the proxy works, reach it via the ?token= URL
    #                 printed below.
    #   token empty -> `GET /` resolves to `/lab` (200), badge goes green, but the
    #                 unguessable proxy URL is then the ONLY thing protecting a
    #                 root shell.
    AUTH_ARGS=(--ServerApp.token="$JUPYTER_TOKEN" --ServerApp.password='')
    JUPYTER_URL="https://${RUNPOD_POD_ID:-<podid>}-8888.proxy.runpod.net/lab"
    if [ -z "$JUPYTER_TOKEN" ]; then
        AUTH_ARGS+=(--ServerApp.disable_check_xsrf=True)
        echo "!! JupyterLab: NO TOKEN — anyone with $JUPYTER_URL gets a root shell"
    else
        echo "-- JupyterLab: token set — RunPod's :8888 badge stays 'Initializing' (cosmetic)."
        echo "   Open: ${JUPYTER_URL}?token=${JUPYTER_TOKEN}"
    fi

    echo "-- JupyterLab on :8888  (root=$JUPYTER_ROOT)"
    # allow_origin/trust_xheaders: required behind RunPod's reverse proxy, whose
    # public domain differs from what the server sees internally — without
    # these, jupyter_server's Origin check 403s the terminal/kernel websockets.
    nohup jupyter lab \
        --ip=0.0.0.0 --port=8888 --no-browser --allow-root \
        --ServerApp.root_dir="$JUPYTER_ROOT" \
        --ServerApp.allow_origin='*' \
        --ServerApp.allow_remote_access=True \
        --ServerApp.trust_xheaders=True \
        "${AUTH_ARGS[@]}" \
        >/var/log/jupyterlab.log 2>&1 &
    JUPYTER_PID=$!

    # Health-check: on a startup crash, dump the log to *stdout* (the RunPod pod
    # log) so the cause is visible without a shell into the container.
    jupyter_ok=0
    for _ in $(seq 1 30); do
        if ! kill -0 "$JUPYTER_PID" 2>/dev/null; then
            echo "!! JupyterLab exited during startup — /var/log/jupyterlab.log follows:"
            sed 's/^/   jupyter| /' /var/log/jupyterlab.log 2>/dev/null || true
            break
        fi
        code="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8888/lab 2>/dev/null || true)"
        if [ -n "$code" ] && [ "$code" != "000" ]; then
            jupyter_ok=1
            echo "-- JupyterLab is serving on :8888 (pid $JUPYTER_PID, GET /lab -> HTTP $code)"
            break
        fi
        sleep 1
    done
    [ "$jupyter_ok" = 1 ] || echo "!! JupyterLab not answering on :8888 after 30s — see /var/log/jupyterlab.log"
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
# The container disk is not persistent, so $COMFYUI_DIR/user/default/workflows/
# is empty on every fresh pod and must be repopulated here, before ComfyUI
# starts and scans that folder.
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
