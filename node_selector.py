"""
node_selector.py — CSD 节点选择器

功能：
  1. 检测本机上行/下行带宽
  2. 并发测量所有引导节点的 TCP 连接延迟
  3. 根据带宽阈值决定使用单个最优节点还是全部节点

带宽阈值默认：< 5 Mbps 视为低带宽，仅连接延迟最低的一个节点。
"""

import asyncio
import logging
import re
import socket
import time
import urllib.request
from typing import Optional

日志 = logging.getLogger("csd-矿工.节点选择器")

# ── 默认参数 ───────────────────────────────────────────────────────────────────

# 低带宽阈值（Mbps）：低于此值时仅使用最优单节点
低带宽阈值_Mbps = 5.0

# 带宽测速：下载小文件测速（约 1 MB）
测速URL = "https://speed.cloudflare.com/__down?bytes=1048576"

# 节点延迟测量超时（秒）
延迟超时秒 = 5.0

# 节点延迟测量重复次数（取最小值）
延迟测量次数 = 3


# ── 工具函数 ───────────────────────────────────────────────────────────────────

def 解析节点地址(多地址: str) -> tuple[str, int]:
    """
    将 /ip4/1.2.3.4/tcp/17999 解析为 ('1.2.3.4', 17999)。
    """
    匹配 = re.match(r'/ip4/([^/]+)/tcp/(\d+)', 多地址)
    if not 匹配:
        raise ValueError(f"无法解析节点地址：{多地址}")
    return 匹配.group(1), int(匹配.group(2))


def 测量TCP延迟(主机: str, 端口: int, 超时: float = 延迟超时秒) -> Optional[float]:
    """
    测量到指定主机:端口的 TCP 握手延迟（毫秒）。
    连接失败返回 None。
    """
    最短延迟 = None
    for _ in range(延迟测量次数):
        try:
            开始 = time.perf_counter()
            with socket.create_connection((主机, 端口), timeout=超时):
                pass
            耗时ms = (time.perf_counter() - 开始) * 1000
            if 最短延迟 is None or 耗时ms < 最短延迟:
                最短延迟 = 耗时ms
        except (socket.timeout, ConnectionRefusedError, OSError):
            pass
    return 最短延迟


def 测量带宽() -> Optional[float]:
    """
    下载约 1 MB 数据测量下行带宽（Mbps）。
    失败返回 None。
    """
    try:
        开始 = time.perf_counter()
        with urllib.request.urlopen(测速URL, timeout=15) as 响应:
            数据 = 响应.read()
        耗时 = time.perf_counter() - 开始
        字节数 = len(数据)
        带宽Mbps = (字节数 * 8) / 耗时 / 1_000_000
        return 带宽Mbps
    except Exception as 异常:
        日志.debug("带宽测速失败：%s", 异常)
        return None


# ── 节点选择器 ─────────────────────────────────────────────────────────────────

class 节点选择器:
    """
    根据带宽自动选择最优引导节点。

    逻辑：
      - 带宽 >= 低带宽阈值  → 使用全部节点
      - 带宽 <  低带宽阈值  → 仅使用延迟最低的一个节点
      - 无法测速           → 仅使用延迟最低的一个节点（保守策略）
    """

    def __init__(
        self,
        引导节点列表: list[str],
        低带宽阈值: float = 低带宽阈值_Mbps,
    ):
        self.引导节点列表 = 引导节点列表
        self.低带宽阈值 = 低带宽阈值
        self.测量带宽Mbps: Optional[float] = None
        self.节点延迟表: dict[str, Optional[float]] = {}

    def 测量所有节点延迟(self) -> dict[str, Optional[float]]:
        """并发测量所有节点延迟，返回 {多地址: 延迟ms 或 None}。"""
        日志.info("正在测量引导节点延迟...")
        结果 = {}
        for 节点 in self.引导节点列表:
            try:
                主机, 端口 = 解析节点地址(节点)
                延迟 = 测量TCP延迟(主机, 端口)
                结果[节点] = 延迟
                if 延迟 is not None:
                    日志.info("  %-38s  延迟: %.1f ms", 节点, 延迟)
                else:
                    日志.warning("  %-38s  不可达", 节点)
            except ValueError as 异常:
                日志.warning("  节点地址解析失败：%s", 异常)
                结果[节点] = None
        self.节点延迟表 = 结果
        return 结果

    def 获取最优节点(self) -> Optional[str]:
        """返回延迟最低的可达节点。"""
        可达节点 = {节点: 延迟 for 节点, 延迟 in self.节点延迟表.items() if 延迟 is not None}
        if not 可达节点:
            日志.warning("所有节点均不可达，返回第一个节点作为备用")
            return self.引导节点列表[0] if self.引导节点列表 else None
        最优 = min(可达节点, key=lambda k: 可达节点[k])
        return 最优

    def 选择节点(self, 跳过带宽检测: bool = False) -> tuple[list[str], str]:
        """
        执行完整的节点选择流程。

        返回：
          (选中节点列表, 选择原因说明)
        """
        # 第一步：测量节点延迟
        self.测量所有节点延迟()
        最优节点 = self.获取最优节点()

        if 跳过带宽检测:
            日志.info("跳过带宽检测，使用全部节点")
            return self.引导节点列表, "跳过带宽检测（使用全部节点）"

        # 第二步：测量带宽
        日志.info("正在测量本机带宽（下载约 1 MB）...")
        带宽 = 测量带宽()
        self.测量带宽Mbps = 带宽

        if 带宽 is None:
            日志.warning("带宽测速失败，低带宽保守模式：仅使用最优节点 %s", 最优节点)
            return ([最优节点] if 最优节点 else self.引导节点列表,
                    "带宽测速失败，保守模式：使用最优单节点")

        日志.info("本机带宽：%.2f Mbps（阈值：%.1f Mbps）", 带宽, self.低带宽阈值)

        if 带宽 < self.低带宽阈值:
            原因 = f"低带宽 ({带宽:.2f} Mbps < {self.低带宽阈值} Mbps)：仅使用最优节点"
            日志.warning("检测到低带宽！%s", 原因)
            日志.info("最优节点：%s  (延迟 %.1f ms)",
                      最优节点, self.节点延迟表.get(最优节点) or 0)
            return ([最优节点] if 最优节点 else self.引导节点列表, 原因)
        else:
            原因 = f"带宽正常 ({带宽:.2f} Mbps)：使用全部 {len(self.引导节点列表)} 个节点"
            日志.info("带宽充足，%s", 原因)
            return (self.引导节点列表, 原因)

    def 打印报告(self):
        """打印节点延迟报告。"""
        print("\n" + "=" * 55)
        print("  节点延迟报告")
        print("=" * 55)
        if self.测量带宽Mbps is not None:
            状态 = "低带宽" if self.测量带宽Mbps < self.低带宽阈值 else "正常"
            print(f"  本机带宽：{self.测量带宽Mbps:.2f} Mbps  [{状态}]")
        print("-" * 55)
        # 按延迟排序
        排序后 = sorted(
            self.节点延迟表.items(),
            key=lambda x: (x[1] is None, x[1] or 9999)
        )
        for i, (节点, 延迟) in enumerate(排序后):
            标记 = " ★ 最优" if i == 0 and 延迟 is not None else ""
            延迟文本 = f"{延迟:.1f} ms" if 延迟 is not None else "不可达"
            print(f"  {节点:<40}  {延迟文本}{标记}")
        print("=" * 55 + "\n")


# ── 命令行直接运行（调试用）────────────────────────────────────────────────────

if __name__ == "__main__":
    import sys
    logging.basicConfig(level=logging.INFO, format="%(asctime)s  %(message)s")

    主网节点 = [
        "/ip4/151.240.121.186/tcp/17999",
        "/ip4/151.240.121.220/tcp/17999",
        "/ip4/151.240.121.187/tcp/17999",
        "/ip4/158.69.116.36/tcp/17999",
        "/ip4/145.239.0.111/tcp/17999",
        "/ip4/151.240.121.189/tcp/17999",
    ]

    选择器 = 节点选择器(主网节点)
    选中节点, 原因 = 选择器.选择节点()
    选择器.打印报告()

    print(f"选择结果：{原因}")
    print(f"使用节点（共 {len(选中节点)} 个）：")
    for n in 选中节点:
        print(f"  {n}")
