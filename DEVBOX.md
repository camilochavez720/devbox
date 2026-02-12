DEVBOX (Python) — Documento de diseño y plan de implementación (Ubuntu 24.04)
0) Objetivo

Construir un daemon local (“devbox”) que corre en Ubuntu como servicio systemd y expone un API HTTP en localhost para:

inspeccionar estado del sistema (CPU/RAM/Disk/Uptime)

inspeccionar estado de servicios (systemd)

ejecutar acciones controladas (ej. restart del propio servicio)

dejar trazabilidad en logs (journald) y tener tests básicos

El propósito principal es aprender desarrollo en Linux: CLI, permisos, systemd, logs, estructura de proyecto, empaquetado/instalación, y buenas prácticas operativas.

1) Alcance (lo que SÍ haremos)
1.1 Funcionalidades mínimas (MVP)

API (FastAPI)

GET /health → estado simple

GET /system → cpu, mem, disk, uptime

GET /services → estado de una lista de servicios (docker, ssh, etc.)

POST /actions/restart → reinicia devbox de forma segura (sin root)

Operación

correr como usuario no privilegiado devbox

configurar por archivo en /etc/devbox/config.yaml

logs a journald (ver journalctl -u devbox)

servicio systemd con restart automático

Seguridad básica

bind solo a 127.0.0.1

token estático local para endpoints de acciones (header)

Calidad

tests unitarios para recolectores (pytest)

lint/format mínimo (black + ruff)

1.2 Extensiones (después del MVP)

endpoint /metrics estilo Prometheus (opcional)

caché de métricas con TTL

endpoint /actions/run-tests (solo si está bien encerrado)

instalador script install.sh (idempotente) y uninstall.sh

2) No objetivos (para evitar que se descontrole)

No exponer el servicio a la red LAN/Internet (no TLS, no auth robusta)

No ejecutar comandos arbitrarios del sistema

No administrar servicios como root (nada de systemctl restart docker desde el API)

No GUI (por ahora)

3) Decisiones técnicas
3.1 Stack

Python 3.12 (Ubuntu 24.04)

FastAPI + Uvicorn

psutil para métricas del sistema

PyYAML para config YAML

pytest para tests

ruff + black (calidad)

logging: logging estándar (formato consistente, ideal JSON si quieres)

3.2 Principio de seguridad clave

Las “acciones” deben ser whitelist y sin privilegios.

Para “restart” del propio servicio: el proceso sale y systemd lo levanta de nuevo (Restart=on-failure o always).

Nada de sudo dentro del servicio.

Token local en header para acciones.

4) Arquitectura (simple y mantenible)
4.1 Componentes

API layer: FastAPI routes

Collectors: módulos que recolectan métricas (psutil)

Service checker: consulta systemctl is-active <service>

Actions: operaciones controladas (restart = exit controlado)

4.2 Flujo “restart”

POST /actions/restart valida token

responde 202 (Accepted)

dispara un shutdown en background (graceful)

proceso termina con exit code no-cero (o normal, según Restart=) y systemd reinicia

5) Especificación de API (MVP)
5.1 Auth (solo acciones)

Header requerido en acciones:

X-Devbox-Token: <token>

Token se define en /etc/devbox/config.yaml.

5.2 Endpoints

GET /health

200: {"status":"ok","service":"devbox","version":"0.1.0"}

GET /system

200 ejemplo:

{
  "cpu_percent": 12.4,
  "mem": {"total": 16777216, "used": 8237056, "percent": 49.1},
  "disk": {"path": "/", "total": 512000000000, "used": 210000000000, "percent": 41.0},
  "uptime_seconds": 123456
}


GET /services

Config define qué servicios mirar.

200 ejemplo:

{
  "services": [
    {"name":"docker", "active": true, "state":"active"},
    {"name":"ssh", "active": true, "state":"active"}
  ]
}


POST /actions/restart

Requiere token

202: {"status":"restarting"}

6) Configuración
6.1 Ubicación y permisos

Archivo: /etc/devbox/config.yaml

Owner: root:devbox

Permisos: 0640 (devbox puede leer, otros no)

6.2 Contenido (MVP)
http:
  host: "127.0.0.1"
  port: 8080

auth:
  token: "CAMBIAR_ESTE_TOKEN"

services:
  - "docker"
  - "ssh"

7) Estructura del repo
devbox/
  DEVBOX.md
  README.md
  pyproject.toml
  src/
    devbox/
      __init__.py
      main.py            # crea app FastAPI
      config.py          # carga config YAML
      collectors/
        system.py        # cpu/mem/disk/uptime
      services/
        systemd.py       # check systemctl
      actions/
        restart.py       # shutdown/exit controlado
      api/
        routes.py        # define endpoints
  tests/
    test_system_collector.py
    test_services.py
  packaging/
    devbox.service       # unit file template
  scripts/
    install.sh
    uninstall.sh

8) Systemd (operación real en Ubuntu)
8.1 Usuario del servicio

Usuario dedicado: devbox

sin login interactivo

8.2 Directorios runtime

código: /opt/devbox (o /srv/devbox)

estado: /var/lib/devbox (si se necesita)

config: /etc/devbox/config.yaml

logs: journald (no archivos por defecto)

8.3 Unit file (MVP)

Archivo: /etc/systemd/system/devbox.service

Requisitos:

User=devbox

WorkingDirectory=/opt/devbox

ExecStart=/opt/devbox/.venv/bin/uvicorn devbox.main:app --host 127.0.0.1 --port 8080

Restart=on-failure

RestartSec=2

hardening mínimo:

NoNewPrivileges=true

PrivateTmp=true

ProtectSystem=strict (puede requerir excepciones si lees algo del FS; se ajusta luego)

ReadWritePaths=/var/lib/devbox

Nota importante: hardening estricto puede romper cosas si el proceso necesita leer rutas fuera de lo permitido. Se activa gradualmente.

8.4 Comandos operativos

Ver estado: systemctl status devbox

Logs: journalctl -u devbox -f

Reinicio manual: sudo systemctl restart devbox

9) Desarrollo local
9.1 Entorno virtual

.venv dentro del repo (simple y explícito)

dependencias en pyproject.toml

9.2 Ejecutar en dev

uvicorn devbox.main:app --reload --host 127.0.0.1 --port 8080

9.3 Calidad

ruff check .

black .

pytest -q

10) Riesgos y controles
10.1 Riesgo: ejecutar comandos del sistema

Control: acciones whitelist y sin shell. Si se usa subprocess:

lista fija de comandos

argumentos validados

shell=False

timeout corto

output limitado

10.2 Riesgo: elevar privilegios

Control: no sudo dentro del servicio. Si alguna acción requiere root, se mueve fuera del MVP y se diseña con polkit o un helper separado (no ahora).

10.3 Riesgo: exponer red

Control: bind 127.0.0.1. (Si el usuario cambia a 0.0.0.0, se considera “inseguro” y se documenta explícitamente.)

11) Plan de trabajo (milestones)
M0 — Repo + entorno (hecho cuando…)

estructura creada

venv + dependencias

GET /health funcionando en dev

M1 — Métricas del sistema

GET /system entrega cpu/mem/disk/uptime

tests unitarios de collectors

M2 — systemd services

GET /services con lista desde config

manejo de errores (servicio inexistente)

M3 — systemd unit y operación

devbox.service instalado

systemctl enable --now devbox

logs en journald correctos

M4 — Seguridad mínima

token requerido para acciones

restart vía “exit controlado” + systemd restart

M5 — Instalador

scripts/install.sh crea usuario, dirs, venv, config template, unit file, enable/start

idempotente (si lo corres dos veces no rompe)

12) Criterios de “terminado”

En localhost:8080/health responde OK

journalctl -u devbox -f muestra logs útiles

Tras POST /actions/restart el servicio vuelve a estar activo en <10s (sin intervención manual)

Codebase con estructura limpia y tests mínimos
