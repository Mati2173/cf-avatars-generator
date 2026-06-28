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