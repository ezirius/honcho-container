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

assert_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"

  if ! grep -Fq -- "$needle" "$file"; then
    printf 'assertion failed: %s\nmissing: %s\nfile: %s\n' "$message" "$needle" "$file" >&2
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

cat > "$HONCHO_ENV_FILE" <<'EOF'
HONCHO_API_HOST_PORT=18080
export HONCHO_DB_HOST_PORT='15432'
HONCHO_REDIS_HOST_PORT="16379"
HONCHO_REMOVE_VOLUMES=1
HONCHO_IMAGE_NAME=should-not-override
LLM_OPENAI_COMPATIBLE_API_KEY=openai-compatible-key
LLM_VLLM_API_KEY=vllm-key
EOF
load_runtime_env_file "$HONCHO_ENV_FILE"
assert_eq "18080" "$HONCHO_API_HOST_PORT" "runtime env loader reads API host port"
assert_eq "15432" "$HONCHO_DB_HOST_PORT" "runtime env loader reads DB host port"
assert_eq "16379" "$HONCHO_REDIS_HOST_PORT" "runtime env loader reads Redis host port"
assert_eq "1" "$HONCHO_REMOVE_VOLUMES" "runtime env loader reads volume removal flag"

cat > "$HONCHO_ENV_FILE" <<'EOF'
LLM_OPENAI_COMPATIBLE_API_KEY=openai...-key
EOF
ensure_required_runtime_env

cat > "$HONCHO_ENV_FILE" <<'EOF'
LLM_OPENAI_COMPATIBLE_API_KEY=openai...-key
LLM_OPENAI_COMPATIBLE_BASE_URL=https://example.invalid/v1
EOF
ensure_required_runtime_env

cat > "$HONCHO_ENV_FILE" <<'EOF'
LLM_VLLM_API_KEY=***
EOF
ensure_required_runtime_env

cat > "$HONCHO_ENV_FILE" <<'EOF'
LLM_VLLM_API_KEY=***
LLM_VLLM_BASE_URL=http://localhost:8001/v1
EOF
ensure_required_runtime_env

cat > "$HONCHO_CONFIG_TOML" <<'EOF'
[llm]
EMBEDDING_PROVIDER = "custom"
EOF
cat > "$HONCHO_ENV_FILE" <<'EOF'
LLM_OPENAI_COMPATIBLE_API_KEY=openai-compatible-key
EOF
OPENAI_COMPAT_ERR_FILE="$(mktemp)"
if HONCHO_ENV_FILE="$HONCHO_ENV_FILE" HONCHO_CONFIG_TOML="$HONCHO_CONFIG_TOML" bash -lc 'set -euo pipefail; source "$1"; ensure_required_runtime_env' _ "$ROOT/lib/shell/common.sh" >/dev/null 2> "$OPENAI_COMPAT_ERR_FILE"; then
  printf 'assertion failed: custom provider validation should fail when the base URL is missing\n' >&2
  exit 1
fi
assert_contains "$OPENAI_COMPAT_ERR_FILE" 'missing required provider credentials' 'custom provider validation emits the shared missing-credentials error'

cat > "$HONCHO_ENV_FILE" <<'EOF'
LLM_OPENAI_COMPATIBLE_API_KEY=openai-compatible-key
LLM_OPENAI_COMPATIBLE_BASE_URL=https://example.invalid/v1
EOF
ensure_required_runtime_env

cat > "$HONCHO_CONFIG_TOML" <<'EOF'
[llm]
EMBEDDING_PROVIDER = "openrouter"
EOF
cat > "$HONCHO_ENV_FILE" <<'EOF'
LLM_OPENAI_COMPATIBLE_API_KEY=openai-compatible-key
EOF
OPENROUTER_ERR_FILE="$(mktemp)"
if HONCHO_ENV_FILE="$HONCHO_ENV_FILE" HONCHO_CONFIG_TOML="$HONCHO_CONFIG_TOML" bash -lc 'set -euo pipefail; source "$1"; ensure_required_runtime_env' _ "$ROOT/lib/shell/common.sh" >/dev/null 2> "$OPENROUTER_ERR_FILE"; then
  printf 'assertion failed: openrouter validation should fail when the base URL is missing\n' >&2
  exit 1
fi
assert_contains "$OPENROUTER_ERR_FILE" 'missing required provider credentials' 'openrouter validation emits the shared missing-credentials error'

cat > "$HONCHO_ENV_FILE" <<'EOF'
LLM_OPENAI_COMPATIBLE_API_KEY=openai-compatible-key
LLM_OPENAI_COMPATIBLE_BASE_URL=https://example.invalid/v1
EOF
ensure_required_runtime_env

cat > "$HONCHO_CONFIG_TOML" <<'EOF'
[deriver]
PROVIDER = "vllm"
EOF
cat > "$HONCHO_ENV_FILE" <<'EOF'
LLM_VLLM_API_KEY=***
EOF
VLLM_ERR_FILE="$(mktemp)"
if HONCHO_ENV_FILE="$HONCHO_ENV_FILE" HONCHO_CONFIG_TOML="$HONCHO_CONFIG_TOML" bash -lc 'set -euo pipefail; source "$1"; ensure_required_runtime_env' _ "$ROOT/lib/shell/common.sh" >/dev/null 2> "$VLLM_ERR_FILE"; then
  printf 'assertion failed: vllm validation should fail when the base URL is missing and vllm is selected\n' >&2
  exit 1
fi
assert_contains "$VLLM_ERR_FILE" 'missing required provider credentials' 'vllm validation emits the shared missing-credentials error'

cat > "$HONCHO_ENV_FILE" <<'EOF'
LLM_VLLM_API_KEY=***
LLM_VLLM_BASE_URL=http://localhost:8001/v1
EOF
ensure_required_runtime_env

cat > "$HONCHO_CONFIG_TOML" <<'EOF'
[deriver]
PROVIDER = "google"

[dream]
PROVIDER = "anthropic"
EOF
cat > "$HONCHO_ENV_FILE" <<'EOF'
LLM_GEMINI_API_KEY=gemini-key
EOF
MISSING_PROVIDER_ERR_FILE="$(mktemp)"
if HONCHO_ENV_FILE="$HONCHO_ENV_FILE" HONCHO_CONFIG_TOML="$HONCHO_CONFIG_TOML" bash -lc 'set -euo pipefail; source "$1"; ensure_required_runtime_env' _ "$ROOT/lib/shell/common.sh" >/dev/null 2> "$MISSING_PROVIDER_ERR_FILE"; then
  printf 'assertion failed: provider-aware validation should fail when a configured provider key is missing\n' >&2
  exit 1
fi
assert_contains "$MISSING_PROVIDER_ERR_FILE" 'missing required provider credentials' 'provider-aware validation emits the shared missing-credentials error'

cat > "$HONCHO_ENV_FILE" <<'EOF'
LLM_GEMINI_API_KEY=gemini-key
LLM_ANTHROPIC_API_KEY=anthropic-key
EOF
ensure_required_runtime_env

cat > "$HONCHO_CONFIG_TOML" <<'EOF'
[app]
LOG_LEVEL = "INFO"
EOF
cat > "$HONCHO_ENV_FILE" <<'EOF'
DERIVER_PROVIDER=google
EOF
ENV_PROVIDER_ERR_FILE="$(mktemp)"
if HONCHO_ENV_FILE="$HONCHO_ENV_FILE" HONCHO_CONFIG_TOML="$HONCHO_CONFIG_TOML" bash -lc 'set -euo pipefail; source "$1"; ensure_required_runtime_env' _ "$ROOT/lib/shell/common.sh" >/dev/null 2> "$ENV_PROVIDER_ERR_FILE"; then
  printf 'assertion failed: env-driven provider selection should fail when its provider key is missing\n' >&2
  exit 1
fi
assert_contains "$ENV_PROVIDER_ERR_FILE" 'missing required provider credentials' 'env-driven provider validation emits the shared missing-credentials error'

cat > "$HONCHO_ENV_FILE" <<'EOF'
DERIVER_PROVIDER=google
LLM_GEMINI_API_KEY=gemini-key
EOF
ensure_required_runtime_env

rm -f "$HONCHO_ENV_FILE"
rm -f "$HONCHO_CONFIG_TOML" "$MISSING_PROVIDER_ERR_FILE" "$ENV_PROVIDER_ERR_FILE" "$OPENAI_COMPAT_ERR_FILE" "$OPENROUTER_ERR_FILE" "$VLLM_ERR_FILE"

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

STATUS_OUTPUT=$'CONTAINER ID  IMAGE  COMMAND  CREATED  STATUS  PORTS  NAMES\n89f0ec768e16  localhost/honcho-local:latest  -  8 seconds ago  Up 2 seconds (starting)  0.0.0.0:8000->8000/tcp  honcho-ezirius-e38edbdb0fdc_api_1\n17fdc019caf2  localhost/honcho-local:latest  -  8 seconds ago  Up 1 second  8000/tcp  honcho-ezirius-e38edbdb0fdc_deriver_1'
if ! stack_has_running_services "$STATUS_OUTPUT"; then
  printf 'assertion failed: stack_has_running_services should recognise Podman compose ps output where status appears before the container name\n' >&2
  exit 1
fi

STATUS_OUTPUT=$'database running\nredis running\napi exited\nderiver exited'
if stack_has_running_services "$STATUS_OUTPUT"; then
  printf 'assertion failed: stack_has_running_services should reject exited api and deriver services\n' >&2
  exit 1
fi

COMPOSE_OVERRIDE_FILE="$(mktemp)"
COMPOSE_ENV_FILE="$(mktemp)"
create_compose_env_file "$COMPOSE_ENV_FILE" "$HONCHO_ENV_FILE"
HONCHO_DB_HOST_PORT=15432
HONCHO_REDIS_HOST_PORT=16379
create_compose_override "$COMPOSE_OVERRIDE_FILE" "$COMPOSE_ENV_FILE"
grep -q '^  api:$' "$COMPOSE_OVERRIDE_FILE"
grep -q '^    env_file:$' "$COMPOSE_OVERRIDE_FILE"
grep -q "^      - \"$COMPOSE_ENV_FILE\"$" "$COMPOSE_OVERRIDE_FILE"
grep -q "^      - \"$HONCHO_WORKSPACE_DIR:/workspace\"$" "$COMPOSE_OVERRIDE_FILE"
grep -q '^  deriver:$' "$COMPOSE_OVERRIDE_FILE"
grep -q '^  database:$' "$COMPOSE_OVERRIDE_FILE"
grep -q '^      - "15432:5432"$' "$COMPOSE_OVERRIDE_FILE"
grep -q '^  redis:$' "$COMPOSE_OVERRIDE_FILE"
grep -q '^      - "16379:6379"$' "$COMPOSE_OVERRIDE_FILE"

BUILD_OVERRIDE_FILE="$(mktemp)"
BUILD_ENV_FILE="$(mktemp)"
HONCHO_WORKSPACE_DIR="(resolved at runtime)"
HONCHO_CONFIG_TOML="(resolved at runtime)"
HONCHO_DB_HOST_PORT=""
HONCHO_REDIS_HOST_PORT=""
DATA_POSTGRES_DIR="(resolved at runtime)"
DATA_REDIS_DIR="(resolved at runtime)"
create_compose_override "$BUILD_OVERRIDE_FILE"
create_compose_env_file "$BUILD_ENV_FILE" /dev/null
if [[ -s "$BUILD_OVERRIDE_FILE" ]]; then
  printf 'assertion failed: build-time compose override should be empty when there are no real overrides\n' >&2
  exit 1
fi
if grep -Fxq '  api:' "$BUILD_OVERRIDE_FILE"; then
  printf 'assertion failed: build-time compose override should not emit empty api service blocks\n' >&2
  exit 1
fi
if grep -Fxq '  deriver:' "$BUILD_OVERRIDE_FILE"; then
  printf 'assertion failed: build-time compose override should not emit empty deriver service blocks\n' >&2
  exit 1
fi
if grep -Fq '/workspace' "$BUILD_OVERRIDE_FILE"; then
  printf 'assertion failed: build-time compose override should not inject placeholder workspace mounts\n' >&2
  exit 1
fi
if grep -Fq 'DATA_POSTGRES_DIR=(resolved at runtime)' "$BUILD_ENV_FILE"; then
  printf 'assertion failed: build-time compose env should not inject placeholder postgres data paths\n' >&2
  exit 1
fi
if grep -Fq 'DATA_REDIS_DIR=(resolved at runtime)' "$BUILD_ENV_FILE"; then
  printf 'assertion failed: build-time compose env should not inject placeholder redis data paths\n' >&2
  exit 1
fi

echo "Common helper checks passed"
