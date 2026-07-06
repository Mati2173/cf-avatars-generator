# Pipeline de Integración y Despliegue Continuo (CI/CD)

El proyecto utiliza GitHub Actions para automatizar el ciclo de vida del software, desde las pruebas y compilación hasta el despliegue directo en AWS EKS.

## CI (Integración Continua)
Definido en `ci.yml` y `release.yml`.
- Se ejecuta en cada Push o Pull Request hacia `develop`.
- **Estrategia:** Compila el código fuente y empaqueta los microservicios en imágenes Docker (optimizadas y "rootless"). Las imágenes finales se empujan hacia el GitHub Container Registry (`ghcr.io`).

## CD (Despliegue Continuo)
Definido en `cd.yml`.
- Se ejecuta en cada Push hacia la rama `staging` o mediante gatillo manual (`workflow_dispatch`).
- **Autenticación "Passwordless" (OIDC):** El pipeline asume un rol de IAM en AWS utilizando *OpenID Connect*. Esto erradica la necesidad de almacenar credenciales de AWS de larga vida útil (`AWS_ACCESS_KEY_ID`) en los Secretos de GitHub, una de las mayores vulnerabilidades en pipelines tradicionales.
- **Estrategia:** El pipeline se autentica, actualiza su `kubeconfig` conectándose al Control Plane de EKS y finalmente ejecuta `kubectl apply -k k8s/overlays/staging` para reconciliar el estado declarativo.

## Configuración Requerida
Para que el CD Pipeline funcione, es necesario que la infraestructura OIDC haya sido aprovisionada previamente mediante Terraform y que el output del ARN del Rol sea inyectado en la variable de entorno `AWS_ROLE_ARN` del archivo `cd.yml`.
