FROM python:3.13-slim-bookworm

ARG HONCHO_REPO_URL=https://github.com/plastic-labs/honcho.git
ARG HONCHO_REF=latest-release
ARG HONCHO_WRAPPER_FINGERPRINT=

LABEL honcho.repo_url=$HONCHO_REPO_URL
LABEL honcho.ref=$HONCHO_REF
LABEL honcho.wrapper_fingerprint=$HONCHO_WRAPPER_FINGERPRINT

COPY --from=ghcr.io/astral-sh/uv:0.9.24 /uv /bin/uv

WORKDIR /app

ENV UV_COMPILE_BYTECODE=1
ENV UV_LINK_MODE=copy
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PATH="/app/.venv/bin:$PATH"
ENV HOME=/app
ENV UV_CACHE_DIR=/tmp/uv-cache
ENV UV_HTTP_TIMEOUT=120
ENV UV_HTTP_RETRIES=5

RUN set -eux; \
  for attempt in 1 2 3; do \
    apt-get update \
      && apt-get install -y --no-install-recommends git ca-certificates build-essential \
      && break; \
    if [ "$attempt" -eq 3 ]; then \
      exit 1; \
    fi; \
    rm -rf /var/lib/apt/lists/*; \
    sleep 5; \
  done; \
  rm -rf /var/lib/apt/lists/*

RUN set -eux; \
  git init /app; \
  git -C /app remote add origin "$HONCHO_REPO_URL"; \
  git -C /app fetch --depth 1 origin "$HONCHO_REF"; \
  git -C /app checkout --detach FETCH_HEAD

RUN --mount=type=cache,target=/root/.cache/uv \
  set -eux; \
  for attempt in 1 2 3; do \
    uv sync --frozen --no-group dev && break; \
    if [ "$attempt" -eq 3 ]; then \
      exit 1; \
    fi; \
    sleep 5; \
  done

RUN addgroup --system app \
  && adduser --system --group app \
  && mkdir -p /tmp/uv-cache \
  && chown -R app:app /app /tmp/uv-cache

USER app

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=5 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/openapi.json')" || exit 1

CMD ["fastapi", "run", "--host", "0.0.0.0", "src/main.py"]
