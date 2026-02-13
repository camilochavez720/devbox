from __future__ import annotations

from fastapi import Header, HTTPException

from devbox.config import load_config


def require_token(x_devbox_token: str | None = Header(default=None)) -> None:
    cfg = load_config()
    expected = (cfg.auth_token or "").strip()

    # Fail-closed: si no hay token configurado, es error de servidor
    if not expected:
        raise HTTPException(status_code=500, detail="Auth token no configurado en config")

    if not x_devbox_token or x_devbox_token.strip() != expected:
        raise HTTPException(status_code=401, detail="Unauthorized")

