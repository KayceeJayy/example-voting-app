FROM node:18-slim@sha256:f9ab18e354e6855ae56ef2b290dd225c1e51a564f87584b9bd21dd651838830e AS dev

# Bootstrap CA trust before HTTPS package downloads
COPY --from=python:3.11-slim@sha256:07d4824036af339fa1b6ef769cc99d9c10a141769538b52b3b597c84f7a7b535 /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

# add curl for healthcheck
RUN sed -i 's|http://deb.debian.org|https://deb.debian.org|g' \
    /etc/apt/sources.list.d/debian.sources && \
    apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl tini && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /usr/local/app

# have nodemon available for local dev use (file watching)
RUN npm install -g nodemon

COPY package*.json ./

RUN npm ci && \
 npm cache clean --force && \
 mv /usr/local/app/node_modules /node_modules

COPY . .

ENV PORT=80
EXPOSE 80

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "server.js"]


# =====================================================
# PRODUCTION STAGE
# =====================================================

# ======================================================
# Production dependencies: Node.js 24 / Alpine 3.23
# ======================================================
FROM public.ecr.aws/docker/library/node@sha256:3946fb783fdce8a2812136ea694bc95c698c4f4096f3fd18568dc27a8ac389dc AS production-deps

ENV NODE_ENV=production

WORKDIR /usr/local/app

COPY package*.json ./

RUN npm ci --omit=dev

# ======================================================
# Minimal production runtime: Alpine 3.23
# ======================================================
FROM public.ecr.aws/docker/library/alpine@sha256:469c9ea410b9215eaee7976ba6c0639039b444be8e5d638f7abbada189971eb2 AS final

RUN apk add --no-cache libstdc++ ca-certificates

ENV NODE_ENV=production \
    PORT=8080 \
    HOME=/tmp

WORKDIR /usr/local/app

# Include Node.js, but exclude npm and Yarn.
COPY --from=production-deps /usr/local/bin/node /usr/local/bin/node

# Copy production dependencies and application files.
COPY --from=production-deps --chown=10001:10001 /usr/local/app/node_modules ./node_modules

COPY --chown=10001:10001 . .

USER 10001:10001

EXPOSE 8080

CMD ["node", "server.js"]
