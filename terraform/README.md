# Infraestructura como Código (Terraform)

Este directorio contiene toda la infraestructura fundacional del proyecto desplegada en AWS. Todo el código sigue prácticas profesionales orientadas a la mantenibilidad y seguridad.

## Estructura de Directorios

- `bootstrap/`: Contiene los recursos "huevo y gallina". Inicializa el bucket S3 para el almacenamiento remoto del estado (Remote State) con encriptación AES-256 y versionamiento habilitado.
- `modules/`: Contiene módulos reutilizables.
  - `vpc`: Crea la red privada, subredes públicas y privadas usando `for_each`, un Internet Gateway y un NAT Gateway.
  - `eks`: Aprovisiona el clúster de Kubernetes, Roles de IAM separados (Control Plane y Workers) y configura los Access Entries modernos.
  - `github-oidc`: Crea el Identity Provider OIDC para permitir despliegues desde GitHub Actions sin secretos estáticos.
- `environments/staging/`: Consume los módulos anteriores para armar el entorno final de "Staging". Guarda su estado remotamente en el bucket S3 aprovisionado por `bootstrap`.

## Decisiones Arquitectónicas Críticas

1. **Aislamiento de Workers:** Los nodos EC2 (Data Plane) de Kubernetes se aprovisionan **exclusivamente en subredes privadas**. No tienen IP pública. Todo el tráfico saliente (ej. para descargar imágenes de GHCR) pasa por el **NAT Gateway**.
2. **Access Entries (Modern EKS Auth):** Se descartó el uso del antiguo ConfigMap `aws-auth` en favor de la API nativa de EKS (`access_config`), otorgando permisos `system:masters` automáticamente al rol aprovisionador.
3. **State Locking Nativo:** Se modernizó el backend de Terraform utilizando `use_lockfile = true` nativo de S3 (Terraform 1.10+), deprecando el uso de tablas DynamoDB para el bloqueo de concurrencia.
4. **CI/CD Seguro (OIDC):** GitHub asume un Rol temporal en AWS usando OpenID Connect (`sts:AssumeRoleWithWebIdentity`), eliminando el riesgo de fuga de credenciales (`AWS_ACCESS_KEY_ID`).

## Operación Básica

**1. Despliegue inicial (o tras cambios):**
```bash
cd environments/staging
terraform init
terraform plan
terraform apply
```

**2. Destrucción del Entorno (Ahorro de Costos):**
Dado que EKS y el NAT Gateway tienen costos fijos por hora, se recomienda destruir el entorno cuando no esté en uso.
```bash
cd environments/staging
terraform destroy
```
