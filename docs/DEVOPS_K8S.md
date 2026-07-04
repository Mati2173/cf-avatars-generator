# DevOps Evolución: Fase 3 (Kubernetes)

Este documento detalla la transición de la aplicación Avatars Generator desde un entorno `docker-compose` hacia una orquestación nativa en Kubernetes.

## Iteración 1: Entorno Local y Configuración

Se estableció un clúster local utilizando `kind` (Kubernetes IN Docker) para aislar el desarrollo y pruebas de despliegue antes de aprovisionar infraestructura en la nube (AWS EKS).

### 1. Configuración Base (`k8s/01-config.yaml`)

El primer paso arquitectónico fue separar lógicamente los recursos de la aplicación del resto del clúster.

**Recursos creados:**
- **Namespace (`avatars`):** Crea una barrera lógica. Todos los pods, servicios y secretos vivirán dentro de este espacio, evitando colisiones de nombres con otras aplicaciones.
- **ConfigMap (`avatars-config`):** Centraliza las variables de entorno no sensibles (como `FLASK_ENV` y `DB_PATH`). En lugar de harcodear estas variables en los contenedores, los Pods las inyectarán dinámicamente desde este mapa. Esto asegura que la imagen Docker permanezca inmutable y agnóstica al entorno.

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
- **Deployment (`avatars-api`):** Es el controlador principal. Se encarga de descargar tu imagen `ghcr.io/mati2173/cf-avatars-generator-api:1.0.0` y mantener siempre 1 réplica ejecutándose (Pod).
  - **Inyección y Volumen:** Conecta el ConfigMap a las variables de entorno, y "enchufa" el disco PVC (`api-data-pvc`) en el directorio `/data`.
  - **Probes (Health Checks):** Instruye a Kubernetes para hacer peticiones HTTP constantes a `/health` (Liveness) y `/ready` (Readiness). Si la API deja de responder 200 OK, Kubernetes reinicia el contenedor automáticamente o deja de enviarle tráfico.
  - **Recursos (Requests y Limits):** Se definieron explícantemente para evitar el problema de "noisy neighbor". `requests` asegura que el Pod solo se agende en Nodos con capacidad suficiente (ej. 128Mi RAM), mientras que `limits` protege al clúster matando el Pod si este sufre un memory leak (ej. >256Mi RAM).
- **Service (`avatars-api`):** Un LoadBalancer interno de tipo `ClusterIP`. Abstrae la IP efímera del Pod y provee un nombre DNS interno estático (las peticiones a `avatars-api:5000` son enviadas al Pod correcto mágicamente).

### 4. Frontend Web y Alias DNS (`k8s/04-web.yaml`)

El frontend empaquetado en Nginx Unprivileged también necesita un conjunto administrado.

**El desafío del proxy (Problema):**
En Docker Compose, el servicio backend se llamaba `api`. Por lo tanto, nuestro archivo `nginx.conf` tiene hardcodeado un proxy: `proxy_pass http://api:5000;`.
Sin embargo, en Kubernetes renombramos el servicio a `avatars-api` por ser más descriptivo y profesional. Si subíamos el frontend tal cual, Nginx iba a fallar intentando resolver el DNS `api` que ya no existe.
Re-construir la imagen de Docker solo para cambiar una palabra en el Nginx rompería nuestra regla de usar la imagen `1.0.0` inmutable.

**Solución DevOps Implementada (ExternalName):**
- **Deployment (`avatars-web`):** Corre Nginx de manera segura y controlada con bajísimos recursos requeridos (`requests` CPU 50m).
- **Service (`avatars-web`):** Servicio ClusterIP exponiendo el puerto 8080 del frontend.
- **Service (`api` - Tipo ExternalName):** Aquí aplicamos un "Truco DevOps". Creamos un servicio falso llamado `api` que actúa como un simple alias (CNAME DNS) hacia `avatars-api.avatars.svc.cluster.local`. Gracias a esto, engañamos al `nginx.conf` existente; cuando Nginx busque `http://api:5000`, Kubernetes interceptará la petición DNS y lo ruteará transparentemente hacia el nuevo servicio de la API. Todo esto sin modificar ni una línea de código ni regenerar imágenes.

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

### 2. Gestión del Clúster (kind)
```bash
# Crear un clúster de prueba nuevo
kind create cluster --name avatars-cluster

# Validar que el clúster está corriendo y conectado
kubectl cluster-info
kubectl get nodes

# Destruir el clúster (eliminar todo el entorno local)
kind delete cluster --name avatars-cluster
```

### 3. Despliegue de la Aplicación
Todos los manifiestos se aplican en orden para garantizar que las dependencias lógicas (como el Namespace) existan primero.

```bash
# Opción A: Despliegue paso a paso
kubectl apply -f k8s/01-config.yaml
kubectl apply -f k8s/02-storage.yaml
kubectl apply -f k8s/03-api.yaml
kubectl apply -f k8s/04-web.yaml

# Opción B: Despliegue de toda la carpeta de una vez
kubectl apply -f k8s/
```

### 4. Validación y Acceso (Port-Forward)
Para visualizar la aplicación corriendo, necesitamos un túnel desde nuestra máquina hacia el Service del Frontend.

```bash
# Esperar a que todos los Pods estén en estado "Running" y READY "1/1"
kubectl get pods -n avatars -w

# Abrir el túnel en el puerto 8080 (presiona Ctrl+C para detener)
kubectl port-forward svc/avatars-web -n avatars 8080:8080
```
*Una vez activo el túnel, navega a `http://localhost:8080` en tu navegador.*

### 5. Comandos Básicos de Debugging
Si un Pod se queda en `Pending`, `CrashLoopBackOff` o `Error`, utiliza estos comandos de diagnóstico rápido (reemplazando `<pod-name>` por el nombre real de tu Pod):

```bash
# Ver el estado general de los componentes en el namespace
kubectl get all -n avatars

# Inspeccionar por qué un Pod falla o no se levanta (Eventos)
kubectl describe pod <pod-name> -n avatars

# Ver los logs de la aplicación de un Pod específico
kubectl logs <pod-name> -n avatars

# Ver logs en tiempo real (seguimiento continuo)
kubectl logs -f <pod-name> -n avatars
```
