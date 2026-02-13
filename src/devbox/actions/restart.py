from __future__ import annotations

import os
import threading
import time


def _exit_process_after_delay(delay_s: float) -> None:
    time.sleep(delay_s)
    os._exit(0)  # systemd reinicia el proceso


def schedule_restart(delay_s: float = 0.3) -> None:
    t = threading.Thread(target=_exit_process_after_delay, args=(delay_s,), daemon=True)
    t.start()
