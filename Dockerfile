# # ==============================================================================
# # DOCKERFILE - Imagen básica sin optimizar
# # ==============================================================================
# # Un Dockerfile es un "recetario" que le dice a Docker cómo construir una imagen.
# # Cada instrucción (FROM, COPY, RUN...) crea una CAPA que se puede reutilizar (cache).

# # FROM define la imagen base, siempre incluye ya una distro de Linux
# FROM node:22

# # WORKDIR crea y fija el directorio de trabajo dentro del contenedor.
# # Todas las instrucciones siguientes se ejecutan en /app.
# WORKDIR /app

# # COPY <origen> <destino> copia archivos del host (contexto de build) al contenedor.
# # Aquí copiamos SOLO package.json y package-lock.json ANTES del código fuente.
# # Esto es deliberado: como Docker cachea por capa, si solo cambia el código fuente,
# # la capa de "npm install" se reutiliza y el build es más rápido.
# COPY package*.json ./

# # RUN ejecuta un comando dentro del contenedor durante el build.
# # `npm ci` instala dependencias EXACTAS según package-lock.json
# # (mejor que `npm install` porque es reproducible y más rápido en CI).
# RUN npm ci

# # COPY <origen> <destino> copia todo el proyecto
# COPY . .

# # ENV define variables de entorno dentro del contenedor.
# # NODE_ENV=production desactiva mensajes de depuración y optimiza Express.
# # No es conveniente pasar variables sensibles en el Dockerfile, se pasan por CLI
# ENV NODE_ENV=production
# ENV PORT=3000
# ENV JWT_SECRET=cambia-este-secreto-en-produccion
# ENV JWT_EXPIRES_IN=1d
# # En caso que la DB este en la maquina host, usamos host.docker.internal
# ENV MONGO_URI=mongodb://host.docker.internal:27017/docker-app
# # En caso que la DB este en un contenedor, usamos el nombre del servicio
# # ENV MONGO_URI=mongodb://mongo:27017/docker-app

# # EXPOSE es SOLO documentación/informativo: declara que la app escucha en el
# # puerto 3000. NO publica el puerto (eso lo hace docker run -p o docker compose).
# # Es una "nota" hacia quien use/inspeccione la imagen.
# EXPOSE 3000

# # CMD define el comando que se ejecuta cuando el contenedor ARRANCA.
# # Formato JSON (array) = forma "exec", ejecuta node directamente sin shell.
# # Aquí arrancamos el servidor.
# # CMD ["node", "src/server.js"]

# # ==============================================================================
# # DOCKERFILE - Imagen básica más liviana
# # ==============================================================================

# # node:22-alpine es Node 22 sobre Alpine Linux,
# # una distribución mínima (~5MB) muy usada en contenedores por su tamaño.
# FROM node:22-alpine

# # WORKDIR crea y fija el directorio de trabajo dentro del contenedor.
# # Todas las instrucciones siguientes se ejecutan en /app.
# WORKDIR /app
# COPY package*.json ./
# RUN npm ci
# COPY . .
# # Pasamos por ENV solo ésta instrucción y las demás por CLI.
# ENV NODE_ENV=production

# EXPOSE 3000
# CMD ["node", "src/server.js"]


# ==============================================================================
# DOCKERFILE — Imagen totalmente optimizada
# ==============================================================================
# Usamos un build MULTI-STAGE (2 etapas): separamos la etapa de "construcción"
# de la etapa "de ejecución" para obtener una imagen final MUY liviana y segura.
# La primera etapa instala las dependencias; la segunda solo copia lo necesario.
# ==============================================================================

# ==============================================================================
# STAGE 1: BUILDER — construye/instala lo pesado
# ==============================================================================
# El bloque "AS builder" nombra la etapa para poder referenciarla después.
FROM node:22-alpine AS builder

WORKDIR /app
COPY package*.json ./

RUN npm ci

# ==============================================================================
# STAGE 2: RUNTIME — imagen final ligera que solo ejecuta la app
# ==============================================================================
# Empezamos de nuevo desde node:22-alpine. Esta imagen NO contiene node_modules
# ni el código ni los archivos de build del stage anterior (son capas separadas).
FROM node:22-alpine

WORKDIR /app
ENV NODE_ENV=production

# USER cambia el usuario con el que se ejecuta el proceso.
# Por buenas prácticas de seguridad, ejecutamos como usuario NO-ROOT.
# La imagen oficial ya incluye el usuario "node" (no hace falta crearlo).
USER node

# COPY --from=builder: copiamos solo node_modules desde el stage "builder".
# --chown=node:node asigna la propiedad de los archivos al usuario node
# (si no, el usuario no-root no podría leer/escribir sus propios archivos).
# Esto es fundamental para que el usuario no-root tenga permisos de escritura.
COPY --from=builder --chown=node:node /app/node_modules ./node_modules

# Copiamos el código fuente de nuestra app (src, tests, package.json...)
# también con ownership para el usuario node.
COPY --chown=node:node . .

EXPOSE 3000
CMD ["node", "src/server.js"]
