# 👤 Avatares — Proyecto DevOps Completo

Aplicación full-stack nativa en la nube (Cloud-Native) diseñada para generar y personalizar avatares SVG. Este proyecto ha sido llevado desde un simple desarrollo local hasta un sistema orquestado en **Kubernetes (AWS EKS)** con **CI/CD, Seguridad (IRSA/OIDC) y Observabilidad**, resolviendo los desafíos del Bootcamp DevOps.

![Avatares App](./docs/avatar.png)

---

## 🏗️ Arquitectura de Alto Nivel

El proyecto emplea una arquitectura clásica de 3 capas adaptada para contenedores:

```text
┌────────────────┐       ┌───────────────┐       ┌──────────────┐
│  Browser / DNS │──────▶│ Nginx (Web)   │──/api/▶ Flask (API)  │
│  (AWS ALB)     │◀──────│ React SPA     │◀──────│ Gunicorn     │
└────────────────┘  :80  └───────────────┘       └──────┬───────┘
                                                        │
                                                 ┌──────▼───────┐
                                                 │ SQLite (EBS) │
                                                 │ (Persistente)│
                                                 └──────────────┘
```

- **Frontend (`web`):** Single Page Application en React empaquetada como estático en un servidor NGINX optimizado y sin privilegios (rootless). Proxy inverso inyectado para `/api`.
- **Backend (`api`):** API Python (Flask + Gunicorn) que procesa gráficos vectoriales y utiliza SQLite para la base de datos de galería.
- **Almacenamiento:** Volúmenes dinámicos aprovisionados por el EBS CSI Driver de AWS para evitar pérdida de la base de datos durante reinicios de Pods.

---

## 🎨 Funcionalidades de la Aplicación

- **Editor de Avatares:** Personalización completa de rostros (ojos, cejas, boca, pelo, barba y colores) con vista previa SVG en tiempo real. Botón "Aleatorio" para combinaciones automáticas.
- **Galería Persistente:** Posibilidad de guardar avatares favoritos, organizarlos en un grid y eliminarlos. Resiste reinicios de contenedores.
- **API Endpoints Principales:**
  - `GET /api/avatar` (Renderiza SVG paramétrico).
  - `GET /api/gallery` y `POST /api/gallery` (CRUD de la base de datos).
  - `GET /metrics` (Expone datos estándar para Prometheus).
- **Diseño Moderno:** Frontend React con Glassmorphism, animaciones y diseño completamente responsive.

---

## 🌍 Entornos y Escenarios de Ejecución

El proyecto está diseñado para funcionar en cuatro escenarios progresivos, permitiendo a los desarrolladores probar el software y la infraestructura con seguridad antes de llegar a Producción.

### 1. Desarrollo Local (Docker Compose)
Ideal para desarrollo diario de código frontend/backend sin tener que lidiar con orquestadores pesados.

- **Levantar:** `make up`
- **Acceso:** `http://localhost:8080`
- **Características:** Base de datos persistente mediante docker volumes, hot-reloading desactivado (orientado a testing completo). Documentación completa en [ABOUT.md](ABOUT.md).

### 2. Pruebas de Orquestación (Kubernetes Local / Kind)
El puente perfecto para el equipo de DevOps que necesita probar configuración Kustomize sin gastar dinero en AWS.

- **Prerrequisitos:** Debes tener `kind` y `kubectl` instalados en tu máquina local.
- **Levantar Clúster:** 
  Utilizamos un archivo de configuración para mapear los puertos del Ingress:
  ```bash
  kind create cluster --name avatars-generator-cluster --config infra/kind/config.yaml
  ```
- **Instalar Ingress Controller (NGINX):**
  ```bash
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
  ```
- **Configurar DNS Local:** Agrega `127.0.0.1 avatars-generator.local` a tu `/etc/hosts`.
- **Desplegar la App:** 
  ```bash
  kubectl apply -k k8s/overlays/local
  ```
- **Acceso:** `http://avatars-generator.local:8081`
- **Testing Local (K6):** Para lanzar pruebas de carga contra el entorno de Kind, debes setear la variable de entorno `TARGET_ENV=k8s`:
  ```bash
  make load-quick TARGET_ENV=k8s
  ```
- **Características:** Despliegue emulado de Kubernetes mediante contenedores locales. Revisa la guía exhaustiva en [docs/DEVOPS_K8S.md](docs/DEVOPS_K8S.md).

### 3. Entorno de Staging (AWS EKS)
El entorno cloud en tiempo real, mantenido automáticamente por Integración y Despliegue Continuo (CI/CD).

- **Estructura:** Cluster EKS (Data plane aislado en subredes privadas), NAT Gateway. Aprovisionado completamente en Terraform.
- **Limitaciones de Staging:** Para ahorrar costos, se emplean instancias EC2 pequeñas (`t3.small`). El despliegue de Kubernetes utiliza estrategia Kustomize `Recreate` para evitar saturar las interfaces de red (ENI limit).
- **Despliegue:** Automático mediante Merge a la rama `staging` usando Autenticación **OIDC Passwordless** contra AWS.

### 4. Producción (Flujo de Release)
**Nota importante:** Actualmente no existe un entorno físico de Producción (clúster EKS) desplegado en AWS por razones de costos de la cuenta. Sin embargo, el **flujo técnico está 100% resuelto**.
- **Cómo funciona:** Al crear un Tag Semántico en Git (Ej. `v1.2.0`), el pipeline `release.yml` entra en acción, reconstruye artefactos optimizados y los publica oficial y permanentemente en GHCR, listos para que cualquier clúster productivo futuro pueda extraerlos de forma confiable.

---

## ⚡ Guía Rápida (Quickstart)

Para probar la aplicación en tu máquina de la forma más sencilla:

1. **Clona el repositorio**
   ```bash
   git clone https://github.com/Mati2173/cf-avatars-generator.git
   cd cf-avatars-generator
   ```
2. **Levanta con Make/Docker**
   ```bash
   make up
   ```
3. **Pruébalo**
   Abre [http://localhost:8080](http://localhost:8080) en tu navegador. Puedes lanzar tests de humo mediante `make test-api`.

---

## 🔗 Índice Analítico de Documentación

Esta arquitectura requirió el ensamblaje de múltiples dominios DevOps. Explora cada uno de ellos a profundidad en sus respectivos módulos:

* **[Kustomize & Kubernetes](k8s/README.md):** Cómo abstrajimos la configuración (`base/` vs `overlays/`).
* **[Infraestructura como Código (Terraform)](terraform/README.md):** Módulos AWS, VPC, EKS, IRSA y State locking nativo.
* **[Pipelines CI/CD y Flujo Git](.github/README.md):** Shift-left testing, despliegues sin secretos (OIDC) y flujos GitHub Actions.
* **[Manual de Operaciones y Troubleshooting](docs/OPERATIONS.md):** Comandos imprescindibles y arquitectura técnica en el día a día.

---

## 📖 Bitácora DevOps (Evolución Arquitectónica)

A lo largo del proyecto, la infraestructura fue iterando, mejorando y corrigiendo errores clásicos de escalado y redes. Estos documentos narran de forma transparente (a modo de portfolio) dichas decisiones y evoluciones:

- [Historia 1: Transición del Testing local a Docker](docs/DEVOPS_EVOLUTION_TESTING.md)
- [Historia 2: Corrección de healthchecks e Infraestructura Base](docs/DEVOPS_INFRA_CHANGES.md)
- [Historia 3: El paso a Kubernetes (Local)](docs/DEVOPS_K8S.md)

---

## 📈 Observabilidad y Rendimiento

La aplicación expone un endpoint `/metrics` estandarizado para Prometheus y se provee load-testing automatizado de fábrica:

- **Monitoreo Local:** Ejecuta `make monitoring` para desplegar Prometheus + Grafana y ver un Dashboard auto-aprovisionado.
- **Load Testing (k6):** `make load-quick` somete a la API a pruebas de carga locales para observar cómo reaccionan las métricas doradas (latencia, tráfico, errores).
