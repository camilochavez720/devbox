#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPT_DIR="/opt/devbox"
UNIT_FILE="/etc/systemd/system/devbox.service"
PIP_CACHE_DIR="${OPT_DIR}/.cache/pip"

echo "[0/8] Sanity checks..."
cd "$REPO_DIR"

# Fail fast: no despliegues cambios sin commitear
if [[ -n "$(git status --porcelain)" ]]; then
  echo "ERROR: repo con cambios sin commitear. Aborto." >&2
  git status --porcelain >&2
  exit 1
fi

echo "[1/8] Running tests (DEV venv)..."
source .venv/bin/activate
pytest -q

echo "[2/8] Computing git commit..."
COMMIT_EXPECTED="$(git rev-parse --short=12 HEAD)"
echo "Commit: $COMMIT_EXPECTED"

echo "[3/8] Building wheel (DEV)..."
python -m pip install -q -U build
rm -rf dist build *.egg-info src/*.egg-info
python -m build --wheel
WHEEL_PATH="$(ls -1 dist/devbox-*.whl | tail -n 1)"
WHEEL_FILE="$(basename "$WHEEL_PATH")"
echo "Wheel: $WHEEL_FILE"

echo "[4/8] Syncing artifact -> $OPT_DIR ..."
sudo mkdir -p "$OPT_DIR"
sudo rsync -a --delete   --exclude '.git'   --exclude '.venv'   --exclude '__pycache__'   --exclude '.pytest_cache'   "$REPO_DIR/pyproject.toml"   "$REPO_DIR/README.md"   "$REPO_DIR/config"   "$REPO_DIR/packaging"   "$REPO_DIR/scripts"   "$REPO_DIR/dist"   "$OPT_DIR/"

# Asegurar ownership consistente en /opt/devbox (evita mezclar root/glitch/devbox)
sudo chown -R devbox:devbox "$OPT_DIR"
sudo chmod -R g+rwX "$OPT_DIR"

# Cache de pip controlado (evita warnings por HOME/permisos)
sudo install -d -o devbox -g devbox "$PIP_CACHE_DIR"

echo "[5/8] Creating fresh prod venv (as devbox)..."
sudo rm -rf "$OPT_DIR/.venv"
sudo -H -u devbox env PIP_CACHE_DIR="$PIP_CACHE_DIR" python3 -m venv "$OPT_DIR/.venv"
sudo -H -u devbox env PIP_CACHE_DIR="$PIP_CACHE_DIR" "$OPT_DIR/.venv/bin/python" -m pip install -U pip

echo "[6/8] Installing ONLY runtime deps + wheel (as devbox)..."
REQS_FILE="/tmp/devbox-runtime-reqs.txt"

# 1) runtime deps desde [project].dependencies
sudo -H -u devbox env PIP_CACHE_DIR="$PIP_CACHE_DIR" bash -lc '
/opt/devbox/.venv/bin/python - <<'"'"'PY'"'"' > /tmp/devbox-runtime-reqs.txt
import tomllib
from pathlib import Path
d = tomllib.loads(Path("/opt/devbox/pyproject.toml").read_text(encoding="utf-8"))
print("\n".join(d["project"]["dependencies"]))
PY
'

sudo -H -u devbox env PIP_CACHE_DIR="$PIP_CACHE_DIR" "$OPT_DIR/.venv/bin/python" -m pip install -r "$REQS_FILE"

# 2) instala el wheel (NO editable, sin traer deps extra)
sudo -H -u devbox env PIP_CACHE_DIR="$PIP_CACHE_DIR" "$OPT_DIR/.venv/bin/python" -m pip install --no-deps "$OPT_DIR/dist/$WHEEL_FILE"

echo "[7/8] Updating systemd env DEVBOX_GIT_COMMIT..."
if ! sudo test -f "$UNIT_FILE"; then
  echo "ERROR: unit file not found: $UNIT_FILE" >&2
  exit 1
fi

if sudo grep -q '^Environment=DEVBOX_GIT_COMMIT=' "$UNIT_FILE"; then
  sudo sed -i -E "s/^Environment=DEVBOX_GIT_COMMIT=.*/Environment=DEVBOX_GIT_COMMIT=${COMMIT_EXPECTED}/" "$UNIT_FILE"
else
  if sudo grep -q '^Environment=DEVBOX_CONFIG=' "$UNIT_FILE"; then
    sudo sed -i "/^Environment=DEVBOX_CONFIG=/a Environment=DEVBOX_GIT_COMMIT=${COMMIT_EXPECTED}" "$UNIT_FILE"
  else
    sudo sed -i "/^\[Service\]/a Environment=DEVBOX_GIT_COMMIT=${COMMIT_EXPECTED}" "$UNIT_FILE"
  fi
fi

sudo systemctl daemon-reload
sudo systemctl restart devbox

echo "[8/8] Verifying systemd env + /info + no dev deps in prod..."
sleep 1

# 8a) systemd debe haber cargado el Environment correcto
ENV_LINE="$(sudo systemctl show devbox -p Environment --value || true)"
if ! grep -q "DEVBOX_GIT_COMMIT=${COMMIT_EXPECTED}" <<<"$ENV_LINE"; then
  echo "ERROR: systemd no cargó DEVBOX_GIT_COMMIT esperado." >&2
  echo "Environment actual: $ENV_LINE" >&2
  sudo systemctl status devbox --no-pager >&2 || true
  exit 1
fi

# 8b) /info debe responder y reportar el commit esperado
INFO_JSON="$(curl -fsS http://127.0.0.1:8080/info)"
echo "$INFO_JSON" | python3 -m json.tool >/dev/null
echo "$INFO_JSON"

INFO_COMMIT="$(python3 - <<'PY'
import json,sys
print(json.loads(sys.stdin.read()).get("git_commit",""))
PY
<<<"$INFO_JSON")"

if [[ "$INFO_COMMIT" != "$COMMIT_EXPECTED" ]]; then
  echo "ERROR: PROD corre commit distinto." >&2
  echo "Esperado: $COMMIT_EXPECTED" >&2
  echo "Corriendo: $INFO_COMMIT" >&2
  echo "Respuesta /info: $INFO_JSON" >&2
  sudo journalctl -u devbox -n 200 --no-pager >&2 || true
  exit 1
fi

# 8c) checks: pytest/httpx NO deben estar en prod
sudo "$OPT_DIR/.venv/bin/python" -m pip show pytest >/dev/null 2>&1 && { echo "ERROR: pytest instalado en prod" >&2; exit 1; } || echo "OK: pytest NO instalado (bien)"
sudo "$OPT_DIR/.venv/bin/python" -m pip show httpx  >/dev/null 2>&1 && { echo "ERROR: httpx instalado en prod"  >&2; exit 1; } || echo "OK: httpx NO instalado (bien)"

echo "DONE: PROD aligned at ${COMMIT_EXPECTED}"
