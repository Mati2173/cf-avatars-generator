# Pipeline de Integración y Despliegue Continuo (CI/CD)

El proyecto utiliza GitHub Actions para automatizar el ciclo de vida del software, desde las pruebas y compilación hasta el despliegue directo en AWS EKS y la publicación en producción.

## Estructura de Workflows

La estrategia de CI/CD está dividida en tres workflows principales que acompañan la estrategia GitFlow:

### 1. CI (Integración Continua) - `ci.yml`
- **Cuándo se ejecuta:** En cada Push o Pull Request hacia la rama `develop`.
- **Objetivo:** Validación rápida y temprana (Shift-Left).
- **Pasos principales:**
  - Ejecuta tests unitarios (Backend y Frontend).
  - Escanea vulnerabilidades usando Trivy.
  - Compila y empaqueta las imágenes Docker.
  - Verifica que los manifiestos de Kubernetes se rendericen correctamente mediante Kustomize.

### 2. CD (Despliegue Continuo) - `cd.yml`
- **Cuándo se ejecuta:** En cada Push hacia la rama `staging`.
- **Objetivo:** Despliegue automático y validación final en un entorno vivo.
- **Autenticación "Passwordless" (OIDC):** El pipeline asume un rol de IAM en AWS utilizando *OpenID Connect*. Esto erradica la necesidad de almacenar credenciales de AWS de larga vida útil (`AWS_ACCESS_KEY_ID`) en los Secretos de GitHub.
- **Estrategia:** 
  1. Compila imágenes Docker y las publica temporalmente en GitHub Container Registry (GHCR) etiquetadas con el SHA del commit.
  2. Autentica contra EKS.
  3. Modifica los manifiestos localmente con `kustomize edit set image` apuntando a las nuevas imágenes.
  4. Ejecuta `kubectl apply -k k8s/overlays/staging` para desplegar.
  5. Realiza un *smoke test* contra el balanceador de carga público.

### 3. Release (Producción) - `release.yml`
- **Cuándo se ejecuta:** Al pushear un Tag Semántico (ej. `v1.2.3`).
- **Objetivo:** Generar un release inmutable para producción.
- **Estrategia:**
  - Re-empaqueta las imágenes Docker y las publica en GHCR etiquetadas explícitamente con `latest` y con el número de versión (ej. `v1.2.3`).
  - No realiza despliegue a infraestructura (ver sección de entornos en el README principal), sino que prepara el artefacto final listo para ser consumido por un entorno productivo.

## Configuración Requerida
Para que el CD Pipeline de Staging funcione, es estrictamente necesario:
1. Haber aprovisionado la infraestructura base con Terraform, incluyendo el módulo OIDC de GitHub.
2. Configurar la variable `AWS_ROLE_ARN` en el archivo `cd.yml` con el ARN resultante del módulo Terraform.
3. El Repositorio debe tener configurados permisos de escritura de paquetes para GHCR.
