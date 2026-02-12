from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml


@dataclass(frozen=True)
class DevboxConfig:
    http_host: str
    http_port: int
    auth_token: str
    services: List[str]
    config_path: str


def _first_existing(paths: List[Path]) -> Optional[Path]:
    for p in paths:
        if p.exists() and p.is_file():
            return p
    return None


def get_config_path() -> Path:
    env = os.environ.get("DEVBOX_CONFIG")
    candidates: List[Path] = []
    if env:
        candidates.append(Path(env).expanduser())
    candidates.append(Path("/etc/devbox/config.yaml"))
    candidates.append(Path.cwd() / "config" / "devbox.yaml")

    chosen = _first_existing(candidates)
    if not chosen:
        raise FileNotFoundError(
            "No se encontró config. Crea ./config/devbox.yaml o define DEVBOX_CONFIG "
            "o usa /etc/devbox/config.yaml."
        )
    return chosen


def load_config() -> DevboxConfig:
    path = get_config_path()
    with path.open("r", encoding="utf-8") as f:
        data: Dict[str, Any] = yaml.safe_load(f) or {}

    http = data.get("http", {}) or {}
    auth = data.get("auth", {}) or {}

    http_host = str(http.get("host", "127.0.0.1"))
    http_port = int(http.get("port", 8080))
    auth_token = str(auth.get("token", ""))

    services = data.get("services") or []
    if not isinstance(services, list):
        raise ValueError("config.services debe ser una lista de strings")
    services = [str(s) for s in services]

    return DevboxConfig(
        http_host=http_host,
        http_port=http_port,
        auth_token=auth_token,
        services=services,
        config_path=str(path),
    )
