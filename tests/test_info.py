from devbox.collectors.info import get_info


def test_info_has_keys(monkeypatch):
    monkeypatch.setenv("DEVBOX_CONFIG", "config/devbox.yaml")
    info = get_info(service="devbox")

    assert info["service"] == "devbox"
    assert "version" in info
    assert isinstance(info["pid"], int)
    assert "config_path" in info
    assert "uptime_seconds" in info
    assert "python" in info
    assert "git_commit" in info

    assert isinstance(info["version"], str)
    assert info["version"] != ""
