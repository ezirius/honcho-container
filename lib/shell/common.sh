#!/usr/bin/env bash
set -euo pipefail

HONCHO_BASE_ROOT="${HONCHO_BASE_ROOT:-~/Documents/Ezirius/.applications-data/Honcho}"
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

require_python_runtime_validation() {
  require_python3
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
tags_url = f"{base}/repos/{repo_slug}/tags?per_page=1"
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
    if exc.code != 404:
        raise SystemExit(f"failed to resolve latest upstream Honcho release: HTTP {exc.code}")
except urllib.error.URLError as exc:
    raise SystemExit(f"failed to resolve latest upstream Honcho release: {exc.reason}")

try:
    tags = fetch_json(tags_url)
    if isinstance(tags, list) and tags:
        tag_name = tags[0].get("name", "")
        if tag_name:
            print(tag_name)
            sys.exit(0)
except urllib.error.HTTPError as exc:
    if exc.code == 404:
        raise SystemExit("Latest upstream Honcho release and tags not found")
    raise SystemExit(f"failed to resolve latest upstream Honcho release: HTTP {exc.code}")
except urllib.error.URLError as exc:
    raise SystemExit(f"failed to resolve latest upstream Honcho release: {exc.reason}")

raise SystemExit("Latest upstream Honcho release and tags did not include a tag name")
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

require_existing_workspace() {
  [[ -d "$WORKSPACE_ROOT" ]] || fail "workspace not found: $WORKSPACE_ROOT"
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
  local parsed_env_file

  [[ -f "$env_file" ]] || fail "env file not found: $env_file"
  require_python3

  parsed_env_file="$(mktemp)"
  trap 'rm -f "$parsed_env_file"' RETURN

  python3 - "$env_file" > "$parsed_env_file" <<'PY'
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
    print(f"{key}={value}")
PY

  while IFS='=' read -r key value; do
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
  done < "$parsed_env_file"
}

ensure_required_runtime_env() {
  require_python_runtime_validation

  python3 - "$HONCHO_ENV_FILE" "$HONCHO_CONFIG_TOML" <<'PY' >/dev/null || fail "missing required provider credentials for the configured Honcho providers in $HONCHO_ENV_FILE or the current shell environment"
import os
import pathlib
import re
import sys

ENV_PATH = pathlib.Path(sys.argv[1])
CONFIG_PATH = pathlib.Path(sys.argv[2])

provider_to_key = {
    "openai": "LLM_OPENAI_API_KEY",
    "anthropic": "LLM_ANTHROPIC_API_KEY",
    "google": "LLM_GEMINI_API_KEY",
    "groq": "LLM_GROQ_API_KEY",
    "custom": "LLM_OPENAI_COMPATIBLE_API_KEY",
    "vllm": "LLM_VLLM_API_KEY",
    "openrouter": "LLM_OPENAI_COMPATIBLE_API_KEY",
}

provider_requirements = {
    "openai": ["LLM_OPENAI_API_KEY"],
    "anthropic": ["LLM_ANTHROPIC_API_KEY"],
    "google": ["LLM_GEMINI_API_KEY"],
    "groq": ["LLM_GROQ_API_KEY"],
    "custom": ["LLM_OPENAI_COMPATIBLE_API_KEY", "LLM_OPENAI_COMPATIBLE_BASE_URL"],
    "openrouter": ["LLM_OPENAI_COMPATIBLE_API_KEY", "LLM_OPENAI_COMPATIBLE_BASE_URL"],
    "vllm": ["LLM_VLLM_API_KEY", "LLM_VLLM_BASE_URL"],
}

provider_fields = {
    ("llm", "EMBEDDING_PROVIDER"),
    ("deriver", "PROVIDER"),
    ("deriver", "BACKUP_PROVIDER"),
    ("summary", "PROVIDER"),
    ("summary", "BACKUP_PROVIDER"),
    ("dream", "PROVIDER"),
    ("dream", "BACKUP_PROVIDER"),
}

dialectic_levels = ("minimal", "low", "medium", "high", "max")
for level in dialectic_levels:
    provider_fields.add((f"dialectic.levels.{level}", "PROVIDER"))
    provider_fields.add((f"dialectic.levels.{level}", "BACKUP_PROVIDER"))


def parse_env_file(path: pathlib.Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.is_file():
        return values
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:].lstrip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
            continue
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
            value = value[1:-1]
        values[key] = value
    return values


def read_configured_providers(path: pathlib.Path) -> set[str]:
    if not path.is_file():
        return set()
    configured: set[str] = set()
    current_section = None
    section_pattern = re.compile(r"^\[([^\]]+)\]\s*$")
    assignment_pattern = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+?)\s*$")

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        section_match = section_pattern.match(line)
        if section_match:
            current_section = section_match.group(1).strip()
            continue

        assignment_match = assignment_pattern.match(line)
        if not assignment_match or current_section is None:
            continue

        field_name, raw_value = assignment_match.groups()
        candidate = raw_value.split("#", 1)[0].strip()
        if len(candidate) >= 2 and candidate[0] == candidate[-1] and candidate[0] in {'"', "'"}:
            candidate = candidate[1:-1]

        if (current_section, field_name) in provider_fields and candidate:
            configured.add(candidate.strip().lower())

    return configured


def read_env_selected_providers(values: dict[str, str]) -> set[str]:
    selected: set[str] = set()
    env_provider_keys = {
        "LLM_EMBEDDING_PROVIDER",
        "DERIVER_PROVIDER",
        "DERIVER_BACKUP_PROVIDER",
        "SUMMARY_PROVIDER",
        "SUMMARY_BACKUP_PROVIDER",
        "DREAM_PROVIDER",
        "DREAM_BACKUP_PROVIDER",
    }
    for level in dialectic_levels:
        env_provider_keys.add(f"DIALECTIC_LEVELS__{level}__PROVIDER")
        env_provider_keys.add(f"DIALECTIC_LEVELS__{level}__BACKUP_PROVIDER")

    for key in env_provider_keys:
        value = values.get(key, "").strip().lower()
        if value:
            selected.add(value)
    return selected

runtime_values = parse_env_file(ENV_PATH)
for key, value in os.environ.items():
    if value:
        runtime_values[key] = value

configured_providers = read_configured_providers(CONFIG_PATH)
configured_providers.update(read_env_selected_providers(runtime_values))
required_keys = set()
for provider in configured_providers:
    required_keys.update(provider_requirements.get(provider, []))

if not required_keys:
    required_keys = {
        "LLM_OPENAI_API_KEY",
        "LLM_ANTHROPIC_API_KEY",
        "LLM_GEMINI_API_KEY",
        "LLM_GROQ_API_KEY",
        "LLM_OPENAI_COMPATIBLE_API_KEY",
        "LLM_VLLM_API_KEY",
    }
    if any(runtime_values.get(key, "").strip() for key in required_keys):
        raise SystemExit(0)
    raise SystemExit(1)

missing = [key for key in sorted(required_keys) if not runtime_values.get(key, "").strip()]
if missing:
    raise SystemExit(1)

raise SystemExit(0)
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
    if [[ "$DATA_POSTGRES_DIR" == /* ]]; then
      printf 'DATA_POSTGRES_DIR=%s\n' "$DATA_POSTGRES_DIR"
    fi
    if [[ "$DATA_REDIS_DIR" == /* ]]; then
      printf 'DATA_REDIS_DIR=%s\n' "$DATA_REDIS_DIR"
    fi
    if [[ -n "${HONCHO_WRAPPER_FINGERPRINT:-}" ]]; then
      printf 'HONCHO_WRAPPER_FINGERPRINT=%s\n' "$HONCHO_WRAPPER_FINGERPRINT"
    fi
    if [[ -f "$source_file" ]]; then
      require_python3

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
  local runtime_env_file="${2:-}"
  local add_workspace_mounts=0
  local add_runtime_env_file=0
  local has_service_overrides=0

  if [[ "$HONCHO_WORKSPACE_DIR" == /* ]]; then
    add_workspace_mounts=1
  fi

  if [[ -n "$runtime_env_file" && -f "$runtime_env_file" ]]; then
    add_runtime_env_file=1
  fi

  if (( add_workspace_mounts )) || (( add_runtime_env_file )) || [[ -f "$HONCHO_CONFIG_TOML" ]] || [[ -n "$HONCHO_DB_HOST_PORT" ]] || [[ -n "$HONCHO_REDIS_HOST_PORT" ]]; then
    has_service_overrides=1
  fi

  if (( ! has_service_overrides )); then
    : > "$output_file"
    return 0
  fi

  {
    printf '%s\n' 'services:'
    if (( add_workspace_mounts )) || (( add_runtime_env_file )) || [[ -f "$HONCHO_CONFIG_TOML" ]]; then
      printf '%s\n' '  api:'
      if (( add_runtime_env_file )); then
        printf '%s\n' '    env_file:'
        printf '      - "%s"\n' "$runtime_env_file"
      fi
      if (( add_workspace_mounts )) || [[ -f "$HONCHO_CONFIG_TOML" ]]; then
        printf '%s\n' '    volumes:'
        if (( add_workspace_mounts )); then
          printf '      - "%s:/workspace"\n' "$HONCHO_WORKSPACE_DIR"
        fi
        if [[ -f "$HONCHO_CONFIG_TOML" ]]; then
          printf '      - "%s:/app/config.toml:ro"\n' "$HONCHO_CONFIG_TOML"
        fi
      fi
    fi
    if (( add_workspace_mounts )) || (( add_runtime_env_file )) || [[ -f "$HONCHO_CONFIG_TOML" ]]; then
      printf '%s\n' '  deriver:'
      if (( add_runtime_env_file )); then
        printf '%s\n' '    env_file:'
        printf '      - "%s"\n' "$runtime_env_file"
      fi
      if (( add_workspace_mounts )) || [[ -f "$HONCHO_CONFIG_TOML" ]]; then
        printf '%s\n' '    volumes:'
        if (( add_workspace_mounts )); then
          printf '      - "%s:/workspace"\n' "$HONCHO_WORKSPACE_DIR"
        fi
        if [[ -f "$HONCHO_CONFIG_TOML" ]]; then
          printf '      - "%s:/app/config.toml:ro"\n' "$HONCHO_CONFIG_TOML"
        fi
      fi
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

  if [[ -s "$override_file" ]]; then
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

  printf '%s\n' "$status_output" | grep -Eiq '(_api_[0-9]+|^api([[:space:]]|$)).*(running|Up)|(running|Up).*(_api_[0-9]+|^api([[:space:]]|$))' \
    && printf '%s\n' "$status_output" | grep -Eiq '(_deriver_[0-9]+|^deriver([[:space:]]|$)).*(running|Up)|(running|Up).*(_deriver_[0-9]+|^deriver([[:space:]]|$))'
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
import http.client
from urllib.request import urlopen
import sys

from urllib.error import HTTPError, URLError

try:
    with urlopen(sys.argv[1], timeout=5) as response:
        raise SystemExit(0 if 200 <= response.status < 300 else 1)
except (URLError, HTTPError, http.client.HTTPException, ConnectionError, OSError):
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
