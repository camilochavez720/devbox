#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPT_DIR="/opt/devbox"
UNIT_FILE="/etc/systemd/system/devbox.service"

echo "[1/8] Running tests (DEV venv)..."
cd "$REPO_DIR"
source .venv/bin/activate
pytest -q

echo "[2/8] Computing git commit..."
COMMIT="$(git rev-parse --short=12 HEAD)"
echo "Commit: $COMMIT"

echo "[3/8] Building wheel (DEV)..."
python -m pip install -q -U build
rm -rf dist build *.egg-info src/*.egg-info
python -m build --wheel
WHEEL_PATH="$(ls -1 dist/devbox-*.whl | tail -n 1)"
WHEEL_FILE="$(basename "$WHEEL_PATH")"
echo "Wheel: $WHEEL_FILE"

echo "[4/8] Syncing artifact -> $OPT_DIR ..."
sudo mkdir -p "$OPT_DIR"
sudo rsync -a --delete \
  --exclude '.git' \
  --exclude '.venv' \
  --exclude '__pycache__' \
  --exclude '.pytest_cache' \
  "$REPO_DIR/pyproject.toml" \
  "$REPO_DIR/README.md" \
  "$REPO_DIR/config" \
  "$REPO_DIR/packaging" \
  "$REPO_DIR/scripts" \
  "$REPO_DIR/dist" \
  "$OPT_DIR/"

# Asegurar ownership consistente en /opt/devbox (evita mezclar root/glitch/devbox)
sudo chown -R devbox:devbox "$OPT_DIR"
sudo chmod -R g+rwX "$OPT_DIR"

echo "[5/8] Creating fresh prod venv (as devbox)..."
sudo rm -rf "$OPT_DIR/.venv"
sudo -H -u devbox python3 -m venv "$OPT_DIR/.venv"
sudo -H -u devbox "$OPT_DIR/.venv/bin/python" -m pip install -U pip

echo "[6/8] Installing ONLY runtime deps + wheel (as devbox)..."
# 1) runtime deps desde [project].dependencies
REQS_FILE="/tmp/devbox-runtime-reqs.txt"

sudo -H -u devbox bash -lc '
/opt/devbox/.venv/bin/python - <<'"'"'PY'"'"' > /tmp/devbox-runtime-reqs.txt
import tomllib
from pathlib import Path
d = tomllib.loads(Path("/opt/devbox/pyproject.toml").read_text(encoding="utf-8"))
print("\n".join(d["project"]["dependencies"]))
PY
'

sudo -H -u devbox /opt/devbox/.venv/bin/python -m pip install -r "$REQS_FILE"


# Instala desde archivo (evita /dev/stdin)
sudo -H -u devbox "$OPT_DIR/.venv/bin/python" -m pip install -r "$REQS_FILE"

# 2) instala el wheel (NO editable)
sudo -H -u devbox "$OPT_DIR/.venv/bin/python" -m pip install --no-deps "$OPT_DIR/dist/$WHEEL_FILE"

echo "[7/8] Updating systemd env DEVBOX_GIT_COMMIT..."
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

echo "[8/8] Verifying /info + no dev deps in prod..."
sleep 1
INFO_JSON="$(curl -s http://127.0.0.1:8080/info)"
echo "$INFO_JSON" | python3 -m json.tool >/dev/null
echo "$INFO_JSON"

INFO_COMMIT="$(echo "$INFO_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("git_commit",""))')"
if [[ "$INFO_COMMIT" != "$COMMIT" ]]; then
  echo "WARNING: /info git_commit ($INFO_COMMIT) != repo commit ($COMMIT)" >&2
fi

# checks: pytest/httpx NO deben estar en prod
sudo "$OPT_DIR/.venv/bin/python" -m pip show pytest >/dev/null 2>&1 && echo "WARNING: pytest instalado en prod" || echo "OK: pytest NO instalado (bien)"
sudo "$OPT_DIR/.venv/bin/python" -m pip show httpx  >/dev/null 2>&1 && echo "WARNING: httpx instalado en prod"  || echo "OK: httpx NO instalado (bien)"

echo "DONE"
