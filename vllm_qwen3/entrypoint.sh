#!/usr/bin/env bash
###############################################################################
# Container entrypoint: exec `vllm serve` with tool-calling/reasoning enabled
# for Qwen3.8-27B, exposing an OpenAI-compatible API.
#
# Env knobs:
#   MODEL_ID                     HF repo to serve            (default Qwen/Qwen3.8-27B)
#   VLLM_HOST / VLLM_PORT        bind address / port          (default 0.0.0.0 / 8000)
#   GPU_MEMORY_UTILIZATION       vLLM weight+KV-cache budget  (default 0.90)
#   MAX_MODEL_LEN                context cap; empty = model default (262144).
#                                 Lower this on VRAM-constrained GPUs.
#   QUANTIZATION                 empty = bf16; e.g. "fp8" for ~48GB-class GPUs
#   KV_CACHE_DTYPE                empty = default; e.g. "fp8" (pair with QUANTIZATION=fp8)
#   TENSOR_PARALLEL_SIZE          GPU shard count               (default 1)
#   VLLM_API_KEY                  bearer key required by clients. REQUIRED in
#                                 practice: the pod is reachable over RunPod's
#                                 public proxy, so this is the only thing
#                                 stopping a stranger from using your GPU /
#                                 seeing your prompts. Warns loudly if unset.
#   HF_TOKEN                     passed through, for gated HF repos
#   VLLM_EXTRA_ARGS               extra args appended after everything else
#   SKIP_TOOL_CALLING=1           escape hatch: drop the tool-calling/reasoning
#                                 flags below (should not normally be needed)
#
# Fixed (not overridable): --enable-auto-tool-choice --tool-call-parser
# qwen3_coder --reasoning-parser qwen3 — this is the whole point of the image.
###############################################################################
set -euo pipefail

: "${MODEL_ID:=Qwen/Qwen3.8-27B}"
: "${VLLM_HOST:=0.0.0.0}"
: "${VLLM_PORT:=8000}"
: "${GPU_MEMORY_UTILIZATION:=0.90}"
: "${TENSOR_PARALLEL_SIZE:=1}"

echo "=================== vLLM OpenAI-compatible server ==================="
echo "-- model:  $MODEL_ID"
echo "-- listen: $VLLM_HOST:$VLLM_PORT"

if [ -z "${VLLM_API_KEY:-}" ]; then
    echo "!! VLLM_API_KEY is empty — the OpenAI-compatible endpoint will be OPEN to anyone who can reach the port"
fi

# --- extra args from the baked-in file (mirrors comfyui_args.txt) ----------
ARGS_FILE=/opt/vllm_args.txt
FILE_ARGS=""
# `|| true`: grep exits 1 when the file is all comments/blank (the default), and
# `set -o pipefail` would otherwise make that abort the whole entrypoint.
if [ -s "$ARGS_FILE" ]; then
    FILE_ARGS="$(grep -vE '^\s*#' "$ARGS_FILE" | tr '\n' ' ' || true)"
fi

TOOL_ARGS="--enable-auto-tool-choice --tool-call-parser qwen3_coder --reasoning-parser qwen3"
if [ "${SKIP_TOOL_CALLING:-0}" = "1" ]; then
    echo "!! SKIP_TOOL_CALLING=1 — tool calling / reasoning parsing is DISABLED"
    TOOL_ARGS=""
fi

echo "-- exec: vllm serve $MODEL_ID --host $VLLM_HOST --port $VLLM_PORT ..."
echo "================================================================"
exec vllm serve "$MODEL_ID" \
    --host "$VLLM_HOST" --port "$VLLM_PORT" \
    --gpu-memory-utilization "$GPU_MEMORY_UTILIZATION" \
    --tensor-parallel-size "$TENSOR_PARALLEL_SIZE" \
    ${MAX_MODEL_LEN:+--max-model-len "$MAX_MODEL_LEN"} \
    ${QUANTIZATION:+--quantization "$QUANTIZATION"} \
    ${KV_CACHE_DTYPE:+--kv-cache-dtype "$KV_CACHE_DTYPE"} \
    ${VLLM_API_KEY:+--api-key "$VLLM_API_KEY"} \
    $TOOL_ARGS $FILE_ARGS ${VLLM_EXTRA_ARGS:-}
