#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPT_DIR="/opt/devbox"
UNIT_FILE="/etc/systemd/system/devbox.service"

echo "[1/7] Running tests (DEV venv)..."
cd "$REPO_DIR"
source .venv/bin/activate
pytest -q

echo "[2/7] Computing git commit..."
COMMIT="$(git rev-parse --short=12 HEAD)"
echo "Commit: $COMMIT"

echo "[3/7] Syncing repo -> $OPT_DIR ..."
sudo mkdir -p "$OPT_DIR"
sudo rsync -a --delete \
  --exclude '.git' \
  --exclude '.venv' \
  --exclude '__pycache__' \
  --exclude '.pytest_cache' \
  "$REPO_DIR/" "$OPT_DIR/"

# MUY IMPORTANTE:
# evitar que quede un src/devbox.egg-info con permisos raros que rompa installs editable
sudo rm -rf "$OPT_DIR/src/devbox.egg-info" || true

echo "[4/7] Creating/refreshing venv (prod venv) ..."
sudo rm -rf "$OPT_DIR/.venv"
sudo python3 -m venv "$OPT_DIR/.venv"
sudo "$OPT_DIR/.venv/bin/python" -m pip install -U pip

echo "[5/7] Installing ONLY runtime deps + editable package (NO dev extras) ..."
# 1) Instala runtime deps (las de [project].dependencies)
sudo "$OPT_DIR/.venv/bin/python" - <<'PY' | sudo "$OPT_DIR/.venv/bin/python" -m pip install -r /dev/stdin
import tomllib
from pathlib import Path
d = tomllib.loads(Path("/opt/devbox/pyproject.toml").read_text(encoding="utf-8"))
print("\n".join(d["project"]["dependencies"]))
PY

# 2) Instala tu paquete editable sin dependencias (para no arrastrar extras)
sudo "$OPT_DIR/.venv/bin/python" -m pip install -e "$OPT_DIR" --no-deps

echo "[6/7] Updating systemd env DEVBOX_GIT_COMMIT..."
if ! sudo test -f "$UNIT_FILE"; then
  echo "ERROR: unit file not found: $UNIT_FILE" >&2
  exit 1
fi

if sudo grep -q '^Environment=DEVBOX_GIT_COMMIT=' "$UNIT_FILE"; then
  sudo sed -i -E "s/^Environment=DEVBOX_GIT_COMMIT=.*/Environment=DEVBOX_GIT_COMMIT=${COMMIT}/" "$UNIT_FILE"
else
  if sudo grep -q '^Environment=DEVBOX_CONFIG=' "$UNIT_FILE"; then
    sudo sed -i "/^Environment=DEVBOX_CONFIG=/a Environment=DEVBOX_GIT_COMMIT=${COMMIT}" "$UNIT_FILE"
  else
    sudo sed -i "/^\[Service\]/a Environment=DEVBOX_GIT_COMMIT=${COMMIT}" "$UNIT_FILE"
  fi
fi

sudo systemctl daemon-reload
sudo systemctl restart devbox

echo "[7/7] Verifying /info..."
sleep 1
INFO_JSON="$(curl -s http://127.0.0.1:8080/info)"
echo "$INFO_JSON" | python3 -m json.tool >/dev/null
echo "$INFO_JSON"

INFO_COMMIT="$(echo "$INFO_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("git_commit",""))')"
if [[ "$INFO_COMMIT" != "$COMMIT" ]]; then
  echo "WARNING: /info git_commit ($INFO_COMMIT) != repo commit ($COMMIT)" >&2
fi

echo "DONE"
