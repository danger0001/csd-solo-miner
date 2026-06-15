#!/usr/bin/env python3
"""
miner.py — CSD 单机 GPU 矿工
Compute Substrate 主网矿工，使用 GPU 加速哈希计算，
自动向 CSD 网络提交提案与认证。
"""

import argparse
import asyncio
import json
import logging
import os
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Optional

import aiohttp
import yaml

from gpu_worker import GPU工作器
from node_selector import 节点选择器

# ── 日志配置 ──────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
日志 = logging.getLogger("csd-矿工")

# ── 主网引导节点 ──────────────────────────────────────────────────────────────

主网引导节点 = [
    "/ip4/151.240.121.186/tcp/17999",
    "/ip4/151.240.121.220/tcp/17999",
    "/ip4/151.240.121.187/tcp/17999",
    "/ip4/158.69.116.36/tcp/17999",
    "/ip4/145.239.0.111/tcp/17999",
    "/ip4/151.240.121.189/tcp/17999",
]


# ── 配置加载 ──────────────────────────────────────────────────────────────────

def 加载配置(路径: str) -> dict:
    with open(路径) as f:
        return yaml.safe_load(f)


def 构建RPC地址(配置: dict) -> str:
    主机 = 配置["node"]["rpc_host"].replace("0.0.0.0", "127.0.0.1")
    端口 = 配置["node"]["rpc_port"]
    return f"http://{主机}:{端口}"


# ── CSD 节点管理 ──────────────────────────────────────────────────────────────

class CSD节点:
    """管理 csd 节点子进程。"""

    def __init__(self, 配置: dict, 引导节点列表: list[str]):
        self.配置 = 配置
        self.引导节点列表 = 引导节点列表
        self.进程: Optional[subprocess.Popen] = None

    def _构建命令(self) -> list[str]:
        n = self.配置["node"]
        命令 = [
            "./csd", "node",
            "--datadir", n["datadir"],
            "--rpc", f"{n['rpc_host']}:{n['rpc_port']}",
            "--genesis", n["genesis"],
            "--p2p-listen", f"/ip4/{n['p2p_host']}/tcp/{n['p2p_port']}",
        ]
        for 节点 in self.引导节点列表:
            命令 += ["--bootnodes", 节点]
        return 命令

    def 启动(self):
        命令 = self._构建命令()
        节点摘要 = "、".join(self.引导节点列表[:3])
        if len(self.引导节点列表) > 3:
            节点摘要 += f" 等共 {len(self.引导节点列表)} 个"
        日志.info("正在启动 csd 节点...")
        日志.info("  引导节点：%s", 节点摘要)
        日志.info("  RPC 地址：%s:%s", self.配置["node"]["rpc_host"], self.配置["node"]["rpc_port"])
        日志.info("  P2P 地址：/ip4/%s/tcp/%s", self.配置["node"]["p2p_host"], self.配置["node"]["p2p_port"])

        self.进程 = subprocess.Popen(
            命令,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        日志.info("csd 节点已启动（PID %d）", self.进程.pid)

    def 停止(self):
        if self.进程 and self.进程.poll() is None:
            日志.info("正在停止 csd 节点（PID %d）...", self.进程.pid)
            self.进程.terminate()
            try:
                self.进程.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.进程.kill()

    def 运行中(self) -> bool:
        return self.进程 is not None and self.进程.poll() is None

    async def 输出日志(self):
        if not self.进程:
            return
        循环 = asyncio.get_event_loop()
        while self.运行中():
            行 = await 循环.run_in_executor(None, self.进程.stdout.readline)
            if 行:
                日志.debug("[节点] %s", 行.rstrip())
            else:
                await asyncio.sleep(0.1)


# ── RPC 客户端 ────────────────────────────────────────────────────────────────

class CSD客户端:
    """csd 节点 RPC 异步 HTTP 客户端。"""

    def __init__(self, 基础地址: str):
        self.基础地址 = 基础地址
        self._会话: Optional[aiohttp.ClientSession] = None

    async def __aenter__(self):
        self._会话 = aiohttp.ClientSession(
            timeout=aiohttp.ClientTimeout(total=10)
        )
        return self

    async def __aexit__(self, *_):
        if self._会话:
            await self._会话.close()

    async def _GET(self, 路径: str) -> dict:
        async with self._会话.get(f"{self.基础地址}{路径}") as r:
            r.raise_for_status()
            return await r.json()

    async def _POST(self, 路径: str, 数据: dict) -> dict:
        async with self._会话.post(
            f"{self.基础地址}{路径}",
            json=数据,
            headers={"Content-Type": "application/json"},
        ) as r:
            r.raise_for_status()
            return await r.json()

    async def 获取状态(self) -> dict:
        return await self._GET("/status")

    async def 获取轮次(self) -> int:
        状态 = await self.获取状态()
        return 状态.get("epoch", 0)

    async def 获取节点列表(self) -> list:
        结果 = await self._GET("/peers")
        return 结果.get("peers", [])

    async def 提交提案(self, 域: str, 随机数: int, 哈希: str, 载荷: str) -> dict:
        return await self._POST("/proposal", {
            "domain": 域,
            "nonce": 随机数,
            "hash": 哈希,
            "payload": 载荷,
        })

    async def 提交认证(self, 提案ID: str, 分数: float, 置信度: float) -> dict:
        return await self._POST("/attest", {
            "proposal_id": 提案ID,
            "score": 分数,
            "confidence": 置信度,
        })

    async def 获取提案列表(self, 域: str, 轮次: int) -> list:
        结果 = await self._GET(f"/proposals/{域}/{轮次}")
        return 结果.get("proposals", [])

    async def 等待节点就绪(self, 最大重试次数: int = 40, 间隔秒数: float = 3.0):
        日志.info("等待节点 RPC 就绪...")
        for 第几次 in range(最大重试次数):
            try:
                await self.获取状态()
                日志.info("节点 RPC 已就绪")
                return
            except Exception:
                if 第几次 < 最大重试次数 - 1:
                    await asyncio.sleep(间隔秒数)
        raise RuntimeError("节点 RPC 等待超时，请检查节点是否正常启动")


# ── 统计数据 ──────────────────────────────────────────────────────────────────

class 挖矿统计:
    def __init__(self):
        self.启动时间 = time.time()
        self.已提交提案数 = 0
        self.已接受提案数 = 0
        self.已提交认证数 = 0
        self.当前轮次 = 0
        self.上次获奖轮次 = 0
        self.GPU算力MHs = 0.0
        self.已连接节点数 = 0

    def 运行时间(self) -> int:
        return int(time.time() - self.启动时间)

    def 转为字典(self) -> dict:
        return {
            "运行时间（秒）": self.运行时间(),
            "已提交提案数": self.已提交提案数,
            "已接受提案数": self.已接受提案数,
            "已提交认证数": self.已提交认证数,
            "GPU算力（MH/s）": round(self.GPU算力MHs, 2),
            "已连接节点数": self.已连接节点数,
            "当前轮次": self.当前轮次,
            "上次获奖轮次": self.上次获奖轮次,
        }

    def 打印摘要(self):
        日志.info(
            "统计 | 轮次=%d  提案=%d/%d  认证=%d  算力=%.1f MH/s  节点=%d  运行=%d秒",
            self.当前轮次,
            self.已接受提案数,
            self.已提交提案数,
            self.已提交认证数,
            self.GPU算力MHs,
            self.已连接节点数,
            self.运行时间(),
        )


# ── 统计 HTTP 服务 ────────────────────────────────────────────────────────────

async def 统计服务(统计: 挖矿统计, 主机: str = "127.0.0.1", 端口: int = 9090):
    from aiohttp import web

    async def 处理请求(request):
        return web.json_response(统计.转为字典(), dumps=lambda d: json.dumps(d, ensure_ascii=False, indent=2))

    应用 = web.Application()
    应用.router.add_get("/stats", 处理请求)
    应用.router.add_get("/统计", 处理请求)
    运行器 = web.AppRunner(应用)
    await 运行器.setup()
    站点 = web.TCPSite(运行器, 主机, 端口)
    await 站点.start()
    日志.info("监控面板：http://%s:%d/统计", 主机, 端口)


# ── 提案循环 ──────────────────────────────────────────────────────────────────

async def 提案循环(客户端: CSD客户端, GPU: GPU工作器, 配置: dict, 统计: 挖矿统计):
    域 = 配置["mining"]["domain"]
    间隔 = 配置["mining"]["proposal_interval"]
    难度 = 配置["mining"]["difficulty_target"]
    钱包 = 配置["miner"]["wallet_address"]
    工作器 = 配置["miner"]["worker_name"]

    日志.info("提案循环已启动 | 域=%s  间隔=%d秒", 域, 间隔)

    while True:
        try:
            轮次 = await 客户端.获取轮次()
            统计.当前轮次 = 轮次

            # GPU 计算最优随机数和哈希
            t0 = time.perf_counter()
            随机数, 哈希值 = await asyncio.get_event_loop().run_in_executor(
                None, GPU.搜索随机数, 轮次, 难度
            )
            耗时 = time.perf_counter() - t0
            统计.GPU算力MHs = (GPU.批量大小 / 耗时) / 1e6

            载荷 = json.dumps({
                "wallet": 钱包,
                "worker": 工作器,
                "epoch": 轮次,
                "ts": int(time.time()),
            })

            结果 = await 客户端.提交提案(域, 随机数, 哈希值, 载荷)
            统计.已提交提案数 += 1

            if 结果.get("accepted"):
                统计.已接受提案数 += 1
                日志.info(
                    "提案已接受 | 轮次=%d  随机数=%d  哈希=%s...  算力=%.1f MH/s",
                    轮次, 随机数, 哈希值[:16], 统计.GPU算力MHs,
                )
            else:
                原因 = 结果.get("reason", "未知")
                日志.warning("提案被拒绝 | 轮次=%d  原因=%s", 轮次, 原因)

        except aiohttp.ClientError as 异常:
            日志.warning("提案循环 RPC 错误：%s", 异常)
        except Exception as 异常:
            日志.error("提案循环意外错误：%s", 异常, exc_info=True)

        await asyncio.sleep(间隔)


async def 认证循环(客户端: CSD客户端, GPU: GPU工作器, 配置: dict, 统计: 挖矿统计):
    域 = 配置["mining"]["domain"]
    间隔 = 配置["mining"]["attestation_interval"]

    日志.info("认证循环已启动 | 域=%s  间隔=%d秒", 域, 间隔)

    while True:
        try:
            轮次 = await 客户端.获取轮次()
            提案列表 = await 客户端.获取提案列表(域, 轮次)

            if 提案列表:
                已评分 = await asyncio.get_event_loop().run_in_executor(
                    None, GPU.评分提案, 提案列表
                )
                最优 = max(已评分, key=lambda x: x["score"])
                await 客户端.提交认证(最优["id"], 最优["score"], 最优["confidence"])
                统计.已提交认证数 += 1
                日志.debug(
                    "认证已提交 | 提案=%s  分数=%.4f  置信度=%.4f",
                    最优["id"][:12], 最优["score"], 最优["confidence"],
                )

        except aiohttp.ClientError as 异常:
            日志.warning("认证循环 RPC 错误：%s", 异常)
        except Exception as 异常:
            日志.error("认证循环意外错误：%s", 异常, exc_info=True)

        await asyncio.sleep(间隔)


async def 节点监控(客户端: CSD客户端, 统计: 挖矿统计):
    while True:
        try:
            节点列表 = await 客户端.获取节点列表()
            统计.已连接节点数 = len(节点列表)
            if 统计.已连接节点数 == 0:
                日志.warning("当前无已连接节点，请检查引导节点配置或网络连接")
        except Exception:
            pass
        await asyncio.sleep(30)


async def 定时统计(统计: 挖矿统计):
    while True:
        await asyncio.sleep(60)
        统计.打印摘要()


# ── 参数解析 ──────────────────────────────────────────────────────────────────

def 解析参数():
    解析器 = argparse.ArgumentParser(description="CSD 单机 GPU 矿工")
    解析器.add_argument("--config", "--配置", default="config.yaml", help="配置文件路径")
    解析器.add_argument(
        "--bootnodes", "--引导节点", default=None,
        help='引导节点（逗号分隔），或 "全部"/"all" 使用所有主网节点',
    )
    解析器.add_argument("--no-node", "--仅矿工", action="store_true", help="跳过启动 csd 节点")
    解析器.add_argument("--gpu", "--显卡", type=int, default=None, help="指定显卡设备编号")
    解析器.add_argument("--debug", "--调试", action="store_true", help="开启详细日志")
    解析器.add_argument(
        "--skip-bw", "--跳过带宽检测", action="store_true",
        help="跳过带宽检测，强制使用全部引导节点",
    )
    解析器.add_argument(
        "--bw-threshold", "--带宽阈值", type=float, default=5.0,
        help="低带宽阈值（Mbps），低于此值仅使用最优单节点（默认 5.0）",
    )
    return 解析器.parse_args()


def 解析引导节点(参数值: Optional[str], 配置节点: list[str]) -> list[str]:
    if 参数值 is None:
        return 配置节点 or 主网引导节点
    if 参数值.strip().lower() in ("全部", "all"):
        return 主网引导节点
    return [n.strip() for n in 参数值.split(",") if n.strip()]


# ── 主程序 ────────────────────────────────────────────────────────────────────

async def 主程序():
    参数 = 解析参数()

    if 参数.debug:
        logging.getLogger().setLevel(logging.DEBUG)

    配置路径 = Path(参数.config)
    if not 配置路径.exists():
        日志.error("配置文件不存在：%s  请先运行 ./install.sh", 配置路径)
        sys.exit(1)
    配置 = 加载配置(str(配置路径))

    if 参数.gpu is not None:
        配置["gpu"]["device_id"] = 参数.gpu

    候选节点列表 = 解析引导节点(参数.bootnodes, 配置.get("bootnodes", []))

    # ── 带宽检测 + 最优节点选择 ───────────────────────────────────────────────
    选择器 = 节点选择器(候选节点列表, 低带宽阈值=参数.bw_threshold)
    引导节点列表, 选择原因 = 选择器.选择节点(跳过带宽检测=参数.skip_bw)
    选择器.打印报告()
    日志.info("节点选择策略：%s", 选择原因)
    日志.info("最终使用引导节点（共 %d 个）：", len(引导节点列表))
    for 节点 in 引导节点列表:
        日志.info("  %s", 节点)

    钱包 = 配置["miner"].get("wallet_address", "")
    if not 钱包 or 钱包 == "YOUR_WALLET_ADDRESS_HERE":
        日志.error("wallet_address 未在 config.yaml 中设置")
        sys.exit(1)

    统计 = 挖矿统计()

    # 启动 csd 节点
    节点 = CSD节点(配置, 引导节点列表)
    if not 参数.no_node:
        节点.启动()

    # 优雅退出处理
    循环 = asyncio.get_event_loop()
    退出事件 = asyncio.Event()

    def _退出处理():
        日志.info("收到退出信号...")
        退出事件.set()

    for 信号量 in (signal.SIGINT, signal.SIGTERM):
        循环.add_signal_handler(信号量, _退出处理)

    # 初始化 GPU 工作器
    GPU = GPU工作器(
        设备编号=配置["gpu"]["device_id"],
        每块线程数=配置["gpu"]["threads_per_block"],
        最大块数=配置["gpu"]["max_blocks"],
        批量大小=配置["gpu"]["batch_size"],
    )
    GPU.初始化()

    RPC地址 = 构建RPC地址(配置)

    async with CSD客户端(RPC地址) as 客户端:
        await 客户端.等待节点就绪()

        任务列表 = [
            asyncio.create_task(提案循环(客户端, GPU, 配置, 统计)),
            asyncio.create_task(认证循环(客户端, GPU, 配置, 统计)),
            asyncio.create_task(节点监控(客户端, 统计)),
            asyncio.create_task(定时统计(统计)),
            asyncio.create_task(统计服务(统计)),
        ]
        if not 参数.no_node:
            任务列表.append(asyncio.create_task(节点.输出日志()))

        带宽文本 = f"{选择器.测量带宽Mbps:.2f} Mbps" if 选择器.测量带宽Mbps else "未测量"
        日志.info("=" * 60)
        日志.info("  CSD 单机 GPU 矿工已启动")
        日志.info("  钱包地址  : %s", 钱包)
        日志.info("  挖矿域    : %s", 配置["mining"]["domain"])
        日志.info("  显卡设备  : %d", 配置["gpu"]["device_id"])
        日志.info("  本机带宽  : %s", 带宽文本)
        日志.info("  引导节点  : %d 个（%s）", len(引导节点列表), 选择原因)
        日志.info("  监控面板  : http://127.0.0.1:9090/统计")
        日志.info("=" * 60)

        await 退出事件.wait()

        日志.info("正在关闭...")
        for t in 任务列表:
            t.cancel()
        await asyncio.gather(*任务列表, return_exceptions=True)

    节点.停止()
    GPU.关闭()
    日志.info("矿工已停止，最终统计：")
    统计.打印摘要()


if __name__ == "__main__":
    asyncio.run(主程序())
