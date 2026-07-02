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

Inicialmente, el stack de monitoreo (`Prometheus` + `Grafana`) se levantaba utilizando múltiples archivos Compose combinados:

```bash
docker compose -f docker-compose.yml -f monitoring/docker-compose.monitoring.yml up -d
```

Este enfoque generaba varios problemas:

* acoplamiento entre aplicación y monitoreo
* dependencia implícita entre stacks distintos
* dificultad para reutilizar el stack de observabilidad
* conflictos por nombres dinámicos de redes Docker
* comportamiento inconsistente entre distintos entornos locales

Además, Docker Compose generaba automáticamente nombres de red basados en el directorio del proyecto, provocando fallos al intentar compartir networking entre stacks independientes.

---

### Solución

Se desacopló completamente el stack de observabilidad.

#### Cambios realizados

#### Definición explícita de nombres de proyecto Compose

Se agregó un nombre fijo a cada stack:

```yaml
name: avatars-generator
```

```yaml
name: avatars-generator-monitoring
```

Esto evita dependencias del nombre local del directorio del repositorio.

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

Esto permite que ambos stacks compartan una red estable y predecible sin necesidad de ejecutarse como un único proyecto Compose.

---

#### Ejecución independiente del stack de monitoreo

El Makefile fue modificado para levantar el stack de observabilidad utilizando un compose dedicado e independiente del stack principal:

```makefile
monitoring:
	$(COMPOSE) -f docker-compose.monitoring.yml up -d
```

También se agregó un comando específico para detener únicamente los servicios de observabilidad:

```makefile
monitoring-down:
	$(COMPOSE) -f docker-compose.monitoring.yml down
```

Y el target `clean` fue extendido para eliminar también los recursos asociados al monitoreo:

```makefile
clean:
	$(COMPOSE) -f docker-compose.monitoring.yml down -v
	$(COMPOSE) down -v --rmi local
```

---

#### Organización del stack de monitoreo

El archivo `docker-compose.monitoring.yml` fue desacoplado del compose principal y ahora funciona como un stack independiente ubicado en la raíz del proyecto.

La configuración de Prometheus y Grafana permanece organizada dentro del directorio `monitoring/`:

```text
monitoring/
├── prometheus.yml
└── grafana/
    ├── dashboards/
    └── provisioning/
```

Esto permite mantener separada la configuración de observabilidad sin mezclar responsabilidades con los servicios principales de la aplicación.

---

### Impacto

* separación real entre aplicación y observabilidad
* networking Docker más predecible
* eliminación de dependencias implícitas
* mayor portabilidad entre entornos
* simplificación del mantenimiento del stack de monitoreo
* desacoplamiento operativo entre servicios

---

### Resultado

El stack de observabilidad quedó desacoplado de la aplicación principal, permitiendo ejecutar `Prometheus` y `Grafana` como servicios independientes conectados mediante una red Docker compartida y explícitamente definida.

La infraestructura ahora utiliza nombres de proyecto y redes determinísticos, eliminando dependencias del nombre local del repositorio y mejorando la reproducibilidad del entorno entre distintas máquinas y entornos DevOps.

Además, la observabilidad quedó organizada como un stack independiente, facilitando mantenimiento, reutilización y futuras migraciones hacia entornos Kubernetes o arquitecturas multi-stack.

---

## 4. Externalización y estandarización de variables de entorno

### Problema

Inicialmente, múltiples variables de configuración estaban hardcodeadas directamente dentro de los archivos `docker-compose`:

```yaml
environment:
  - FLASK_ENV=production
  - DB_PATH=/data/avatars.db
```

```yaml
environment:
  - BASE_URL=http://host.docker.internal:8080
```

```yaml
environment:
  - GF_SECURITY_ADMIN_PASSWORD=admin
  - GF_USERS_ALLOW_SIGN_UP=false
```

Esto generaba varios problemas:

* configuración duplicada entre entornos
* dificultad para reutilizar configuraciones
* menor portabilidad entre desarrollo local y CI/CD
* exposición accidental de valores sensibles
* necesidad de modificar archivos Compose para cambiar parámetros operativos

---

### Solución aplicada

Se centralizó toda la configuración de entorno utilizando un archivo `.env` en la raíz del proyecto.

#### Archivo `.env.example`

Se agregó un template versionado:

```env
FLASK_ENV=production
DB_PATH=/data/avatars.db

BASE_URL=http://host.docker.internal:8080

GF_SECURITY_ADMIN_PASSWORD=admin
GF_USERS_ALLOW_SIGN_UP=false
```

---

#### Exclusión de variables sensibles

El `.gitignore` fue actualizado para evitar subir archivos reales de entorno:

```gitignore
# Environment Variables
.env
.env.*
!.env.example
```

Esto permite compartir únicamente el template de configuración sin exponer valores reales.

---

#### Parametrización de Docker Compose

Los stacks Docker fueron modificados para consumir variables dinámicas mediante interpolación:

Antes:

```yaml
environment:
  - FLASK_ENV=production
  - DB_PATH=/data/avatars.db
```

Ahora:

```yaml
environment:
  FLASK_ENV: ${FLASK_ENV:-development}
  DB_PATH: ${DB_PATH:-/data/avatars.db}
```

---

También se aplicó el mismo patrón a:

* k6 (`BASE_URL`)
* Grafana (`GF_SECURITY_ADMIN_PASSWORD`, `GF_USERS_ALLOW_SIGN_UP`)
* futuras configuraciones multi-entorno

---

### Impacto

* configuración desacoplada del código fuente
* mayor reproducibilidad entre entornos
* compatibilidad directa con CI/CD
* simplificación de overrides por entorno
* alineación con prácticas DevOps y Twelve-Factor App

---

### Resultado

La infraestructura ahora soporta configuración dinámica y portable mediante variables de entorno centralizadas, permitiendo reutilizar los mismos archivos Docker Compose en desarrollo local, testing y pipelines CI/CD sin necesidad de modificar la definición de servicios.

El uso de `.env.example` además documenta explícitamente las variables requeridas por el proyecto y reduce errores de configuración en nuevos entornos.

---

## 5. Migración a contenedores No-Root y Optimización Multi-Stage

### Problema

Las imágenes iniciales presentaban áreas de mejora de cara a entornos productivos estrictos (DevSecOps):

* El contenedor frontend (`nginx`) corría sus procesos maestros como usuario `root` (UID 0), necesario para escuchar en el puerto privilegiado `80`.
* El contenedor backend (`api`) instalaba dependencias globalmente, dejando basura de compilación y cachés en la imagen final.

---

### Soluciones Aplicadas

#### Frontend (Nginx Unprivileged)

Se migró la imagen base a la variante oficial `nginxinc/nginx-unprivileged:alpine`.
* El proceso corre bajo el usuario `nginx` (UID 101).
* Se modificó el archivo `nginx.conf` y el `docker-compose.yml` para escuchar y mapear sobre el puerto **`8080`** (ya que los puertos < 1024 requieren permisos de root).

#### Backend (Multi-Stage y Usuario No-Root)

Se reestructuró el `api/Dockerfile` utilizando el patrón *Multi-Stage*:
* **Stage Builder:** Crea un entorno virtual (`venv`) e instala todas las dependencias necesarias.
* **Stage Production:** Solo copia el `venv` limpio y el código fuente. Se creó el usuario `appuser` (UID 1000) y se configuraron los permisos adecuados (`chown`) sobre el directorio `/data` (SQLite).

#### Limpieza de Contexto

Se actualizaron los `.dockerignore` para excluir `.env`, `.venv` y otros archivos locales que aumentaban el peso y riesgo del contexto de build.

---

### Impacto
* Cumplimiento estricto de buenas prácticas DevSecOps (No-Root Containers).
* Imágenes productivas significativamente más limpias.

---

## 6. Fase 2 (Iteración 1): Integración Continua Base (CI) y GHCR

### Problema / Objetivo
Con la infraestructura local estandarizada mediante Makefile y multi-stage Dockerfiles, el siguiente paso lógico es llevar la verificación de código a un pipeline automatizado, comprobando que las compilaciones y pruebas funcionan consistentemente antes de integrar código en las ramas principales. Además, requerimos que las compilaciones exitosas en ramas de integración generen y publiquen imágenes Docker.

---

### Solución Implementada (CI Base)

Se diseñó e implementó un flujo de **Integración Continua Mínimo Viable** en GitHub Actions (`.github/workflows/ci.yml`).

Esta primera iteración parcial se enfoca exclusivamente en estabilidad, delegando el versionado semántico, escaneo profundo de vulnerabilidades (DevSecOps) y Continuous Deployment (CD) para etapas posteriores.

#### Características de la Iteración:
1. **Triggers Controlados:**
   - Se ejecuta en **Pull Requests** hacia `main` y `develop` (Solo validación).
   - Se ejecuta en **Pushes directos** a `develop` (Validación + Construcción + Push a Registry).

2. **Reaprovechamiento de Infraestructura Local:**
   - El pipeline utiliza `make test-backend` y `make test-frontend`, garantizando que CI ejecute **exactamente los mismos tests y targets Docker** que corren los desarrolladores en sus máquinas locales.

3. **Autenticación GHCR sin secretos quemados:**
   - Se configuraron los permisos granulares `packages: write` en el job de Actions.
   - Se utilizó `secrets.GITHUB_TOKEN` para autenticarse automáticamente con GitHub Container Registry, evitando la creación de Personal Access Tokens (PATs) en el repositorio público.

4. **Optimización con Caché:**
   - Se integró `docker/setup-buildx-action` junto con directivas `cache-to: type=gha,mode=max` y `cache-from: type=gha`. Esto permite que GitHub almacene las capas de Docker (como la instalación de dependencias npm/pip), acelerando drásticamente ejecuciones subsecuentes del pipeline.

5. **Push Condicional de Imágenes (`edge` y `sha-*`):**
   - El pipeline utiliza `docker/metadata-action` para etiquetar las imágenes automáticamente.
   - Si (y solo si) el evento es un push directo a `develop`, el pipeline sube las imágenes construidas a GHCR con el tag `edge` y un tag inmutable con el SHA del commit.

---

### Impacto de la Iteración
* **Visibilidad temprana:** Cualquier rotura de dependencias o tests fallidos se visibiliza de inmediato en los PRs, antes del merge.
* **Artefactos continuos:** La rama `develop` ahora siempre cuenta con una imagen lista y empaquetada (tag `edge`) para pruebas end-to-end.
* **Fundación sólida:** Queda establecida la base YAML y permisos para posteriormente sumar escáneres de seguridad y flujos de release.

---

## 7. Fase 2 (Iteración 2): Workflow de Release y Semantic Versioning

### Problema / Objetivo
Con el pipeline de CI validando integraciones en `develop` de forma exitosa, el siguiente paso es automatizar la generación de entregables estables y listos para producción. Necesitamos un mecanismo formal para etiquetar y publicar imágenes definitivas en GHCR de acuerdo a estándares de la industria, asegurando que K8s y otras infraestructuras tengan referencias inmutables.

---

### Solución Implementada (Release Workflow)

Se implementó el archivo `.github/workflows/release.yml`, diseñado exclusivamente para dispararse cuando se etiquetan versiones en la rama principal.

#### Características de la Iteración:
1. **Trigger por Tags (SemVer):**
   - El pipeline solo se ejecuta cuando se detecta un push de un tag en formato de Semantic Versioning (ej. `v1.2.3`).
   - Esto mantiene la separación entre integraciones continuas (commits normales) y releases formales.

2. **Validación Pre-Release:**
   - Antes de empaquetar, el workflow ejecuta la suite completa de tests (`make test`), asegurando que solo el código que pase las pruebas pueda convertirse en una release.

3. **Etiquetado Semántico Automático:**
   - Utilizando `docker/metadata-action`, GHCR automáticamente recibe las imágenes con múltiples etiquetas correspondientes al versionado semántico:
     - `{{version}}` (ej. `1.2.3`)
     - `{{major}}.{{minor}}` (ej. `1.2`)
     - `{{major}}` (ej. `1`)
   - Esto permite que los deployments referencien la versión exacta o consuman actualizaciones menores automáticamente.

4. **Cacheado y Optimización:**
   - Se mantiene la directiva `cache-to: type=gha,mode=max` y `cache-from: type=gha`, logrando que la construcción del release herede las capas cacheadas durante la fase de CI en `develop`.

---

### Impacto de la Iteración
* **Trazabilidad Total:** Cada imagen productiva ahora está estrictamente ligada a un tag de Git.
* **Separación de Responsabilidades:** CI para iterar rápido en `develop`, CD (Release) para entregables estables.
* **Listo para Fase 3:** Las bases están establecidas para que cualquier clúster de Kubernetes o instancia de AWS despliegue la versión generada desde GHCR con total predictibilidad.
