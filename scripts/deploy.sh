#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPT_DIR="/opt/devbox"
UNIT_NAME="devbox"
UNIT_FILE="/etc/systemd/system/devbox.service"
ENV_FILE="/etc/devbox/devbox.env"
PIP_CACHE_DIR="${OPT_DIR}/.cache/pip"

log() { echo "$@"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

log "[0/8] Sanity checks..."
cd "$REPO_DIR"

# Fail fast: no despliegues cambios sin commitear
if [[ -n "$(git status --porcelain)" ]]; then
  echo "ERROR: repo con cambios sin commitear. Aborto." >&2
  git status --porcelain >&2
  exit 1
fi

if [[ ! -x .venv/bin/python ]]; then
  fail "DEV venv no encontrado en $REPO_DIR/.venv (esperaba .venv/bin/python)"
fi

log "[1/8] Running tests (DEV venv)..."
source .venv/bin/activate
pytest -q

log "[2/8] Computing git commit..."
COMMIT_EXPECTED="$(git rev-parse --short=12 HEAD)"
log "Commit: ${COMMIT_EXPECTED}"

log "[3/8] Building wheel (DEV)..."
python -m pip install -q -U build
rm -rf dist build *.egg-info src/*.egg-info
python -m build --wheel
WHEEL_PATH="$(ls -1 dist/devbox-*.whl | tail -n 1)"
WHEEL_FILE="$(basename "$WHEEL_PATH")"
log "Wheel: ${WHEEL_FILE}"

log "[4/8] Syncing artifact -> ${OPT_DIR} ..."
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

# Cache de pip controlado (evita warnings por HOME/permisos)
sudo install -d -o devbox -g devbox "$PIP_CACHE_DIR"

log "[5/8] Creating fresh prod venv (as devbox)..."
sudo rm -rf "$OPT_DIR/.venv"
sudo -H -u devbox env PIP_CACHE_DIR="$PIP_CACHE_DIR" python3 -m venv "$OPT_DIR/.venv"
sudo -H -u devbox env PIP_CACHE_DIR="$PIP_CACHE_DIR" "$OPT_DIR/.venv/bin/python" -m pip install -U pip

log "[6/8] Installing ONLY runtime deps + wheel (as devbox)..."
REQS_FILE="/tmp/devbox-runtime-reqs.txt"

# runtime deps desde [project].dependencies
sudo -H -u devbox env PIP_CACHE_DIR="$PIP_CACHE_DIR" bash -lc '
/opt/devbox/.venv/bin/python - <<"PY" > /tmp/devbox-runtime-reqs.txt
import tomllib
from pathlib import Path
p = Path("/opt/devbox/pyproject.toml")
d = tomllib.loads(p.read_text(encoding="utf-8"))
print("\n".join(d["project"]["dependencies"]))
PY
'

sudo -H -u devbox env PIP_CACHE_DIR="$PIP_CACHE_DIR" "$OPT_DIR/.venv/bin/python" -m pip install -r "$REQS_FILE"

# instala el wheel (NO editable, sin traer deps extra)
sudo -H -u devbox env PIP_CACHE_DIR="$PIP_CACHE_DIR" "$OPT_DIR/.venv/bin/python" -m pip install --no-deps "$OPT_DIR/dist/$WHEEL_FILE"

log "[7/8] Updating DEVBOX_GIT_COMMIT via EnvironmentFile..."

# Verifica que el servicio use EnvironmentFile (para evitar que el deploy mienta)
if ! sudo systemctl cat "$UNIT_NAME" 2>/dev/null | grep -q "^EnvironmentFile=${ENV_FILE}$"; then
  fail "El unit $UNIT_NAME no está configurado con EnvironmentFile=${ENV_FILE}. Actualiza /etc/systemd/system/devbox.service"
fi

sudo install -d -m 0755 /etc/devbox

if ! sudo test -f "$ENV_FILE"; then
  sudo tee "$ENV_FILE" >/dev/null <<EOF_ENV
DEVBOX_CONFIG=/etc/devbox/config.yaml
DEVBOX_GIT_COMMIT=${COMMIT_EXPECTED}
EOF_ENV
  sudo chown root:devbox "$ENV_FILE"
  sudo chmod 640 "$ENV_FILE"
else
  # Asegura que exista DEVBOX_CONFIG (si no, lo añade).
  if ! sudo grep -q '^DEVBOX_CONFIG=' "$ENV_FILE"; then
    echo "DEVBOX_CONFIG=/etc/devbox/config.yaml" | sudo tee -a "$ENV_FILE" >/dev/null
  fi
  # Actualiza commit (si no existe, lo añade).
  if sudo grep -q '^DEVBOX_GIT_COMMIT=' "$ENV_FILE"; then
    sudo sed -i -E "s/^DEVBOX_GIT_COMMIT=.*/DEVBOX_GIT_COMMIT=${COMMIT_EXPECTED}/" "$ENV_FILE"
  else
    echo "DEVBOX_GIT_COMMIT=${COMMIT_EXPECTED}" | sudo tee -a "$ENV_FILE" >/dev/null
  fi
  sudo chown root:devbox "$ENV_FILE"
  sudo chmod 640 "$ENV_FILE"
fi

sudo systemctl restart "$UNIT_NAME"

log "[8/8] Verifying readiness + /info + no dev deps in prod..."

# Espera a que el servicio esté listo (evita carreras post-restart)
READY=0
for _ in {1..60}; do
  if curl -fsS http://127.0.0.1:8080/health >/dev/null; then
    READY=1
    break
  fi
  sleep 0.2
done
if [[ "$READY" -ne 1 ]]; then
  echo "ERROR: devbox no quedó listo en http://127.0.0.1:8080" >&2
  sudo systemctl status "$UNIT_NAME" --no-pager >&2 || true
  sudo journalctl -u "$UNIT_NAME" -n 200 --no-pager >&2 || true
  exit 1
fi

INFO_JSON="$(curl -fsS --retry 20 --retry-connrefused --retry-delay 1 http://127.0.0.1:8080/info)"
echo "$INFO_JSON" | python3 -m json.tool >/dev/null
log "$INFO_JSON"
COMMIT_PROD="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("git_commit",""))' "$INFO_JSON")"

if [[ "$COMMIT_PROD" != "$COMMIT_EXPECTED" ]]; then
  echo "ERROR: PROD corre commit distinto." >&2
  echo "Esperado: $COMMIT_EXPECTED" >&2
  echo "Corriendo: $COMMIT_PROD" >&2
  echo "Respuesta /info: $INFO_JSON" >&2
  sudo journalctl -u "$UNIT_NAME" -n 200 --no-pager >&2 || true
  exit 1
fi

# checks: pytest/httpx NO deben estar en prod
sudo "$OPT_DIR/.venv/bin/python" -m pip show pytest >/dev/null 2>&1 && fail "pytest instalado en prod"
sudo "$OPT_DIR/.venv/bin/python" -m pip show httpx  >/dev/null 2>&1 && fail "httpx instalado en prod"
log "OK: pytest/httpx NO instalados (bien)"

log "DONE: PROD aligned at ${COMMIT_EXPECTED}"
