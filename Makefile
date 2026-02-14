.PHONY: test deploy logs status info

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
