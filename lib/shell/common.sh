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

show_help() {
  printf '%s\n' "$1"
  exit 0
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

local_build_fingerprint() {
  require_python3

  python3 - "$ROOT" <<'PY'
import hashlib
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
paths = sorted(path for path in (root / "config/containers").rglob("*") if path.is_file())

digest = hashlib.sha256()
for path in paths:
    relative = path.relative_to(root).as_posix()
    digest.update(relative.encode("utf-8"))
    digest.update(b"\0")
    digest.update(path.read_bytes())
    digest.update(b"\0")

print(digest.hexdigest())
PY
}

current_image_build_fingerprint() {
  image_label honcho.wrapper_fingerprint
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

  [[ -n "$name" ]] || fail "workspace name must not be empty"
  [[ "$name" != */* ]] || fail "workspace name must not contain path separators: $name"
  [[ "$name" != "." ]] || fail "workspace name must not be '.'"
  [[ "$name" != ".." ]] || fail "workspace name must not be '..'"
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || fail "workspace name may only contain letters, numbers, dots, underscores, and hyphens"
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

  SAFE_WORKSPACE_NAME="$(printf '%s' "$WORKSPACE_NAME" | tr '[:upper:]' '[:lower:]')"

  HONCHO_HOME_DIR="$WORKSPACE_ROOT/honcho-home"
  HONCHO_WORKSPACE_DIR="$WORKSPACE_ROOT/workspace"
  HONCHO_ENV_FILE="$HONCHO_HOME_DIR/.env"
  HONCHO_CONFIG_TOML="$HONCHO_HOME_DIR/config.toml"
  DATA_POSTGRES_DIR="$HONCHO_HOME_DIR/postgres-data"
  DATA_REDIS_DIR="$HONCHO_HOME_DIR/redis-data"
  HONCHO_PROJECT_NAME="${HONCHO_PROJECT_PREFIX}-${SAFE_WORKSPACE_NAME}-$(hash_workspace_path "$WORKSPACE_ROOT")"

  export WORKSPACE_INPUT WORKSPACE_ROOT WORKSPACE_NAME SAFE_WORKSPACE_NAME
  export HONCHO_HOME_DIR HONCHO_WORKSPACE_DIR HONCHO_ENV_FILE HONCHO_CONFIG_TOML DATA_POSTGRES_DIR DATA_REDIS_DIR HONCHO_PROJECT_NAME
}

ensure_workspace_dirs() {
  mkdir -p "$WORKSPACE_ROOT" "$HONCHO_HOME_DIR" "$HONCHO_WORKSPACE_DIR" "$DATA_POSTGRES_DIR" "$DATA_REDIS_DIR"
}

migrate_legacy_workspace_layout() {
  local legacy_path
  local target

  for legacy_path in ".env" "config.toml" "postgres-data" "redis-data"; do
    if [[ ! -e "$WORKSPACE_ROOT/$legacy_path" ]]; then
      continue
    fi

    target="$HONCHO_HOME_DIR/$legacy_path"

    if [[ -d "$WORKSPACE_ROOT/$legacy_path" ]]; then
      mkdir -p "$target"
      shopt -s dotglob nullglob
      mv "$WORKSPACE_ROOT/$legacy_path"/* "$target"/ 2>/dev/null || true
      shopt -u dotglob nullglob
      rmdir "$WORKSPACE_ROOT/$legacy_path" 2>/dev/null || true
      continue
    fi

    if [[ ! -e "$target" ]]; then
      mv "$WORKSPACE_ROOT/$legacy_path" "$target"
    fi
  done
}

load_runtime_env_file() {
  local env_file="$1"

  [[ -f "$env_file" ]] || fail "env file not found: $env_file"

  while IFS= read -r -d '' key && IFS= read -r -d '' value; do
    case "$key" in
      HONCHO_API_HOST_PORT)
        HONCHO_API_HOST_PORT="$value"
        ;;
      HONCHO_DB_HOST_PORT)
        HONCHO_DB_HOST_PORT="$value"
        ;;
      HONCHO_REDIS_HOST_PORT)
        HONCHO_REDIS_HOST_PORT="$value"
        ;;
      HONCHO_REMOVE_VOLUMES)
        HONCHO_REMOVE_VOLUMES="$value"
        ;;
    esac
  done < <(python3 - "$env_file" <<'PY'
import pathlib
import re
import sys

allowed = {
    "HONCHO_API_HOST_PORT",
    "HONCHO_DB_HOST_PORT",
    "HONCHO_REDIS_HOST_PORT",
    "HONCHO_REMOVE_VOLUMES",
}

for raw_line in pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    line = raw_line.strip()
    if not line or line.startswith("#"):
        continue
    if line.startswith("export "):
        line = line[7:].lstrip()
    if "=" not in line:
        continue
    key, value = line.split("=", 1)
    key = key.strip()
    if key not in allowed or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
        continue
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
        value = value[1:-1]
    sys.stdout.buffer.write(key.encode("utf-8") + b"\0" + value.encode("utf-8") + b"\0")
PY
)
}

ensure_required_runtime_env() {
  if [[ -n "${LLM_OPENAI_API_KEY:-}" || -n "${LLM_ANTHROPIC_API_KEY:-}" || -n "${LLM_GEMINI_API_KEY:-}" || -n "${LLM_GROQ_API_KEY:-}" ]]; then
    return 0
  fi

  python3 - "$HONCHO_ENV_FILE" <<'PY' >/dev/null || fail "at least one LLM provider API key is required in $HONCHO_ENV_FILE"
import pathlib
import re
import sys

keys = {
    "LLM_OPENAI_API_KEY",
    "LLM_ANTHROPIC_API_KEY",
    "LLM_GEMINI_API_KEY",
    "LLM_GROQ_API_KEY",
}

for raw_line in pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    line = raw_line.strip()
    if not line or line.startswith("#"):
        continue
    if line.startswith("export "):
        line = line[7:].lstrip()
    if "=" not in line:
        continue
    key, value = line.split("=", 1)
    key = key.strip()
    if key not in keys or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
        continue
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
        value = value[1:-1]
    if value:
        raise SystemExit(0)

raise SystemExit(1)
PY
}

create_compose_env_file() {
  local output_file="$1"
  local source_file="$2"

  {
    printf 'HONCHO_IMAGE_NAME=%s\n' "$HONCHO_IMAGE_NAME"
    printf 'HONCHO_REPO_URL=%s\n' "$HONCHO_REPO_URL"
    printf 'HONCHO_REF=%s\n' "$HONCHO_REF"
    printf 'HONCHO_API_HOST_PORT=%s\n' "$HONCHO_API_HOST_PORT"
    printf 'HONCHO_DB_HOST_PORT=%s\n' "$HONCHO_DB_HOST_PORT"
    printf 'HONCHO_REDIS_HOST_PORT=%s\n' "$HONCHO_REDIS_HOST_PORT"
    printf 'DATA_POSTGRES_DIR=%s\n' "$DATA_POSTGRES_DIR"
    printf 'DATA_REDIS_DIR=%s\n' "$DATA_REDIS_DIR"
    if [[ -n "${HONCHO_WRAPPER_FINGERPRINT:-}" ]]; then
      printf 'HONCHO_WRAPPER_FINGERPRINT=%s\n' "$HONCHO_WRAPPER_FINGERPRINT"
    fi
    if [[ -f "$source_file" ]]; then
      python3 - "$source_file" <<'PY'
import pathlib
import re
import sys

excluded = {
    "HONCHO_BASE_ROOT",
    "HONCHO_IMAGE_NAME",
    "HONCHO_PROJECT_PREFIX",
    "HONCHO_REPO_URL",
    "HONCHO_REF",
    "HONCHO_GITHUB_API_BASE",
    "DATA_POSTGRES_DIR",
    "DATA_REDIS_DIR",
    "HONCHO_WRAPPER_FINGERPRINT",
}

for raw_line in pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    stripped = raw_line.strip()
    if not stripped or stripped.startswith("#"):
        print(raw_line)
        continue
    line = stripped
    if line.startswith("export "):
        line = line[7:].lstrip()
    if "=" not in line:
        print(raw_line)
        continue
    key = line.split("=", 1)[0].strip()
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
        print(raw_line)
        continue
    if key in excluded:
        continue
    print(raw_line)
PY
    fi
  } > "$output_file"
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
    printf '%s\n' '  api:'
    printf '%s\n' '    volumes:'
    printf '      - "%s:/workspace"\n' "$HONCHO_WORKSPACE_DIR"
    if [[ -f "$HONCHO_CONFIG_TOML" ]]; then
      printf '      - "%s:/app/config.toml:ro"\n' "$HONCHO_CONFIG_TOML"
    fi
    printf '%s\n' '  deriver:'
    printf '%s\n' '    volumes:'
    printf '      - "%s:/workspace"\n' "$HONCHO_WORKSPACE_DIR"
    if [[ -f "$HONCHO_CONFIG_TOML" ]]; then
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
  local env_file="$1"
  local override_file="$2"
  shift
  shift
  local -a cmd=(podman compose -p "$HONCHO_PROJECT_NAME")

  if [[ -f "$env_file" ]]; then
    cmd+=(--env-file "$env_file")
  fi

  cmd+=( -f "$(compose_file_path)" )

  if [[ -f "$override_file" ]]; then
    cmd+=( -f "$override_file" )
  fi

  cmd+=( "$@" )
  "${cmd[@]}"
}

stack_status_output() {
  local env_file="$1"
  local override_file="$2"

  run_compose "$env_file" "$override_file" ps 2>/dev/null || true
}

stack_has_running_services() {
  local status_output="$1"

  [[ "$status_output" == *running* || "$status_output" == *Up* ]]
}

stack_has_known_services() {
  local status_output="$1"

  [[ "$status_output" == *api* || "$status_output" == *deriver* || "$status_output" == *database* || "$status_output" == *redis* ]]
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
  echo "==> Honcho home:     $HONCHO_HOME_DIR"
  echo "==> Workspace dir:   $HONCHO_WORKSPACE_DIR"
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
