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

FROM public.ecr.aws/docker/library/node@sha256:dc26ae92c9fb15cf6b1d63e20f0944b2efe0f115b20e00be48fb23fceb061c54 AS final

ENV NODE_ENV=production \
    PORT=8080

WORKDIR /usr/local/app

# Install production dependencies only.
COPY package*.json ./

RUN npm ci --omit=dev && \
    npm cache clean --force

# Copy application files with non-root ownership.
COPY --chown=node:node . .

# Run the application as a non-root user.
USER node

EXPOSE 8080

CMD ["node", "server.js"]
