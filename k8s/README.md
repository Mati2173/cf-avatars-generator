# Manifiestos de Kubernetes (Kustomize)

El despliegue de la aplicación en el clúster de Kubernetes se gestiona íntegramente de forma declarativa mediante `Kustomize`.

## Arquitectura de Overlays

El proyecto utiliza una arquitectura Base/Overlay para separar la configuración común de los detalles específicos de cada entorno:

- `base/`: Contiene los recursos fundamentales que se comparten entre todos los entornos (`Deployment`, `Service`, `ConfigMap`). Define las peticiones de recursos optimizadas (`requests`/`limits`) para los microservicios `api` y `web`.
- `overlays/local/`: Configuraciones específicas para despliegues locales (minikube/k3d).
- `overlays/staging/`: Configuraciones específicas para despliegues en AWS EKS (Free Tier).

## Decisiones Críticas en Staging (Restricciones t3.micro)

Debido a que el entorno de Staging corre en instancias `t3.micro` de AWS (límite duro de 4 Pods máximos por nodo y 1GB RAM), se tomaron decisiones arquitectónicas atípicas para priorizar funcionalidad sobre complejidad:

1. **Evitación del Ingress Controller:**
   Instalar NGINX Ingress requeriría Pods adicionales. En su lugar, el frontend (`web`) se expone utilizando un `Service` de tipo `LoadBalancer`. AWS aprovisiona de forma externa y nativa un Classic Load Balancer sin consumir slots de Pods en el clúster.

2. **Resolución DNS Interna (El Truco del Alias):**
   El código fuente del frontend espera comunicarse con un host llamado estrictamente `api`. Para mantener el estándar de Kubernetes sin renombrar servicios reales, utilizamos un `Service` de tipo `ExternalName` (`k8s/overlays/staging/alias.yaml`). Este servicio crea un CNAME a nivel de clúster que redirige las peticiones de `api` hacia `avatars-generator-api.avatars-generator.svc.cluster.local`.

3. **Almacenamiento Efímero (`emptyDir`):**
   La API necesita un volumen para SQLite. En AWS, proveer almacenamiento persistente requiere el add-on *EBS CSI Driver*. Para mantener el clúster ligero en esta etapa, aplicamos un parche (`patch-api-storage.yaml`) que sustituye el `PersistentVolumeClaim` original por un volumen de tipo `emptyDir`. Los datos de la DB se reiniciarán si el Pod de la API se elimina, lo cual es aceptable para demostraciones.

## Flujo de Despliegue Manual

```bash
# 1. Generar los Secretos dinámicos en el overlay de Staging
echo "API_KEY=tu_secreto" > k8s/overlays/staging/.env.secret

# 2. Aplicar Kustomize hacia el clúster
kubectl apply -k k8s/overlays/staging
```
