# Infraestructura como Código (Terraform)

Este directorio contiene toda la infraestructura fundacional del proyecto desplegada en AWS. Todo el código sigue prácticas profesionales orientadas a la mantenibilidad y seguridad.

## Estructura de Directorios

- `bootstrap/`: Contiene los recursos "huevo y gallina". Inicializa el bucket S3 para el almacenamiento remoto del estado (Remote State) con encriptación AES-256 y versionamiento habilitado.
- `modules/`: Contiene módulos reutilizables de infraestructura.
  - `vpc`: Crea la red privada, subredes públicas y privadas usando `for_each`, un Internet Gateway y un NAT Gateway.
  - `eks`: Aprovisiona el clúster de Kubernetes, Roles de IAM separados (Control Plane y Workers) y configura los Access Entries modernos. Instala el Add-on `aws-ebs-csi-driver` utilizando IRSA para el almacenamiento persistente seguro.
  - `github-oidc`: Crea el Identity Provider OIDC para permitir despliegues desde GitHub Actions sin secretos estáticos.
- `environments/staging/`: Consume los módulos anteriores para armar el entorno final de "Staging". Guarda su estado remotamente en el bucket S3 aprovisionado por `bootstrap`.

## Decisiones Arquitectónicas Críticas

1. **Aislamiento de Workers:** Los nodos EC2 (Data Plane) de Kubernetes se aprovisionan **exclusivamente en subredes privadas**. No tienen IP pública. Todo el tráfico saliente pasa por el **NAT Gateway**.
2. **Access Entries (Modern EKS Auth):** Se descartó el uso del antiguo ConfigMap `aws-auth` en favor de la API nativa de EKS (`access_config`), otorgando permisos automáticamente al rol de CI/CD.
3. **State Locking Nativo:** Se modernizó el backend de Terraform utilizando `use_lockfile = true` nativo de S3 (Terraform 1.15+), deprecando el uso de tablas DynamoDB para el bloqueo de concurrencia.
4. **CI/CD Seguro (OIDC):** GitHub asume un Rol temporal en AWS usando OpenID Connect (`sts:AssumeRoleWithWebIdentity`), eliminando el riesgo de fuga de credenciales.
5. **Persistencia con EBS CSI Driver:** El almacenamiento persistente (PVC) es delegado nativamente a discos AWS EBS mediante el aprovisionamiento del add-on EBS CSI Driver.
6. **Seguridad en CSI Driver (IRSA):** Para el CSI Driver de EBS, se usa *IAM Roles for Service Accounts (IRSA)* para esquivar las duras restricciones de red de AWS (como IMDSv2 con Hop Limit=1), garantizando que el pod de almacenamiento solo posea acceso granulado a los discos necesarios.
