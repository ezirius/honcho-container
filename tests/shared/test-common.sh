#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/lib/shell/common.sh"

export HONCHO_BASE_ROOT="$ROOT/.tmp/workspaces"
rm -rf "$HONCHO_BASE_ROOT"

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
assert_eq "$WORKSPACE_ROOT/honcho-home" "$HONCHO_HOME_DIR" "Honcho home resolves under workspace root"
assert_eq "$WORKSPACE_ROOT/workspace" "$HONCHO_WORKSPACE_DIR" "workspace dir resolves under workspace root"
assert_eq "$HONCHO_HOME_DIR/.env" "$HONCHO_ENV_FILE" "workspace env file resolves under honcho home"
assert_eq "$HONCHO_HOME_DIR/config.toml" "$HONCHO_CONFIG_TOML" "workspace config TOML resolves under honcho home"
assert_eq "$HONCHO_HOME_DIR/postgres-data" "$DATA_POSTGRES_DIR" "postgres data dir resolves under honcho home"
assert_eq "$HONCHO_HOME_DIR/redis-data" "$DATA_REDIS_DIR" "redis data dir resolves under honcho home"

ensure_workspace_dirs
test -d "$HONCHO_HOME_DIR"
test -d "$HONCHO_WORKSPACE_DIR"

touch "$WORKSPACE_ROOT/.env"
touch "$WORKSPACE_ROOT/config.toml"
mkdir -p "$WORKSPACE_ROOT/postgres-data" "$WORKSPACE_ROOT/redis-data"
migrate_legacy_workspace_layout
test -f "$HONCHO_ENV_FILE"
test -f "$HONCHO_CONFIG_TOML"
test -d "$DATA_POSTGRES_DIR"
test -d "$DATA_REDIS_DIR"
test ! -e "$WORKSPACE_ROOT/.env"

trap 'rm -f "$COMPOSE_OVERRIDE_FILE" "$ABSOLUTE_ERR_FILE"' EXIT

ABSOLUTE_ERR_FILE="$(mktemp)"

if bash -lc 'set -euo pipefail; source "$1"; resolve_workspace "/tmp/absolute"' _ "$ROOT/lib/shell/common.sh" >/dev/null 2> "$ABSOLUTE_ERR_FILE"; then
  printf 'assertion failed: absolute workspace paths should be rejected\n' >&2
  exit 1
fi
grep -Fq 'workspace name must not contain path separators' "$ABSOLUTE_ERR_FILE"

if bash -lc 'set -euo pipefail; source "$1"; resolve_workspace "bad name"' _ "$ROOT/lib/shell/common.sh" >/dev/null 2> "$ABSOLUTE_ERR_FILE"; then
  printf 'assertion failed: invalid workspace names should be rejected\n' >&2
  exit 1
fi
grep -Fq 'workspace name may only contain letters, numbers, dots, underscores, and hyphens' "$ABSOLUTE_ERR_FILE"

EXPECTED_HASH="$(hash_workspace_path "$HONCHO_BASE_ROOT/ezirius")"
assert_eq "${HONCHO_PROJECT_PREFIX}-ezirius-$EXPECTED_HASH" "$HONCHO_PROJECT_NAME" "project name includes workspace path hash"

HONCHO_API_HOST_PORT=9000
assert_eq "http://localhost:9000" "$(honcho_api_url)" "API URL uses configured port"

COMPOSE_OVERRIDE_FILE="$(mktemp)"
HONCHO_DB_HOST_PORT=15432
HONCHO_REDIS_HOST_PORT=16379
create_compose_override "$COMPOSE_OVERRIDE_FILE"
grep -q '^  api:$' "$COMPOSE_OVERRIDE_FILE"
grep -q "^      - \"$HONCHO_WORKSPACE_DIR:/workspace\"$" "$COMPOSE_OVERRIDE_FILE"
grep -q '^  deriver:$' "$COMPOSE_OVERRIDE_FILE"
grep -q '^  database:$' "$COMPOSE_OVERRIDE_FILE"
grep -q '^      - "15432:5432"$' "$COMPOSE_OVERRIDE_FILE"
grep -q '^  redis:$' "$COMPOSE_OVERRIDE_FILE"
grep -q '^      - "16379:6379"$' "$COMPOSE_OVERRIDE_FILE"

echo "Common helper checks passed"
