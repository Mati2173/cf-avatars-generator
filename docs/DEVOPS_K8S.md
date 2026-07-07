# DevOps Evolución: Fase 3 (Kubernetes)

Este documento detalla la transición de la aplicación Avatars Generator desde un entorno `docker-compose` hacia una orquestación nativa en Kubernetes.

## Iteración 1: Entorno Local y Configuración

Se estableció un clúster local utilizando `kind` (Kubernetes IN Docker) para aislar el desarrollo y pruebas de despliegue antes de aprovisionar infraestructura en la nube (AWS EKS).

### 1. Configuración Base (`k8s/01-config.yaml`)

El primer paso arquitectónico fue separar lógicamente los recursos de la aplicación del resto del clúster.

**Recursos creados:**
- **Namespace (`avatars-generator`):** Crea una barrera lógica. Todos los pods, servicios y secretos vivirán dentro de este espacio, evitando colisiones de nombres con otras aplicaciones.
- **ConfigMap (`avatars-generator-config`):** Centraliza las variables de entorno no sensibles (como `FLASK_ENV` y `DB_PATH`). En lugar de harcodear estas variables en los contenedores, los Pods las inyectarán dinámicamente desde este mapa. Esto asegura que la imagen Docker permanezca inmutable y agnóstica al entorno.

### 2. Capa de Almacenamiento (`k8s/02-storage.yaml`)

Nuestra aplicación utiliza SQLite, lo cual requiere que el archivo de la base de datos resida en un disco físico.

**Problema que resuelve:**
En Kubernetes, los contenedores (Pods) son efímeros; nacen y mueren continuamente. Si SQLite guardara los datos en el disco interno del Pod, la base de datos entera desaparecería cada vez que el Pod se reinicia o se actualiza.

**Recursos creados:**
- **PersistentVolumeClaim (`api-data-pvc`):** Es una "petición" formal de almacenamiento. Le pedimos al clúster que nos asigne `1Gi` de disco externo persistente. Cuando el Pod de nuestra API se levante, Kubernetes "conectará" este disco al contenedor. Si el Pod muere, el disco y los datos de SQLite sobreviven, y se volverán a conectar al Pod nuevo que lo reemplace.

**Comportamiento de Kubernetes detectado (WaitForFirstConsumer):**
Al crear el PVC en un clúster local como `kind`, el estado inicial del volumen será `Pending`. Esto **no es un error**. La clase de almacenamiento por defecto (`standard` / `local-path-storage`) utiliza un modo de enlace llamado `WaitForFirstConsumer`. Kubernetes retrasa intencionalmente la creación física del disco hasta que exista un Pod real que solicite usarlo. Esto asegura que el disco se provisione exactamente en el mismo Nodo físico donde el Pod sea agendado (vital en arquitecturas distribuidas locales o Multi-Zone en AWS).

### 3. API Backend (`k8s/03-api.yaml`)

El backend de la aplicación se despliega como un conjunto administrado.

**Problema que resuelve:**
Necesitamos asegurarnos de que el backend siempre esté corriendo, sea capaz de reiniciarse si falla, exponga sus endpoints a otros servicios internos, y sea consciente del estado de salud de su propio proceso.

**Recursos creados:**
- **Deployment (`avatars-generator-api`):** Es el controlador principal. Se encarga de descargar tu imagen `ghcr.io/mati2173/cf-avatars-generator-api:1.0.0` y mantener siempre 1 réplica ejecutándose (Pod).
  - **Inyección y Volumen:** Conecta el ConfigMap a las variables de entorno, y "enchufa" el disco PVC (`api-data-pvc`) en el directorio `/data`.
  - **Probes (Health Checks):** Instruye a Kubernetes para hacer peticiones HTTP constantes a `/health` (Liveness) y `/ready` (Readiness). Si la API deja de responder 200 OK, Kubernetes reinicia el contenedor automáticamente o deja de enviarle tráfico.
  - **Recursos (Requests y Limits):** Se definieron explícantemente para evitar el problema de "noisy neighbor". `requests` asegura que el Pod solo se agende en Nodos con capacidad suficiente (ej. 128Mi RAM), mientras que `limits` protege al clúster matando el Pod si este sufre un memory leak (ej. >256Mi RAM).
- **Service (`avatars-generator-api`):** Un LoadBalancer interno de tipo `ClusterIP`. Abstrae la IP efímera del Pod y provee un nombre DNS interno estático (las peticiones a `avatars-generator-api:5000` son enviadas al Pod correcto mágicamente).

### 4. Frontend Web y Alias DNS (`k8s/04-web.yaml`)

El frontend empaquetado en Nginx Unprivileged también necesita un conjunto administrado.

**El desafío del proxy (Problema):**
En Docker Compose, el servicio backend se llamaba `api`. Por lo tanto, nuestro archivo `nginx.conf` tiene hardcodeado un proxy: `proxy_pass http://api:5000;`.
Sin embargo, en Kubernetes renombramos el servicio a `avatars-generator-api` por ser más descriptivo y profesional. Si subíamos el frontend tal cual, Nginx iba a fallar intentando resolver el DNS `api` que ya no existe.
Re-construir la imagen de Docker solo para cambiar una palabra en el Nginx rompería nuestra regla de usar la imagen `1.0.0` inmutable.

**Solución DevOps Implementada (ExternalName):**
- **Deployment (`avatars-generator-web`):** Corre Nginx de manera segura y controlada con bajísimos recursos requeridos (`requests` CPU 50m).
- **Service (`avatars-generator-web`):** Servicio ClusterIP exponiendo el puerto 8080 del frontend.
- **Service (`api` - Tipo ExternalName):** Aquí aplicamos un "Truco DevOps". Creamos un servicio falso llamado `api` que actúa como un simple alias (CNAME DNS) hacia `avatars-generator-api.avatars.svc.cluster.local`. Gracias a esto, engañamos al `nginx.conf` existente; cuando Nginx busque `http://api:5000`, Kubernetes interceptará la petición DNS y lo ruteará transparentemente hacia el nuevo servicio de la API. Todo esto sin modificar ni una línea de código ni regenerar imágenes.

### Notas Arquitectónicas sobre ExternalName

**1. ¿Cuándo conviene usar un ExternalName?**
- Para abstraer migraciones progresivas (ej. el backend sigue en una máquina virtual externa y queremos que los Pods de K8s le peguen a un nombre local que luego cambiaremos).
- Para solucionar fricciones de *hardcoding* de nombres de host *legacy* al migrar de Docker Compose a K8s (nuestro caso), evitando reconstruir contenedores estáticos.
- Para enrutar tráfico hacia bases de datos externas como RDS en AWS sin que la aplicación sepa dónde está físicamente la BD.

**2. Alternativas en Kubernetes:**
- **Renombrar el Service original:** Podríamos haber llamado `api` a nuestro backend Service directamente. Sin embargo, en Kubernetes la convención es usar nombres descriptivos (`[app]-[component]`) para evitar colisiones en namespaces muy poblados.
- **Inyección de variables en Runtime:** Para aplicaciones como Nginx, requeriría un *entrypoint script* complejo que lea variables de entorno (`$BACKEND_URL`) y modifique el `nginx.conf` (con comandos como `envsubst`) *antes* de que Nginx arranque. Es la práctica más pura, pero aumenta la complejidad del contenedor base.

**3. ¿Es recomendable para Producción?**
- **Sí, es 100% válido para Producción.** `ExternalName` es un recurso nativo de Kubernetes respaldado por CoreDNS. No añade latencia de proxy (ya que resuelve a nivel DNS local), es extremadamente estable y se usa frecuentemente en arquitecturas empresariales maduras para conectar microservicios a infraestructuras heterogéneas.

---

## Guía Operativa (Runbook Local)

> [!WARNING]
> **Alcance:** Las instrucciones de esta sección aplican EXCLUSIVAMENTE al entorno de desarrollo local con `kind`. **No aplican** al despliegue productivo en AWS EKS, el cual será abordado en futuras iteraciones.

### 1. Prerequisitos
Para ejecutar este proyecto en K8s local, tu máquina debe tener instalados:
- **Docker:** Motor de contenedores activo.
- **kind:** (Kubernetes IN Docker) para aprovisionar el clúster local.
- **kubectl:** El cliente CLI oficial para interactuar con la API de Kubernetes.

### 2. Gestión del Clúster (kind) e Ingress Controller
> [!NOTE]
> El archivo `infra/kind/config.yaml` contiene los mapeos de puertos (8081/8443) necesarios para que el Ingress Controller sea accesible desde tu `localhost` sin requerir `sudo` ni colisionar con servicios existentes como Apache. **Este archivo NO se aplica con `kubectl`.**

```bash
# Crear un clúster de prueba nuevo usando la configuración especial
kind create cluster --name avatars-generator-cluster --config infra/kind/config.yaml

# Validar que el clúster está corriendo y conectado
kubectl cluster-info

# Instalar NGINX Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Esperar a que el Ingress Controller esté READY 1/1
kubectl get pods -n ingress-nginx -w
```

### 3. Configuración de DNS Local
Para simular un dominio real en K8s de Capa 7, mapeamos un host inventado a tu IP local.
Añade la siguiente línea al final de tu archivo `/etc/hosts` (requiere `sudo`):
```text
127.0.0.1 avatars-generator.local
```

### 4. Despliegue y Validación
Una vez que el Ingress Controller esté corriendo, aplica los manifiestos de la aplicación en la carpeta `k8s/`.

```bash
# Aplicar todos los manifiestos de una vez
kubectl apply -f k8s/

# Esperar a que los Pods de la aplicación (API y Web) estén listos
kubectl get pods -n avatars-generator -w
```

Para probar conectividad (¡sin port-forward!):
- **Navegador:** `http://avatars-generator.local:8081`
- **Curl:** `curl -s http://avatars-generator.local:8081/health`

### 5. Comandos Básicos de Debugging
Si un Pod se queda en `Pending`, `CrashLoopBackOff` o `Error`, utiliza estos comandos de diagnóstico rápido (reemplazando `<pod-name>` por el nombre real de tu Pod):

```bash
# Ver el estado general de los componentes en el namespace
kubectl get all -n avatars-generator

# Inspeccionar por qué un Pod falla o no se levanta (Eventos)
kubectl describe pod <pod-name> -n avatars-generator

# Ver los logs de la aplicación de un Pod específico
kubectl logs <pod-name> -n avatars-generator

# Ver logs en tiempo real (seguimiento continuo)
kubectl logs -f <pod-name> -n avatars-generator
```

---

## Conceptos Arquitectónicos de Kubernetes

### El Flujo de Peticiones End-to-End (Ingress a Base de Datos)
Para entender cómo funciona nuestra aplicación en Kubernetes, este es el viaje exacto que realiza una petición HTTP desde tu navegador hasta la base de datos SQLite:

1. **Browser / K6:** Hace una petición a `http://avatars-generator.local:8081/api/avatar`.
2. **Máquina Host:** El `/etc/hosts` resuelve `avatars-generator.local` hacia `127.0.0.1`. El puerto `8081` es interceptado por Docker (que corre a `kind`).
3. **NGINX Ingress Controller:** Recibe la petición en el puerto 80 del Nodo. Lee la URL y matchea la regla de `avatars-generator-ingress` (Todo lo que empiece con `/` va a `avatars-generator-web`).
4. **Service (Frontend):** El Ingress envía la petición al Service `avatars-generator-web`, que funciona como un Load Balancer interno.
5. **Pod (Frontend):** El Service elige un Pod de Nginx Unprivileged vivo y le entrega la petición en el puerto 8080.
6. **Nginx (Frontend):** El bloque de proxy en `nginx.conf` detecta el prefijo `/api/` y redirige el tráfico hacia `http://api:5000`.
7. **Service Alias (ExternalName):** Kubernetes intercepta la búsqueda DNS de `api` y devuelve el CNAME `avatars-generator-api.avatars.svc.cluster.local`.
8. **Service (Backend):** La petición llega al Service `avatars-generator-api`, que balancea la carga hacia un Pod de Flask.
9. **Pod (Backend):** Flask procesa la lógica, lee/escribe en `/data/avatars.db`.
10. **Persistent Volume:** SQLite interactúa con el disco físico atado al Pod a través del PVC.

### Ingress vs NodePort vs LoadBalancer
- **NodePort:** Abre un puerto estático (usualmente en el rango 30000-32767) en *todos* los nodos físicos del clúster. Es primitivo, feo para los usuarios y poco seguro para exponer HTTP. Se usa mayormente para servicios internos muy específicos.
- **LoadBalancer:** Instruye al proveedor de la nube (AWS, GCP) para que provisione un Balanceador de Carga de red nativo con una IP pública exclusiva. Es caro (se factura por cada servicio) y no entiende de rutas HTTP o dominios, solo de puertos (Capa 4).
- **Ingress:** Es la forma inteligente de exponer aplicaciones web (Capa 7). Requieres solo un LoadBalancer físico (para el Ingress Controller) y luego puedes enrutar miles de servicios distintos basándote en la URL, subdominios, o *paths*, centralizando el SSL/HTTPS.

---

## Arquitectura Multi-Entorno (Kustomize)
Para evitar la duplicación de código y permitir que la aplicación escale a múltiples entornos (Local, Staging, Producción) sin romper nada, utilizamos **Kustomize** (nativo en `kubectl`).

Nuestra carpeta `k8s/` está dividida lógicamente en:
1. **`base/`:** Contiene "La Aplicación Pura". Aquí viven los Deployments, Services y ConfigMaps. No hay mención a Ingress, ni volúmenes persistentes atados a infraestructuras específicas, ni reglas de escalado masivo.
2. **`overlays/`:** Contienen los "Parches de Entorno". 
   - El entorno `local/` importa la base y le inyecta el `PersistentVolumeClaim` (porque localmente usamos SQLite en disco), el `Ingress` de NGINX, y nuestro Service Alias (`ExternalName`).

### Comandos de Kustomize
```bash
# Validar y previsualizar el YAML final que Kustomize construirá (Dry Run)
kubectl kustomize k8s/overlays/local/

# Aplicar el entorno completo al clúster (Nota la bandera -k en lugar de -f)
kubectl apply -k k8s/overlays/local/
```

## Estrategia GitOps y Tags Inmutables

Nuestra arquitectura Kustomize está diseñada con principios de **Infraestructura Inmutable** para posibilitar flujos maduros de CI/CD (Continuous Deployment/GitOps):

### 1. Desacoplamiento del Tag de Imagen
Los manifiestos en `k8s/base/` **no declaran ninguna versión (tag)** de las imágenes Docker (ej. `ghcr.io/...-api`). La base es un contrato puramente estructural.

La inyección de la versión específica ocurre **dinámicamente en cada entorno** (ej. `overlays/local/kustomization.yaml` o durante la ejecución en CI mediante `kustomize edit set image`). Esto permite que un pipeline o un agente GitOps (como ArgoCD) actualice la versión desplegada sin mutar jamás el código fundacional.

### 2. imagePullPolicy: IfNotPresent
A diferencia de configuraciones estándar que usan `imagePullPolicy: Always`, nosotros forzamos explícitamente `IfNotPresent`.
¿Por qué?
- **Tags inmutables:** Asumimos que los tags de nuestras imágenes (e.g. `sha-5a3d9bc` o `v1.2.0`) son inmutables. Nunca sobreescribimos un tag publicado.
- **Resiliencia (Anti-Rate Limiting):** Si un nodo de Kubernetes se reinicia y vuelve a levantar el Pod, con `Always` el clúster intentaría forzar una conexión a Internet (Docker Hub / GHCR) para verificar si la imagen cambió. Si el registry está caído o nos aplica *rate-limiting*, el Pod crashearía a pesar de ya tener la imagen sana en disco (`ErrImagePull`).
- **Performance local y CI:** Al usar `IfNotPresent`, los tests E2E locales (Kind) cargan imágenes pre-cacheadas y levantan Pods en milisegundos, totalmente aislados de la red.
