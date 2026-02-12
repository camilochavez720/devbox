from __future__ import annotations

import subprocess
from dataclasses import dataclass
from typing import List, Optional


@dataclass(frozen=True)
class ServiceStatus:
    name: str
    state: str
    active: bool
    error: Optional[str] = None


def _run_is_active(service: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["systemctl", "is-active", service],
        capture_output=True,
        text=True,
        timeout=2,
        check=False,
    )


def get_service_status(service: str) -> ServiceStatus:
    try:
        cp = _run_is_active(service)
    except subprocess.TimeoutExpired:
        return ServiceStatus(service, "timeout", False, "timeout")
    except Exception as e:
        return ServiceStatus(service, "error", False, str(e))

    out = (cp.stdout or "").strip()
    err = (cp.stderr or "").strip()

    if cp.returncode == 0:
        state = out or "active"
        return ServiceStatus(service, state, state == "active")

    # unit not found
    if "could not be found" in err.lower():
        return ServiceStatus(service, "not-found", False, err or None)

    state = out or "unknown"
    return ServiceStatus(service, state, False, err or None)


def get_services_status(services: List[str]) -> List[ServiceStatus]:
    return [get_service_status(s) for s in services]
