.PHONY: bootstrap preflight up up-gpu ps logs health backup update down

bootstrap:
	./scripts/bootstrap.sh

preflight:
	./scripts/preflight.sh

up: bootstrap preflight
	docker compose up -d --build

up-gpu: bootstrap preflight
	docker compose -f compose.yml -f compose.gpu.yml up -d --build

ps:
	docker compose ps

logs:
	docker compose logs -f --tail=200

health:
	@docker compose ps
	@echo "\nHUB:"
	@docker compose exec -T hub-core php -r 'echo file_get_contents("http://127.0.0.1/health.php"), PHP_EOL;'
	@echo "\nTotem:"
	@docker compose exec -T totem-api node -e 'fetch("http://127.0.0.1:3080/api/health").then(r=>r.text()).then(console.log)'
	@echo "\nFace Scanner:"
	@docker compose exec -T face-scanner python -c 'import urllib.request; print(urllib.request.urlopen("http://127.0.0.1:8091/api/v1/health").read().decode())'

backup:
	./scripts/backup.sh

update:
	./scripts/update.sh

down:
	docker compose down
