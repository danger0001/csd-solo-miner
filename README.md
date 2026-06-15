# CSD 单机 GPU 挖矿程序

针对 [Compute Substrate](https://computesubstrate.org/) 网络的 GPU 加速单机挖矿工具。使用 CUDA 并行计算提案哈希，向 CSD 主网提交提案与认证，最大化挖矿收益。

---

## 目录

- [硬件要求](#硬件要求)
- [一键安装](#一键安装)
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
| 显卡 | NVIDIA GTX 1060（CUDA 6.1+） | NVIDIA RTX 3080 以上 |
| 硬盘 | 20 GB SSD | 100 GB NVMe SSD |
| 网络 | 10 Mbps | 100 Mbps 以上 |

**系统环境：**
- Linux（推荐 Ubuntu 20.04 及以上）
- NVIDIA 驱动 >= 470
- CUDA Toolkit >= 11.4
- Python >= 3.9

---

## 一键安装

```bash
# 克隆项目
git clone https://github.com/danger0001/csd-solo-miner.git
cd csd-solo-miner

# 一键安装并启动（推荐）
chmod +x install.sh && ./install.sh
```

`install.sh` 会自动完成：下载 csd 节点程序、下载 genesis 文件、安装 Python 依赖、检测 GPU 并安装 CUDA 支持、生成配置文件，最后引导你填写钱包地址并启动挖矿。

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

本程序通过以下方式加速挖矿：

1. **批量哈希计算** — CUDA 内核每批并行计算数万个候选随机数，筛选满足当前难度目标的最佳结果。
2. **并行提案评分** — GPU 同时评估多个提案，找出置信度最高的认证目标。
3. **零拷贝数据传输** — 使用锁页内存（Pinned Memory）在 CPU 与 GPU 之间高速传输数据，降低提案提交延迟。

**启动时显卡信息示例：**
```
[GPU] 检测到 1 块 CUDA 显卡：
[GPU]   [0] NVIDIA GeForce RTX 3080  |  显存: 10240 MB  |  算力: 8.6  |  CUDA核心: 8704
[GPU] 使用设备 0
```

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

**提示 `CUDA 不可用`**
- 检查 `nvidia-smi` 是否正常运行，驱动是否已安装。
- 安装与驱动匹配的 CUDA Toolkit：https://developer.nvidia.com/cuda-downloads
- 无 GPU 时程序会自动切换为 CPU 模式继续运行。

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
| [v2.0.0](https://github.com/danger0001/csd-solo-miner) | 中文界面、一键安装脚本 |
| [v1.0.0](https://github.com/danger0001/csd-solo-miner/releases/tag/v1.0.0) | 英文版初始发布 |

---

## 许可证

MIT License — 详见 [LICENSE](LICENSE) 文件。

---

## 相关链接

- [Compute Substrate 官网](https://computesubstrate.org/)
- [官方白皮书](https://computesubstrate.org/downloads/Compute_Substrate_Original_Paper.pdf)
- [官方 GitHub](https://github.com/compute-substrate/compute-substrate)
- [区块浏览器](https://explorer.computesubstrate.org)
