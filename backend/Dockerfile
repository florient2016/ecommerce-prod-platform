# ─────────────────────────────────────────────────────
# Stage 1: Dependencies
# ─────────────────────────────────────────────────────
FROM node:20-alpine AS deps
WORKDIR /app
COPY package*.json ./
COPY prisma ./prisma/
RUN npm ci --only=production && \
    npm install -g prisma && \
    npx prisma generate

# ─────────────────────────────────────────────────────
# Stage 2: Build
# ─────────────────────────────────────────────────────
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# ─────────────────────────────────────────────────────
# Stage 3: Production image
# ─────────────────────────────────────────────────────
FROM node:20-alpine AS production

# Security: non-root user (UID 1001 compatible OpenShift arbitrary UID)
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nestjs -u 1001 -G nodejs

WORKDIR /app

# Copy production dependencies
COPY --from=deps --chown=1001:1001 /app/node_modules ./node_modules
COPY --from=deps --chown=1001:1001 /app/prisma ./prisma

# Copy built application
COPY --from=builder --chown=1001:1001 /app/dist ./dist
COPY --from=builder --chown=1001:1001 /app/package.json ./

# OpenShift: grant write permissions on workdir for arbitrary UID
RUN chmod -R g+rwX /app && \
    chown -R 1001:0 /app

# Non-root
USER 1001

ENV NODE_ENV=production \
    PORT=3000

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

# Run migrations then start
CMD ["sh", "-c", "npx prisma migrate deploy && node dist/main"]
