#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPT_DIR="/opt/devbox"
UNIT_FILE="/etc/systemd/system/devbox.service"

echo "[1/6] Running tests..."
cd "$REPO_DIR"
source .venv/bin/activate
pytest -q

echo "[2/6] Computing git commit..."
COMMIT="$(git rev-parse --short=12 HEAD)"
echo "Commit: $COMMIT"

echo "[3/6] Syncing repo -> $OPT_DIR ..."
sudo rsync -a --delete \
  --exclude '.git' \
  --exclude '.venv' \
  "$REPO_DIR"/ "$OPT_DIR"/

echo "[4/6] Setting ownership + installing editable..."
sudo chown -R devbox:devbox "$OPT_DIR"
sudo -u devbox "$OPT_DIR/.venv/bin/pip" install -e "$OPT_DIR"

echo "[5/6] Updating systemd env DEVBOX_GIT_COMMIT..."
if ! sudo test -f "$UNIT_FILE"; then
  echo "ERROR: unit file not found: $UNIT_FILE" >&2
  exit 1
fi

# Replace if exists, otherwise add under the existing DEVBOX_CONFIG line (or under [Service])
if sudo grep -q '^Environment=DEVBOX_GIT_COMMIT=' "$UNIT_FILE"; then
  sudo sed -i "s/^Environment=DEVBOX_GIT_COMMIT=.*/Environment=DEVBOX_GIT_COMMIT=${COMMIT}/" "$UNIT_FILE"
else
  if sudo grep -q '^Environment=DEVBOX_CONFIG=' "$UNIT_FILE"; then
    sudo sed -i "/^Environment=DEVBOX_CONFIG=/a Environment=DEVBOX_GIT_COMMIT=${COMMIT}" "$UNIT_FILE"
  else
    sudo sed -i "/^\[Service\]/a Environment=DEVBOX_GIT_COMMIT=${COMMIT}" "$UNIT_FILE"
  fi
fi

sudo systemctl daemon-reload
sudo systemctl restart devbox

echo "[6/6] Verifying /info..."
sleep 1
curl -s http://127.0.0.1:8080/info

INFO_COMMIT="$(curl -s http://127.0.0.1:8080/info | python3 -c "import sys,json; print(json.load(sys.stdin).get('git_commit',''))")"
if [ "$INFO_COMMIT" != "$COMMIT" ]; then
  echo "WARNING: /info git_commit ($INFO_COMMIT) != repo commit ($COMMIT)" >&2
fi

echo
echo "DONE"
