#!/usr/bin/env python3
"""
Queue a ComfyUI UI-format workflow JSON via the HTTP API and report the result.

The .json files ComfyUI saves from the graph editor are in "UI" / litegraph format
(nodes + links + widgets_values). The /prompt endpoint wants "API" format
({node_id: {class_type, inputs}}). This script converts UI -> API using /object_info,
queues it, polls /history, and prints the output image paths.

Usage:
    .venv-cu128/bin/python run_workflow.py [workflow.json] [options]

    workflow.json        path to the UI-format workflow
                         (default: ComfyUI/ipadapter_juggernaut_faceid.json)

Options:
    --server URL         ComfyUI base URL (default: http://127.0.0.1:8188)
    --smoke              override to 512x512 / 8 steps for a fast sanity run
    --steps N            override KSampler steps
    --size WxH           override EmptyLatentImage size, e.g. 768x1024
    --seed N             override KSampler / KSamplerAdvanced seed
    --prefix STR         override SaveImage filename_prefix
    --dry-run            convert + print the API prompt, don't queue
    --timeout SEC        max seconds to wait for the run (default 600)

Exit codes: 0 ok, 1 request rejected, 2 run failed, 3 bad input.
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

_WF_CANDIDATES = [
    os.environ.get("WORKFLOW"),
    "/opt/workflows/ipadapter_juggernaut_faceid.json",
    "/workspace/runpod-slim/ComfyUI/ipadapter_juggernaut_faceid.json",
    "ipadapter_juggernaut_faceid.json",
]
DEFAULT_WF = next((p for p in _WF_CANDIDATES if p and os.path.isfile(p)),
                  "/opt/workflows/ipadapter_juggernaut_faceid.json")
PRIMITIVE_WIDGET_TYPES = {"INT", "FLOAT", "STRING", "BOOLEAN"}
SEED_WIDGETS = {"seed", "noise_seed"}
SEED_CONTROL_VALUES = {"fixed", "increment", "decrement", "randomize"}


def api(base, path, payload=None):
    url = base.rstrip("/") + path
    data = json.dumps(payload).encode() if payload is not None else None
    with urllib.request.urlopen(url, data, timeout=30) as r:
        return json.load(r)


def get_object_info(base, class_types):
    """Fetch /object_info once per class_type; return {class_type: info}."""
    out = {}
    for ct in sorted(class_types):
        try:
            d = api(base, f"/object_info/{urllib.parse.quote(ct)}")
        except urllib.error.HTTPError:
            raise SystemExit(f"[3] unknown node type for this server: {ct!r}")
        out[ct] = d[ct]
    return out


def ui_to_api(wf, object_info):
    """Convert a litegraph UI workflow dict to an API prompt dict."""
    # link_id -> (from_node_id, from_slot_index)
    links = {}
    for l in wf.get("links", []):
        # [link_id, from_node, from_slot, to_node, to_slot, type]
        links[l[0]] = (l[1], l[2])

    prompt = {}
    for node in wf["nodes"]:
        ct = node["type"]
        mode = node.get("mode", 0)
        if mode in (2, 4):  # muted / bypassed
            continue
        if ct in ("Note", "MarkdownNote", "Reroute", "PrimitiveNode"):
            continue
        if ct not in object_info:
            raise SystemExit(f"[3] node type {ct!r} missing from /object_info")

        info_in = object_info[ct].get("input", {})
        ordered = list(info_in.get("required", {}).items()) + \
                  list(info_in.get("optional", {}).items())

        # names already satisfied by an incoming connection
        connected = {}
        for slot in node.get("inputs", []) or []:
            lid = slot.get("link")
            if lid is not None and lid in links:
                src_node, src_slot = links[lid]
                connected[slot["name"]] = [str(src_node), src_slot]

        widgets = list(node.get("widgets_values", []) or [])
        wi = 0
        inputs = {}
        for name, spec in ordered:
            typ = spec[0] if isinstance(spec, list) and spec else spec
            is_widget = isinstance(typ, list) or typ in PRIMITIVE_WIDGET_TYPES
            if name in connected:
                inputs[name] = connected[name]
                continue
            if not is_widget:
                continue  # unconnected optional link input -> leave out
            if wi < len(widgets):
                inputs[name] = widgets[wi]
                wi += 1
                # litegraph stores a control-after-generate value right after a seed
                if name in SEED_WIDGETS and wi < len(widgets) \
                        and widgets[wi] in SEED_CONTROL_VALUES:
                    wi += 1
            else:
                # workflow saved before this widget existed -> use the schema default
                if isinstance(spec, list) and len(spec) > 1 and isinstance(spec[1], dict) \
                        and "default" in spec[1]:
                    inputs[name] = spec[1]["default"]
                elif isinstance(typ, list) and typ:
                    inputs[name] = typ[0]
        prompt[str(node["id"])] = {"class_type": ct, "inputs": inputs}
    return prompt


def apply_overrides(prompt, args):
    for nid, node in prompt.items():
        ct, inp = node["class_type"], node["inputs"]
        if ct in ("KSampler", "KSamplerAdvanced", "SamplerCustom"):
            if args.smoke:
                inp["steps"] = 8
            if args.steps is not None:
                inp["steps"] = args.steps
            if args.seed is not None:
                inp["seed" if "seed" in inp else "noise_seed"] = args.seed
        if ct in ("EmptyLatentImage", "EmptySD3LatentImage"):
            if args.smoke:
                inp["width"], inp["height"] = 512, 512
            if args.size:
                w, h = args.size.lower().split("x")
                inp["width"], inp["height"] = int(w), int(h)
        if ct == "SaveImage" and args.prefix:
            inp["filename_prefix"] = args.prefix
    return prompt


def main():
    p = argparse.ArgumentParser(add_help=True)
    p.add_argument("workflow", nargs="?", default=DEFAULT_WF)
    p.add_argument("--server", default="http://127.0.0.1:8188")
    p.add_argument("--smoke", action="store_true")
    p.add_argument("--steps", type=int)
    p.add_argument("--size")
    p.add_argument("--seed", type=int)
    p.add_argument("--prefix")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--timeout", type=int, default=600)
    args = p.parse_args()

    try:
        wf = json.load(open(args.workflow))
    except FileNotFoundError:
        raise SystemExit(f"[3] workflow not found: {args.workflow}")
    if "nodes" not in wf:
        raise SystemExit("[3] not a UI-format workflow (no 'nodes' key)")

    class_types = {n["type"] for n in wf["nodes"]}
    object_info = get_object_info(args.server, class_types)
    prompt = apply_overrides(ui_to_api(wf, object_info), args)

    if args.dry_run:
        print(json.dumps(prompt, indent=2))
        return

    print(f"workflow : {args.workflow}")
    print(f"server   : {args.server}")
    print(f"nodes    : {len(prompt)}")
    t0 = time.time()
    try:
        res = api(args.server, "/prompt", {"prompt": prompt})
    except urllib.error.HTTPError as e:
        print("[1] /prompt rejected:\n" + e.read().decode()[:4000])
        sys.exit(1)
    pid = res["prompt_id"]
    print(f"queued   : {pid}")

    deadline = t0 + args.timeout
    while time.time() < deadline:
        hist = api(args.server, f"/history/{pid}")
        if pid in hist:
            break
        time.sleep(2)
    else:
        print("[2] timed out waiting for the run")
        sys.exit(2)

    entry = hist[pid]
    st = entry["status"]
    ok = st.get("status_str") == "success"
    print(f"status   : {st.get('status_str')} ({time.time()-t0:.1f}s)")
    if not ok:
        for m in st.get("messages", []):
            print("  " + json.dumps(m)[:2000])
        sys.exit(2)
    for node_id, out in entry["outputs"].items():
        for im in out.get("images", []):
            sub = f"{im['subfolder']}/" if im["subfolder"] else ""
            print(f"  output/{sub}{im['filename']}  (node {node_id})")


if __name__ == "__main__":
    main()
