# DEVBOX (Python) — Documento de diseño y estado actual (Ubuntu 24.04)

## 0) Objetivo

Construir un daemon local (“devbox”) que corre en Ubuntu como servicio systemd y expone un API HTTP **solo en localhost (127.0.0.1)** para:

- inspeccionar estado del sistema (CPU/RAM/Disk/Uptime)
- inspeccionar estado de servicios (systemd)
- ejecutar acciones controladas (reinicio del propio servicio)
- dejar trazabilidad en logs (journald) y tener tests básicos

Propósito principal: aprender desarrollo “real” en Linux: CLI, permisos, systemd, logs, estructura de proyecto, empaquetado/instalación y prácticas operativas.

---

## 1) Estado actual (lo que YA existe y funciona)

### 1.1 Endpoints implementados (MVP actual)

- `GET /health`
  - Respuesta actual:
    - `{"status":"ok","service":"devbox"}`

- `GET /system`
  - Snapshot del sistema (usando `psutil`):
    - `cpu_percent`
    - `mem` (estructura de memoria)
    - `disk` (estructura de disco)
    - `uptime_seconds` (uptime del sistema)

- `GET /services`
  - Lee lista `services` desde config y consulta `systemctl is-active <service>`.
  - Respuesta actual incluye `config_path` y lista con:
    - `name`, `state`, `active`, `error`

- `POST /actions/restart`
  - Protegido por token `X-Devbox-Token` (header).
  - Dispara un reinicio controlado: la request responde, luego el proceso programa su salida y systemd lo levanta de nuevo.

- `GET /info`
  - Metadata operativa:
    - `service`, `version`, `pid`, `config_path`, `python`, `uptime_seconds`, `git_commit`
  - `git_commit` en prod viene de `DEVBOX_GIT_COMMIT` (variable en unit file) para no depender de `.git`.

### 1.2 Modos de ejecución

- **DEV (manual, puerto 8081)**
  - Corre desde el repo `~/devbox` con tu venv local.
  - Usa config del repo (`config/devbox.yaml`) vía `DEVBOX_CONFIG`.
  - Objetivo: iterar rápido.

- **PROD (systemd, puerto 8080)**
  - Corre como `User=devbox` / `Group=devbox`.
  - Código en `/opt/devbox`.
  - Config en `/etc/devbox/config.yaml`.
  - Logs en journald (`journalctl -u devbox`).
  - Deploy automatizado con `make deploy` (usa `scripts/deploy.sh`).

### 1.3 Seguridad operativa aplicada (lo que se cumple)

- Bind solo a `127.0.0.1` (no expuesto a LAN/Internet).
- Acciones protegidas por token local (header `X-Devbox-Token`) leído desde config.
- Servicio corre sin privilegios (usuario `devbox`).
- Unit file con hardening básico:
  - `NoNewPrivileges=true`
  - `PrivateTmp=true`
- En prod se evita instalar dependencias de desarrollo (`pytest`, `httpx`, etc.).

---

## 2) Alcance

### 2.1 Lo que SÍ hacemos (MVP)

- API local FastAPI en localhost.
- Métricas del sistema con `psutil`.
- Estado de servicios con systemd.
- Acción controlada: reinicio del propio servicio.
- Configuración por YAML.
- Logs via journald (systemd).
- Tests básicos con pytest (solo en DEV).
- Workflow reproducible de deploy.

### 2.2 Extensiones posibles (post-MVP)

- `/metrics` estilo Prometheus.
- Cache con TTL para collectors.
- `install.sh` y `uninstall.sh` idempotentes.
- Healthchecks más ricos (sanity check de config, etc.).
- Rotación/control de token o reload de config (siempre sin sobrecomplicar).

---

## 3) No objetivos

- No exponer el servicio a la red LAN/Internet (sin TLS, sin auth robusta, sin hardening avanzado).
- No ejecutar comandos arbitrarios del sistema.
- No administrar servicios de terceros como root desde el API (no reiniciar docker, etc.).
- No GUI.

---

## 4) Decisiones técnicas (alineadas a lo implementado)

### 4.1 Stack

- Python 3.12 (Ubuntu 24.04)
- FastAPI + Uvicorn
- psutil (métricas)
- PyYAML (config)
- pytest (tests, DEV)
- ruff + black (calidad, DEV)
- systemd + journald (operación)

### 4.2 Principio de seguridad clave

- “Acciones” = whitelist, sin privilegios.
- El servicio no usa sudo.
- El reinicio se hace dejando que systemd lo gestione (Restart=always).

---

## 5) Configuración y operación real

### 5.1 Config real (prod)

Archivo: `/etc/devbox/config.yaml`  
Recomendación de permisos:
- owner: `root:devbox`
- modo: `0640`

Ejemplo (forma y claves reales):

```yaml
http:
  host: "127.0.0.1"
  port: 8080

auth:
  token: "<TOKEN_HEX_LARGO>"

services:
  - "ssh"
  - "NetworkManager"
  - "systemd-resolved"
```

Regla operativa:
- El servicio en prod usa ese archivo por env:
  - `DEVBOX_CONFIG=/etc/devbox/config.yaml`

### 5.2 Unit file real (prod)

Archivo: `/etc/systemd/system/devbox.service`

Puntos clave:
- corre como `User=devbox` / `Group=devbox`
- `WorkingDirectory=/opt/devbox`
- variables:
  - `DEVBOX_CONFIG=/etc/devbox/config.yaml`
  - `DEVBOX_GIT_COMMIT=<12-chars>` (actualizado por deploy)
- start:
  - `ExecStart=/opt/devbox/.venv/bin/uvicorn devbox.main:app --host 127.0.0.1 --port 8080`
- restart:
  - `Restart=always`
  - `RestartSec=2`
- hardening:
  - `NoNewPrivileges=true`
  - `PrivateTmp=true`

Ejemplo representativo:

```ini
[Unit]
Description=Devbox local API
After=network.target
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=simple
User=devbox
Group=devbox
WorkingDirectory=/opt/devbox

Environment=DEVBOX_CONFIG=/etc/devbox/config.yaml
Environment=DEVBOX_GIT_COMMIT=<12-chars>
ExecStart=/opt/devbox/.venv/bin/uvicorn devbox.main:app --host 127.0.0.1 --port 8080

Restart=always
RestartSec=2

NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

---

## 6) Arquitectura del código (lo implementado)

Estructura (real/actual):

- `src/devbox/main.py`
  - FastAPI app + rutas: `/health`, `/system`, `/services`, `/actions/restart`, `/info`

- `src/devbox/config.py`
  - resuelve config path (prioridad):
    1) `DEVBOX_CONFIG` si existe
    2) `/etc/devbox/config.yaml`
    3) `./config/devbox.yaml` relativo (DEV)
  - parsea YAML y normaliza:
    - `http_host`, `http_port`
    - `auth_token`
    - lista `services`
  - expone `load_config()`

- `src/devbox/auth.py`
  - dependencia `require_token(...)`
  - fail-closed:
    - si token no está configurado en config => 500
    - si header no coincide => 401

- `src/devbox/collectors/system.py`
  - snapshot: cpu/mem/disk/uptime

- `src/devbox/services/systemd.py`
  - consulta `systemctl is-active <service>` y devuelve estado (y error si aplica)

- `src/devbox/actions/restart.py`
  - programa el restart con delay pequeño para no cortar la respuesta HTTP
  - systemd reinicia el proceso (por Restart=always)

- `src/devbox/collectors/info.py`
  - uptime del proceso (no del sistema)
  - `config_path` desde `load_config()`
  - `git_commit`:
    - si existe `DEVBOX_GIT_COMMIT` => usarlo (prod)
    - si no, intenta leer `.git/HEAD` (dev)
    - si falla => `"unknown"`

---

## 7) Workflow operativo (cómo trabajar)

### 7.1 Comandos para editar y ver archivos

Editar este documento:
```bash
nano ~/devbox/DEVBOX.md
```

Ver el documento (sin editor):
```bash
sed -n '1,260p' ~/devbox/DEVBOX.md
```

Editar script de deploy:
```bash
nano ~/devbox/scripts/deploy.sh
```

Editar unit file:
```bash
sudo nano /etc/systemd/system/devbox.service
sudo systemctl daemon-reload
sudo systemctl restart devbox
```

Editar config:
```bash
sudo nano /etc/devbox/config.yaml
sudo systemctl restart devbox
```

Ver unit file y config:
```bash
sudo sed -n '1,220p' /etc/systemd/system/devbox.service
sudo sed -n '1,160p' /etc/devbox/config.yaml
```

### 7.2 DEV mode (8081)

Opción A (si tu Makefile tiene target `dev`):
```bash
cd ~/devbox
make dev
```

Opción B (manual):
```bash
cd ~/devbox
source .venv/bin/activate
export DEVBOX_CONFIG=config/devbox.yaml
uvicorn devbox.main:app --reload --host 127.0.0.1 --port 8081
```

Verificación DEV:
```bash
curl -s http://127.0.0.1:8081/health && echo
curl -s http://127.0.0.1:8081/info && echo
curl -s http://127.0.0.1:8081/services && echo
```

### 7.3 PROD mode (8080/systemd)

Verificación PROD:
```bash
sudo systemctl status devbox --no-pager | sed -n '1,18p'
sudo ss -ltnp | grep ':8080' || true
curl -s http://127.0.0.1:8080/health && echo
curl -s http://127.0.0.1:8080/info && echo
curl -s http://127.0.0.1:8080/services && echo
```

Logs:
```bash
sudo journalctl -u devbox -n 120 --no-pager
```

---

## 8) Deploy (lo implementado)

### 8.1 Objetivo del deploy

- correr tests en DEV
- construir artefacto (wheel) en DEV
- copiar artefacto a `/opt/devbox`
- crear venv limpio en `/opt/devbox/.venv` (prod)
- instalar **solo runtime deps** + wheel (sin extras dev)
- actualizar `DEVBOX_GIT_COMMIT` en unit file
- reiniciar servicio
- verificar `/info`
- verificar que **NO** hay dev deps en prod

### 8.2 Comando estándar

```bash
cd ~/devbox
make deploy
```

---

## 9) Auth de acciones (real)

Header requerido:
- `X-Devbox-Token: <token>`

El token sale de `/etc/devbox/config.yaml` (`auth.token`).

Endpoint protegido principal:
- `POST /actions/restart`

Ejemplo llamada (sin `yq` real, usando `awk`):
```bash
TOKEN="$(sudo awk -F': ' '/token:/{gsub(/"/,"",$2); print $2}' /etc/devbox/config.yaml)"
curl -i -X POST http://127.0.0.1:8080/actions/restart -H "X-Devbox-Token: $TOKEN"
```

Verificar que reinició (PID cambia, uptime se resetea):
```bash
sleep 1
curl -s http://127.0.0.1:8080/info && echo
sudo systemctl status devbox --no-pager | sed -n '1,14p'
```

---

## 10) Calidad (tests y estilo)

Tests solo en DEV:
```bash
cd ~/devbox
make test   # o: pytest -q
```

En PROD NO debe existir pytest ni httpx:
```bash
sudo /opt/devbox/.venv/bin/python -m pip show pytest || echo "pytest NO"
sudo /opt/devbox/.venv/bin/python -m pip show httpx  || echo "httpx NO"
```

---

## 11) Próximos pasos sugeridos (sin perder foco)

1) Mantener este `DEVBOX.md` como fuente de verdad (estado + decisiones + comandos).
2) `install.sh` / `uninstall.sh` idempotentes:
   - crear usuario/grupo `devbox`
   - crear `/etc/devbox/config.yaml` (si no existe) con permisos correctos
   - instalar unit file desde template
   - `systemctl enable --now devbox`
3) `/metrics` opcional (Prometheus) + TTL cache (sin complicar el core).
4) Mejoras de hardening systemd (solo si entiendes tradeoffs):
   - `ProtectSystem=strict`, `ProtectHome=true` (evaluar impacto)
   - `ReadWritePaths=` para permitir solo lo necesario

---

## APÉNDICE A — Checklist rápido (DEV / PROD / DEPLOY)

DEV:
```bash
cd ~/devbox
source .venv/bin/activate
export DEVBOX_CONFIG=config/devbox.yaml
uvicorn devbox.main:app --reload --host 127.0.0.1 --port 8081
```

PROD:
```bash
sudo systemctl status devbox --no-pager | sed -n '1,18p'
curl -s http://127.0.0.1:8080/health && echo
curl -s http://127.0.0.1:8080/info && echo
sudo journalctl -u devbox -n 120 --no-pager
```

DEPLOY:
```bash
cd ~/devbox
make test
make deploy
```
