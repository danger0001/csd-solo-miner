#!/usr/bin/env bash
# start.sh — Launch the CSD Solo GPU Miner
#
# Usage:
#   ./start.sh                                              # Use bootnodes from config.yaml
#   ./start.sh --bootnodes all                              # Force all mainnet bootnodes
#   ./start.sh --bootnodes "/ip4/151.240.121.186/tcp/17999" # Single custom bootnode
#   ./start.sh --bootnodes "/ip4/A/tcp/17999,/ip4/B/tcp/17999"  # Multiple custom bootnodes
#   ./start.sh --gpu 1                                      # Use second GPU
#   ./start.sh --no-node                                    # Skip launching csd node
#   ./start.sh --debug                                      # Verbose logging
#
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${CYAN}[start]${NC} $*"; }
ok()   { echo -e "${GREEN}[  OK  ]${NC} $*"; }
warn() { echo -e "${YELLOW}[ WARN ]${NC} $*"; }
die()  { echo -e "${RED}[ERROR ]${NC} $*"; exit 1; }

# ── Default mainnet bootstrap nodes ──────────────────────────────────────────
MAINNET_BOOTNODES=(
    "/ip4/151.240.121.186/tcp/17999"
    "/ip4/151.240.121.220/tcp/17999"
    "/ip4/151.240.121.187/tcp/17999"
    "/ip4/158.69.116.36/tcp/17999"
    "/ip4/145.239.0.111/tcp/17999"
    "/ip4/151.240.121.189/tcp/17999"
)

# ── Parse arguments ───────────────────────────────────────────────────────────
BOOTNODES_ARG=""
GPU_ARG=""
NO_NODE=""
DEBUG_ARG=""
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bootnodes)
            BOOTNODES_ARG="$2"
            shift 2
            ;;
        --gpu)
            GPU_ARG="$2"
            shift 2
            ;;
        --no-node)
            NO_NODE="--no-node"
            shift
            ;;
        --debug)
            DEBUG_ARG="--debug"
            shift
            ;;
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        *)
            EXTRA_ARGS+=("$1")
            shift
            ;;
    esac
done

CONFIG_FILE="${CONFIG_FILE:-config.yaml}"

# ── Pre-flight checks ─────────────────────────────────────────────────────────
[[ -f "$CONFIG_FILE" ]] || die "config.yaml not found. Run ./setup.sh first."
[[ -f "csd" ]]          || die "csd binary not found. Run ./setup.sh first."
[[ -f "genesis.bin" ]]  || die "genesis.bin not found. Run ./setup.sh first."
python3 --version >/dev/null 2>&1 || die "python3 not found."
python3 -c "import aiohttp" 2>/dev/null || die "aiohttp not installed. Run: pip install -r requirements.txt"

# ── Resolve bootnodes ─────────────────────────────────────────────────────────
if [[ -z "$BOOTNODES_ARG" ]]; then
    # Use whatever is in config.yaml — miner.py reads it
    BOOTNODE_FLAG=""
    log "Bootstrap nodes: from config.yaml"
elif [[ "${BOOTNODES_ARG,,}" == "all" ]]; then
    BN_LIST=$(IFS=","; echo "${MAINNET_BOOTNODES[*]}")
    BOOTNODE_FLAG="--bootnodes ${BN_LIST}"
    log "Bootstrap nodes: all ${#MAINNET_BOOTNODES[@]} mainnet nodes"
else
    BOOTNODE_FLAG="--bootnodes ${BOOTNODES_ARG}"
    IFS=',' read -ra BN_ARRAY <<< "$BOOTNODES_ARG"
    log "Bootstrap nodes: ${#BN_ARRAY[@]} custom node(s)"
    for bn in "${BN_ARRAY[@]}"; do
        log "  → $bn"
    done
fi

# ── GPU info ──────────────────────────────────────────────────────────────────
if command -v nvidia-smi &>/dev/null; then
    GPU_IDX="${GPU_ARG:-0}"
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader -i "$GPU_IDX" 2>/dev/null || echo "Unknown")
    ok "GPU $GPU_IDX: $GPU_NAME"
else
    warn "nvidia-smi not found — CPU mining mode"
fi

[[ -n "$GPU_ARG" ]] && GPU_FLAG="--gpu $GPU_ARG" || GPU_FLAG=""

# ── Launch ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Starting CSD Solo GPU Miner${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""

CMD="python3 miner.py --config ${CONFIG_FILE} ${BOOTNODE_FLAG} ${GPU_FLAG} ${NO_NODE} ${DEBUG_ARG}"

log "Command: $CMD"
echo ""

exec $CMD "${EXTRA_ARGS[@]}"
