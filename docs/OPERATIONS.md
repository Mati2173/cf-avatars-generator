# Guía de Operaciones (Runbook)

Este documento detalla los procedimientos estándar para operar el clúster de Amazon EKS, entender el flujo de la infraestructura y realizar tareas de troubleshooting comunes en la aplicación.

## Autenticación al Clúster EKS

Para que tu herramienta local `kubectl` pueda comunicarse con el Control Plane de Kubernetes de AWS, debes generar el token de acceso utilizando AWS CLI. Asegúrate de tener credenciales de AWS válidas exportadas en tu sesión.

```bash
aws eks update-kubeconfig --region us-east-1 --name staging-cluster
```
*Si tienes éxito, verás un mensaje indicando que el contexto de Kubernetes ha sido actualizado.*

## Comandos Útiles de Troubleshooting (Day 2 Operations)

### Obtener el estado general del Clúster
```bash
# Ver los nodos worker EC2 y su estado (Deberían estar "Ready")
kubectl get nodes

# Ver estado de los add-ons (Ej. EBS CSI Driver pods, coredns)
kubectl get pods -n kube-system
```

### Trabajar con la Aplicación (Namespace: avatars-generator)

Todos los componentes de nuestra aplicación (exceptuando Ingress global) viven dentro del namespace `avatars-generator`.

```bash
# Ver los Pods de la aplicación (Web y API)
kubectl get pods -n avatars-generator

# Ver detalles completos de un Pod específico (para ver errores de agendado o liveness probes)
kubectl describe pod <nombre-del-pod> -n avatars-generator

# Leer logs en tiempo real (útil para ver los de la API Flask o NGINX)
kubectl logs -f deployment/avatars-generator-api -n avatars-generator
kubectl logs -f deployment/avatars-generator-web -n avatars-generator
```

### Troubleshooting de Almacenamiento (Discos EBS)

Si la base de datos de SQLite no persiste o la API no logra arrancar, el problema generalmente radica en la inyección de los volúmenes en EKS.

```bash
# Comprobar el estado del PersistentVolumeClaim (Debería estar "Bound")
kubectl get pvc -n avatars-generator

# Revisar si hay errores aprovisionando el volumen gp3
kubectl describe pvc avatars-generator-data -n avatars-generator

# Ver el PersistentVolume real creado por AWS
kubectl get pv
```

### Forzar Reinicio de la Aplicación
Si realizaste un cambio externo (por ejemplo un fix directo en el disco o un cambio manual de ConfigMap) y necesitas reiniciar la app sin un push nuevo a Git:

```bash
kubectl rollout restart deployment/avatars-generator-api -n avatars-generator
kubectl rollout restart deployment/avatars-generator-web -n avatars-generator
```

---

## Escalado a Producción (Checklist de Operaciones)

La arquitectura actual en **Staging** es un entorno "Miniatura". EKS impone límites matemáticos severos en instancias pequeñas (ej. en una EC2 `t3.small` puedes alojar como máximo 11 pods debido a la limitación de interfaces de red ENI).

Elevar este proyecto al siguiente nivel u orientarlo para un tráfico real y masivo, requiere revisar este checklist de operaciones:

1. **Migración de Base de Datos:** Abandonar SQLite e implementar Amazon RDS (PostgreSQL). SQLite utiliza bloqueo por archivo y corrupta instantáneamente si se abre concurrentemente.
2. **Escalado Horizontal:** Con la DB resuelta, aumentar los resources de EKS (instancias `t3.large` o `m5.large`) y cambiar la variable `replicas: 1` a un número superior, usando preferiblemente un HPA (Horizontal Pod Autoscaler).
3. **Rollout Strategies:** Modificar `patch-api-strategy.yaml` en Kustomize. Actualmente se usa `Recreate` para vaciar el nodo antes de instalar el pod nuevo. En producción con RDS, esto debe volver a `RollingUpdate` para garantizar **Zero-Downtime Deployments**.
