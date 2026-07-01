# --- Build ---
FROM node:22-alpine AS build

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci

COPY . .
RUN npm run build

# --- Test ---
FROM build AS test
ENTRYPOINT ["npm"]
CMD ["test"]

# --- Production ---
# Utilizamos la imagen unprivileged oficial de Nginx para correr sin acceso root
FROM nginxinc/nginx-unprivileged:alpine

# Copiar build estático
COPY --from=build /app/dist /usr/share/nginx/html

# Configuración de nginx con proxy reverso al API
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Exponemos el puerto 8080, ya que los puertos < 1024 requieren root
EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/health || exit 1

CMD ["nginx", "-g", "daemon off;"]
