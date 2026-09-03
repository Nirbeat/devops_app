# Login App — Node + Express + MongoDB (Docker + CI/CD)

Proyecto mínimo de autenticación (register, login, profile) construido para enseñar
**Docker**, **Docker Compose** y **CI/CD** con GitHub Actions (deploy manual a una VM local).

## Stack

| Capa        | Tecnología                        |
|-------------|-----------------------------------|
| Runtime     | Node.js 22 (ES modules)           |
| Framework   | Express                           |
| Base datos  | MongoDB 7 + Mongoose              |
| Autentic.   | JWT + bcrypt                      |
| Validación  | express-validator                 |
| Tests       | Mocha + Chai + Supertest          |
| CI/CD       | GitHub Actions → GHCR (deploy manual) |

## Endpoints

| Método | Ruta                  | JWT | Descripción                     |
|--------|-----------------------|-----|--------------------------------|
| POST   | `/api/auth/register`  | no  | Registro → 201                 |
| POST   | `/api/auth/login`     | no  | Login → 200 `{ token }`        |
| GET    | `/api/auth/profile`   | sí  | Perfil del usuario → 200       |
| GET    | `/health`             | no  | Healthcheck                    |

## Estructura

```
devops/
├── src/
│   ├── config/           # env.js, db.js
│   ├── controllers/      # authController.js
│   ├── middlewares/      # auth.js (JWT), validate.js
│   ├── models/           # User.js
│   ├── routes/           # authRoutes.js
│   ├── app.js            # app express (exportable, sin listen)
│   └── server.js         # entrypoint (DB + listen)
├── tests/
│   ├── unit/             # pruebas puras (bcrypt, JWT)
│   └── integration/      # API real contra MongoDB (supertest)
├── .github/workflows/    # ci-cd.yml
├── Dockerfile            # multi-stage, usuario no-root
├── docker-compose.yml
├── .env.example
└── .mocharc.json
```

## Requisitos previos

- Node.js ≥ 22
- Docker Desktop (con engine Linux)
- MongoDB local **o** el `mongo` del compose (para tests de integración)
- (Opcional) cuenta GitHub

## Configuración

Copiar `.env.example` a `.env` y ajustar:

```bash
cp .env.example .env
```

## Correr localmente (sin Docker)

```bash
npm install
npm run dev        # desarrollo (Node 22 --watch)
npm start          # producción
```

## Tests

```bash
npm run test:unit         # tests puros (sin DB)
npm run test:integration  # API contra Mongo real (MONGO_URI_TEST)
npm test                  # suite completa
```

> Los tests de integración limpian la base de datos al final de la suite (`after()` en
> `tests/integration/authApi.test.js`). Necesitan `MONGO_URI_TEST` apuntando a un Mongo real.

---

## Sección de clase: Docker

### Dockerfile (multi-stage + no-root)

```dockerfile
# Stage 1: builder — instala dependencias
FROM node:22-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci

# Stage 2: runtime — imagen final liviana
FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production
USER node                            # usuario no-root
COPY --from=builder --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node . .
EXPOSE 3000
CMD ["node", "src/server.js"]
```

**Puntos a explicar:**
1. **Multi-stage**: `builder` corre `npm ci`, `runtime` solo copia lo necesario → imagen más pequeña y segura.
2. **No-root**: `USER node` (el usuario `node` ya existe en las imágenes oficiales) + `--chown` para ownership de archivos.
3. **`.dockerignore`**: excluye `node_modules` y `.env` del contexto de build.

### Docker Compose

```yaml
services:
  app:
    build: .
    ports: ["3000:3000"]
    env_file: .env
    environment:
      - MONGO_URI=mongodb://mongo:27017/login
    depends_on:
      - mongo
    restart: unless-stopped
  mongo:
    image: mongo:7
    volumes:
      - mongo-data:/data/db
    restart: unless-stopped
volumes:
  mongo-data:
```

**Puntos a explicar:**
- Dos servicios (`app`, `mongo`) en una **red** por defecto → `app` alcanza a `mongo` por nombre de servicio.
- **Volumen** `mongo-data` persiste los datos aunque el contenedor se borre.
- `depends_on` define orden de arranque.

### Comandos de demo

```bash
docker compose build                 # construye imágenes
docker compose up -d                 # levanta app + mongo en background
docker compose ps                    # estado de los servicios
docker compose logs -f app           # logs en vivo
curl http://localhost:3000/health
docker compose down -v               # detiene y borra todo (incl. volumen)
```

---

## Sección de clase: CI/CD (GitHub Actions)

El pipeline hace **test + build + push** a **GHCR** (GitHub Container Registry).
El **deploy es manual** en la VM: GitHub produce el artefacto, tú lo despliegas a mano.

### Workflow `ci-cd.yml`

| Job          | Trigger             | Qué hace                                                        |
|--------------|---------------------|-----------------------------------------------------------------|
| `test`       | push / PR           | Corre la suite (unit + integración) contra un `service: mongo` |
| `build-and-push` | push a `main` (tras test OK) | Construye con buildx y publica en `ghcr.io/<repo>:latest` |

### Deploy manual a tu VM local

Una vez publicado, en la VM:

```bash
# 1. Autenticarse contra GHCR
echo $GHCR_TOKEN | docker login ghcr.io -u <usuario> --password-stdin

# 2. Configurar compose para usar la imagen publicada
#    (la imagen ya se llama ghcr.io/...:latest en docker-compose.yml)

# 3. Descargar y levantar
docker compose pull
docker compose up -d
```

> GitHub Actions **no puede** acceder a una VM local sin IP pública / túnel / self-hosted runner.
> Por eso este flujo usa GHCR como registro intermedio y deja el despliegue en tus manos.

### Secretos necesarios en GitHub

- Ninguno para test/build/push (usa el `GITHUB_TOKEN` automático).
- Para subir manualmente a tu VM: solo tu credencial/`docker login` de GHCR.

---

## Guion sugerido de la clase

1. **Conceptos**: contenedor vs imagen, capas, multi-stage.
2. **Dockerfile**: construir paso a paso y explicar `USER node`.
3. **Compose**: levantar el stack completo, mostrar volumen y red.
4. **Tests**: `npm test` → verde; explicar que CI los repite automáticamente.
5. **CI/CD**: push al repo → ver el workflow correr → imagen en GHCR.
6. **Deploy manual**: en la VM `docker compose pull && docker compose up -d`.
7. **Demo final**: `curl /health`, registrar, login, profile.

## Extensión opcional (mencionar en clase)

- **Rate limiting** (`express-rate-limit`): limita intentos de login para prevenir fuerza bruta.
- **Docker healthcheck** en el contenedor.
- **Docker secrets** en vez de `.env`.
- **Self-hosted runner** para deploy 100% automático a tu VM.
