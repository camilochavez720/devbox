from devbox.collectors.system import get_system_snapshot, get_uptime_seconds


def test_uptime_seconds_non_negative():
    assert get_uptime_seconds() >= 0


def test_system_snapshot_shape():
    snap = get_system_snapshot("/")
    assert isinstance(snap.cpu_percent, float)
    assert "total" in snap.mem and "percent" in snap.mem
    assert snap.disk["path"] == "/"
    assert snap.uptime_seconds >= 0
