#!/usr/bin/env bash
# setup.sh — Bootstrap the CSD Solo GPU Miner environment
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${CYAN}[setup]${NC} $*"; }
ok()   { echo -e "${GREEN}[  OK  ]${NC} $*"; }
warn() { echo -e "${YELLOW}[ WARN ]${NC} $*"; }
die()  { echo -e "${RED}[ERROR ]${NC} $*"; exit 1; }

CSD_BASE_URL="https://computesubstrate.org/downloads"
GENESIS_FILE="genesis.bin"
CHECKSUM_FILE="checksums.txt"

# Detect OS / architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  ARCH_TAG="amd64" ;;
  aarch64) ARCH_TAG="arm64" ;;
  *)       die "Unsupported architecture: $ARCH" ;;
esac

CSD_BINARY="csd-${OS}-${ARCH_TAG}"

log "============================================"
log "  CSD Solo GPU Miner — Setup"
log "============================================"

# ── Python check ─────────────────────────────────────────────────────────────
log "Checking Python version..."
python3 --version >/dev/null 2>&1 || die "Python 3 is required. Install it and retry."
PY_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
log "Found Python $PY_VER"
[[ $(echo "$PY_VER >= 3.9" | bc -l) -eq 1 ]] || die "Python 3.9+ is required (found $PY_VER)"

# ── CUDA check ────────────────────────────────────────────────────────────────
log "Checking CUDA availability..."
if command -v nvidia-smi &>/dev/null; then
    DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
    ok "NVIDIA GPU detected: $GPU_NAME  (Driver: $DRIVER)"
    GPU_AVAILABLE=true
else
    warn "nvidia-smi not found. GPU mining will be disabled (CPU fallback)."
    warn "Install NVIDIA drivers + CUDA Toolkit for GPU support."
    GPU_AVAILABLE=false
fi

# ── pip dependencies ──────────────────────────────────────────────────────────
log "Installing Python dependencies..."
pip3 install -q --upgrade pip
pip3 install -q -r requirements.txt

if [[ "$GPU_AVAILABLE" == "true" ]]; then
    log "Installing CUDA Python packages..."
    # Try cupy matching installed CUDA version
    CUDA_VER=$(nvcc --version 2>/dev/null | grep -oP 'release \K[0-9]+\.[0-9]+' | head -1 || echo "")
    if [[ -n "$CUDA_VER" ]]; then
        CUDA_MAJOR=$(echo "$CUDA_VER" | cut -d. -f1)
        CUDA_MINOR=$(echo "$CUDA_VER" | cut -d. -f2)
        CUPY_PKG="cupy-cuda${CUDA_MAJOR}${CUDA_MINOR}x"
        log "Installing $CUPY_PKG for CUDA $CUDA_VER..."
        pip3 install -q "$CUPY_PKG" || warn "cupy install failed — falling back to pycuda"
        pip3 install -q pycuda || warn "pycuda install also failed — GPU features may not work"
    else
        warn "nvcc not found; installing cupy-cuda12x as default..."
        pip3 install -q cupy-cuda12x || warn "cupy install failed"
    fi
fi

# ── Download csd binary ───────────────────────────────────────────────────────
if [[ ! -f "csd" ]]; then
    log "Downloading csd binary ($CSD_BINARY)..."
    curl -fSL "${CSD_BASE_URL}/${CSD_BINARY}" -o csd || die "Failed to download csd binary"
    chmod +x csd
    ok "csd binary downloaded"
else
    ok "csd binary already present — skipping download"
fi

# ── Download genesis file ─────────────────────────────────────────────────────
if [[ ! -f "$GENESIS_FILE" ]]; then
    log "Downloading genesis.bin..."
    curl -fSL "${CSD_BASE_URL}/${GENESIS_FILE}" -o "$GENESIS_FILE" || die "Failed to download genesis.bin"
    ok "genesis.bin downloaded"
else
    ok "genesis.bin already present — skipping download"
fi

# ── Verify checksums ──────────────────────────────────────────────────────────
if [[ ! -f "$CHECKSUM_FILE" ]]; then
    log "Downloading checksums.txt..."
    curl -fSL "${CSD_BASE_URL}/${CHECKSUM_FILE}" -o "$CHECKSUM_FILE" 2>/dev/null || \
        warn "Could not download checksums.txt — skipping verification"
fi

if [[ -f "$CHECKSUM_FILE" ]]; then
    log "Verifying file checksums..."
    sha256sum -c "$CHECKSUM_FILE" --ignore-missing && ok "Checksums verified" || \
        warn "Checksum mismatch — files may be corrupted, re-run setup.sh"
fi

# ── Copy default config ───────────────────────────────────────────────────────
if [[ ! -f "config.yaml" ]]; then
    cp config.yaml.example config.yaml
    ok "config.yaml created from example"
    warn "Edit config.yaml and set your wallet_address before mining!"
else
    ok "config.yaml already exists — not overwriting"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Setup complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "  Next steps:"
echo "  1. Edit config.yaml and set your wallet_address"
echo "  2. Start mining:"
echo "       ./start.sh"
echo "  3. Or with custom bootnodes:"
echo '       ./start.sh --bootnodes "/ip4/151.240.121.186/tcp/17999,/ip4/158.69.116.36/tcp/17999"'
echo ""
