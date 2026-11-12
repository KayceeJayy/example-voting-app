# base defines a base stage that uses the official python runtime base image
FROM python:3.11-slim@sha256:07d4824036af339fa1b6ef769cc99d9c10a141769538b52b3b597c84f7a7b535 AS base

# Add curl for healthcheck
RUN sed -i 's|http://deb.debian.org|https://deb.debian.org|g' \
    /etc/apt/sources.list.d/debian.sources && \
    apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

# Set the application directory
WORKDIR /usr/local/app

# Install our requirements.txt
COPY requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# dev defines a stage for development, where it'll watch for filesystem changes
FROM base AS dev
RUN pip install watchdog
ENV FLASK_ENV=development
CMD ["python", "app.py"]

# final defines the stage that will bundle the application for production
# ======================================================
# Hardened production stage: Python 3.11 / Alpine 3.23
# ======================================================

FROM public.ecr.aws/docker/library/python@sha256:3e6740f02c2a48bfcf675c39ae0f456153667d9d87c1e5bb2e13ff848dba307f AS final

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    HOME=/tmp

WORKDIR /usr/local/app

# Install the patched Kerberos library.
RUN apk add --no-cache --upgrade \
    'krb5-libs>=1.22.3-r0'

# Install application dependencies.
COPY requirements-prod.lock ./requirements-prod.lock

RUN python -m pip install --no-cache-dir --no-deps -r requirements-prod.lock && \
    python -m pip uninstall -y setuptools && \
    python -m pip check

# Copy source files with non-root ownership.
COPY --chown=10001:10001 . .

# Run the application without root privileges.
USER 10001:10001

EXPOSE 8080

CMD ["gunicorn", "app:app", "-b", "0.0.0.0:8080", "--log-file", "-", "--access-logfile", "-", "--workers", "4", "--keep-alive", "0"]
