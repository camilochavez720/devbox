from __future__ import annotations

import os
import platform
import time
from importlib.metadata import PackageNotFoundError, version as pkg_version
from typing import Any, Dict

from devbox.config import load_config

PROCESS_START = time.time()


def get_runtime_version(package_name: str = "devbox") -> str:
    try:
        return pkg_version(package_name)
    except PackageNotFoundError:
        return "unknown"


def get_git_commit() -> str:
    # Preferimos env var inyectada por systemd (DEVBOX_GIT_COMMIT)
    commit = os.environ.get("DEVBOX_GIT_COMMIT", "").strip()
    return commit or "unknown"


def get_info(service: str = "devbox") -> Dict[str, Any]:
    cfg = load_config()
    uptime = int(time.time() - PROCESS_START)

    return {
        "service": service,
        "version": get_runtime_version("devbox"),
        "pid": os.getpid(),
        "config_path": cfg.config_path,
        "python": platform.python_version(),
        "uptime_seconds": uptime,
        "git_commit": get_git_commit(),
    }

