#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

required_files=(
  "$ROOT/README.md"
  "$ROOT/.gitignore"
  "$ROOT/config/containers/Dockerfile"
  "$ROOT/config/containers/compose.yaml"
  "$ROOT/config/containers/.env.template"
  "$ROOT/config/containers/wrapper.env.example"
  "$ROOT/config/containers/config.toml.example"
  "$ROOT/config/containers/database/init.sql"
  "$ROOT/docs/shared/usage.md"
  "$ROOT/lib/shell/common.sh"
  "$ROOT/scripts/shared/bootstrap"
  "$ROOT/scripts/shared/bootstrap-test"
  "$ROOT/scripts/shared/honcho-build"
  "$ROOT/scripts/shared/honcho-upgrade"
  "$ROOT/scripts/shared/honcho-start"
  "$ROOT/scripts/shared/honcho-status"
  "$ROOT/scripts/shared/honcho-logs"
  "$ROOT/scripts/shared/honcho-shell"
  "$ROOT/scripts/shared/honcho-stop"
  "$ROOT/scripts/shared/honcho-remove"
  "$ROOT/tests/shared/test-all.sh"
  "$ROOT/tests/shared/test-args.sh"
  "$ROOT/tests/shared/test-common.sh"
  "$ROOT/tests/shared/test-upstream-alignment.sh"
  "$ROOT/tests/shared/test-ref-resolution.sh"
  "$ROOT/tests/shared/test-runtime.sh"
  "$ROOT/tests/shared/test-smoke-live.sh"
)

for path in "${required_files[@]}"; do
  test -f "$path"
done

grep -q '^\.tmp/$' "$ROOT/.gitignore"
grep -q '^CREATE EXTENSION IF NOT EXISTS vector;$' "$ROOT/config/containers/database/init.sql"

# Compose contract
for service in api deriver database redis; do
  grep -q "^  ${service}:$" "$ROOT/config/containers/compose.yaml"
done
grep -q '^      - \${HONCHO_API_HOST_PORT:-8000}:8000$' "$ROOT/config/containers/compose.yaml"
! grep -q '^      - .*:5432$' "$ROOT/config/containers/compose.yaml"
! grep -q '^      - .*:6379$' "$ROOT/config/containers/compose.yaml"
grep -q 'HONCHO_WRAPPER_FINGERPRINT: \${HONCHO_WRAPPER_FINGERPRINT:-}' "$ROOT/config/containers/compose.yaml"
grep -q 'src.deriver' "$ROOT/config/containers/compose.yaml"
grep -q 'scripts/provision_db.py && exec /app/.venv/bin/fastapi run' "$ROOT/config/containers/compose.yaml"

# Workspace env / wrapper env split
grep -q '^HONCHO_API_HOST_PORT=8000$' "$ROOT/config/containers/.env.template"
grep -q '^HONCHO_DB_HOST_PORT=$' "$ROOT/config/containers/.env.template"
grep -q '^HONCHO_REDIS_HOST_PORT=$' "$ROOT/config/containers/.env.template"
! grep -q '^HONCHO_BASE_ROOT=' "$ROOT/config/containers/.env.template"
! grep -q '^HONCHO_REF=latest-release$' "$ROOT/config/containers/.env.template"
grep -q 'LLM_OPENAI_COMPATIBLE_API_KEY' "$ROOT/config/containers/.env.template"
grep -q 'LLM_VLLM_API_KEY' "$ROOT/config/containers/.env.template"
grep -q 'AUTH_JWT_SECRET' "$ROOT/config/containers/.env.template"

grep -q '^HONCHO_BASE_ROOT=~/Documents/Ezirius/.applications-data/Honcho$' "$ROOT/config/containers/wrapper.env.example"
grep -q '^HONCHO_REF=latest-release$' "$ROOT/config/containers/wrapper.env.example"

# Dockerfile contract
grep -q '^LABEL honcho.repo_url=\$HONCHO_REPO_URL$' "$ROOT/config/containers/Dockerfile"
grep -q '^LABEL honcho.ref=\$HONCHO_REF$' "$ROOT/config/containers/Dockerfile"
grep -q '^LABEL honcho.wrapper_fingerprint=\$HONCHO_WRAPPER_FINGERPRINT$' "$ROOT/config/containers/Dockerfile"
grep -q '^ENV UV_HTTP_TIMEOUT=120$' "$ROOT/config/containers/Dockerfile"
grep -q '^ENV UV_HTTP_RETRIES=5$' "$ROOT/config/containers/Dockerfile"
grep -q 'git init /app' "$ROOT/config/containers/Dockerfile"
grep -q 'git -C /app fetch --depth 1 origin "\$HONCHO_REF"' "$ROOT/config/containers/Dockerfile"
grep -q 'git -C /app checkout --detach FETCH_HEAD' "$ROOT/config/containers/Dockerfile"

# Docs contract
grep -q 'latest validated upstream baseline is `v3.0.3`' "$ROOT/README.md"
grep -q 'latest validated upstream baseline is `v3.0.3`' "$ROOT/docs/shared/usage.md"
grep -q 'Use upstream Docker or compose directly when you want one standard Honcho deployment with upstream defaults.' "$ROOT/README.md"
grep -q 'Use upstream Docker or compose directly when you want one standard Honcho deployment with upstream defaults.' "$ROOT/docs/shared/usage.md"
grep -q 'repeatable fresh test lane through `bootstrap-test`' "$ROOT/README.md"
grep -q 'destructive fresh wrapper test lane' "$ROOT/docs/shared/usage.md"
grep -q 'curated wrapper-oriented subset aligned to upstream `v3.0.3` defaults where practical' "$ROOT/README.md"
grep -q 'host-side helper scripts require `python3`' "$ROOT/README.md"
grep -q 'host-side helper scripts require `python3`' "$ROOT/docs/shared/usage.md"

# Shell helper contract
for fn in \
  github_repo_slug \
  image_exists \
  image_label \
  local_build_fingerprint \
  current_image_build_fingerprint \
  resolve_honcho_ref \
  require_podman_compose \
  require_python_runtime_validation \
  resolve_workspace \
  ensure_workspace_dirs \
  require_existing_workspace \
  migrate_legacy_workspace_layout \
  load_runtime_env_file \
  ensure_required_runtime_env \
  create_compose_env_file \
  create_compose_override \
  stack_status_output \
  stack_has_running_services \
  stack_has_known_services \
  honcho_api_url \
  wait_for_api; do
  grep -q "^${fn}() {$" "$ROOT/lib/shell/common.sh"
done

grep -q '^HONCHO_GITHUB_API_BASE="\${HONCHO_GITHUB_API_BASE:-https://api.github.com}"$' "$ROOT/lib/shell/common.sh"
grep -q 'http.client.HTTPException' "$ROOT/lib/shell/common.sh"

# Command wiring contract
for script in bootstrap bootstrap-test honcho-build honcho-upgrade honcho-start honcho-status honcho-logs honcho-shell honcho-stop honcho-remove; do
  test -x "$ROOT/scripts/shared/$script"
done

grep -q '^"\$SCRIPT_DIR/honcho-build"$' "$ROOT/scripts/shared/bootstrap"
grep -q '^"\$SCRIPT_DIR/honcho-upgrade"$' "$ROOT/scripts/shared/bootstrap"
grep -q '^"\$SCRIPT_DIR/honcho-start" "\$1"$' "$ROOT/scripts/shared/bootstrap"
grep -q '^"\$SCRIPT_DIR/honcho-status" "\$1"$' "$ROOT/scripts/shared/bootstrap"
grep -q '^TEST_WORKSPACE="test"$' "$ROOT/scripts/shared/bootstrap-test"
grep -q '^TEST_IMAGE_NAME="honcho-local-test"$' "$ROOT/scripts/shared/bootstrap-test"
grep -q '^podman image rm -f "\$TEST_IMAGE_NAME" >/dev/null 2>&1 || true$' "$ROOT/scripts/shared/bootstrap-test"
grep -q '^rm -rf "\$WORKSPACE_ROOT"$' "$ROOT/scripts/shared/bootstrap-test"
grep -q '^HONCHO_IMAGE_NAME="\$TEST_IMAGE_NAME" "\$SCRIPT_DIR/honcho-build"$' "$ROOT/scripts/shared/bootstrap-test"
grep -q '^exec env HONCHO_IMAGE_NAME="\$TEST_IMAGE_NAME" "\$SCRIPT_DIR/honcho-status" "\$TEST_WORKSPACE"$' "$ROOT/scripts/shared/bootstrap-test"
grep -q '^HONCHO_REF="\$(resolve_honcho_ref)"$' "$ROOT/scripts/shared/honcho-build"
grep -q '^HONCHO_WRAPPER_FINGERPRINT="\$(local_build_fingerprint)"$' "$ROOT/scripts/shared/honcho-build"
grep -q '^CURRENT_REPO_URL="\$(image_label honcho.repo_url)"$' "$ROOT/scripts/shared/honcho-upgrade"
grep -q '^CURRENT_REF="\$(image_label honcho.ref)"$' "$ROOT/scripts/shared/honcho-upgrade"
grep -q '^CURRENT_BUILD_FINGERPRINT="\$(current_image_build_fingerprint)"$' "$ROOT/scripts/shared/honcho-upgrade"
grep -q 'run_compose ".*" ".*" up -d database redis api deriver' "$ROOT/scripts/shared/honcho-start"
grep -q 'run_compose ".*" ".*" exec api /bin/sh' "$ROOT/scripts/shared/honcho-shell"

echo "Layout checks passed"
