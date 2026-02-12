from fastapi import FastAPI

from devbox.collectors.system import get_system_snapshot

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
