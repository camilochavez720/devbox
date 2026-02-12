import subprocess

import devbox.services.systemd as systemd


def test_active(monkeypatch):
    def fake_run(_service: str):
        return subprocess.CompletedProcess(args=[], returncode=0, stdout="active\n", stderr="")

    monkeypatch.setattr(systemd, "_run_is_active", fake_run)
    s = systemd.get_service_status("ssh")
    assert s.active is True
    assert s.state == "active"


def test_inactive(monkeypatch):
    def fake_run(_service: str):
        return subprocess.CompletedProcess(args=[], returncode=3, stdout="inactive\n", stderr="")

    monkeypatch.setattr(systemd, "_run_is_active", fake_run)
    s = systemd.get_service_status("ssh")
    assert s.active is False
    assert s.state == "inactive"


def test_not_found(monkeypatch):
    def fake_run(_service: str):
        return subprocess.CompletedProcess(
            args=[],
            returncode=4,
            stdout="",
            stderr="Unit foo.service could not be found.",
        )

    monkeypatch.setattr(systemd, "_run_is_active", fake_run)
    s = systemd.get_service_status("foo")
    assert s.active is False
    assert s.state == "not-found"
