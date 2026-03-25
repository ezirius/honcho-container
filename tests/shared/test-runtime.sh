#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

MOCK_BIN="$TMPDIR/bin"
STATE_DIR="$TMPDIR/state"
SERVER_ROOT="$TMPDIR/server"
mkdir -p "$MOCK_BIN" "$STATE_DIR" "$SERVER_ROOT"

assert_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"

  if ! grep -Fq -- "$needle" "$file"; then
    printf 'assertion failed: %s\nmissing: %s\nfile: %s\n' "$message" "$needle" "$file" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"

  if grep -Fq -- "$needle" "$file"; then
    printf 'assertion failed: %s\nunexpected: %s\nfile: %s\n' "$message" "$needle" "$file" >&2
    exit 1
  fi
}

write_file() {
  local path="$1"
  local content="${2-}"
  printf '%s' "$content" > "$path"
}

reset_state() {
  rm -f "$STATE_DIR"/*
  : > "$STATE_DIR/podman.log"
}

cat > "$MOCK_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${STATE_DIR:?}"
LOG_FILE="$STATE_DIR/podman.log"

log_call() {
  printf '%s\n' "$*" >> "$LOG_FILE"
}

read_value() {
  local name="$1"
  local path="$STATE_DIR/$name"
  if [[ -f "$path" ]]; then
    cat "$path"
  fi
}

write_value() {
  local name="$1"
  local value="$2"
  printf '%s' "$value" > "$STATE_DIR/$name"
}

subcommand="${1:?podman subcommand required}"
shift || true

case "$subcommand" in
  compose)
    if [[ "${1-}" == version ]]; then
      log_call "compose version"
      printf 'podman compose version mock\n'
      exit 0
    fi

    while [[ $# -gt 0 && ( "$1" == -p || "$1" == -f ) ]]; do
      shift 2
    done

    action="${1:?compose command required}"
    shift || true
    log_call "compose $action $*"

    case "$action" in
      build)
        write_value image_exists 1
        write_value image_label_honcho_repo_url "${HONCHO_REPO_URL:-}"
        write_value image_label_honcho_ref "${HONCHO_REF:-}"
        ;;
      up)
        write_value stack_running 1
        ;;
      ps|stop|down|logs|exec)
        ;;
      *)
        printf 'unexpected compose action: %s\n' "$action" >&2
        exit 1
        ;;
    esac
    ;;
  image)
    action="${1:?podman image action required}"
    shift || true
    case "$action" in
      exists)
        log_call "image exists $*"
        [[ "$(read_value image_exists)" == "1" ]]
        ;;
      inspect)
        log_call "image inspect $*"
        format="$2"
        case "$format" in
          '{{ index .Labels "honcho.repo_url" }}')
            printf '%s\n' "$(read_value image_label_honcho_repo_url)"
            ;;
          '{{ index .Labels "honcho.ref" }}')
            printf '%s\n' "$(read_value image_label_honcho_ref)"
            ;;
          *)
            printf 'unexpected image inspect format: %s\n' "$format" >&2
            exit 1
            ;;
        esac
        ;;
      rm)
        log_call "image rm $*"
        rm -f "$STATE_DIR/image_exists" "$STATE_DIR/image_label_honcho_repo_url" "$STATE_DIR/image_label_honcho_ref"
        ;;
      *)
        printf 'unexpected podman image action: %s\n' "$action" >&2
        exit 1
        ;;
    esac
    ;;
  *)
    printf 'unexpected podman subcommand: %s\n' "$subcommand" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$MOCK_BIN/podman"

export PATH="$MOCK_BIN:$PATH"
export STATE_DIR
export HONCHO_BASE_ROOT="$TMPDIR/workspaces"
export HONCHO_IMAGE_NAME="mock-honcho-image"
export HONCHO_REPO_URL="https://github.com/plastic-labs/honcho.git"
export HONCHO_REF="v3.0.3"
export HONCHO_API_HOST_PORT="18081"

mkdir -p "$SERVER_ROOT"
printf '{}' > "$SERVER_ROOT/openapi.json"
python3 -m http.server 18081 --bind 127.0.0.1 --directory "$SERVER_ROOT" >/dev/null 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" >/dev/null 2>&1 || true; wait "$SERVER_PID" 2>/dev/null || true; rm -rf "$TMPDIR"' EXIT
sleep 1

reset_state
write_file "$STATE_DIR/image_exists" "1"
"$ROOT/scripts/shared/honcho-build" > "$STATE_DIR/build-skip.out"
assert_contains "$STATE_DIR/build-skip.out" 'Honcho image already exists: mock-honcho-image' 'build reports existing image'
assert_contains "$STATE_DIR/build-skip.out" 'Skipping rebuild' 'build skips when image exists'
assert_not_contains "$STATE_DIR/podman.log" 'compose build ' 'build skip does not trigger compose build'

reset_state
"$ROOT/scripts/shared/honcho-build" > "$STATE_DIR/build-run.out"
assert_contains "$STATE_DIR/build-run.out" 'Building Honcho image' 'build reports image build'
assert_contains "$STATE_DIR/podman.log" 'compose build --pull --no-cache api deriver' 'build invokes compose build'

reset_state
write_file "$STATE_DIR/image_exists" "1"
write_file "$STATE_DIR/image_label_honcho_repo_url" 'https://github.com/plastic-labs/honcho.git'
write_file "$STATE_DIR/image_label_honcho_ref" 'v3.0.3'
"$ROOT/scripts/shared/honcho-upgrade" > "$STATE_DIR/upgrade-skip.out"
assert_contains "$STATE_DIR/upgrade-skip.out" 'No upgrade needed' 'upgrade skips when repo and ref match'
assert_not_contains "$STATE_DIR/podman.log" 'image rm ' 'upgrade skip does not remove image'

reset_state
write_file "$STATE_DIR/image_exists" "1"
write_file "$STATE_DIR/image_label_honcho_repo_url" 'https://github.com/plastic-labs/honcho.git'
write_file "$STATE_DIR/image_label_honcho_ref" 'v3.0.2'
"$ROOT/scripts/shared/honcho-upgrade" > "$STATE_DIR/upgrade-run.out"
assert_contains "$STATE_DIR/upgrade-run.out" 'Upgrading Honcho image: mock-honcho-image' 'upgrade reports rebuild'
assert_contains "$STATE_DIR/podman.log" 'image rm -f mock-honcho-image' 'upgrade removes old image'
assert_contains "$STATE_DIR/podman.log" 'compose build --pull --no-cache api deriver' 'upgrade rebuilds image'

reset_state
write_file "$STATE_DIR/image_exists" "1"
write_file "$STATE_DIR/image_label_honcho_repo_url" 'https://github.com/plastic-labs/honcho.git'
write_file "$STATE_DIR/image_label_honcho_ref" 'v3.0.3'
mkdir -p "$HONCHO_BASE_ROOT/ezirius"
cp "$ROOT/config/containers/.env.template" "$HONCHO_BASE_ROOT/ezirius/.env"
printf '\nLLM_OPENAI_API_KEY=test-key\n' >> "$HONCHO_BASE_ROOT/ezirius/.env"
printf 'HONCHO_API_HOST_PORT=18081\n' >> "$HONCHO_BASE_ROOT/ezirius/.env"
"$ROOT/scripts/shared/bootstrap" ezirius > "$STATE_DIR/bootstrap.out"
assert_contains "$STATE_DIR/bootstrap.out" 'No upgrade needed' 'bootstrap checks upgrade after build'
assert_contains "$STATE_DIR/bootstrap.out" 'Honcho stack started' 'bootstrap starts stack'
assert_contains "$STATE_DIR/bootstrap.out" 'Honcho API is healthy:' 'bootstrap reports healthy API'
assert_contains "$STATE_DIR/podman.log" 'compose up -d database redis api deriver' 'bootstrap starts compose stack'
assert_contains "$STATE_DIR/podman.log" 'compose ps ' 'bootstrap prints compose status'

echo "Runtime behaviour checks passed"
