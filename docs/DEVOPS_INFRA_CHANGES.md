# 🛠 DevOps Infrastructure Changes Log

Este documento registra ajustes técnicos realizados durante la evolución del entorno de infraestructura del proyecto, enfocados en estabilidad, aislamiento de servicios y reproducibilidad en entornos Docker.

---

## 1. Corrección de healthcheck en contenedor Nginx

### Problema

El contenedor `web` utilizaba un `HEALTHCHECK` basado en `wget` apuntando a:

```dockerfile
HEALTHCHECK CMD wget -qO- http://localhost/health || exit 1
```

Sin embargo, el healthcheck fallaba constantemente aun cuando el servicio Nginx estaba funcionando correctamente dentro del contenedor.

El error observado era:

```bash
# wget -qO- http://localhost/health
wget: can't connect to remote host: Connection refused
```

Esto provocaba falsos estados `unhealthy`

---

### Causa raíz

Dentro del contenedor Alpine utilizado por Nginx, la resolución de `localhost` no siempre apuntaba correctamente al loopback IPv4 esperado por `wget`.

En ciertos entornos Docker/Alpine, `localhost` podía resolverse hacia IPv6 (`::1`) o generar inconsistencias internas de resolución, causando que el healthcheck intentara conectarse a una interfaz distinta de la utilizada por Nginx.

Como resultado, el contenedor respondía correctamente en IPv4, pero el healthcheck seguía fallando.

---

### Solución aplicada

Se reemplazó `localhost` por la dirección explícita IPv4 `127.0.0.1` en el `HEALTHCHECK` del Dockerfile:

```dockerfile
HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1/health || exit 1
```

---

### Impacto

* healthchecks estables y determinísticos
* eliminación de falsos negativos
* arranque más confiable del frontend
* mayor compatibilidad entre entornos Linux y Docker

---

### Resultado

El contenedor `web` ahora reporta correctamente su estado de salud, permitiendo que Docker Compose gestione las dependencias entre servicios de forma confiable y alineada con buenas prácticas de contenedorización.

---

## 2. Corrección de permisos y reproducibilidad en pruebas de carga con k6

### Problema

Los targets originales del Makefile para ejecutar pruebas de carga con k6 eran:

```makefile
load-quick:
	$(COMPOSE) -f docker-compose.k6.yml run --rm k6-quick

load-full:
	$(COMPOSE) -f docker-compose.k6.yml run --rm k6-full
```

Sin embargo, las ejecuciones fallaban al momento de generar los reportes HTML dentro del volumen montado desde el host.

El error observado era:

```bash
ERRO[0030] failed to handle the end-of-test summary
error="Could not save some summary information:
	- could not open '/reports/quick-report.html':
	open /reports/quick-report.html: permission denied"
```

Esto impedía que k6 pudiera escribir los reportes finales en `loadtest/reports/`.

---

### Causa raíz

La imagen oficial `grafana/k6` ejecuta el contenedor utilizando un usuario sin privilegios.

Al montar el directorio local:

```yaml
- ./loadtest/reports:/reports
```

el usuario interno del contenedor no tenía permisos suficientes para escribir archivos dentro del directorio del host.

---

### Solución aplicada
Se modificaron dos elementos:

**1. Docker Compose** — Se agregó la directiva `user` en los servicios k6:
```yaml
services:
  k6-quick:
    image: grafana/k6:0.57.0
    user: "${UID:-1000}:${GID:-1000}"
    volumes:
      - ./loadtest:/scripts:ro
      - ./loadtest/reports:/reports
    environment:
      - BASE_URL=http://host.docker.internal:8080
    command: run /scripts/quick.js
    extra_hosts:
      - "host.docker.internal:host-gateway"
  k6-full:
    image: grafana/k6:0.57.0
    user: "${UID:-1000}:${GID:-1000}"
    volumes:
      - ./loadtest:/scripts:ro
      - ./loadtest/reports:/reports
    environment:
      - BASE_URL=http://host.docker.internal:8080
    command: run /scripts/script.js
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

**2. Makefile** — Se garantiza la existencia del directorio de reportes antes de ejecutar:
```makefile
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
```

---

### Resultado de ejecución

El contenedor pudo generar correctamente:

```text
📊 Reporte: loadtest/reports/quick-report.html
📊 Reporte: loadtest/reports/full-report.html
```

sin errores de permisos.

---

### Impacto

* generación correcta de reportes HTML
* eliminación de errores `permission denied`
* ownership correcto de archivos generados
* mayor reproducibilidad en entornos locales y CI/CD
* configuración centralizada en docker-compose.yml (no depende del Makefile)

---

### Resultado
Las pruebas de carga ahora son completamente reproducibles y compatibles con buenas prácticas DevOps, garantizando que los artefactos generados por k6 pertenezcan correctamente al usuario que ejecuta el comando en el host. La directiva `user` en Docker Compose asegura que el contenedor siempre tenga los permisos adecuados, independientemente del usuario que ejecute `make load-*`.