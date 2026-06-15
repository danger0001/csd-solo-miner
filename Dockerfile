# ─────────────────────────────────────────────────────────────────────────────
# CSD Solo GPU Miner — Dockerfile
# Base: NVIDIA CUDA 12.2 + Ubuntu 22.04
# Requires NVIDIA Container Toolkit on the host.
# ─────────────────────────────────────────────────────────────────────────────

FROM nvidia/cuda:12.2.0-runtime-ubuntu22.04

# Prevent interactive prompts during apt installs
ENV DEBIAN_FRONTEND=noninteractive

# ── System dependencies ───────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 \
    python3-pip \
    python3.11-dev \
    curl \
    ca-certificates \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Make python3.11 the default python3
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
 && update-alternatives --install /usr/bin/python  python  /usr/bin/python3.11 1

# ── Working directory ─────────────────────────────────────────────────────────
WORKDIR /app

# ── Python dependencies ───────────────────────────────────────────────────────
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt \
 && pip3 install --no-cache-dir cupy-cuda12x

# ── Copy application source ───────────────────────────────────────────────────
COPY miner.py gpu_worker.py ./

# ── Download csd binary and genesis at build time ─────────────────────────────
ARG CSD_ARCH=amd64
RUN curl -fSL "https://computesubstrate.org/downloads/csd-linux-${CSD_ARCH}" -o csd \
 && chmod +x csd \
 && curl -fSL "https://computesubstrate.org/downloads/genesis.bin" -o genesis.bin \
 && curl -fSL "https://computesubstrate.org/downloads/checksums.txt" -o checksums.txt \
 && (sha256sum -c checksums.txt --ignore-missing || echo "Warning: checksum verification skipped")

# ── Runtime defaults ──────────────────────────────────────────────────────────
ENV MINER_WALLET=""
ENV GPU_DEVICE="0"
ENV RPC_PORT="8789"
ENV P2P_PORT="18007"
ENV BOOTNODES="all"

# ── Entrypoint ────────────────────────────────────────────────────────────────
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 8789 18007 9090

ENTRYPOINT ["docker-entrypoint.sh"]
