# syntax=docker/dockerfile:1.7
###############################################################################
# vLLM OpenAI-compatible server — Qwen3.8-27B
#
#   * Built on the official prebuilt vllm/vllm-openai image (pinned tag), no
#     from-source build needed.
#   * The model itself is NOT baked in. vLLM downloads it from Hugging Face
#     (MODEL_ID) into its HF cache on first start; a volume mounted at
#     /root/.cache/huggingface is an optional cache, never a requirement.
#   * This server only ever answers OpenAI-compatible chat-completion /
#     tool-calling requests. It never mounts or touches any local
#     filesystem/repo — that stays entirely on the machine running the
#     coding agent (see README).
#
# Build:  docker build -t vllm-qwen3:latest .
# Run:    docker run --gpus all -p 8000:8000 -e VLLM_API_KEY=changeme vllm-qwen3:latest
###############################################################################

ARG VLLM_IMAGE=vllm/vllm-openai:v0.29.0-cu129
FROM ${VLLM_IMAGE}

ENV MODEL_ID=Qwen/Qwen3.8-27B \
    VLLM_HOST=0.0.0.0 \
    VLLM_PORT=8000 \
    GPU_MEMORY_UTILIZATION=0.90 \
    TENSOR_PARALLEL_SIZE=1

COPY entrypoint.sh          /opt/entrypoint.sh
COPY config/vllm_args.txt   /opt/vllm_args.txt
RUN chmod +x /opt/entrypoint.sh

EXPOSE 8000

# No VOLUME is declared on purpose: by default the container is stateless and
# re-downloads the model from Hugging Face each start. Mount your own volume
# at /root/.cache/huggingface to cache it across restarts.

ENTRYPOINT ["/opt/entrypoint.sh"]
