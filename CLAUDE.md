# Runpod_Setup

Monorepo of **independent Docker image setups** meant to run as custom templates on
RunPod. Each top-level folder is one self-contained image with its own Dockerfile,
its own GHCR image name, and its own GitHub Actions workflow that builds & pushes
it. Folders do not share code or build context.

## Layout

```
Runpod_Setup/
├── comfyui_ip_adapter/          reference setup — ComfyUI + IPAdapter-FaceID
│   ├── Dockerfile               self-contained: code baked in at pinned versions, weights streamed at start
│   ├── entrypoint.sh            optional FileBrowser/JupyterLab → download models → seed workflows → exec ComfyUI
│   ├── docker-compose.yml       local convenience runner (GPU, ports, optional volumes)
│   ├── .dockerignore
│   ├── run_workflow.py          queue a UI-format workflow JSON via the ComfyUI API
│   ├── scripts/
│   │   ├── install_comfyui.sh   build-time: clone ComfyUI + custom nodes at pinned commits
│   │   └── download_models.sh   start-time: fetch missing weights per manifest, verify sha256, idempotent
│   ├── config/
│   │   ├── custom_nodes.txt     one `repo_url | git_ref` per line (`#` comments ok)
│   │   ├── models.txt           manifest: `dest_path | url | sha256` per line
│   │   ├── requirements-extra.txt  extra pip deps installed after torch
│   │   └── comfyui_args.txt     extra CLI flags appended to `python main.py` (`#` comments ok)
│   └── workflows/               *.json workflows + reference *.png images, seeded into the container
└── .github/workflows/
    └── push_comfyui_ip_adapter.yml   builds & pushes comfyui_ip_adapter → ghcr.io/speedcy/comfyui-faceid
```

## Design conventions (followed by `comfyui_ip_adapter`, reuse for new folders)

- **Self-contained image, no persistent-volume dependency.** All code/deps are
  baked in at pinned versions during build. Large model weights are *not* baked
  in — `entrypoint.sh` downloads anything missing on container start, so a volume
  mounted at the models dir is only a cache, never a requirement.
- **Pin everything.** Base image, torch, framework ref, and every custom
  node/model go in as build args or manifest lines with explicit versions/commits
  and (for models) sha256.
- **`entrypoint.sh` env knobs** are documented in a header comment at the top of
  the script; keep that comment in sync.
- **Ports:** ComfyUI 8188, FileBrowser 8080 (opt), JupyterLab 8888 (opt).
- Build/run docs live in each folder's own `README.md`.

## GitHub Actions — one workflow file per folder

Each folder gets its own workflow under `.github/workflows/`. They are kept
separate on purpose (simple, readable, independent runs). The per-folder
`paths:` filter is what makes a push only rebuild the image whose folder changed.

**Naming convention:** the workflow file is `push_<folder>.yml` — the prefix
`push_` followed by the exact folder name (e.g. `comfyui_ip_adapter/` →
`.github/workflows/push_comfyui_ip_adapter.yml`).

Template for a new folder `<folder>` → image `ghcr.io/speedcy/<image>`:

```yaml
name: Build and Push Docker Image (<folder>)

on:
  push:
    branches: [main]
    paths:
      - '<folder>/**'
      - '.github/workflows/push_<folder>.yml'
  workflow_dispatch:

env:
  IMAGE_NAME: ghcr.io/speedcy/<image>

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: ./<folder>
          push: true
          tags: |
            ${{ env.IMAGE_NAME }}:latest
            ${{ env.IMAGE_NAME }}:${{ github.sha }}
          cache-from: type=gha,scope=<folder>
          cache-to: type=gha,mode=max,scope=<folder>
```

Rules:
- **`paths:`** must list the folder *and* the workflow file itself.
- **`workflow_dispatch`** stays, so the image can always be rebuilt manually
  (`paths:` filters do not apply to manual runs).
- **`scope=<folder>`** on both `cache-from`/`cache-to` — GHA build cache is shared
  across an entire repo by default; a distinct scope per folder stops the images
  from evicting each other's cache.
- **`IMAGE_NAME`** is unique per folder; each becomes its own GHCR package.
- Shared root files (README, this file, `.gitignore`) are not in any `paths:`, so
  editing them triggers no build. Add them to a `paths:` list only if that image
  genuinely depends on them.

## Adding a new Docker setup folder — checklist

1. `mkdir <folder>/` and add its `Dockerfile` (+ any `scripts/`, `config/`,
   `entrypoint.sh`, `README.md`). Keep it self-contained; the build `context:`
   will be `./<folder>` only.
2. Copy `.github/workflows/push_comfyui_ip_adapter.yml` to
   `.github/workflows/push_<folder>.yml` and fill in `<folder>`, `<image>`, the
   workflow filename in `paths:`, and `scope=<folder>`.
3. Confirm `IMAGE_NAME` does not collide with an existing folder's.
4. Commit. First push that touches `<folder>/**` builds with a cold cache
   (no prior scope) — subsequent pushes reuse it.
5. On RunPod: create a custom template pointing at `ghcr.io/speedcy/<image>:latest`
   (public package, or add Container Registry Auth credentials).
