# CSD 单机挖矿程序

针对 [Compute Substrate](https://computesubstrate.org/) 网络的单机挖矿工具。向 CSD 主网提交提案与认证，获得挖矿收益。

## 🎉 v5.0.0 重大更新

- ✅ **零依赖安装**：只需 Python 3.9+，无需 CUDA/GPU
- ✅ **开箱即用**：不再强制要求显卡驱动和 CUDA Toolkit
- ✅ **CPU 友好**：自动使用 CPU 模式，适合更多设备
- ✅ **简化部署**：移除复杂的 GPU 检测和配置步骤
- ⚡ **可选 GPU**：高级用户可手动安装 CuPy 启用 GPU 加速

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
| 内存 | 4 GB | 8 GB |
| 显卡 | 无需显卡（CPU 模式） | NVIDIA GPU（可选，需手动启用） |
| 硬盘 | 10 GB SSD | 50 GB SSD |
| 网络 | 5 Mbps | 50 Mbps 以上 |

**系统环境：**
- Linux（推荐 Ubuntu 20.04 及以上）
- Python 3.9 或更高版本
- ⚠️ **注意**：本版本（v5.0.0）使用 CPU 模式，无需安装显卡驱动或 CUDA

---

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/danger0001/solo-miner/main/install.sh | bash
```

`install.sh` 会自动完成：下载 csd 节点程序、下载 genesis 文件、安装 Python 依赖（仅需 Python 3.9+）、生成配置文件，最后引导你填写钱包地址并启动挖矿。

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

## 挖矿原理

本程序通过以下方式运行挖矿：

1. **哈希计算** — 使用 Python hashlib 计算 SHA-256(轮次 || 随机数)，筛选满足难度目标的结果
2. **提案评分** — 评估提案列表，找出置信度最高的认证目标
3. **自动提交** — 向 CSD 节点提交提案和认证，无需人工干预

**v5.0.0 版本特点：**
- 使用 CPU 模式，无需显卡
- 适合云服务器、VPS、个人电脑等各种环境
- 若需 GPU 加速，可手动安装：`pip install cupy-cuda12x`

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

**v5.0.0 需要 GPU 吗？**
- 不需要！本版本默认使用 CPU 模式，适合任何 Linux 系统
- 若需 GPU 加速，可手动安装 CuPy：`pip install cupy-cuda12x`

**CPU 模式挖矿效率如何？**
- CPU 模式可以正常提交提案和认证，只是哈希计算速度较 GPU 慢
- 适合低成本测试和学习 CSD 挖矿流程

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
| [v5.0.0](https://github.com/danger0001/solo-miner) | 🎉 **重大更新**：只需 Python 3.9+，移除 GPU 硬依赖，CPU 友好模式 |
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
