#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if [[ "${HONCHO_RUN_UPSTREAM_ALIGNMENT_TEST:-0}" != "1" ]]; then
  echo "Skipping upstream alignment test (set HONCHO_RUN_UPSTREAM_ALIGNMENT_TEST=1 to enable)"
  exit 0
fi

ROOT="$ROOT" python3 - <<'PY'
import os
import urllib.request
from pathlib import Path

headers = {"User-Agent": "honcho-container-tests"}
root = Path(os.environ["ROOT"])
ref = "v3.0.3"


def get_text(url):
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as response:
        return response.read().decode("utf-8", errors="replace")


types = get_text(f"https://raw.githubusercontent.com/plastic-labs/honcho/{ref}/src/utils/types.py")
for provider in ('"custom"', '"vllm"', '"openai"', '"anthropic"', '"google"', '"groq"'):
    assert provider in types, f"missing provider {provider} in upstream {ref}"

compose_example = get_text(f"https://raw.githubusercontent.com/plastic-labs/honcho/{ref}/docker-compose.yml.example")
assert 'src.deriver' in compose_example, 'upstream compose example no longer exposes deriver worker'
for service in ('api:', 'deriver:', 'database:'):
    assert service in compose_example, f'missing service {service} in upstream compose example'

config_example = get_text(f"https://raw.githubusercontent.com/plastic-labs/honcho/{ref}/config.toml.example")
for section in ('[deriver]', '[summary]', '[dream]', '[vector_store]'):
    assert section in config_example, f"missing section {section} in upstream config example"

local_common = (root / 'lib/shell' / 'common.sh').read_text(encoding='utf-8')
for key in ('LLM_OPENAI_COMPATIBLE_API_KEY', 'LLM_VLLM_API_KEY', 'require_python_runtime_validation'):
    assert key in local_common, f'wrapper contract missing {key}'

local_readme = (root / 'README.md').read_text(encoding='utf-8')
local_usage = (root / 'docs/shared/usage.md').read_text(encoding='utf-8')
assert ref in local_readme and ref in local_usage, f'local docs are stale relative to validated baseline {ref}'
print(f'Upstream alignment checks passed against {ref}')
PY
