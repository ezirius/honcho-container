#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

bash -n \
  "$ROOT/scripts/shared/bootstrap" \
  "$ROOT/scripts/shared/honcho-build" \
  "$ROOT/scripts/shared/honcho-upgrade" \
  "$ROOT/scripts/shared/honcho-start" \
  "$ROOT/scripts/shared/honcho-status" \
  "$ROOT/scripts/shared/honcho-logs" \
  "$ROOT/scripts/shared/honcho-shell" \
  "$ROOT/scripts/shared/honcho-stop" \
  "$ROOT/scripts/shared/honcho-remove" \
  "$ROOT/lib/shell/common.sh" \
  "$ROOT/tests/shared/test-layout.sh" \
  "$ROOT/tests/shared/test-common.sh" \
  "$ROOT/tests/shared/test-args.sh" \
  "$ROOT/tests/shared/test-ref-resolution.sh" \
  "$ROOT/tests/shared/test-runtime.sh"

"$ROOT/tests/shared/test-layout.sh"
"$ROOT/tests/shared/test-common.sh"
"$ROOT/tests/shared/test-args.sh"
"$ROOT/tests/shared/test-ref-resolution.sh"
"$ROOT/tests/shared/test-runtime.sh"

echo "All Honcho checks passed"
