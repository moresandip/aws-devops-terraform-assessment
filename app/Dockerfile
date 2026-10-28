FROM node:20-alpine AS builder

WORKDIR /app

# Install dependencies first (layer caching)
COPY package*.json ./
RUN npm ci --omit=dev

# Copy application source
COPY src/ ./src/

# ── Production stage ─────────────────────────────────────────────────────────
FROM node:20-alpine

# Create non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Copy from builder
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/src          ./src
COPY package.json                     ./

# Create log directories with correct permissions
RUN mkdir -p /var/log/app && chown -R appuser:appgroup /var/log/app /app

USER appuser

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget -qO- http://localhost:80/health || exit 1

CMD ["node", "src/server.js"]
