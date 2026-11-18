# syntax=docker/dockerfile:1.7
# Multi-stage build: dependencies are compiled in "builder", the runtime image only
# carries the virtualenv + app code and runs as an unprivileged user.

# Base image pinned by digest (python:3.13-slim-trixie); bump tag + digest together.
FROM python:3.13-slim-trixie@sha256:e48f59cdba69a3cbd9ed2cf0f348d90d45a8d350d98134cf1070bc106ee9ed90 AS builder
ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-compile -r requirements.txt

FROM python:3.13-slim-trixie@sha256:e48f59cdba69a3cbd9ed2cf0f348d90d45a8d350d98134cf1070bc106ee9ed90 AS runtime
ARG APP_VERSION=0.0.0-dev
ARG GIT_SHA=unknown
LABEL org.opencontainers.image.title="release-ledger" \
      org.opencontainers.image.description="Django release ledger for ECS Fargate" \
      org.opencontainers.image.source="https://github.com/shubhamkhedkar/django-ecs-fargate-delivery-platform" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.licenses="MIT"
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/opt/venv/bin:${PATH}" \
    PORT=8000 \
    APP_VERSION=${APP_VERSION} \
    GIT_SHA=${GIT_SHA}

RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --no-create-home \
       --home-dir /nonexistent --shell /usr/sbin/nologin app

WORKDIR /srv/app
COPY --from=builder /opt/venv /opt/venv
# Code stays root-owned and read-only for the app user.
COPY app/ ./
RUN DJANGO_ALLOW_INSECURE_KEY=1 python manage.py collectstatic --noinput \
    && python -m compileall -q /srv/app /opt/venv

USER 10001:10001
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD ["python", "/srv/app/healthcheck.py"]
CMD ["gunicorn", "--config", "/srv/app/gunicorn.conf.py", "config.wsgi:application"]
