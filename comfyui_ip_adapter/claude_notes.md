/workspace/comfyui_ip_adapter/ is ready — a from-scratch image with zero persistent-storage dependency, models streamed in at container start.

  Layout

  comfyui_ip_adapter/
  ├── Dockerfile                 CUDA 12.8 base → torch cu128 → ComfyUI v0.26.2 → 5 custom nodes → FaceID extras → claude CLI
  ├── docker-compose.yml         GPU, ports 8188/8080, optional model-cache volume
  ├── entrypoint.sh              FileBrowser (opt) → download models → exec ComfyUI
  ├── scripts/
  │   ├── install_comfyui.sh     build-time: clone ComfyUI + nodes at pinned commits
  │   └── download_models.sh     start-time: fetch missing weights, verify sha256, extract zips — idempotent
  ├── config/
  │   ├── custom_nodes.txt       5 repos pinned to exact commits
  │   ├── models.txt             dest │ url │ sha256  (5 entries)
  │   ├── requirements-extra.txt insightface / onnxruntime (CPU) / onnx / scikit-image
  │   └── comfyui_args.txt       extra CLI flags
  ├── workflows/                 the FaceID JSON + leon-marchand.png reference
  └── run_workflow.py            UI→API converter / queue client

  How the "no persistent volume" part works

  Everything code-side is baked into the image at pinned versions. The ~12 GB of weights are not — on every start download_models.sh reads config/models.txt and pulls anything missing (aria2c, 8 connections), checks
  sha256, and unzips buffalo_l. It skips files that are already present and valid, so mounting a volume at /opt/ComfyUI/models just turns it into a cache. Nothing breaks without one.

  Verified here

  - All 5 model URLs → HTTP 200, content-length matches the on-disk sizes exactly (incl. confirming the CLIP-ViT-H file is h94/IP-Adapter's image_encoder/model.safetensors, renamed)
  - The 4 captured sha256 hashes match the working files
  - download_models.sh parses the manifest and correctly skips all present files
  - run_workflow.py + all shell scripts pass syntax/functional checks

  Not build-tested — there's no Docker daemon in this pod. Build on a machine with Docker + NVIDIA Container Toolkit:
  cd comfyui_ip_adapter && docker build -t comfyui-faceid:latest .
  docker run --gpus all -p 8188:8188 comfyui-faceid:latest

  README.md has the full env-var reference (DOWNLOAD_IN_BACKGROUND, SKIP_MODEL_DOWNLOAD, HF_TOKEN, STRICT_SHA256, FILEBROWSER_ENABLE, …) and RunPod notes. If you push this to a registry, it works as a RunPod custom
  template with no /start.sh and no baked volume.
