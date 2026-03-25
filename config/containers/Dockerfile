FROM python:3.13-slim-bookworm

ARG HONCHO_REPO_URL=https://github.com/plastic-labs/honcho.git
ARG HONCHO_REF=latest-release

LABEL honcho.repo_url=$HONCHO_REPO_URL
LABEL honcho.ref=$HONCHO_REF

COPY --from=ghcr.io/astral-sh/uv:0.9.24 /uv /bin/uv

WORKDIR /app

ENV UV_COMPILE_BYTECODE=1
ENV UV_LINK_MODE=copy
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PATH="/app/.venv/bin:$PATH"
ENV HOME=/app
ENV UV_CACHE_DIR=/tmp/uv-cache

RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates build-essential \
  && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "$HONCHO_REF" "$HONCHO_REPO_URL" /app

RUN --mount=type=cache,target=/root/.cache/uv \
  uv sync --frozen --no-group dev

RUN addgroup --system app \
  && adduser --system --group app \
  && mkdir -p /tmp/uv-cache \
  && chown -R app:app /app /tmp/uv-cache

USER app

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=5 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/openapi.json')" || exit 1

CMD ["fastapi", "run", "--host", "0.0.0.0", "src/main.py"]
