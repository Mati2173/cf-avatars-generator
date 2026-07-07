# Kubernetes & Kustomize

Este directorio contiene todos los manifiestos declarativos utilizados para desplegar la aplicación en Kubernetes.
Utilizamos **Kustomize** de manera estricta para garantizar la separación de entornos y prevenir el código duplicado o configuraciones de un entorno impactando a otro.

## Estructura de Directorios

La estructura sigue el patrón estándar de `base/` y `overlays/`:

```text
k8s/
├── base/                   # Recetas base (agnósticas al entorno)
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── configmap.yaml
│   ├── api-deployment.yaml
│   ├── api-service.yaml
│   ├── web-deployment.yaml
│   └── web-service.yaml
│
└── overlays/               # Capas específicas por entorno
    ├── local/              # Entorno local (Kind / Minikube)
    │   ├── kustomization.yaml
    │   ├── ingress.yaml    # Ingress Controller local
    │   └── storage-pvc.yaml # Almacenamiento local (hostPath)
    │
    ├── staging/            # AWS EKS Staging (Réplica de producción)
    │   ├── kustomization.yaml
    │   ├── patch-api-strategy.yaml   # Forzar Recreate strategy (Límites t3.micro)
    │   ├── patch-web-strategy.yaml   # Forzar Recreate strategy
    │   ├── patch-api-storage.yaml    # Mounts para el volumen EBS
    │   ├── storage-class.yaml        # aws-ebs-csi-driver (gp3)
    │   └── storage-pvc.yaml          # PersistentVolumeClaim (EBS gp3)
    │
    └── prod/               # AWS EKS Producción (Reservado para el release final)
        └── (Configuración vacía/no implementada intencionalmente en este proyecto por costos)
```

## Entornos y Casos de Uso

### 1. Entorno Local (`overlays/local`)
**Objetivo:** Probar el ciclo de vida de los manifiestos Kustomize de la misma forma que actuarían en producción, pero en una máquina de desarrollo sin costos de nube.
- **Red:** Utiliza un `Ingress` genérico respaldado por NGINX Ingress Controller en el puerto local, mapeado a través de *ExternalName*.
- **Persistencia:** Almacena la base de datos de SQLite en el disco duro de la máquina utilizando la StorageClass estándar de Kind (generalmente `hostPath` transparente).

**Cómo desplegar:**
```bash
# Asumiendo que Kind con Ingress-Ready ya está instalado
kubectl apply -k k8s/overlays/local/
```

### 2. Entorno Staging (`overlays/staging`)
**Objetivo:** Réplica lo más exacta posible a un entorno productivo real, alojado en AWS EKS. Usado como paso final de validación continua (CD).
- **Despliegue Continuo:** Este directorio no está pensado para aplicarse manualmente. GitHub Actions (ver `cd.yml`) inyecta dinámicamente las versiones de las imágenes mediante `kustomize edit set image` durante el despliegue automático de la rama `staging`.
- **Persistencia:** Emplea de manera nativa la StorageClass `gp3` configurada por el *EBS CSI Driver* que aprovisiona automáticamente volúmenes persistentes robustos. Además inyecta un `securityContext: fsGroup` para permitir la convivencia entre contenedores que se ejecutan como usuario no-root y los discos nativos creados en AWS.
- **Estrategias de Despliegue:** Para sortear las limitaciones de recursos físicos de las EC2 (ej: máximo número de Pods por nodo en `t3.micro`/`t3.small`), se utilizan parches Kustomize para forzar la estrategia `Recreate` en los despliegues de la API y Web, destruyendo el Pod antiguo antes de crear el nuevo.
