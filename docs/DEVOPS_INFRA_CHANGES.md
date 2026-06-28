# 🛠 DevOps Infrastructure Changes Log

Este documento registra ajustes técnicos realizados durante la evolución del entorno de infraestructura del proyecto, enfocados en estabilidad, aislamiento de servicios y reproducibilidad en entornos Docker.

---

## 1. Corrección de healthcheck en contenedor Nginx

### Problema

El contenedor `web` utilizaba un `HEALTHCHECK` basado en `wget` apuntando a:

```dockerfile
HEALTHCHECK CMD wget -qO- http://localhost/health || exit 1
```

Sin embargo, el healthcheck fallaba constantemente aun cuando el servicio Nginx estaba funcionando correctamente dentro del contenedor.

El error observado era:

```bash
# wget -qO- http://localhost/health
wget: can't connect to remote host: Connection refused
```

Esto provocaba falsos estados `unhealthy`

---

### Causa raíz

Dentro del contenedor Alpine utilizado por Nginx, la resolución de `localhost` no siempre apuntaba correctamente al loopback IPv4 esperado por `wget`.

En ciertos entornos Docker/Alpine, `localhost` podía resolverse hacia IPv6 (`::1`) o generar inconsistencias internas de resolución, causando que el healthcheck intentara conectarse a una interfaz distinta de la utilizada por Nginx.

Como resultado, el contenedor respondía correctamente en IPv4, pero el healthcheck seguía fallando.

---

### Solución aplicada

Se reemplazó `localhost` por la dirección explícita IPv4 `127.0.0.1` en el `HEALTHCHECK` del Dockerfile:

```dockerfile
HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1/health || exit 1
```

---

### Impacto

* healthchecks estables y determinísticos
* eliminación de falsos negativos
* arranque más confiable del frontend
* mayor compatibilidad entre entornos Linux y Docker

---

### Resultado

El contenedor `web` ahora reporta correctamente su estado de salud, permitiendo que Docker Compose gestione las dependencias entre servicios de forma confiable y alineada con buenas prácticas de contenedorización.