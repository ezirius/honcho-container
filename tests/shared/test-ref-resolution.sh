#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/lib/shell/common.sh"

TMPDIR="$(mktemp -d)"
SERVER_PID=""
cleanup() {
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

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

mkdir -p "$TMPDIR/repos/plastic-labs/honcho/releases" "$TMPDIR/repos/plastic-labs/honcho"
printf '{"tag_name":"v9.9.9"}\n' > "$TMPDIR/repos/plastic-labs/honcho/releases/latest"

SERVER_PORT="$(python3 - <<'PY'
import socket
with socket.socket() as s:
    s.bind(('127.0.0.1', 0))
    print(s.getsockname()[1])
PY
)"

python3 -m http.server "$SERVER_PORT" --bind 127.0.0.1 --directory "$TMPDIR" >/dev/null 2>&1 &
SERVER_PID=$!
python3 - "$SERVER_PORT" <<'PY'
from urllib.request import urlopen
from urllib.error import URLError, HTTPError
import sys, time
url = f'http://127.0.0.1:{sys.argv[1]}/repos/plastic-labs/honcho/'
for _ in range(30):
    try:
        with urlopen(url, timeout=1):
            raise SystemExit(0)
    except (URLError, HTTPError, OSError):
        time.sleep(0.2)
raise SystemExit(1)
PY

assert_eq 'v9.9.9' "$(HONCHO_REF=latest-release HONCHO_GITHUB_API_BASE=http://127.0.0.1:$SERVER_PORT resolve_honcho_ref)" 'latest release endpoint is preferred when available'

rm -f "$TMPDIR/repos/plastic-labs/honcho/releases/latest"
printf '[{"name":"v9.9.8"}]\n' > "$TMPDIR/repos/plastic-labs/honcho/tags"
assert_eq 'v9.9.8' "$(HONCHO_REF=latest-release HONCHO_GITHUB_API_BASE=http://127.0.0.1:$SERVER_PORT resolve_honcho_ref)" 'latest tag fallback is used when release endpoint is unavailable'

rm -f "$TMPDIR/repos/plastic-labs/honcho/tags"
ERR_FILE="$TMPDIR/release.err"
if HONCHO_REF=latest-release HONCHO_GITHUB_API_BASE=http://127.0.0.1:$SERVER_PORT resolve_honcho_ref >/dev/null 2> "$ERR_FILE"; then
  printf 'assertion failed: latest-release should fail when neither releases nor tags are available\n' >&2
  exit 1
fi
assert_contains "$ERR_FILE" 'Latest upstream Honcho release and tags not found' 'missing release and tags fail clearly'

assert_eq 'v3.0.3' "$(HONCHO_REF=v3.0.3 resolve_honcho_ref)" 'explicit ref bypasses remote resolution'

if HONCHO_REF=latest-release HONCHO_REPO_URL=https://example.com/plastic-labs/honcho.git resolve_honcho_ref >/dev/null 2> "$TMPDIR/non-github.err"; then
  printf 'assertion failed: non-GitHub latest-release resolution should fail clearly\n' >&2
  exit 1
fi
assert_contains "$TMPDIR/non-github.err" 'requires a GitHub repo URL' 'non-GitHub latest-release resolution fails clearly'

echo "Ref resolution checks passed"
