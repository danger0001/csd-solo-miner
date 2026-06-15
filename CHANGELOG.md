# 更新日志

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
