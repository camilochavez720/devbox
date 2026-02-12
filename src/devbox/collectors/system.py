from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Any, Dict

import psutil


@dataclass(frozen=True)
class SystemSnapshot:
    cpu_percent: float
    mem: Dict[str, Any]
    disk: Dict[str, Any]
    uptime_seconds: int


def get_uptime_seconds() -> int:
    boot_time = int(psutil.boot_time())
    now = int(time.time())
    return max(0, now - boot_time)


def get_system_snapshot(disk_path: str = "/") -> SystemSnapshot:
    cpu = float(psutil.cpu_percent(interval=0.1))

    vm = psutil.virtual_memory()
    mem = {
        "total": int(vm.total),
        "used": int(vm.used),
        "available": int(vm.available),
        "percent": float(vm.percent),
    }

    du = psutil.disk_usage(disk_path)
    disk = {
        "path": disk_path,
        "total": int(du.total),
        "used": int(du.used),
        "free": int(du.free),
        "percent": float(du.percent),
    }

    return SystemSnapshot(
        cpu_percent=cpu,
        mem=mem,
        disk=disk,
        uptime_seconds=get_uptime_seconds(),
    )
