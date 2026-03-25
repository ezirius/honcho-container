#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/lib/shell/common.sh"

COMPOSE_OVERRIDE_FILE=""
ABSOLUTE_ERR_FILE=""

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [[ "$expected" != "$actual" ]]; then
    printf 'assertion failed: %s\nexpected: %s\nactual:   %s\n' "$message" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_eq "$ROOT" "$(repo_root)" "repo_root resolves repository root"
assert_eq "$ROOT/config/containers/compose.yaml" "$(compose_file_path)" "compose file path resolves correctly"
assert_eq "http://localhost:8000" "$(honcho_api_url)" "default API URL uses localhost and default port"

resolve_workspace "ezirius"
assert_eq "$HONCHO_BASE_ROOT/ezirius" "$WORKSPACE_ROOT" "named workspace resolves under base root"
assert_eq "$WORKSPACE_ROOT/.env" "$HONCHO_ENV_FILE" "workspace env file resolves at workspace root"
assert_eq "$WORKSPACE_ROOT/config.toml" "$HONCHO_CONFIG_TOML" "workspace config TOML resolves at workspace root"
assert_eq "$WORKSPACE_ROOT/postgres-data" "$DATA_POSTGRES_DIR" "postgres data dir resolves under workspace root"
assert_eq "$WORKSPACE_ROOT/redis-data" "$DATA_REDIS_DIR" "redis data dir resolves under workspace root"

trap 'rm -f "$COMPOSE_OVERRIDE_FILE" "$ABSOLUTE_ERR_FILE"' EXIT

ABSOLUTE_ERR_FILE="$(mktemp)"

if bash -lc 'set -euo pipefail; source "$1"; resolve_workspace "/tmp/absolute"' _ "$ROOT/lib/shell/common.sh" >/dev/null 2> "$ABSOLUTE_ERR_FILE"; then
  printf 'assertion failed: absolute workspace paths should be rejected\n' >&2
  exit 1
fi
grep -Fq 'workspace name must not contain path separators' "$ABSOLUTE_ERR_FILE"

EXPECTED_HASH="$(hash_workspace_path "$HONCHO_BASE_ROOT/ezirius")"
assert_eq "${HONCHO_PROJECT_PREFIX}-ezirius-$EXPECTED_HASH" "$HONCHO_PROJECT_NAME" "project name includes workspace path hash"

HONCHO_API_HOST_PORT=9000
assert_eq "http://localhost:9000" "$(honcho_api_url)" "API URL uses configured port"

COMPOSE_OVERRIDE_FILE="$(mktemp)"
HONCHO_DB_HOST_PORT=15432
HONCHO_REDIS_HOST_PORT=16379
create_compose_override "$COMPOSE_OVERRIDE_FILE"
grep -q '^  database:$' "$COMPOSE_OVERRIDE_FILE"
grep -q '^      - "15432:5432"$' "$COMPOSE_OVERRIDE_FILE"
grep -q '^  redis:$' "$COMPOSE_OVERRIDE_FILE"
grep -q '^      - "16379:6379"$' "$COMPOSE_OVERRIDE_FILE"

echo "Common helper checks passed"
