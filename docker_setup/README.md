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
| `COMFYUI_REF` | `v0.26.2` | ComfyUI git ref (tag/branch/commit) |
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
  -v claude_config:/root/.claude \
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
| `ANTHROPIC_API_KEY` | – | *optional* API-key auth for `claude`; not needed if you use browser login (see below) |

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
(native install, symlinked to `/usr/local/bin/claude`). Its config dir is set to
`/root/.claude` (`CLAUDE_CONFIG_DIR`), and `docker-compose.yml` mounts the
`claude_config` volume there so the login survives container restarts.

### Sign in with a Claude subscription (no API key)

The container is headless, so `claude` uses the manual code-paste flow instead of
opening a browser itself:

```bash
docker compose exec comfyui claude     # or: docker exec -it <container> claude
```

1. Run `/login`, choose **"Claude account with subscription"**.
2. Copy the printed URL into a browser on any machine, sign in, approve.
3. Paste the authorization code it shows back into the terminal.

Credentials land in `/root/.claude/` (the `claude_config` volume), so you only do
this once. Use an interactive exec (`-it` / `compose exec`) — the initial login
can't happen in `-p`/print mode. Plain `docker run` without the volume mount
means logging in again on every fresh container.

API-key auth is still available as an alternative: pass
`-e ANTHROPIC_API_KEY=sk-ant-...`.

## Docker Images options

### Docker Hub (docker.io)

- Docker's own official registry — the default one most tutorials assume.
- Free tier lets you host public images with no real limits.
- You'd sign up at hub.docker.com, pick a username — that becomes your <youruser>.
- Command: docker login (logs into Docker Hub by default).

### GHCR (ghcr.io — GitHub Container Registry)

GitHub's registry, tied to your GitHub account.
Also free for public images.
Useful if you already have a GitHub account and want your images to live alongside your repos.
Command: docker login ghcr.io with a GitHub username + a GitHub Personal Access Token (not your GitHub password) as the credential.



## Deploy on RunPod

RunPod runs a **prebuilt image** pulled from a registry — it does not build the
Dockerfile for you. Flow: **build → push → template → pod**.

### 1. Build and push (any machine with Docker — no GPU needed)

```bash
cd docker_setup
docker build -t docker.io/<youruser>/comfyui-faceid:latest .
docker push docker.io/<youruser>/comfyui-faceid:latest
```

`ghcr.io/<youruser>/…` works too. Keep the repo public, or add credentials under
RunPod → **Settings → Container Registry Auth** and select them in the template.
RunPod pods don't expose a Docker daemon, so you can't build on the pod itself.

#### 1. Create a GitHub Personal Access Token (PAT)

Go to GitHub → your profile picture → **Settings** → **Developer settings** →
**Personal access tokens** → **Tokens (classic)** → **Generate new token**.

Give it these scopes:
- `write:packages`
- `read:packages` (included by `write:packages`, but fine to check both)

Copy the token somewhere safe — GitHub only shows it once.

#### 2. Log in to GHCR from Docker

```bash
echo YOUR_TOKEN | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
```

Replace:
- `YOUR_TOKEN` with the PAT you just created
- `YOUR_GITHUB_USERNAME` with your GitHub username

You should see `Login Succeeded`.

#### 3. Build the image

```bash
cd docker_setup
docker build -t ghcr.io/YOUR_GITHUB_USERNAME/comfyui-faceid:latest .
```

The trailing `.` matters — it means "build from this directory." First build
can take a while (base layers + dependencies).

#### 4. Push the image

```bash
docker push ghcr.io/YOUR_GITHUB_USERNAME/comfyui-faceid:latest
```

Since the account/repo context is private, the pushed package defaults to
**private** visibility — which is what we want.

#### 5. Keep the PAT for later

You'll need this same PAT (or a similarly scoped one) again in:

**RunPod → Settings → Container Registry Auth**

so the pod can pull the private image in Step 2 (creating the template).

### 2. Create a template

Console → **Templates → New Template**:

| Field | Value |
|-------|-------|
| Container Image | `docker.io/<youruser>/comfyui-faceid:latest` |
| Container Disk | `25 GB` (image + input/output scratch) |
| Volume Disk | `30 GB` (caches the ~12 GB of weights) |
| Volume Mount Path | `/opt/ComfyUI/models` |
| Expose HTTP Ports | `8188,8080` |
| Docker Command | *leave empty* — uses the image `ENTRYPOINT` |

Environment variables:

| var | value | why |
|-----|-------|-----|
| `DOWNLOAD_IN_BACKGROUND` | `1` | pod looks "ready" fast; weights stream in behind ComfyUI |
| `FILEBROWSER_ENABLE` | `1` | file browser on :8080 |
| `FB_PASS` | *your choice* | FileBrowser password |
| `CLAUDE_CONFIG_DIR` | `/opt/ComfyUI/models/.claude` | puts the `claude` login on the persistent volume (a pod has only one volume, so it rides along with the weights) |
| `COMFY_EXTRA_ARGS` | `--lowvram` | *only* for GPUs under ~16 GB |

### 3. Deploy a pod

**Pods → Deploy** → pick a GPU with **16 GB+ VRAM** for SDXL (RTX 4000/A4000 Ada,
or RTX 2000 Ada with `--lowvram`) → select your template → deploy On-Demand or
Spot.

### 4. First boot

Pod logs show the torch/CUDA check, then model downloads. With
`DOWNLOAD_IN_BACKGROUND=1` ComfyUI is up immediately and the ~12 GB of weights
land over the next few minutes (`/var/log/download_models.log`); a workflow run
fails until the weights it needs are present. If the volume already holds them
from a prior run, startup is instant.

### 5. Connect

* Pod → **Connect → HTTP Service [Port 8188]** → `https://<podid>-8188.proxy.runpod.net` — ComfyUI UI
* Port 8080 → FileBrowser (`admin` / your `FB_PASS`) to browse `output/`

### 6. Run the workflow / sign into Claude

Pod → **Connect → Start Web Terminal** (or SSH). You are already inside the
container — no `docker exec`:

```bash
claude          # /login → "Claude account with subscription" → open the URL in
                # your own browser → paste the code back (persists on the volume)

python /opt/run_workflow.py /opt/workflows/ipadapter_juggernaut_faceid.json --smoke
```

Outputs go to `/opt/ComfyUI/output/`.

**Stopping** the pod wipes the container disk but keeps the volume (small storage
fee), so weights and the Claude login survive to the next start.

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
* **RunPod:** see [Deploy on RunPod](#deploy-on-runpod) for the full walkthrough
  (build/push, template settings, volume layout, connecting, and running `claude`
  from the pod's web terminal).
