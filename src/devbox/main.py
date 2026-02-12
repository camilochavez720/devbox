from fastapi import FastAPI
from devbox.collectors.system import get_system_snapshot
from devbox.config import load_config
from devbox.services.systemd import get_services_status

app = FastAPI(title="devbox", version="0.1.0")


@app.get("/health")
def health():
    return {"status": "ok", "service": "devbox", "version": "0.1.0"}


@app.get("/system")
def system():
    snap = get_system_snapshot(disk_path="/")
    return {
        "cpu_percent": snap.cpu_percent,
        "mem": snap.mem,
        "disk": snap.disk,
        "uptime_seconds": snap.uptime_seconds,
    }

@app.get("/services")
def services():
    cfg = load_config()
    statuses = get_services_status(cfg.services)
    return {
        "config_path": cfg.config_path,
        "services": [
            {"name": s.name, "state": s.state, "active": s.active, "error": s.error}
            for s in statuses
        ],
    }
