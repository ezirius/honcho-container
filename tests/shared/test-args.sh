#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

assert_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"

  if ! grep -Fq -- "$needle" "$file"; then
    printf 'assertion failed: %s\nmissing: %s\nfile: %s\n' "$message" "$needle" "$file" >&2
    exit 1
  fi
}

assert_rejects_unexpected_args() {
  local script_path="$1"
  local invocation="$2"
  local expected_message="$3"
  local error_file="$TMPDIR/$(basename "$script_path").err"

  shift 3

  if "$script_path" "$@" >/dev/null 2> "$error_file"; then
    printf 'assertion failed: %s should reject invalid argument usage (%s)\n' "$script_path" "$invocation" >&2
    exit 1
  fi

  assert_contains "$error_file" "$expected_message" "script reports invalid usage clearly"
}

assert_rejects_unexpected_args "$ROOT/scripts/shared/honcho-build" 'unexpected argument' 'takes no arguments' unexpected
assert_rejects_unexpected_args "$ROOT/scripts/shared/honcho-upgrade" 'unexpected argument' 'takes no arguments' unexpected
assert_rejects_unexpected_args "$ROOT/scripts/shared/bootstrap-test" 'unexpected argument' 'takes no arguments' unexpected
assert_rejects_unexpected_args "$ROOT/scripts/shared/bootstrap" 'missing workspace' 'requires exactly 1 argument'
assert_rejects_unexpected_args "$ROOT/scripts/shared/bootstrap" 'extra argument' 'requires exactly 1 argument' one two
assert_rejects_unexpected_args "$ROOT/scripts/shared/honcho-start" 'missing workspace' 'requires exactly 1 argument'
assert_rejects_unexpected_args "$ROOT/scripts/shared/honcho-start" 'extra argument' 'requires exactly 1 argument' one two
assert_rejects_unexpected_args "$ROOT/scripts/shared/honcho-status" 'missing workspace' 'requires exactly 1 argument'
assert_rejects_unexpected_args "$ROOT/scripts/shared/honcho-status" 'extra argument' 'requires exactly 1 argument' one two
assert_rejects_unexpected_args "$ROOT/scripts/shared/honcho-shell" 'missing workspace' 'requires exactly 1 argument'
assert_rejects_unexpected_args "$ROOT/scripts/shared/honcho-shell" 'extra argument' 'requires exactly 1 argument' one two
assert_rejects_unexpected_args "$ROOT/scripts/shared/honcho-stop" 'missing workspace' 'requires exactly 1 argument'
assert_rejects_unexpected_args "$ROOT/scripts/shared/honcho-stop" 'extra argument' 'requires exactly 1 argument' one two
assert_rejects_unexpected_args "$ROOT/scripts/shared/honcho-remove" 'missing workspace' 'requires exactly 1 argument'
assert_rejects_unexpected_args "$ROOT/scripts/shared/honcho-remove" 'extra argument' 'requires exactly 1 argument' one two

if "$ROOT/scripts/shared/honcho-logs" >/dev/null 2> "$TMPDIR/honcho-logs.err"; then
  printf 'assertion failed: honcho-logs should reject missing workspace arguments\n' >&2
  exit 1
fi
assert_contains "$TMPDIR/honcho-logs.err" 'requires at least 1 argument' 'honcho-logs reports missing workspace clearly'

HELP_FILE="$TMPDIR/help.out"

"$ROOT/scripts/shared/bootstrap" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Usage:' 'bootstrap help has usage header'
assert_contains "$HELP_FILE" '<workspace-name>' 'bootstrap help documents workspace argument'

"$ROOT/scripts/shared/honcho-build" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Usage:' 'build help has usage header'
assert_contains "$HELP_FILE" 'shared Honcho image' 'build help describes image purpose'

"$ROOT/scripts/shared/bootstrap-test" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Usage:' 'bootstrap-test help has usage header'
assert_contains "$HELP_FILE" 'dedicated test workspace' 'bootstrap-test help describes the test lane'
assert_contains "$HELP_FILE" 'LLM_OPENAI_API_KEY' 'bootstrap-test help documents required provider keys'

"$ROOT/scripts/shared/honcho-upgrade" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Usage:' 'upgrade help has usage header'
assert_contains "$HELP_FILE" 'Refresh the shared Honcho image' 'upgrade help describes upgrade purpose'

"$ROOT/scripts/shared/honcho-start" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Usage:' 'start help has usage header'
assert_contains "$HELP_FILE" '<workspace-name>' 'start help documents workspace argument'
assert_contains "$HELP_FILE" 'honcho-home/.env' 'start help documents honcho-home env path'

"$ROOT/scripts/shared/honcho-status" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Usage:' 'status help has usage header'
assert_contains "$HELP_FILE" 'current Honcho stack status' 'status help describes status purpose'

"$ROOT/scripts/shared/honcho-logs" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Usage:' 'logs help has usage header'
assert_contains "$HELP_FILE" 'Common compose log args:' 'logs help documents compose log args'
assert_contains "$HELP_FILE" 'snapshot of the current logs' 'logs help documents default snapshot mode'

"$ROOT/scripts/shared/honcho-shell" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Usage:' 'shell help has usage header'
assert_contains "$HELP_FILE" 'interactive shell' 'shell help describes shell purpose'

"$ROOT/scripts/shared/honcho-stop" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Usage:' 'stop help has usage header'
assert_contains "$HELP_FILE" 'Stop the Honcho stack' 'stop help describes stop purpose'

"$ROOT/scripts/shared/honcho-remove" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Usage:' 'remove help has usage header'
assert_contains "$HELP_FILE" 'HONCHO_REMOVE_VOLUMES=1' 'remove help documents volume removal'

echo "Argument contract checks passed"
