.PHONY: test dev deploy logs status info ports prod-restart

test:
	. .venv/bin/activate && pytest -q

dev:
	. .venv/bin/activate && DEVBOX_CONFIG=config/devbox.yaml uvicorn devbox.main:app --reload --host 127.0.0.1 --port 8081

deploy:
	./scripts/deploy.sh

logs:
	sudo journalctl -u devbox -n 120 --no-pager

status:
	sudo systemctl status devbox --no-pager | sed -n '1,18p'

info:
	curl -s http://127.0.0.1:8080/info && echo

ports:
	sudo ss -ltnp | grep -E ':8080|:8081' || true

prod-restart:
	curl -s -X POST http://127.0.0.1:8080/actions/restart \
		-H "X-Devbox-Token: $$(sudo yq -r '.auth.token' /etc/devbox/config.yaml)" && echo
