.PHONY: help build up down restart logs logs-api logs-web clean test test-backend test-frontend health metrics test-api load-quick load-full monitoring

COMPOSE = docker compose

help: ## Mostrar esta ayuda
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-18s\033[0m %s\n", $$1, $$2}'

build: ## Construir imágenes
	$(COMPOSE) build

up: ## Levantar todos los servicios
	$(COMPOSE) up -d --build

down: ## Detener todos los servicios
	$(COMPOSE) down

restart: down up ## Reiniciar todos los servicios

logs: ## Ver logs de todos los servicios
	$(COMPOSE) logs -f

logs-api: ## Ver logs del API
	$(COMPOSE) logs -f api

logs-web: ## Ver logs del frontend
	$(COMPOSE) logs -f web

clean: ## Eliminar contenedores, imágenes y volúmenes de todos los stacks
	cd monitoring && $(COMPOSE) -f docker-compose.monitoring.yml down -v
	$(COMPOSE) down -v --rmi local

health: ## Verificar health del API
	@curl -sf http://localhost:8080/health | python3 -m json.tool || echo "API no disponible"

metrics: ## Ver métricas del API
	@curl -sf http://localhost:8080/metrics || echo "Métricas no disponibles"

test: test-backend test-frontend ## Ejecutar todos los tests

test-backend: ## Tests unitarios del backend (pytest)
	docker build -q -t avatar-generator-api-test -f api/Dockerfile.test api/
	docker run --rm avatar-generator-api-test

test-frontend: ## Tests unitarios del frontend (vitest)
	docker build -q -t avatar-generator-web-test -f web/Dockerfile.test web/
	docker run --rm avatar-generator-web-test

test-api: ## Probar endpoints del API (requiere servicios corriendo)
	@echo "=== Health ==="
	@curl -sf http://localhost:8080/health | python3 -m json.tool
	@echo "=== Ready ==="
	@curl -sf -o /dev/null -w "Status: %{http_code}\n" http://localhost:8080/ready
	@echo "=== Avatar Spec ==="
	@curl -sf http://localhost:8080/api/avatar/spec | python3 -m json.tool | head -20
	@echo "=== Avatar SVG ==="
	@curl -sf -o /dev/null -w "Status: %{http_code}, Size: %{size_download} bytes\n" "http://localhost:8080/api/avatar?eyes=default&mouth=smile"
	@echo "=== Gallery ==="
	@curl -sf http://localhost:8080/api/gallery | python3 -m json.tool
	@echo "Todos los endpoints OK"

monitoring: ## Levantar Prometheus + Grafana
	cd monitoring && $(COMPOSE) -f docker-compose.monitoring.yml up -d

monitoring-down: ## Detener Prometheus + Grafana
	cd monitoring && $(COMPOSE) -f docker-compose.monitoring.yml down

load-quick: ## Load test rápido (30s, 10 usuarios)
	@mkdir -p loadtest/reports
	$(COMPOSE) -f docker-compose.k6.yml run --rm k6-quick
	@echo "📊 Reporte: loadtest/reports/quick-report.html"
	@open loadtest/reports/quick-report.html 2>/dev/null || true

load-full: ## Load test completo (2min, 20 usuarios pico)
	@mkdir -p loadtest/reports
	$(COMPOSE) -f docker-compose.k6.yml run --rm k6-full
	@echo "📊 Reporte: loadtest/reports/full-report.html"
	@open loadtest/reports/full-report.html 2>/dev/null || true
