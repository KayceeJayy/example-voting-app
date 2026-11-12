FROM node:18-slim

# Bootstrap CA trust before HTTPS package downloads
COPY --from=python:3.11-slim /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

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
