#!/usr/bin/env bash
set -euo pipefail

HONCHO_BASE_ROOT="${HONCHO_BASE_ROOT:-$HOME/Documents/Ezirius/.applications-data/Honcho}"
HONCHO_IMAGE_NAME="${HONCHO_IMAGE_NAME:-honcho-local}"
HONCHO_PROJECT_PREFIX="${HONCHO_PROJECT_PREFIX:-honcho}"
HONCHO_REPO_URL="${HONCHO_REPO_URL:-https://github.com/plastic-labs/honcho.git}"
HONCHO_REF="${HONCHO_REF:-latest-release}"
HONCHO_GITHUB_API_BASE="${HONCHO_GITHUB_API_BASE:-https://api.github.com}"
HONCHO_API_HOST_PORT="${HONCHO_API_HOST_PORT:-8000}"
HONCHO_DB_HOST_PORT="${HONCHO_DB_HOST_PORT:-}"
HONCHO_REDIS_HOST_PORT="${HONCHO_REDIS_HOST_PORT:-}"
HONCHO_REMOVE_VOLUMES="${HONCHO_REMOVE_VOLUMES:-0}"

fail() {
  echo "Error: $*" >&2
  exit 1
}

usage_error() {
  echo "Usage: $1" >&2
  exit 1
}

repo_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$script_dir/../.." && pwd
}

require_podman() {
  command -v podman >/dev/null 2>&1 || fail "podman is not installed or not on PATH"
}

require_podman_compose() {
  podman compose version >/dev/null 2>&1 || fail "podman compose is required"
}

image_exists() {
  podman image exists "$HONCHO_IMAGE_NAME"
}

image_label() {
  local key="$1"
  local value

  value="$(podman image inspect -f "{{ index .Labels \"$key\" }}" "$HONCHO_IMAGE_NAME" 2>/dev/null || true)"
  if [[ "$value" == "<no value>" ]]; then
    value=""
  fi
  printf '%s' "$value"
}

require_python3() {
  command -v python3 >/dev/null 2>&1 || fail "python3 is required"
}

github_repo_slug() {
  local repo_url="$1"

  case "$repo_url" in
    https://github.com/*)
      repo_url="${repo_url#https://github.com/}"
      ;;
    http://github.com/*)
      repo_url="${repo_url#http://github.com/}"
      ;;
    git@github.com:*)
      repo_url="${repo_url#git@github.com:}"
      ;;
    *)
      fail "HONCHO_REF=latest-release requires a GitHub repo URL; set HONCHO_REF explicitly for non-GitHub sources"
      ;;
  esac

  repo_url="${repo_url%.git}"
  [[ "$repo_url" = */* ]] || fail "could not derive owner/repo from HONCHO_REPO_URL: $1"
  printf '%s' "$repo_url"
}

resolve_honcho_ref() {
  local requested_ref="${HONCHO_REF:-latest-release}"
  local repo_slug

  if [[ "$requested_ref" != "latest-release" ]]; then
    printf '%s' "$requested_ref"
    return 0
  fi

  require_python3
  repo_slug="$(github_repo_slug "$HONCHO_REPO_URL")"

  HONCHO_REPO_SLUG="$repo_slug" python3 - <<'PY'
import json
import os
import sys
import urllib.error
import urllib.request

base = os.environ.get("HONCHO_GITHUB_API_BASE", "https://api.github.com").rstrip("/")
repo_slug = os.environ["HONCHO_REPO_SLUG"].strip("/")
latest_url = f"{base}/repos/{repo_slug}/releases/latest"
headers = {
    "Accept": "application/vnd.github+json",
    "User-Agent": "honcho-container/1.0",
}

def fetch_json(url):
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=20) as response:
        return json.load(response)

try:
    latest = fetch_json(latest_url)
    tag_name = latest.get("tag_name", "")
    if tag_name:
        print(tag_name)
        sys.exit(0)
except urllib.error.HTTPError as exc:
    if exc.code == 404:
        raise SystemExit("Latest upstream Honcho release not found")
    raise SystemExit(f"failed to resolve latest upstream Honcho release: HTTP {exc.code}")
except urllib.error.URLError as exc:
    raise SystemExit(f"failed to resolve latest upstream Honcho release: {exc.reason}")

raise SystemExit("Latest upstream Honcho release did not include a tag name")
PY
}

require_workspace_root() {
  [[ -n "$HONCHO_BASE_ROOT" ]] || fail "HONCHO_BASE_ROOT is empty"
}

require_workspace_name() {
  local name="$1"

  [[ "$name" != */* ]] || fail "workspace name must not contain path separators: $name"
  [[ "$name" != "." ]] || fail "workspace name must not be '.'"
  [[ "$name" != ".." ]] || fail "workspace name must not be '..'"
}

sanitize_name() {
  local raw="$1"

  printf '%s' "$raw" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9_.-]+/-/g; s/^-+//; s/-+$//'
}

normalize_path() {
  local raw="$1"

  while [[ "$raw" != "/" && "$raw" = */ ]]; do
    raw="${raw%/}"
  done

  printf '%s' "$raw"
}

expand_home_path() {
  local raw="$1"

  case "$raw" in
    '~')
      printf '%s' "$HOME"
      ;;
    '~/'*)
      printf '%s' "$HOME/${raw#\~/}"
      ;;
    *)
      printf '%s' "$raw"
      ;;
  esac
}

normalize_absolute_path() {
  local raw="$1"
  local segment
  local -a parts=()
  local -a normalized=()

  [[ "$raw" = /* ]] || fail "path must be absolute: $raw"

  raw="$(normalize_path "$raw")"
  IFS='/' read -r -a parts <<< "${raw#/}"

  for segment in "${parts[@]}"; do
    case "$segment" in
      ''|.) ;;
      ..)
        if ((${#normalized[@]} > 0)); then
          unset 'normalized[${#normalized[@]}-1]'
        fi
        ;;
      *)
        normalized+=("$segment")
        ;;
    esac
  done

  if ((${#normalized[@]} == 0)); then
    printf '/'
  else
    local joined=""
    local item
    for item in "${normalized[@]}"; do
      joined+="/$item"
    done
    printf '%s' "$joined"
  fi
}

hash_workspace_path() {
  local raw="$1"

  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$raw" | shasum -a 256 | cut -c1-12
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$raw" | sha256sum | cut -c1-12
  else
    fail "requires shasum or sha256sum to derive a unique project name"
  fi
}

resolve_workspace() {
  local input="${1:?workspace required}"
  local workspace_base_root

  input="$(normalize_path "$input")"
  WORKSPACE_INPUT="$input"

  require_workspace_root
  require_workspace_name "$input"
  WORKSPACE_NAME="$input"
  workspace_base_root="$(expand_home_path "$HONCHO_BASE_ROOT")"
  WORKSPACE_ROOT="$(normalize_absolute_path "$(normalize_path "$workspace_base_root")/$WORKSPACE_NAME")"

  SAFE_WORKSPACE_NAME="$(sanitize_name "$WORKSPACE_NAME")"
  [[ -n "$SAFE_WORKSPACE_NAME" ]] || fail "workspace name resolved to an empty project-safe name"

  HONCHO_ENV_FILE="$WORKSPACE_ROOT/.env"
  HONCHO_CONFIG_TOML="$WORKSPACE_ROOT/config.toml"
  DATA_POSTGRES_DIR="$WORKSPACE_ROOT/postgres-data"
  DATA_REDIS_DIR="$WORKSPACE_ROOT/redis-data"
  HONCHO_PROJECT_NAME="${HONCHO_PROJECT_PREFIX}-${SAFE_WORKSPACE_NAME}-$(hash_workspace_path "$WORKSPACE_ROOT")"

  export WORKSPACE_INPUT WORKSPACE_ROOT WORKSPACE_NAME SAFE_WORKSPACE_NAME
  export HONCHO_ENV_FILE HONCHO_CONFIG_TOML DATA_POSTGRES_DIR DATA_REDIS_DIR HONCHO_PROJECT_NAME
}

ensure_workspace_dirs() {
  mkdir -p "$WORKSPACE_ROOT" "$DATA_POSTGRES_DIR" "$DATA_REDIS_DIR"
}

load_env_file() {
  local env_file="$1"

  [[ -f "$env_file" ]] || fail "env file not found: $env_file"

  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a

  HONCHO_BASE_ROOT="${HONCHO_BASE_ROOT:-$HOME/Documents/Ezirius/.applications-data/Honcho}"
  HONCHO_IMAGE_NAME="${HONCHO_IMAGE_NAME:-honcho-local}"
  HONCHO_PROJECT_PREFIX="${HONCHO_PROJECT_PREFIX:-honcho}"
  HONCHO_REPO_URL="${HONCHO_REPO_URL:-https://github.com/plastic-labs/honcho.git}"
  HONCHO_REF="${HONCHO_REF:-latest-release}"
  HONCHO_GITHUB_API_BASE="${HONCHO_GITHUB_API_BASE:-https://api.github.com}"
  HONCHO_API_HOST_PORT="${HONCHO_API_HOST_PORT:-8000}"
  HONCHO_DB_HOST_PORT="${HONCHO_DB_HOST_PORT:-}"
  HONCHO_REDIS_HOST_PORT="${HONCHO_REDIS_HOST_PORT:-}"
  HONCHO_REMOVE_VOLUMES="${HONCHO_REMOVE_VOLUMES:-0}"
}

ensure_required_runtime_env() {
  [[ -n "${LLM_OPENAI_API_KEY:-}" || -n "${LLM_ANTHROPIC_API_KEY:-}" || -n "${LLM_GEMINI_API_KEY:-}" || -n "${LLM_GROQ_API_KEY:-}" ]] \
    || fail "at least one LLM provider API key is required in $HONCHO_ENV_FILE"
}

compose_file_path() {
  printf '%s/config/containers/compose.yaml\n' "$(repo_root)"
}

env_template_path() {
  printf '%s/config/containers/.env.template\n' "$(repo_root)"
}

create_compose_override() {
  local output_file="$1"

  {
    printf '%s\n' 'services:'
    if [[ -f "$HONCHO_CONFIG_TOML" ]]; then
      printf '%s\n' '  api:'
      printf '%s\n' '    volumes:'
      printf '      - "%s:/app/config.toml:ro"\n' "$HONCHO_CONFIG_TOML"
      printf '%s\n' '  deriver:'
      printf '%s\n' '    volumes:'
      printf '      - "%s:/app/config.toml:ro"\n' "$HONCHO_CONFIG_TOML"
    fi
    if [[ -n "$HONCHO_DB_HOST_PORT" ]]; then
      printf '%s\n' '  database:'
      printf '%s\n' '    ports:'
      printf '      - "%s:5432"\n' "$HONCHO_DB_HOST_PORT"
    fi
    if [[ -n "$HONCHO_REDIS_HOST_PORT" ]]; then
      printf '%s\n' '  redis:'
      printf '%s\n' '    ports:'
      printf '      - "%s:6379"\n' "$HONCHO_REDIS_HOST_PORT"
    fi
  } > "$output_file"
}

run_compose() {
  local override_file="$1"
  shift
  local -a cmd=(podman compose -p "$HONCHO_PROJECT_NAME" -f "$(compose_file_path)")

  if [[ -f "$override_file" ]]; then
    cmd+=( -f "$override_file" )
  fi

  cmd+=( "$@" )
  "${cmd[@]}"
}

honcho_api_url() {
  printf 'http://localhost:%s\n' "$HONCHO_API_HOST_PORT"
}

wait_for_api() {
  local api_url
  local attempts=0

  api_url="$(honcho_api_url)/openapi.json"

  until python3 - "$api_url" <<'PY'
from urllib.request import urlopen
import sys

from urllib.error import URLError

try:
    urlopen(sys.argv[1], timeout=5)
except URLError:
    raise SystemExit(1)
PY
  do
    attempts=$((attempts + 1))
    if [[ "$attempts" -ge 30 ]]; then
      fail "Honcho API did not become healthy in time"
    fi
    sleep 2
  done
}

print_summary() {
  echo "==> Workspace arg:   $WORKSPACE_INPUT"
  echo "==> Workspace root:  $WORKSPACE_ROOT"
  echo "==> Env file:        $HONCHO_ENV_FILE"
  echo "==> Config TOML:     ${HONCHO_CONFIG_TOML}"
  echo "==> Postgres data:   $DATA_POSTGRES_DIR"
  echo "==> Redis data:      $DATA_REDIS_DIR"
  echo "==> Project:         $HONCHO_PROJECT_NAME"
  echo "==> Image:           $HONCHO_IMAGE_NAME"
  echo "==> Upstream repo:   $HONCHO_REPO_URL"
  echo "==> Upstream ref:    $HONCHO_REF"
  echo "==> API URL:         $(honcho_api_url)"
  echo "==> DB host port:    ${HONCHO_DB_HOST_PORT:-internal only}"
  echo "==> Redis host port: ${HONCHO_REDIS_HOST_PORT:-internal only}"
  if [[ -n "$HONCHO_DB_HOST_PORT" || -n "$HONCHO_REDIS_HOST_PORT" ]]; then
    echo "==> Network note:    DB/Redis host ports are exposed on all interfaces when set"
  fi
}
