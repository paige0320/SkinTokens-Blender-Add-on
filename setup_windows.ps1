<#
.SYNOPSIS
    One-shot Windows setup for SkinTokens / TokenRig.
    Installs uv, creates a Python 3.11 venv, installs PyTorch (cu128),
    project requirements, a prebuilt flash-attn wheel, and downloads the
    pretrained models.

.NOTES
    Launch from the project root WITHOUT changing the execution policy (this
    one command needs no prompt and no policy change):

        powershell -ExecutionPolicy Bypass -File .\setup_windows.ps1

    Requires an existing python+pip on PATH (your Anaconda 'base' works) to
    bootstrap uv. Re-runnable: steps already done are skipped.
#>

param(
    # Optional HTTP/HTTPS proxy, e.g. -Proxy "http://10.0.0.1:3128". Empty = no proxy.
    [string]$Proxy   = "",
    # Hosts/CIDRs that must bypass the proxy (the local Gradio/bpy server lives here).
    [string]$NoProxy = "localhost,127.0.0.1",
    # Skip the (large) model download if you only want the environment ready.
    [switch]$SkipModels
)

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
Set-Location $ProjectRoot

# Exact wheel matching torch 2.7.0 + cu128 + cp311 + win_amd64. Do not change
# unless you also change the Python / torch versions below.
$FlashAttnWheel = "https://huggingface.co/lldacing/flash-attention-windows-wheel/resolve/main/flash_attn-2.7.4.post1+cu128torch2.7.0cxx11abiFALSE-cp311-cp311-win_amd64.whl"

function Step($n, $msg) { Write-Host "`n=== [$n] $msg ===" -ForegroundColor Cyan }

# --- 0. Proxy ---------------------------------------------------------------
Step 0 "Configuring proxy for this session"
if ($Proxy) {
    $env:HTTP_PROXY  = $Proxy
    $env:HTTPS_PROXY = $Proxy
    $env:NO_PROXY    = $NoProxy
    # Windows PowerShell 5.1's Invoke-* cmdlets ignore *_PROXY env vars, so set
    # the .NET default proxy too (used by the uv installer's irm download).
    [System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy($Proxy, $true)
    Write-Host "Proxy = $Proxy  (NO_PROXY = $NoProxy)"
} else {
    Write-Host "No proxy set."
}

# --- 1. uv ------------------------------------------------------------------
# Installed via pip (PyPI) rather than the astral.sh installer script, because
# the proxy blocks astral.sh. Requires an existing python+pip (Anaconda base is
# fine) -- it is only used to bootstrap uv; the project itself runs in the venv.
Step 1 "Installing uv (if missing)"
if ($Proxy) { $env:PIP_PROXY = $Proxy }
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    python -m pip install --upgrade uv
}
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    # pip may have put uv in a Scripts dir that isn't on PATH yet; fall back to
    # invoking it through python for the rest of the script.
    Write-Host "uv not on PATH; using 'python -m uv'."
    function uv { python -m uv @args }
}
Write-Host "uv version: $(uv --version)"

# --- 2. venv ----------------------------------------------------------------
Step 2 "Creating Python 3.11 virtual environment (.venv)"
if (-not (Test-Path ".venv")) {
    uv venv --python 3.11
} else {
    Write-Host ".venv already exists, skipping."
}
$venvPy = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
if (-not (Test-Path $venvPy)) { throw "venv python not found at $venvPy" }

# --- 3. PyTorch (cu128) -----------------------------------------------------
Step 3 "Installing PyTorch 2.7.0 (cu128)"
uv pip install torch==2.7.0 torchvision==0.22.0 torchaudio==2.7.0 --index-url https://download.pytorch.org/whl/cu128

# --- 4. Project requirements ------------------------------------------------
Step 4 "Installing requirements.txt"
uv pip install -r requirements.txt

# --- 5. flash-attn (prebuilt wheel) -----------------------------------------
Step 5 "Installing prebuilt flash-attn wheel"
uv pip install $FlashAttnWheel
& $venvPy -c "import flash_attn; print('flash_attn', flash_attn.__version__)"

# --- 6. Pretrained models ---------------------------------------------------
if ($SkipModels) {
    Step 6 "Skipping model download (-SkipModels)"
} else {
    Step 6 "Downloading pretrained models"
    & $venvPy download.py --model
}

# --- Done -------------------------------------------------------------------
Write-Host "`nSetup complete." -ForegroundColor Green
Write-Host "To use the environment in a new shell:"
Write-Host "    .\.venv\Scripts\Activate.ps1"
Write-Host "Then try:"
Write-Host "    python demo.py --input examples\giraffe.glb --output results\giraffe.glb --use_transfer"
Write-Host "    python demo.py     # Gradio UI at http://127.0.0.1:1024"
