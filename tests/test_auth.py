import pytest
from fastapi import HTTPException

import devbox.auth as auth


class DummyCfg:
    auth_token = "secret"
    config_path = "dummy"


def test_require_token_ok(monkeypatch):
    monkeypatch.setattr(auth, "load_config", lambda: DummyCfg())
    auth.require_token("secret")


def test_require_token_missing(monkeypatch):
    monkeypatch.setattr(auth, "load_config", lambda: DummyCfg())
    with pytest.raises(HTTPException) as e:
        auth.require_token(None)
    assert e.value.status_code == 401


def test_require_token_bad(monkeypatch):
    monkeypatch.setattr(auth, "load_config", lambda: DummyCfg())
    with pytest.raises(HTTPException) as e:
        auth.require_token("nope")
    assert e.value.status_code == 401
