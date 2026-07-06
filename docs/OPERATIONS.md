# Guía de Operaciones (Runbook)

Este documento detalla los procedimientos estándar para operar el clúster de Amazon EKS y la infraestructura subyacente.

## Autenticación al Clúster EKS
Para que tu herramienta local `kubectl` pueda comunicarse con el Control Plane de Kubernetes, debes generar el token de acceso utilizando AWS CLI. Asegúrate de tener credenciales de AWS válidas exportadas en tu sesión.

```bash
aws eks update-kubeconfig --region us-east-1 --name staging-cluster
```
*Si tienes éxito, verás un mensaje indicando que el contexto de Kubernetes ha sido actualizado.*

## Comandos Útiles (Day 2 Operations)

### Obtener el estado general
```bash
# Ver nodos y su estado (Deberían estar "Ready")
kubectl get nodes

# Ver los Pods de la aplicación
kubectl get pods -n avatars-generator

# Ver los balanceadores de carga asignados por AWS
kubectl get svc -n avatars-generator
```

### Troubleshooting
Si la aplicación falla o un Pod está en estado `Error` o `CrashLoopBackOff`:

1. **Revisar Logs de la Aplicación:**
```bash
# Logs del Frontend
kubectl logs deployment/avatars-generator-web -n avatars-generator
# Logs de la API
kubectl logs deployment/avatars-generator-api -n avatars-generator
```

2. **Revisar Eventos del Pod (Falta de recursos, Errores de Imagen):**
```bash
kubectl describe pod -l app=avatars-generator-web -n avatars-generator
```

## Aprovisionamiento desde Cero (Disaster Recovery)

Si se necesita recrear el entorno por completo (ej. en otra cuenta de AWS):
1. Navega a `terraform/bootstrap` y ejecuta `terraform init && terraform apply`.
2. Actualiza el nombre del bucket S3 en `terraform/environments/staging/main.tf` con el output generado por bootstrap.
3. Navega a `terraform/environments/staging` y ejecuta `terraform init && terraform apply`. Demorará unos 15 minutos en levantar la VPC, el NAT y el EKS Control Plane.
4. Conéctate al clúster con `aws eks update-kubeconfig`.
5. Recrea los secretos faltantes (ej. `k8s/overlays/staging/.env.secret`) e inyectalos usando Kustomize o directamente vía GitHub Actions.

## Limpieza de Entorno (Cost Optimization)
El Control Plane de EKS y el NAT Gateway incurren en costos fijos por hora. Cuando el entorno no se encuentre en demostración activa, **es obligatorio destruirlo**.

```bash
cd terraform/environments/staging
terraform destroy
```
*Nota: Terraform se encargará de eliminar los Worker Nodes, el Load Balancer físico, el Control Plane y finalmente las reglas de Networking y la VPC de forma ordenada.*
