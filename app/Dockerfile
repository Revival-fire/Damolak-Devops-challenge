# ─── Stage 1: Dependencies ───────────────────────────────────────────────────
FROM node:20-alpine AS deps

WORKDIR /app

# Copy only manifests first (better layer caching)
COPY package*.json ./

# Install only production deps; audit for known vulnerabilities
RUN npm ci --only=production --audit && \
    npm cache clean --force


# ─── Stage 2: Builder / Test ─────────────────────────────────────────────────
FROM node:20-alpine AS builder

WORKDIR /app

COPY package*.json ./
# Install ALL deps (including devDependencies) for testing
RUN npm ci

COPY src/ ./src/

# Run tests inside build stage so a test failure kills the image build
RUN npm test


# ─── Stage 3: Production image ───────────────────────────────────────────────
FROM node:20-alpine AS production

# Security hardening
RUN apk add --no-cache dumb-init && \
    addgroup -g 1001 -S nodejs && \
    adduser  -S nodeapp -u 1001 -G nodejs

WORKDIR /app

# Copy production node_modules from deps stage (no dev deps in final image)
COPY --from=deps  --chown=nodeapp:nodejs /app/node_modules ./node_modules
# Copy application source
COPY --from=builder --chown=nodeapp:nodejs /app/src ./src
COPY --chown=nodeapp:nodejs package.json ./

# Drop to non-root user
USER nodeapp

# Expose application port
EXPOSE 3000

# Health check for container runtimes (ECS, Docker Compose, etc.)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

# Use dumb-init to properly handle PID 1 and signal forwarding
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "src/index.js"]
