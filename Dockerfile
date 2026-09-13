# ==============================================================================
# STAGE 1: BUILDER
# ==============================================================================
FROM node:22-alpine AS builder

WORKDIR /app
COPY package*.json ./

RUN npm ci

# ==============================================================================
# STAGE 2: RUNTIME
# ==============================================================================
FROM node:22-alpine

WORKDIR /app
ENV NODE_ENV=production
USER node
COPY --from=builder --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node . .

EXPOSE 3000
CMD ["node", "src/server.js"]
