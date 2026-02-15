from __future__ import annotations

from fastapi import Header, HTTPException, status

from devbox.config import load_config


def require_token(
    x_devbox_token: str | None = Header(default=None, alias="X-Devbox-Token"),
) -> None:
    cfg = load_config()
    expected = (cfg.auth_token or "").strip()

    # Fail-closed: si no hay token configurado, es error del servidor
    if not expected:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Server misconfigured: auth.token is empty",
        )

    provided = (x_devbox_token or "").strip()
    if not provided or provided != expected:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Unauthorized",
        )
