# vLLM OpenAI-compatible server — Qwen3.8-27B

Self-contained image that serves [`Qwen/Qwen3.8-27B`](https://huggingface.co/Qwen/Qwen3.8-27B)
through [vLLM](https://github.com/vllm-project/vllm)'s OpenAI-compatible API, with
tool calling and reasoning parsing enabled. Built for a **local-code /
remote-GPU** coding-agent setup: the coding agent (e.g.
[OpenCode](https://opencode.ai)) runs entirely on your own machine — repo,
files, and every tool it uses (read/write/edit/bash/grep/git/tests) stay
local — while only the LLM itself runs on a RunPod GPU pod behind this
server. See [Architecture & security model](#architecture--security-model)
below.

## Contents

```
vllm_qwen3/
├── Dockerfile              image definition (pinned vllm/vllm-openai base)
├── docker-compose.yml      local convenience runner (GPU, port, optional HF cache volume)
├── entrypoint.sh           builds and execs the `vllm serve` command
├── .dockerignore
├── config/
│   └── vllm_args.txt       extra vLLM CLI flags, baked in
└── opencode.example.json   copy-paste OpenCode provider config
```

## Build

```bash
cd vllm_qwen3
docker build -t vllm-qwen3:latest .
```

Pinned by build arg (override with `--build-arg`):

| arg | default | meaning |
|-----|---------|---------|
| `VLLM_IMAGE` | `vllm/vllm-openai:v0.29.0-cu129` | prebuilt vLLM base image (vLLM + torch + CUDA 12.9 baked in) |

The model itself is **not** baked into the image — it's downloaded from
Hugging Face on first start (`MODEL_ID`). No custom weight manifest is
needed here (unlike `comfyui_ip_adapter`): vLLM's own `huggingface_hub`
downloader handles it.

## Run locally

```bash
docker compose up --build
```

or plain docker:

```bash
docker run --gpus all -p 8000:8000 \
  -e VLLM_API_KEY=changeme \
  -v hf_cache:/root/.cache/huggingface \
  vllm-qwen3:latest
```

**GPU sizing.** `Qwen/Qwen3.8-27B` is a dense 27B model — BF16 weights alone
are ~54GB, so a full-precision run needs an **80GB-class GPU** (A100/H100).
For a ~48GB-class GPU (L40S/A6000), set `QUANTIZATION=fp8` and
`KV_CACHE_DTYPE=fp8` to fit weights (~27GB) plus KV-cache headroom. Native
context is 262,144 tokens; lower `MAX_MODEL_LEN` if VRAM is tight.

First start downloads the model (tens of GB, progress in the container log),
then the API server boots. Mounting a volume at `/root/.cache/huggingface`
caches it so later starts are instant. **No volume is required** — without
one, the model is re-downloaded each start.

### Runtime env vars

| var | default | effect |
|---|---|---|
| `MODEL_ID` | `Qwen/Qwen3.8-27B` | HF repo to serve |
| `VLLM_HOST` / `VLLM_PORT` | `0.0.0.0` / `8000` | bind address / port |
| `GPU_MEMORY_UTILIZATION` | `0.90` | vLLM weight+KV-cache budget |
| `MAX_MODEL_LEN` | – (model default, 262144) | context cap; lower on VRAM-constrained GPUs |
| `QUANTIZATION` | – (bf16) | e.g. `fp8` for ~48GB-class GPUs |
| `KV_CACHE_DTYPE` | – | e.g. `fp8` (pair with `QUANTIZATION=fp8`) |
| `TENSOR_PARALLEL_SIZE` | `1` | GPU shard count for multi-GPU pods |
| `VLLM_API_KEY` | – | bearer key required by clients — **set this**, see below |
| `HF_TOKEN` | – | bearer token for gated Hugging Face repos |
| `VLLM_EXTRA_ARGS` | – | extra args appended at runtime, no rebuild needed |
| `SKIP_TOOL_CALLING` | `0` | `1` → drop the tool-calling/reasoning flags (should not normally be needed) |

`VLLM_API_KEY` is not just a convenience: once deployed on RunPod the
endpoint is reachable over the public proxy URL, so this is the only thing
stopping a stranger from using your GPU or seeing your prompts. The
entrypoint prints a loud warning on boot if it's unset.

## Deploy on RunPod

RunPod runs a **prebuilt image** pulled from a registry — it does not build
the Dockerfile for you. Flow: **build → push → template → pod**. (Same GHCR
flow as `comfyui_ip_adapter`; see that folder's README for the full
`docker login ghcr.io` / PAT walkthrough if you need it.)

```bash
cd vllm_qwen3
docker build -t ghcr.io/YOUR_GITHUB_USERNAME/vllm-qwen3:latest .
docker push ghcr.io/YOUR_GITHUB_USERNAME/vllm-qwen3:latest
```

Or just push to `main` — `.github/workflows/push_vllm_qwen3.yml` builds and
pushes `ghcr.io/speedcy/vllm-qwen3:latest` automatically on any change under
`vllm_qwen3/**`.

### Create a template

Console → **Templates → New Template**:

| Field | Value |
|-------|-------|
| Container Image | `ghcr.io/speedcy/vllm-qwen3:latest` |
| Container Disk | `80 GB`+ (image ~15GB + model weights, ~55GB BF16 / ~30GB FP8) |
| Expose HTTP Ports | `8000` |
| Docker Command | *leave empty* — uses the image `ENTRYPOINT` |

Environment variables:

| var | value | why |
|---|---|---|
| `VLLM_API_KEY` | *your choice* | required — see above |
| `QUANTIZATION` | `fp8` (only if on a ~48GB-class GPU) | fits weights in less VRAM |
| `KV_CACHE_DTYPE` | `fp8` (pair with the above) | frees more VRAM for KV cache |
| `HF_TOKEN` | *only if the repo is gated* | |

If `8000` isn't listed in **Expose HTTP Ports**, RunPod never opens an HTTP
proxy for it and the "Connect" panel will show the service stuck on
"Initializing" even though it's running fine inside the container.

### Deploy a pod

**Pods → Deploy** → pick a GPU with **80GB VRAM** (A100/H100) for BF16, or
**48GB** (L40S/A6000) with `QUANTIZATION=fp8` → select your template →
deploy On-Demand or Spot.

### Connect

Pod → **Connect → HTTP Service [Port 8000]** →
`https://<podid>-8000.proxy.runpod.net` is your OpenAI-compatible base URL
(append `/v1`). Verify it's up:

```bash
curl https://<podid>-8000.proxy.runpod.net/v1/models \
  -H "Authorization: Bearer $VLLM_API_KEY"
```

**Stopping** the pod wipes the container disk (image, downloaded weights)
unless you attached a persistent volume at `/root/.cache/huggingface` — a
fresh pod re-downloads the model.

## Architecture & security model

```
┌─────────────────────── your Ubuntu machine ───────────────────────┐
│  OpenCode (local process)                                         │
│    - repo / files                     ← never leave this machine  │
│    - tools: read, write, edit, bash,                              │
│      grep, git, tests, python, ...    ← executed locally          │
│    - sends only chat-completion /                                 │
│      tool-calling JSON over HTTPS ──┐                              │
└──────────────────────────────────────┼─────────────────────────────┘
                                        │  /v1/chat/completions
                                        ▼
┌───────────────────────── RunPod GPU pod ───────────────────────────┐
│  this image: vLLM serving Qwen3.8-27B                              │
│    - no volume/mount of your repo or filesystem                    │
│    - never executes any OpenCode tool                              │
│    - only ever sees/returns prompt + completion JSON               │
└──────────────────────────────────────────────────────────────────┘
```

The remote pod is deliberately dumb: it has no code, no bash access to your
project, and no way to touch anything outside its own container. It answers
one thing — OpenAI-compatible chat/completions with tool-call and reasoning
output — and nothing else. All tool *execution* (the actual `read`/`write`/
`bash`/`git` calls the model asks for) happens inside OpenCode, locally.

## Configure OpenCode (local machine)

1. Copy [`opencode.example.json`](opencode.example.json) to
   `~/.config/opencode/opencode.json` (global) or `opencode.json` in your
   project root (project-local), and edit `baseURL` to your pod's actual
   proxy hostname:

   ```json
   {
     "$schema": "https://opencode.ai/config.json",
     "provider": {
       "runpod-qwen3": {
         "npm": "@ai-sdk/openai-compatible",
         "name": "RunPod Qwen3.8-27B (vLLM)",
         "options": {
           "baseURL": "https://<POD_ID>-8000.proxy.runpod.net/v1",
           "apiKey": "{env:VLLM_API_KEY}"
         },
         "models": {
           "qwen3.8-27b": {
             "name": "Qwen3.8-27B (RunPod vLLM)",
             "limit": { "context": 262144, "output": 32768 }
           }
         }
       }
     }
   }
   ```

2. Export the same key locally that you set on the pod:
   ```bash
   export VLLM_API_KEY=changeme
   ```
3. In OpenCode, run `/models` to confirm `runpod-qwen3 / qwen3.8-27b` shows
   up, then select it as the active model.

Tool-calling correctness is entirely handled server-side by the
`--enable-auto-tool-choice --tool-call-parser qwen3_coder --reasoning-parser
qwen3` flags baked into `entrypoint.sh` — nothing extra is needed on the
OpenCode side beyond pointing it at this provider.

## Notes / caveats

* **GPU required** at runtime (`--gpus all` / NVIDIA Container Toolkit). The
  build does not need a GPU.
* Not verified end-to-end against a live RunPod pod from this environment
  (no GPU available here) — the `docker build` was validated locally, but
  actually loading the 27B model and confirming a tool-calling round-trip
  from OpenCode is on you to check on a real pod.
* If the model repo changes hands or is renamed upstream, update `MODEL_ID`
  — no rebuild needed, it's an env var.
