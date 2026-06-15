"""
gpu_worker.py — CUDA-accelerated hash computation for CSD Solo Miner.

Provides two main operations:
  1. find_nonce()       — searches for a nonce whose hash meets the difficulty target
  2. score_proposals()  — evaluates a batch of proposals and returns confidence scores

Falls back to CPU (hashlib) when CUDA is unavailable.
"""

import hashlib
import json
import logging
import os
import struct
import time
from typing import Optional

log = logging.getLogger("csd-miner.gpu")

# ── Optional CUDA imports ─────────────────────────────────────────────────────

try:
    import cupy as cp
    import numpy as np
    CUDA_AVAILABLE = True
    log.info("CuPy loaded — GPU mining enabled")
except ImportError:
    try:
        import pycuda.autoinit  # noqa: F401
        import pycuda.driver as cuda
        from pycuda.compiler import SourceModule
        import numpy as np
        CUDA_AVAILABLE = True
        CUPY_AVAILABLE = False
        log.info("PyCUDA loaded — GPU mining enabled (pycuda backend)")
    except ImportError:
        import numpy as np
        CUDA_AVAILABLE = False
        log.warning("No CUDA backend found — falling back to CPU mining")


# ── CUDA kernel source ────────────────────────────────────────────────────────

# Each thread computes SHA-256(epoch_bytes || nonce_bytes) and checks if the
# resulting hash is below the difficulty target.  The first thread to find a
# valid nonce writes it to the output buffer.

CUDA_KERNEL = r"""
#include <stdint.h>
#include <string.h>

// ── SHA-256 implementation ─────────────────────────────────────────────────

__device__ __constant__ uint32_t K[64] = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,
    0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,
    0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,
    0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,
    0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,
    0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,
    0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,
    0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,
    0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
};

#define ROTR(x, n) (((x) >> (n)) | ((x) << (32-(n))))
#define CH(x,y,z)  (((x) & (y)) ^ (~(x) & (z)))
#define MAJ(x,y,z) (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))
#define EP0(x)     (ROTR(x,2)  ^ ROTR(x,13) ^ ROTR(x,22))
#define EP1(x)     (ROTR(x,6)  ^ ROTR(x,11) ^ ROTR(x,25))
#define SIG0(x)    (ROTR(x,7)  ^ ROTR(x,18) ^ ((x) >> 3))
#define SIG1(x)    (ROTR(x,17) ^ ROTR(x,19) ^ ((x) >> 10))

__device__ void sha256_block(
    const uint8_t* data, uint32_t len, uint8_t* digest
) {
    uint32_t h[8] = {
        0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,
        0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19,
    };

    // Single-block SHA-256 (max 55 bytes of data)
    uint8_t block[64];
    memset(block, 0, 64);
    for (uint32_t i = 0; i < len && i < 64; i++) block[i] = data[i];
    block[len] = 0x80;
    uint64_t bit_len = (uint64_t)len * 8;
    for (int i = 0; i < 8; i++)
        block[63 - i] = (uint8_t)(bit_len >> (i * 8));

    uint32_t w[64];
    for (int i = 0; i < 16; i++) {
        w[i] = ((uint32_t)block[i*4]   << 24) |
               ((uint32_t)block[i*4+1] << 16) |
               ((uint32_t)block[i*4+2] <<  8) |
               ((uint32_t)block[i*4+3]);
    }
    for (int i = 16; i < 64; i++)
        w[i] = SIG1(w[i-2]) + w[i-7] + SIG0(w[i-15]) + w[i-16];

    uint32_t a=h[0],b=h[1],c=h[2],d=h[3],e=h[4],f=h[5],g=h[6],hh=h[7];
    for (int i = 0; i < 64; i++) {
        uint32_t t1 = hh + EP1(e) + CH(e,f,g) + K[i] + w[i];
        uint32_t t2 = EP0(a) + MAJ(a,b,c);
        hh=g; g=f; f=e; e=d+t1;
        d=c;  c=b; b=a; a=t1+t2;
    }
    h[0]+=a; h[1]+=b; h[2]+=c; h[3]+=d;
    h[4]+=e; h[5]+=f; h[6]+=g; h[7]+=hh;

    for (int i = 0; i < 8; i++) {
        digest[i*4]   = (h[i] >> 24) & 0xff;
        digest[i*4+1] = (h[i] >> 16) & 0xff;
        digest[i*4+2] = (h[i] >>  8) & 0xff;
        digest[i*4+3] =  h[i]        & 0xff;
    }
}

// ── Main kernel ────────────────────────────────────────────────────────────

__global__ void mine_nonces(
    const uint8_t* epoch_bytes,   // 8-byte epoch (big-endian int64)
    uint64_t       nonce_start,   // first nonce this batch
    uint32_t       batch_size,    // nonces per batch
    const uint8_t* target,        // 32-byte difficulty target
    int64_t*       found_nonce,   // output: -1 or winning nonce
    uint8_t*       found_hash     // output: 32-byte hash of winning nonce
) {
    uint32_t tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid >= batch_size) return;

    uint64_t nonce = nonce_start + tid;

    // Build input: epoch_bytes (8) || nonce (8) = 16 bytes
    uint8_t input[16];
    for (int i = 0; i < 8; i++) input[i]     = epoch_bytes[i];
    for (int i = 0; i < 8; i++) input[8 + i] = (uint8_t)((nonce >> (56 - i*8)) & 0xff);

    uint8_t digest[32];
    sha256_block(input, 16, digest);

    // Check if hash < target (big-endian comparison)
    for (int i = 0; i < 32; i++) {
        if (digest[i] < target[i]) {
            // Valid nonce found — use atomic to claim it
            if (atomicCAS((unsigned long long*)found_nonce,
                          (unsigned long long)(-1LL),
                          (unsigned long long)nonce) == (unsigned long long)(-1LL)) {
                for (int j = 0; j < 32; j++) found_hash[j] = digest[j];
            }
            return;
        }
        if (digest[i] > target[i]) return;
    }
}
"""


# ── GPUWorker class ───────────────────────────────────────────────────────────

class GPUWorker:
    def __init__(
        self,
        device_id: int = 0,
        threads_per_block: int = 256,
        max_blocks: int = 4096,
        batch_size: int = 65536,
    ):
        self.device_id = device_id
        self.threads_per_block = threads_per_block
        self.max_blocks = max_blocks
        self.batch_size = batch_size
        self._use_cupy = False
        self._use_pycuda = False
        self._kernel_fn = None

    def initialize(self):
        """Detect GPU, print device info, and compile CUDA kernel."""
        global CUDA_AVAILABLE

        if not CUDA_AVAILABLE:
            log.warning("GPU unavailable — using CPU mining (significantly slower)")
            return

        try:
            import cupy as cp
            cp.cuda.Device(self.device_id).use()
            props = cp.cuda.runtime.getDeviceProperties(self.device_id)
            name = props["name"].decode()
            vram_mb = props["totalGlobalMem"] // (1024 * 1024)
            sm_major = props["major"]
            sm_minor = props["minor"]
            # Approximate CUDA cores from SM count × cores/SM
            mp = props["multiProcessorCount"]
            cores_per_sm = {(8, 6): 128, (8, 0): 64, (7, 5): 64, (7, 0): 64}.get(
                (sm_major, sm_minor), 128
            )
            total_cores = mp * cores_per_sm

            log.info("GPU | Detected CUDA device(s):")
            log.info(
                "GPU |   [%d] %s  |  VRAM: %d MB  |  SM: %d.%d  |  Cores: ~%d",
                self.device_id, name, vram_mb, sm_major, sm_minor, total_cores,
            )
            log.info("GPU | Using device %d", self.device_id)

            # Compile kernel via CuPy RawKernel
            self._kernel_fn = cp.RawKernel(CUDA_KERNEL, "mine_nonces")
            self._use_cupy = True

        except Exception as exc:
            log.warning("CuPy init failed (%s) — falling back to CPU", exc)
            CUDA_AVAILABLE = False

    def _target_bytes(self, difficulty_hex: str) -> bytes:
        """Convert a '0x...' hex difficulty target to 32 raw bytes."""
        h = difficulty_hex.replace("0x", "").replace("0X", "")
        return bytes.fromhex(h.zfill(64))

    # ── find_nonce ────────────────────────────────────────────────────────────

    def find_nonce(self, epoch: int, difficulty_hex: str) -> tuple[int, str]:
        """
        Search for a nonce whose SHA-256(epoch || nonce) < difficulty target.
        Returns (nonce, hash_hex).
        """
        if self._use_cupy:
            return self._find_nonce_gpu(epoch, difficulty_hex)
        return self._find_nonce_cpu(epoch, difficulty_hex)

    def _find_nonce_gpu(self, epoch: int, difficulty_hex: str) -> tuple[int, str]:
        import cupy as cp

        target_bytes = self._target_bytes(difficulty_hex)
        epoch_bytes = struct.pack(">q", epoch)

        d_epoch  = cp.array(list(epoch_bytes), dtype=cp.uint8)
        d_target = cp.array(list(target_bytes), dtype=cp.uint8)

        nonce_start = 0
        while True:
            d_found_nonce = cp.array([-1], dtype=cp.int64)
            d_found_hash  = cp.zeros(32, dtype=cp.uint8)

            blocks = min(self.max_blocks, (self.batch_size + self.threads_per_block - 1) // self.threads_per_block)
            self._kernel_fn(
                (blocks,), (self.threads_per_block,),
                (d_epoch, cp.uint64(nonce_start), cp.uint32(self.batch_size),
                 d_target, d_found_nonce, d_found_hash),
            )
            cp.cuda.Stream.null.synchronize()

            found = int(d_found_nonce[0])
            if found != -1:
                hash_hex = "".join(f"{b:02x}" for b in d_found_hash.tolist())
                return found, hash_hex

            nonce_start += self.batch_size

    def _find_nonce_cpu(self, epoch: int, difficulty_hex: str) -> tuple[int, str]:
        target = bytes.fromhex(difficulty_hex.replace("0x", "").zfill(64))
        epoch_bytes = struct.pack(">q", epoch)
        nonce = 0
        while True:
            nonce_bytes = struct.pack(">q", nonce)
            h = hashlib.sha256(epoch_bytes + nonce_bytes).digest()
            if h < target:
                return nonce, h.hex()
            nonce += 1

    # ── score_proposals ───────────────────────────────────────────────────────

    def score_proposals(self, proposals: list[dict]) -> list[dict]:
        """
        Evaluate a list of proposals and return them with GPU-computed scores.
        Uses vectorized numpy operations (or CUDA for large batches).
        """
        if not proposals:
            return []

        if self._use_cupy:
            return self._score_gpu(proposals)
        return self._score_cpu(proposals)

    def _score_gpu(self, proposals: list[dict]) -> list[dict]:
        import cupy as cp

        ids    = [p.get("id", "") for p in proposals]
        hashes = [p.get("hash", "0" * 64) for p in proposals]

        # Convert first 8 bytes of each hash to uint64 for numeric scoring
        vals = cp.array(
            [int(h[:16], 16) if len(h) >= 16 else 0 for h in hashes],
            dtype=cp.float64,
        )
        max_val = float(vals.max()) or 1.0
        scores = (1.0 - vals / max_val).tolist()

        result = []
        for i, p in enumerate(proposals):
            result.append({
                "id": ids[i],
                "score": round(scores[i], 6),
                "confidence": round(min(scores[i] + 0.05, 1.0), 6),
            })
        return result

    def _score_cpu(self, proposals: list[dict]) -> list[dict]:
        result = []
        for p in proposals:
            h = p.get("hash", "0" * 64)
            val = int(h[:16], 16) if len(h) >= 16 else 0
            score = 1.0 - (val / (2 ** 64))
            result.append({
                "id": p.get("id", ""),
                "score": round(score, 6),
                "confidence": round(min(score + 0.05, 1.0), 6),
            })
        return result

    # ── cleanup ───────────────────────────────────────────────────────────────

    def shutdown(self):
        if self._use_cupy:
            try:
                import cupy as cp
                cp.cuda.Device(self.device_id).synchronize()
                log.info("GPU device %d released", self.device_id)
            except Exception:
                pass
