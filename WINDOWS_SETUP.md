# Running SkinTokens / TokenRig on Windows

The upstream README targets Linux/macOS. This guide covers a clean Windows setup,
including a one-shot installer script and a fix for running on **NVIDIA Ampere
GPUs (e.g. RTX 30-series)** where prebuilt flash-attn wheels have no kernel.

## Requirements
- Windows 10/11
- NVIDIA GPU with **≥ 14 GB** VRAM (tested on RTX 3090, 24 GB)
- An existing Python + pip on PATH (Anaconda `base` is fine) — only used to bootstrap `uv`
- Recent NVIDIA driver (CUDA 12.x capable)

## Quick start (one script)

```powershell
# from the project root
powershell -ExecutionPolicy Bypass -File .\setup_windows.ps1
```

This installs `uv`, creates a Python 3.11 venv (`.venv`), installs PyTorch (cu128),
the project requirements, a prebuilt flash-attn wheel, and downloads the models.

Options:
```powershell
# behind a corporate proxy
powershell -ExecutionPolicy Bypass -File .\setup_windows.ps1 -Proxy "http://HOST:PORT"

# set up the environment but skip the (multi-GB) model download
powershell -ExecutionPolicy Bypass -File .\setup_windows.ps1 -SkipModels
```

The script is re-runnable; steps already done are skipped.

> **Why `uv` is installed via pip** instead of the official `astral.sh` installer:
> some networks/proxies block `astral.sh`. `pip install uv` pulls from PyPI, which
> is more universally reachable.

## Running

No need to activate the venv — call its Python directly (avoids ExecutionPolicy prompts):

```powershell
# CLI: rig a single model
.\.venv\Scripts\python.exe demo.py --input examples\giraffe.glb --output results\giraffe.glb --use_transfer

# Web UI (Gradio) at http://127.0.0.1:1024
.\.venv\Scripts\python.exe demo.py
```

If you use a proxy, make sure the local server bypasses it before launching the web UI:
```powershell
$env:NO_PROXY = "localhost,127.0.0.1"
```

## Ampere / flash-attn note (important)

Prebuilt Windows flash-attn wheels are often **not compiled for Ampere (sm_86)**.
flash-attn imports fine, but the first kernel call crashes with:

```
CUDA error: no kernel image is available for execution on the device
```

This fork routes attention through **PyTorch SDPA**
(`torch.nn.functional.scaled_dot_product_attention`), which is Ampere-native and
quality-equivalent. The changes are in:

- `src/model/tokenrig.py` — Qwen3 built with `attn_implementation="sdpa"`; the
  `flash_attn_func` fallback is an SDPA shim.
- `src/model/skin_vae_model.py` — same SDPA shim fallback.
- `src/server/spec.py` — `_attn_implementation="sdpa"`.

If you have a flash-attn build that includes your GPU's architecture, you can
revert these to `flash_attention_2`.

## Troubleshooting

- **`No module named 'scipy'`** — `uv pip install scipy` (missing transitive dep).
- **Web UI won't load** — ensure `NO_PROXY` includes `127.0.0.1` so the local
  server isn't routed through a proxy.
- **Blender import** — remove the `glTF_not_exported` node after importing the
  result `.glb`.
