# 更新日志

## v5.2.1 (2026-06-15)

### 🐛 关键修复

**修复配置文件键名不匹配问题**

### 问题描述

v5.2.0 中安装脚本生成的配置文件使用中文键名（矿工、节点、GPU 等），但 miner.py 代码使用英文键名（miner、node、gpu 等），导致启动时报错：
```
KeyError: 'miner'
```

### 修复内容

- **统一配置文件键名**：将生成的 config.yaml 键名改为英文
  - `矿工` → `miner`
  - `节点` → `node`
  - `GPU` → `gpu`
  - `挖矿` → `mining`
  - `引导节点` → `bootnodes`
- **添加缺失字段**：
  - `mining.difficulty_target`
  - `node.rpc_host` / `node.p2p_host`
  - `node.genesis`
- **移除冗余字段**：删除 `低带宽模式`

### 影响

- **已安装用户**：需要重新安装或手动修复配置文件
- **新安装用户**：自动生成正确格式的配置文件

### 升级方法

**方式一：使用管理脚本重新安装（推荐）**
```bash
~/solo.sh
# 选择 [1] 重新安装
```

**方式二：手动更新**
```bash
cd ~/solo
curl -fsSL https://raw.githubusercontent.com/danger0001/solo-miner/main/solo-miner-install.sh -o solo-install.sh
chmod +x solo-install.sh
# 运行安装脚本会重新生成配置文件
```

---

## v5.2.0 (2026-06-15)

### ⭐ 多合一综合管理脚本

全新的 `solo.sh` 脚本，集成所有功能，提供友好的图形化菜单。

### ✨ 新特性

- **多合一管理脚本**：创建 `solo.sh` 脚本，集成所有功能
  - 安装/重新安装
  - 启动/停止/重启挖矿
  - 查看状态和日志
  - 更新程序
  - 编辑配置
  - 卸载
- **图形化菜单**：友好的交互式菜单界面
- **智能状态检测**：自动检测安装状态和运行状态
- **实时日志查看**：支持实时查看挖矿日志
- **GPU 状态显示**：显示 GPU 温度、使用率、显存等信息
- **配置编辑**：内置配置文件编辑功能

### 🔄 变更

- 新增 `solo.sh` 多合一管理脚本
- 更新 README 添加多合一脚本使用说明
- 优化安装流程，提供两种安装方式

### 📦 使用方法

**快速启动：**

```bash
curl -fsSL https://raw.githubusercontent.com/danger0001/solo-miner/main/solo.sh -o ~/solo.sh
chmod +x ~/solo.sh
~/solo.sh
```

### 💡 特点

- 无需记忆命令，菜单式操作
- 自动检测并显示状态
- 集成所有管理功能
- 适合新手和运维人员

---

## v5.1.0 (2026-06-15)

### 🚀 GPU 挖矿强化

恢复并强化 GPU 挖矿特性，这才是 SOLO 挖矿的核心！

### ✨ 新特性

- **GPU 优先策略**：强调 GPU 挖矿是核心功能，算力是 CPU 的 100-1000 倍
- **智能 CUDA 配置**：自动检测 GPU 并安装对应版本的 CUDA 支持（cupy-cuda12x/11x）
- **用户提示**：安装时若无 GPU 会明确提示收益极低，建议用户安装显卡驱动
- **CPU 备用**：保留 CPU 模式作为备选，但明确标注仅适合测试

### 🔄 变更

- 恢复 GPU 检测和 CUDA 自动安装逻辑
- 更新文档强调 GPU 挖矿优势
- 恢复硬件要求中对 NVIDIA GPU 的推荐
- 更新安装脚本提示信息

### 📦 依赖

- Python >= 3.9
- aiohttp >= 3.9.0
- PyYAML >= 6.0
- numpy >= 1.24.0
- cupy-cuda12x 或 cupy-cuda11x（推荐，自动安装）

### 💡 重要说明

- **GPU 是必需的**：虽然支持 CPU 模式，但 GPU 挖矿才是 SOLO 的核心价值
- 推荐配置：NVIDIA RTX 3080 及以上
- CPU 模式仅用于测试和学习，生产环境必须使用 GPU

---

## v5.0.0 (2026-06-15)

### 🎉 重大更新：CPU 友好模式

这是一个重大版本更新，专注于简化部署和降低系统要求。

### ✨ 新特性

- **零依赖安装**：只需 Python 3.9+，无需 CUDA/GPU
- **开箱即用**：不再强制要求 NVIDIA 驱动或 CUDA Toolkit
- **CPU 友好**：自动使用 CPU 模式，适合更多部署环境
- **简化脚本**：移除复杂的 GPU 检测和 CUDA 安装逻辑
- **可选 GPU**：高级用户可通过 `pip install cupy-cuda12x` 手动启用 GPU

### 🔄 变更

- 移除 GPU 硬依赖
- 简化系统检查流程
- 更新 requirements.txt，只保留核心依赖
- 降低硬件要求（4GB RAM 即可运行）

### 📦 依赖

- Python >= 3.9
- aiohttp >= 3.9.0
- PyYAML >= 6.0
- numpy >= 1.24.0

### 🚀 升级指南

从 v4.x 升级到 v5.0.0：

```bash
cd ~/solo
git pull origin main
pip3 install -r requirements.txt --upgrade
./start.sh
```

### 💡 注意事项

- v5.0.0 默认使用 CPU 模式，挖矿速度相比 GPU 模式较慢
- 适合学习、测试和低成本部署场景
- 若需 GPU 加速，请手动安装：`pip3 install cupy-cuda12x`

---

## v4.0.0 (2026-06-10)

- Solo 文件夹结构统一
- 一键安装命令简化
- 交互式钱包地址输入
- 改进用户体验

## v2.1.0

- 智能带宽检测
- 低带宽自动切换最优单节点
- 延迟测量与节点排名

## v2.0.0

- 中文界面
- 一键安装脚本
- 配置文件简化

## v1.0.0

- 初始发布
- GPU 加速挖矿
- 基本功能实现
