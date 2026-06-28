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

---

## 3. Separación del stack de observabilidad

### Problema

Inicialmente, el stack de monitoreo (`Prometheus` + `Grafana`) se levantaba utilizando múltiples archivos Compose combinados desde la raíz del proyecto:

```bash
docker compose -f docker-compose.yml -f monitoring/docker-compose.monitoring.yml up -d
```

Este enfoque generaba varios problemas:

* acoplamiento entre aplicación y monitoreo
* conflictos de rutas relativas para volúmenes
* dificultad para reutilizar el stack de observabilidad
* dependencias implícitas entre servicios no relacionadas
* errores de resolución de archivos montados en Docker

Además, las redes Docker eran generadas automáticamente utilizando el nombre del directorio del proyecto, provocando inconsistencias entre entornos.

---

### Solución

Se desacopló completamente el stack de observabilidad.

#### Cambios realizados

#### Definición explícita de nombres de proyecto Compose

Se agregó un nombre fijo a cada stack:

```yaml
name: avatar-generator
```

```yaml
name: avatar-generator-monitoring
```

Esto evita dependencias del nombre del directorio local del repositorio.

---

#### Definición explícita de la red compartida

En el stack principal:

```yaml
networks:
  avatars-generator-net:
    driver: bridge
    name: avatars-generator-net
```

En el stack de monitoreo:

```yaml
networks:
  avatars-generator-net:
    external: true
    name: avatars-generator-net
```

Esto permite compartir una red estable entre stacks independientes.

---

#### Ejecución desacoplada desde Makefile

El Makefile fue modificado para ejecutar el stack de monitoreo desde su propio contexto:

```makefile
monitoring:
	cd monitoring && docker compose -f docker-compose.monitoring.yml up -d
```

---

#### Corrección de rutas relativas

Debido al cambio de contexto (`cd monitoring`), las rutas internas del compose de monitoreo fueron simplificadas:

Antes:

```yaml
# prometheus
./monitoring/prometheus.yml

# grafana
./monitoring/grafana/provisioning/datasources:/etc/grafana/provisioning/datasources:ro
./monitoring/grafana/provisioning/dashboards:/etc/grafana/provisioning/dashboards:ro
./monitoring/grafana/dashboards:/var/lib/grafana/dashboards:ro
```

Ahora:

```yaml
# prometheus
./prometheus.yml

# grafana
./grafana/provisioning/datasources:/etc/grafana/provisioning/datasources:ro
./grafana/provisioning/dashboards:/etc/grafana/provisioning/dashboards:ro
./grafana/dashboards:/var/lib/grafana/dashboards:ro
```

Esto vuelve el stack autocontenido dentro del directorio `monitoring/`.

---

### Impacto

* separación real entre aplicación y observabilidad
* networking Docker más predecible
* eliminación de dependencias implícitas
* mayor portabilidad entre entornos
* simplificación del mantenimiento del stack de monitoreo

---

### Resultado

El stack de observabilidad quedó desacoplado de la aplicación principal, permitiendo ejecutar `Prometheus` y `Grafana` como servicios independientes conectados mediante una red Docker compartida y explícitamente definida.

La infraestructura ahora utiliza nombres de proyecto y redes determinísticos, eliminando dependencias del nombre local del repositorio y resolviendo correctamente rutas y volúmenes entre stacks separados.

Esto mejora la portabilidad, mantenibilidad y reproducibilidad del entorno, alineando la arquitectura con prácticas reales de observabilidad y separación de responsabilidades en entornos DevOps.
