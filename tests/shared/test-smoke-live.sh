#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKDIR="$(mktemp -d)"
WORKSPACE_NAME="smoke-$(date +%s)"
BASE_ROOT="$WORKDIR/base"
BOOTSTRAP_LOG="$WORKDIR/bootstrap.log"
REMOVE_LOG="$WORKDIR/remove.log"
trap 'rm -rf "$WORKDIR"' EXIT

if [[ "${HONCHO_RUN_LIVE_SMOKE_TEST:-0}" != "1" ]]; then
  echo "Skipping live smoke test (set HONCHO_RUN_LIVE_SMOKE_TEST=1 to enable)"
  exit 0
fi

for cmd in podman python3; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Missing required command for live smoke test: $cmd" >&2
    exit 1
  }
done
podman compose version >/dev/null 2>&1 || {
  echo "Missing required command for live smoke test: podman compose" >&2
  exit 1
}

mkdir -p "$BASE_ROOT/$WORKSPACE_NAME/honcho-home" "$BASE_ROOT/$WORKSPACE_NAME/workspace"
cp "$ROOT/config/containers/.env.template" "$BASE_ROOT/$WORKSPACE_NAME/honcho-home/.env"
cp "$ROOT/config/containers/config.toml.example" "$BASE_ROOT/$WORKSPACE_NAME/honcho-home/config.toml"

REQUIRED_KEYS=(
  LLM_OPENAI_API_KEY
  LLM_ANTHROPIC_API_KEY
  LLM_GEMINI_API_KEY
)

PROVIDER_LINES=""
for key in "${REQUIRED_KEYS[@]}"; do
  value="${!key:-}"
  if [[ -z "$value" ]]; then
    echo "Live smoke test requires $key because config.toml.example selects OpenAI, Anthropic, and Gemini providers." >&2
    exit 1
  fi
  PROVIDER_LINES+="$key=$value\n"
done

printf '\n%s' "$PROVIDER_LINES" >> "$BASE_ROOT/$WORKSPACE_NAME/honcho-home/.env"

HONCHO_BASE_ROOT="$BASE_ROOT" "$ROOT/scripts/shared/bootstrap" "$WORKSPACE_NAME" >"$BOOTSTRAP_LOG" 2>&1 || {
  cat "$BOOTSTRAP_LOG" >&2
  exit 1
}

cleanup_stack() {
  HONCHO_BASE_ROOT="$BASE_ROOT" "$ROOT/scripts/shared/honcho-remove" "$WORKSPACE_NAME" >"$REMOVE_LOG" 2>&1 || true
}
trap 'cleanup_stack; rm -rf "$WORKDIR"' EXIT

API_URL="$(HONCHO_BASE_ROOT="$BASE_ROOT" ROOT="$ROOT" WORKSPACE_NAME="$WORKSPACE_NAME" python3 - <<'PY'
import os
import pathlib
import re

base_root = pathlib.Path(os.environ['HONCHO_BASE_ROOT'])
workspace_name = os.environ.get('WORKSPACE_NAME')
if not workspace_name:
    workspace_name = ''
env_path = base_root / workspace_name / 'honcho-home' / '.env'
port = '8000'
if env_path.is_file():
    for raw_line in env_path.read_text(encoding='utf-8').splitlines():
        line = raw_line.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('export '):
            line = line[7:].lstrip()
        if '=' not in line:
            continue
        key, value = line.split('=', 1)
        if key.strip() == 'HONCHO_API_HOST_PORT':
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
                value = value[1:-1]
            if re.fullmatch(r'\d+', value):
                port = value
            break
print(f'http://localhost:{port}/openapi.json')
PY
)"

python3 - "$API_URL" <<'PY'
from urllib.request import urlopen
from urllib.error import URLError, HTTPError
import sys
import time
url = sys.argv[1]
for _ in range(30):
    try:
        with urlopen(url, timeout=5) as response:
            if 200 <= response.status < 300:
                raise SystemExit(0)
    except (URLError, HTTPError, OSError):
        time.sleep(2)
raise SystemExit(1)
PY

STATUS_OUTPUT="$(HONCHO_BASE_ROOT="$BASE_ROOT" "$ROOT/scripts/shared/honcho-status" "$WORKSPACE_NAME" 2>/dev/null || true)"
printf '%s\n' "$STATUS_OUTPUT" | grep -Eiq 'api.*(running|Up)'
printf '%s\n' "$STATUS_OUTPUT" | grep -Eiq 'deriver.*(running|Up)'

echo "Live smoke test passed for workspace $WORKSPACE_NAME"
