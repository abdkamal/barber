# Saloni API server — production image (trial deployment).
# Build context: the REPOSITORY ROOT (npm workspaces: packages/engine + server).
#   docker build -f deploy/Dockerfile -t saloni-server .
# Ignore rules: deploy/Dockerfile.dockerignore (BuildKit reads it for this Dockerfile).

ARG NODE_IMAGE=node:22-bookworm-slim

# ---- 1. build: all deps, compile engine + server ---------------------------------
FROM ${NODE_IMAGE} AS build
WORKDIR /src
COPY package.json package-lock.json ./
COPY packages/engine/package.json packages/engine/
COPY server/package.json server/
RUN npm ci --no-audit --no-fund
COPY packages/engine packages/engine
COPY server server
# `build` runs `prebuild` (engine) first.
RUN npm run build -w @saloni/server

# ---- 2. prod-deps: production dependencies only ----------------------------------
FROM ${NODE_IMAGE} AS prod-deps
WORKDIR /app
COPY package.json package-lock.json ./
COPY packages/engine/package.json packages/engine/
COPY server/package.json server/
RUN npm ci --omit=dev --no-audit --no-fund && npm cache clean --force

# ---- 3. runtime ------------------------------------------------------------------
FROM ${NODE_IMAGE} AS runtime
ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=3000 \
    STORAGE_DIR=/data/storage
WORKDIR /app
COPY --from=prod-deps --chown=root:root /app/node_modules ./node_modules
COPY --from=prod-deps /app/package.json ./package.json
COPY --from=build /src/packages/engine/package.json ./packages/engine/package.json
COPY --from=build /src/packages/engine/dist ./packages/engine/dist
COPY --from=build /src/server/package.json ./server/package.json
COPY --from=build /src/server/dist ./server/dist
# Migrations are read at runtime from server/migrations (dist/db/migrator.js → ../../migrations).
COPY --from=build /src/server/migrations ./server/migrations
COPY deploy/docker-entrypoint.sh /usr/local/bin/saloni-entrypoint
RUN chmod 0755 /usr/local/bin/saloni-entrypoint \
 && mkdir -p /data/storage && chown -R node:node /data
# Non-root: the `node` user (uid 1000) from the base image.
USER node
WORKDIR /app/server
EXPOSE 3000
HEALTHCHECK --interval=10s --timeout=5s --start-period=40s --retries=5 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||3000)+'/v1/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
ENTRYPOINT ["saloni-entrypoint"]
CMD ["serve"]
