from __future__ import annotations

import textwrap
from pathlib import Path

import pytest
from fastapi.testclient import TestClient


@pytest.fixture()
def config_file(tmp_path: Path) -> Path:
    p = tmp_path / "devbox.yaml"
    p.write_text(
        textwrap.dedent(
            """
            http:
              host: "127.0.0.1"
              port: 8081

            auth:
              token: "test-token-123"

            services:
              - "ssh"
            """
        ).lstrip(),
        encoding="utf-8",
    )
    return p


@pytest.fixture()
def client(monkeypatch: pytest.MonkeyPatch, config_file: Path) -> TestClient:
    # Asegura que la app en tests use este config temporal, no /etc/devbox/...
    monkeypatch.setenv("DEVBOX_CONFIG", str(config_file))

    # Import aquí para que tome el env var ya seteado
    import devbox.main as main

    # Evita side effects: no queremos reiniciar nada real en tests
    monkeypatch.setattr(main, "schedule_restart", lambda: None)

    return TestClient(main.app)


def test_restart_without_token_is_401(client: TestClient) -> None:
    r = client.post("/actions/restart")
    assert r.status_code == 401
    assert r.json()["detail"] == "Unauthorized"


def test_restart_with_wrong_token_is_401(client: TestClient) -> None:
    r = client.post("/actions/restart", headers={"X-Devbox-Token": "wrong"})
    assert r.status_code == 401


def test_restart_with_correct_token_is_200(client: TestClient) -> None:
    r = client.post("/actions/restart", headers={"X-Devbox-Token": "test-token-123"})
    assert r.status_code == 200
    assert r.json() == {"status": "restarting"}
