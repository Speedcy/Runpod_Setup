# ComfyUI + IPAdapter-FaceID — self-contained Docker image

Rebuilds the ComfyUI environment **from scratch, with no dependency on any
persistent volume**. ComfyUI, custom nodes and all Python packages are baked
into the image at pinned versions. The large model weights are **not** baked in —
they are downloaded on container start from the URLs in
[`config/models.txt`](config/models.txt).

## Contents

```
docker_setup/
├── Dockerfile                 image definition (torch cu128, ComfyUI, nodes, FaceID extras, claude CLI)
├── docker-compose.yml         convenience runner (GPU, ports, optional model cache volume)
├── entrypoint.sh              start FileBrowser (opt) → download models → exec ComfyUI
├── .dockerignore
├── scripts/
│   ├── install_comfyui.sh     build-time: clone ComfyUI + custom nodes at pinned commits
│   └── download_models.sh     start-time: fetch missing weights per the manifest (idempotent)
├── config/
│   ├── custom_nodes.txt       repo + commit for each custom node
│   ├── models.txt             model manifest: dest | url | sha256
│   ├── requirements-extra.txt insightface / onnxruntime / …
│   └── comfyui_args.txt       extra ComfyUI CLI flags
├── workflows/
│   ├── ipadapter_juggernaut_faceid.json
│   └── leon-marchand.png      reference face, copied into ComfyUI/input on start
└── run_workflow.py            queue a UI-format workflow JSON via the API
```

## Build

```bash
cd docker_setup
docker build -t comfyui-faceid:latest .
```

Pinned by build args (override with `--build-arg`):

| arg | default | meaning |
|-----|---------|---------|
| `CUDA_IMAGE` | `nvidia/cuda:12.8.0-cudnn-runtime-ubuntu24.04` | base image |
| `COMFYUI_REF` | `b7ac98a…` (v0.26.2) | ComfyUI commit |
| `TORCH_VERSION` | `2.10.0` | torch/torchaudio, from the cu128 index |
| `TORCHVISION_VERSION` | `0.25.0` | torchvision |

The image is ~10–14 GB (torch + CUDA runtime + ComfyUI + nodes; no weights).
Model weights add ~12 GB at runtime.

## Run

```bash
# with compose (recommended)
docker compose up --build

# or plain docker
docker run --gpus all -p 8188:8188 -p 8080:8080 \
  -e FILEBROWSER_ENABLE=1 -e FB_PASS=changeme \
  -v comfy_models:/opt/ComfyUI/models \
  -v "$PWD/output:/opt/ComfyUI/output" \
  comfyui-faceid:latest
```

* ComfyUI API/UI → <http://localhost:8188>
* FileBrowser (if enabled) → <http://localhost:8080>

First start downloads the weights (progress in the container log, or
`/var/log/download_models.log` when backgrounded), then ComfyUI boots. Mounting a
volume at `/opt/ComfyUI/models` caches them so later starts are instant. **No
volume is required** — without one, weights are re-fetched each start.

### Runtime env vars

| var | default | effect |
|-----|---------|--------|
| `SKIP_MODEL_DOWNLOAD` | `0` | `1` → don't fetch weights this start |
| `DOWNLOAD_IN_BACKGROUND` | `0` | `1` → start ComfyUI immediately, fetch weights in background |
| `FILEBROWSER_ENABLE` | `0` | `1` → run FileBrowser on :8080 |
| `FB_USER` / `FB_PASS` | `admin` / `admin` | FileBrowser credentials |
| `HF_TOKEN` | – | bearer token for gated Hugging Face repos |
| `STRICT_SHA256` | `0` | `1` → abort start on any checksum mismatch |
| `COMFY_EXTRA_ARGS` | – | appended to `python main.py …` (e.g. `--lowvram`) |
| `COMFY_PORT` | `8188` | ComfyUI port |
| `ANTHROPIC_API_KEY` | – | auth for the bundled `claude` CLI (see below) |

## Run the FaceID workflow

Once ComfyUI is up and the weights are present:

```bash
docker exec -it <container> \
  python /opt/run_workflow.py /opt/workflows/ipadapter_juggernaut_faceid.json
```

Options: `--smoke` (512²/8 steps), `--steps N`, `--size WxH`, `--seed N`,
`--prefix STR`, `--dry-run`. Output lands in `ComfyUI/output/` (mount it to keep it).

`run_workflow.py` converts the UI/litegraph JSON to API format via `/object_info`,
`POST`s `/prompt`, and polls `/history`. It also runs fine from the host against
`--server http://localhost:8188` with any Python 3.

## Claude Code CLI

The image bundles the [`claude`](https://docs.claude.com/en/docs/claude-code) CLI
(native install, symlinked to `/usr/local/bin/claude`). Use it inside the
container:

```bash
docker exec -it <container> claude          # interactive
docker exec -it <container> claude -p "..."  # one-shot / print mode
```

Authenticate with an API key (`-e ANTHROPIC_API_KEY=sk-ant-...` on `docker run`,
or the commented line in `docker-compose.yml`), or run `claude login` once in an
interactive exec. To keep the login across container restarts, mount a volume at
`/root/.claude` and `/root/.claude.json`.

## Adding / changing models

Edit [`config/models.txt`](config/models.txt):

```
<dest under ComfyUI/models/> | <direct url> | <sha256 or ->
```

* A `.zip` URL is extracted into `<dest>` (treated as a directory) — that's how
  `buffalo_l` is handled.
* Get a checksum with `sha256sum <file>`. `-` skips the check (size-only).
* On a hash mismatch the file is kept and a warning printed, unless
  `STRICT_SHA256=1`. A mismatch usually means upstream re-uploaded the file —
  verify and update the hash here.

No rebuild needed for model changes; `download_models.sh` reads the manifest at
start. (It's also copied to `/opt/models.txt` in the image — bind-mount your own
over it, or rebuild, to change the baked default.)

## Notes / caveats

* **CPU face detection.** `onnxruntime` (CPU) is installed, not `onnxruntime-gpu`
  — the two conflict. The FaceID node uses `provider="CPU"`; face-analysis on one
  portrait is a few seconds. For GPU: swap to `onnxruntime-gpu` in
  `requirements-extra.txt` and set the node's provider to `CUDA`.
* **Model URLs** are best-effort canonical sources (Hugging Face / GitHub
  releases). If a repo moves, update `config/models.txt`.
* **GPU required** at runtime (`--gpus all` / NVIDIA Container Toolkit). The build
  does not need a GPU.
* **RunPod:** push the image to a registry and use it as a custom template with
  container start command left as the image `ENTRYPOINT`. Expose HTTP ports 8188
  and (optionally) 8080. Set `DOWNLOAD_IN_BACKGROUND=1` if you want the pod to
  look "ready" quickly while weights stream in.
