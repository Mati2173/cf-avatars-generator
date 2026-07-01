# --- Builder ---
FROM python:3.12-slim AS builder

WORKDIR /src

# Crear virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Instalar dependencias Python
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copiar el código fuente
COPY . .

# Pre-instalar SVGs custom en el paquete python_avatars durante el build
RUN python install_parts.py

# --- Test ---
FROM builder AS test
# Variables para evitar pyc y buffering en tests
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/src
COPY requirements-test.txt .
RUN pip install --no-cache-dir -r requirements-test.txt
# El código fuente ya fue copiado en el builder
ENTRYPOINT ["pytest"]
CMD ["tests/", "-v"]

# --- Production ---
FROM python:3.12-slim

WORKDIR /src

# Variables óptimas de entorno para Python
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/opt/venv/bin:$PATH"

# Dependencias del sistema
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

# Copiar el venv desde el builder
COPY --from=builder /opt/venv /opt/venv

# Crear directorio de datos y usuario no-root
RUN useradd --create-home appuser && \
    mkdir -p /data && \
    chown appuser:appuser /data

# Copiar el código de la aplicación con los permisos correctos
COPY --chown=appuser:appuser . .

# Usar el usuario sin privilegios
USER appuser

EXPOSE 5000

HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD curl -f http://localhost:5000/ready || exit 1

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--access-logfile", "-", "app:app"]
