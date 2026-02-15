.PHONY: test deploy logs status info dev ports

test:
	. .venv/bin/activate && pytest -q

deploy:
	./scripts/deploy.sh

logs:
	sudo journalctl -u devbox -n 120 --no-pager

status:
	sudo systemctl status devbox --no-pager | sed -n '1,18p'

info:
	curl -s http://127.0.0.1:8080/info && echo

dev:
	@bash -lc 'source .venv/bin/activate && export DEVBOX_CONFIG=config/devbox.yaml && uvicorn devbox.main:app --reload --host 127.0.0.1 --port 8081'

ports:
	sudo ss -ltnp | grep -E ':8080|:8081' || true

