from __future__ import annotations

import os
import platform
import time
from dataclasses import asdict
from typing import Any, Dict

from devbox.config import load_config

PROCESS_START = time.time()


def get_info(service: str = "devbox", version: str = "0.1.0") -> Dict[str, Any]:
    cfg = load_config()
    uptime = int(time.time() - PROCESS_START)

    return {
        "service": service,
        "version": version,
        "pid": os.getpid(),
        "config_path": cfg.config_path,
        "python": platform.python_version(),
        "uptime_seconds": uptime,
        "git_commit": _git_commit(),
    }


def _git_commit() -> str:
    # No dependemos de git instalado ni de .git en prod
    # Si existe env var, úsala; si no, intenta leer .git/HEAD de forma simple.
    env = os.environ.get("DEVBOX_GIT_COMMIT")
    if env:
        return env

    try:
        head_path = os.path.join(os.getcwd(), ".git", "HEAD")
        with open(head_path, "r", encoding="utf-8") as f:
            head = f.read().strip()

        if head.startswith("ref:"):
            ref = head.split(" ", 1)[1].strip()
            ref_path = os.path.join(os.getcwd(), ".git", ref)
            with open(ref_path, "r", encoding="utf-8") as rf:
                return rf.read().strip()[:12]
        return head[:12]
    except Exception:
        return "unknown"
