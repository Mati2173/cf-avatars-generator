# 🛠 DevOps Evolution — Testing Infrastructure

Este documento resume la evolución del sistema de testing del proyecto hacia un enfoque completamente containerizado, eliminando dependencias del entorno local y garantizando reproducibilidad total.

---

## 🎯 Problema inicial

El sistema de testing estaba diseñado para ejecutarse directamente en el entorno local mediante Makefile:

### Backend (Python)

```makefile
cd api && python3 -m pip install -q -r requirements-test.txt && python3 -m pytest tests/ -v
````

### Frontend (Node)

```makefile
cd web && npm test
```

---

## ❌ Problemas encontrados

### 1. Backend — entorno Python restringido (PEP 668)

Al intentar instalar dependencias se encontró el siguiente error:

```text
error: externally-managed-environment
```

Esto ocurre porque el sistema operativo bloquea instalaciones globales de Python y fuerza el uso de entornos virtuales (`venv`) o aislamiento explícito.

📌 Impacto:

* Imposibilidad de ejecutar `pip install` directamente
* Dependencia obligatoria de configuración local del sistema
* Fricción para ejecutar tests en cualquier máquina

---

### 2. Frontend — dependencias no disponibles en entorno local

Al ejecutar los tests del frontend:

```text
sh: 1: vitest: not found
```

📌 Causa:

* El entorno local no garantizaba instalación de dependencias
* El proyecto dependía de un setup previo manual de Node + npm install
* Inconsistencias entre máquinas y estados del proyecto

---

## 🧱 Decisión de arquitectura

Se decidió migrar completamente la ejecución de tests a **Docker**, con los siguientes objetivos:

* Eliminar dependencia de Python y Node instalados localmente
* Evitar problemas de entornos gestionados (PEP 668)
* Garantizar ejecución consistente en cualquier máquina
* Estandarizar el flujo para CI/CD

---

## 🐳 Solución implementada

### Backend (pytest en Docker)

Se creó un `Dockerfile.test` basado en `python:3.12-slim` que:

* Instala dependencias dentro del contenedor
* Ejecuta `pytest` como proceso principal
* Aísla completamente el entorno Python

---

### Frontend (vitest en Docker)

Se creó un `Dockerfile.test` basado en `node:22-alpine` que:

* Instala dependencias dentro del contenedor
* Ejecuta `npm test` dentro de un entorno Node consistente
* Garantiza que `vitest` exista dentro del contenedor

---

## 🔁 Estandarización con Makefile

El Makefile pasó a actuar como interfaz de ejecución, delegando todo a Docker:

```makefile
test-backend:
	docker build -t avatar-generator-api-test -f api/Dockerfile.test api/
	docker run --rm avatar-generator-api-test

test-frontend:
	docker build -t avatar-generator-web-test -f web/Dockerfile.test web/
	docker run --rm avatar-generator-web-test
```

---

## 🚀 Resultado final

El sistema de testing ahora es:

* 100% containerizado
* Independiente del entorno local
* Reproducible en cualquier máquina
* Compatible con CI/CD
* Aislado entre frontend y backend

---

## 📌 Conclusión

La migración resolvió problemas reales de entorno (PEP 668 en Python y dependencias faltantes en Node) y transformó el sistema en un flujo completamente alineado con prácticas DevOps:

> “El entorno local deja de ser una dependencia. Docker se convierte en la fuente de verdad.”

---

## 🛠 Refactorización: Multi-stage Testing y Module Shadowing

### 1. El problema del Contexto y `.dockerignore`

Inicialmente, el entorno de testing usaba archivos separados (`Dockerfile.test`). Al intentar limpiar las imágenes de producción, se agregaron los directorios `tests/` al archivo `.dockerignore`.

📌 Impacto negativo:
* Al ignorar los tests, Docker dejaba de enviarlos al *Build Context*.
* Cuando `Dockerfile.test` intentaba hacer `COPY . .`, los archivos de prueba ya no existían.
* Resultado: `pytest` fallaba indicando que no encontraba el directorio de tests.

### 2. Unificación mediante Multi-Stage Builds

Para resolver el problema del contexto sin ensuciar la imagen de producción, se decidió eliminar los `Dockerfile.test` y unificarlos en los Dockerfiles principales utilizando un *Target Stage* llamado `test`.

```dockerfile
# --- Builder ---
FROM python:3.12-slim AS builder
# ... (Instalación de dependencias)

# --- Test ---
FROM builder AS test
# ... (Ejecución de tests con pytest)

# --- Production ---
FROM python:3.12-slim
# ... (Copia limpia sin dependencias de test)
```

📌 Beneficios:
* Un único `Build Context` y un único `.dockerignore` que SÍ incluye la carpeta `tests/`.
* La fase `test` consume los archivos y corre los tests.
* La fase `production` NO copia la carpeta de tests, resultando en una imagen final inmaculada.
* Alineación total con prácticas de CI/CD (usando `docker build --target test`).

---

### 3. El problema de Module Shadowing (Import Resolution)

Al unificar los Dockerfiles, el backend heredó la directiva `WORKDIR /app`. Esto provocó un fallo silencioso en `pytest`:

```text
AttributeError: module 'app.app' has no attribute 'config'
```
Y posteriormente, tras intentar ajustes:
```text
ModuleNotFoundError: No module named 'app'
```

📌 Causa:
La combinación de un archivo llamado `app.py`, un archivo `__init__.py` en la raíz, y el directorio de trabajo `/app` confundió al intérprete de Python. Pytest asumió que el directorio `/app` era un paquete de Python, inyectando `/` en el `sys.path`. Como resultado, `import app` intentaba importar el directorio en sí mismo, o directamente fallaba.

### 4. Solución DevOps (Sin modificar código)

Se priorizó NO modificar el código de la aplicación (ej. no borrar `__init__.py` ni renombrar `app.py`) para no adaptar el desarrollo a problemas de infraestructura.

La solución consistió en dos pasos puramente de contenedorización:

1. **Cambio de WORKDIR:**
   Se movió el entorno de trabajo a `WORKDIR /src`. Esto rompe la colisión de nombres entre el directorio padre (`/app`) y el archivo de código (`app.py`).

2. **Definición de PYTHONPATH:**
   Para evitar el comportamiento de *Test Discovery* de Pytest (que asume que `/src` es un sub-paquete e inyecta `/` en lugar de `/src`), se añadió explícitamente al stage de test:
   ```dockerfile
   ENV PYTHONPATH=/src
   ```
   Esto fuerza a Python a resolver los módulos partiendo explícitamente desde la raíz del código fuente, una práctica estándar de *Twelve-Factor App*.

---

### 🚀 Resultado final de la Fase 1

La infraestructura de testing quedó completamente robusta:
* Los tests de Frontend y Backend corren nativamente dentro de contenedores.
* Se superaron las colisiones del motor de Python.
* La imagen de producción final pesa menos y está libre de archivos o librerías de testing.