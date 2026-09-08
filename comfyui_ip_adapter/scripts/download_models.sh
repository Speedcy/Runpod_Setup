#!/usr/bin/env bash
###############################################################################
# Runtime helper: read the model manifest and fetch anything missing into
# $COMFYUI_DIR/models. Idempotent — valid existing files are skipped, so it is
# cheap to run on every container start.
#
# Env:
#   MODELS_FILE      manifest path                 (default /opt/models.txt)
#   COMFYUI_DIR      ComfyUI root                  (default /opt/ComfyUI)
#   HF_TOKEN         bearer token for gated repos  (optional)
#   STRICT_SHA256=1  checksum mismatch is fatal    (default: warn and keep file)
#   ARIA2_CONN       connections per download      (default 8)
###############################################################################
set -uo pipefail

: "${COMFYUI_DIR:=/opt/ComfyUI}"
: "${MODELS_FILE:=/opt/models.txt}"
: "${ARIA2_CONN:=8}"
MODELS_ROOT="$COMFYUI_DIR/models"

sha_of() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

fetch() {   # fetch <url> <output-file>
    local url="$1" out="$2" dir base
    dir="$(dirname "$out")"; base="$(basename "$out")"
    mkdir -p "$dir"
    if command -v aria2c >/dev/null 2>&1; then
        local hdr=()
        [ -n "${HF_TOKEN:-}" ] && hdr=(--header="Authorization: Bearer ${HF_TOKEN}")
        aria2c -x"$ARIA2_CONN" -s"$ARIA2_CONN" -k1M --file-allocation=none \
               --console-log-level=warn --summary-interval=20 --allow-overwrite=true \
               "${hdr[@]}" -d "$dir" -o "$base" "$url"
    else
        local hdr=()
        [ -n "${HF_TOKEN:-}" ] && hdr=(-H "Authorization: Bearer ${HF_TOKEN}")
        curl -fL --retry 3 --retry-delay 5 "${hdr[@]}" -o "$out" "$url"
    fi
}

rc=0
while IFS='|' read -r dest url sha || [ -n "${dest:-}" ]; do
    dest="$(echo "${dest:-}" | xargs)"
    url="$(echo "${url:-}"  | xargs)"
    sha="$(echo "${sha:-}"  | xargs)"
    [ -z "$dest" ] && continue
    case "$dest" in \#*) continue ;; esac

    target="$MODELS_ROOT/$dest"

    # ---- zip archive: extract into <dest> treated as a directory ----------
    if [[ "$url" == *.zip ]]; then
        if [ -d "$target" ] && [ -n "$(ls -A "$target" 2>/dev/null)" ]; then
            echo "== skip (present)  $dest/"
            continue
        fi
        echo "== fetch           $dest/   <- $url"
        tmp="/tmp/$(basename "$url")"
        if ! fetch "$url" "$tmp"; then echo "!! download failed: $url"; rc=1; continue; fi
        mkdir -p "$target"
        unzip -o -q "$tmp" -d "$target" && rm -f "$tmp"
        continue
    fi

    # ---- regular file --------------------------------------------------
    if [ -f "$target" ]; then
        if [ -z "$sha" ] || [ "$sha" = "-" ]; then
            echo "== skip (present)  $dest"
            continue
        fi
        if [ "$(sha_of "$target")" = "$sha" ]; then
            echo "== skip (sha ok)   $dest"
            continue
        fi
        echo "!! stale/partial, re-downloading  $dest"
        rm -f "$target"
    fi

    echo "== fetch           $dest   <- $url"
    if ! fetch "$url" "$target"; then echo "!! download failed: $url"; rc=1; continue; fi

    if [ -n "$sha" ] && [ "$sha" != "-" ]; then
        got="$(sha_of "$target")"
        if [ "$got" != "$sha" ]; then
            echo "!! SHA256 MISMATCH  $dest"
            echo "     expected  $sha"
            echo "     got       $got"
            if [ "${STRICT_SHA256:-0}" = "1" ]; then rm -f "$target"; rc=1; fi
        fi
    fi
done < "$MODELS_FILE"

if [ "$rc" -ne 0 ]; then
    echo "!! one or more model downloads had problems (rc=$rc)"
fi
exit "$rc"
