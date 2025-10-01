# ═══════════════════════════════════════════════════════════════════
# SIMPLIFIED DOCKERFILE - FIXED
# ═══════════════════════════════════════════════════════════════════

# STAGE 1: BUILDER
FROM node:18-alpine AS builder

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install --production && npm cache clean --force

# STAGE 2: PRODUCTION
FROM node:18-alpine

WORKDIR /app

# Copy dependencies from builder
COPY --from=builder /app/node_modules ./node_modules

# Copy application code
COPY app-with-monitoring.js ./
COPY package.json ./

# Create app user with dynamic ID (avoids conflicts)
RUN addgroup -g 1001 appuser && \
    adduser -S -u 1001 -G appuser appuser && \
    chown -R appuser:appuser /app

USER appuser

EXPOSE 3000

# Simple health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

ENV NODE_ENV=production \
    PORT=3000

CMD ["node", "app-with-monitoring.js"]