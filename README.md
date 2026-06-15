# CSD 单机 GPU 挖矿程序

针对 [Compute Substrate](https://computesubstrate.org/) 网络的 GPU 加速单机挖矿工具。使用 CUDA 并行计算提案哈希，向 CSD 主网提交提案与认证，最大化挖矿收益。

## 🎉 v5.1.0 更新

- ✅ **智能安装**：只需 Python 3.9+，自动检测并配置 GPU
- ✅ **GPU 优先**：自动安装 CUDA 支持，发挥显卡最大性能
- ✅ **CPU 备用**：无 GPU 时自动降级为 CPU 模式
- ✅ **简化部署**：一键安装，自动配置所有依赖
- ⚡ **最大算力**：CUDA 并行计算，比 CPU 快数百倍

---

## 快速开始

### 一键安装（推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/danger0001/solo-miner/main/install.sh | bash
```

安装过程中会提示您输入钱包地址，所有文件将安装到 `~/solo` 目录。

### 安装完成后启动

```bash
cd ~/solo
./start.sh
```

> **v4.0.0 新功能**：自动创建 `~/solo` 文件夹，运行时交互式输入钱包地址，一行命令完成所有安装。

---

## 目录结构

安装完成后，`~/solo` 目录结构如下：

```
~/solo/
├── bin/                      # 可执行文件
│   └── compute-substrate     # 挖矿程序
├── config/                   # 配置文件
│   └── miner-config.toml    # 挖矿配置
├── data/                    # 区块链数据
├── logs/                    # 日志文件
├── compute-substrate/       # 源码（编译后可删除）
├── start.sh                # 启动挖矿
├── stop.sh                 # 停止挖矿
├── status.sh               # 查看状态
└── view-logs.sh            # 查看日志
```

**常用命令：**
- 启动挖矿：`./start.sh`
- 停止挖矿：`./stop.sh`
- 查看状态：`./status.sh`
- 查看日志：`./view-logs.sh`

---

## 目录

- [硬件要求](#硬件要求)
- [快速开始](#快速开始)
- [目录结构](#目录结构)
- [配置说明](#配置说明)
- [引导节点](#引导节点)
- [GPU 挖矿原理](#gpu-挖矿原理)
- [Docker 部署](#docker-部署)
- [手动安装](#手动安装)
- [监控面板](#监控面板)
- [常见问题](#常见问题)

---

## 硬件要求

| 组件 | 最低配置 | 推荐配置 |
|------|---------|---------|
| CPU | 4 核 | 8 核以上 |
| 内存 | 8 GB | 16 GB |
| 显卡 | NVIDIA GTX 1060（CUDA 6.1+） | NVIDIA RTX 3080 及以上 |
| 硬盘 | 20 GB SSD | 100 GB NVMe SSD |
| 网络 | 10 Mbps | 100 Mbps 以上 |

**系统环境：**
- Linux（推荐 Ubuntu 20.04 及以上）
- Python 3.9 或更高版本
- NVIDIA 驱动 >= 470（安装脚本会自动检测）
- CUDA Toolkit >= 11.4（安装脚本会自动安装对应版本）

**⚡ GPU 挖矿优势：**
- GPU 算力是 CPU 的 **100-1000 倍**
- 更高的提案接受率和收益
- 强烈推荐使用 NVIDIA GPU 进行挖矿

---

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/danger0001/solo-miner/main/install.sh | bash
```

`install.sh` 会自动完成：检测 GPU、下载 csd 节点程序、下载 genesis 文件、安装 Python 依赖、自动安装 CUDA 支持（如有 GPU）、生成配置文件，最后引导你填写钱包地址并启动挖矿。

---

## 配置说明

编辑 `config.yaml`（由 `install.sh` 自动生成）：

```yaml
矿工:
  钱包地址: "你的CSD钱包地址"     # 必填
  挖矿域: "compute"
  工作器名称: "worker-01"

节点:
  数据目录: "./cs.db"
  RPC端口: 8789
  P2P端口: 18007
  创世文件: "./genesis.bin"

GPU:
  设备编号: 0                    # 0 = 第一块显卡
  每块线程数: 256
  最大块数: 4096
  批量大小: 65536

挖矿:
  提案间隔秒数: 12
  认证间隔秒数: 6
  难度目标: "0x00000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"

引导节点:
  - "/ip4/151.240.121.186/tcp/17999"
  - "/ip4/151.240.121.220/tcp/17999"
  - "/ip4/151.240.121.187/tcp/17999"
  - "/ip4/158.69.116.36/tcp/17999"
  - "/ip4/145.239.0.111/tcp/17999"
  - "/ip4/151.240.121.189/tcp/17999"
```

---

## 智能带宽检测与节点选择

程序启动时会自动执行以下流程：

1. **延迟测量** — 并发 TCP 握手测量所有引导节点的延迟，输出排名表。
2. **带宽检测** — 下载约 1 MB 数据测量本机下行带宽。
3. **自动决策**：
   - 带宽 **≥ 5 Mbps（默认阈值）** → 使用全部引导节点
   - 带宽 **< 5 Mbps** 或测速失败 → **仅使用延迟最低的单个节点**

启动时日志示例：
```
正在测量引导节点延迟...
  /ip4/151.240.121.186/tcp/17999    延迟: 18.3 ms
  /ip4/158.69.116.36/tcp/17999      延迟: 42.7 ms
  /ip4/145.239.0.111/tcp/17999      延迟: 97.1 ms
  ...
本机带宽：2.14 Mbps（阈值：5.0 Mbps）
检测到低带宽！低带宽 (2.14 Mbps < 5.0 Mbps)：仅使用最优节点
最优节点：/ip4/151.240.121.186/tcp/17999  (延迟 18.3 ms)
```

相关启动参数：

| 参数 | 说明 |
|------|------|
| `--跳过带宽检测` | 跳过检测，强制使用全部节点 |
| `--带宽阈值 <Mbps>` | 自定义低带宽阈值，默认 `5.0` |

```bash
# 跳过带宽检测，直接使用全部节点
./start.sh --跳过带宽检测

# 带宽阈值改为 10 Mbps（低于 10 Mbps 才切换单节点）
./start.sh --带宽阈值 10

# 单独运行节点选择器查看延迟报告（调试用）
python3 node_selector.py
```

---

## 引导节点

以下为官方主网引导节点，建议全部启用以加快节点发现：

| 编号 | 地址 |
|------|------|
| 节点 1 | `/ip4/151.240.121.186/tcp/17999` |
| 节点 2 | `/ip4/151.240.121.220/tcp/17999` |
| 节点 3 | `/ip4/151.240.121.187/tcp/17999` |
| 节点 4 | `/ip4/158.69.116.36/tcp/17999`   |
| 节点 5 | `/ip4/145.239.0.111/tcp/17999`   |
| 节点 6 | `/ip4/151.240.121.189/tcp/17999` |

启动时自定义引导节点：

```bash
# 使用单个节点
./start.sh --引导节点 "/ip4/151.240.121.186/tcp/17999"

# 使用多个节点（逗号分隔）
./start.sh --引导节点 "/ip4/151.240.121.186/tcp/17999,/ip4/158.69.116.36/tcp/17999"

# 使用全部主网节点
./start.sh --引导节点 全部
```

---

## GPU 挖矿原理

本程序通过 CUDA 并行计算大幅提升挖矿效率：

1. **批量哈希计算** — CUDA 内核每批并行计算数万个候选随机数，筛选满足当前难度目标的最佳结果
2. **并行提案评分** — GPU 同时评估多个提案，找出置信度最高的认证目标
3. **零拷贝数据传输** — 使用锁页内存（Pinned Memory）在 CPU 与 GPU 之间高速传输数据，降低提案提交延迟

**启动时显卡信息示例：**
```
[GPU] 检测到 1 块 CUDA 显卡：
[GPU]   [0] NVIDIA GeForce RTX 3080  |  显存: 10240 MB  |  算力: 8.6  |  CUDA核心: 8704
[GPU] 使用设备 0
```

**⚠️ CPU 模式说明：**
- 若未检测到 GPU，程序会自动降级为 CPU 模式
- CPU 模式算力远低于 GPU，仅适合测试
- 生产环境强烈推荐使用 NVIDIA GPU

---

## Docker 部署

### 前置条件

安装 NVIDIA Container Toolkit：

```bash
distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list \
  | sudo tee /etc/apt/sources.list.d/nvidia-docker.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo systemctl restart docker
```

### 使用 Docker Compose 启动

```bash
# 设置钱包地址
export MINER_WALLET="你的CSD钱包地址"

# 构建并启动
docker compose up -d

# 查看日志
docker compose logs -f miner

# 停止
docker compose down
```

### 环境变量

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `MINER_WALLET` | **必填** | CSD 钱包地址 |
| `GPU_DEVICE` | `0` | CUDA 设备编号 |
| `BOOTNODES` | 全部主网节点 | 逗号分隔的引导节点 |
| `RPC_PORT` | `8789` | 节点 RPC 端口 |
| `P2P_PORT` | `18007` | P2P 监听端口 |

---

## 手动安装

```bash
# 1. 安装 Python 依赖
pip install -r requirements.txt

# 2. 下载 genesis 文件
curl -O https://computesubstrate.org/downloads/genesis.bin

# 3. 下载 csd 节点程序（Linux x86_64）
curl -O https://computesubstrate.org/downloads/csd-linux-amd64
chmod +x csd-linux-amd64 && mv csd-linux-amd64 csd

# 4. 校验文件
sha256sum -c checksums.txt

# 5. 手动启动节点
./csd node \
  --datadir cs.db \
  --rpc 0.0.0.0:8789 \
  --genesis genesis.bin \
  --p2p-listen /ip4/0.0.0.0/tcp/18007 \
  --bootnodes /ip4/151.240.121.186/tcp/17999 \
  --bootnodes /ip4/151.240.121.220/tcp/17999 \
  --bootnodes /ip4/151.240.121.187/tcp/17999 \
  --bootnodes /ip4/158.69.116.36/tcp/17999 \
  --bootnodes /ip4/145.239.0.111/tcp/17999 \
  --bootnodes /ip4/151.240.121.189/tcp/17999

# 6. 另开终端，启动 GPU 矿工
python miner.py --配置 config.yaml
```

---

## 监控面板

矿工启动后，在本机访问 `http://localhost:9090/统计` 查看实时数据：

```json
{
  "运行时间（秒）": 3600,
  "已提交提案数": 142,
  "已接受提案数": 138,
  "已提交认证数": 891,
  "GPU算力（MH/s）": 1245.3,
  "GPU使用率（%）": 94,
  "已连接节点数": 12,
  "当前轮次": 8821,
  "上次获奖轮次": 8815
}
```

---

## 常见问题

**必须要 GPU 才能挖矿吗？**
- **强烈推荐使用 GPU**！GPU 算力是 CPU 的 100-1000 倍
- 无 GPU 时程序会自动降级为 CPU 模式，但收益极低
- CPU 模式仅适合测试，生产环境必须使用 NVIDIA GPU

**提示 `CUDA 不可用`**
- 检查 `nvidia-smi` 是否正常运行，驱动是否已安装
- 安装脚本会自动安装对应的 CUDA 支持
- 手动安装：根据 CUDA 版本运行 `pip install cupy-cuda12x` 或 `cupy-cuda11x`

**提示 `连接被拒绝`（RPC 错误）**
- 等待 30–60 秒让节点完成初始化和同步。
- 检查防火墙是否放行 8789（RPC）和 18007（P2P）端口。

**提示 `genesis.bin 未找到`**
- 重新运行 `./install.sh`，或手动下载：
  `curl -O https://computesubstrate.org/downloads/genesis.bin`

**节点无法发现对等节点**
- 检查引导节点是否可达：`nc -zv 151.240.121.186 17999`
- 尝试使用全部节点：`./start.sh --引导节点 全部`

---

## 版本历史

| 版本 | 说明 |
|------|------|
| [v5.1.0](https://github.com/danger0001/solo-miner) | 🚀 **智能安装**：自动检测并配置 GPU，强化 GPU 挖矿特性 |
| [v5.0.0](https://github.com/danger0001/solo-miner) | 简化安装流程，只需 Python 3.9+ 基础环境 |
| [v4.0.0](https://github.com/danger0001/solo-miner) | Solo 文件夹结构，一键安装，交互式输入 |
| [v2.1.0](https://github.com/danger0001/solo-miner) | 智能带宽检测，低带宽自动切换最优单节点 |
| [v2.0.0](https://github.com/danger0001/solo-miner/releases/tag/v2.0.0) | 中文界面、一键安装脚本 |
| [v1.0.0](https://github.com/danger0001/solo-miner/releases/tag/v1.0.0) | 英文版初始发布 |

---

## 许可证

MIT License — 详见 [LICENSE](LICENSE) 文件。

---

## 相关链接

- [Compute Substrate 官网](https://computesubstrate.org/)
- [官方白皮书](https://computesubstrate.org/downloads/Compute_Substrate_Original_Paper.pdf)
- [官方 GitHub](https://github.com/compute-substrate/compute-substrate)
- [区块浏览器](https://explorer.computesubstrate.org)
