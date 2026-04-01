# Honcho Wrapper Release Alignment Plan

Goal: Keep the `honcho-container` wrapper as close as practical to upstream Honcho `v3.0.3` while preserving the wrapper’s workspace-scoped operational model.

Architecture: Treat the wrapper as a thin orchestration and packaging layer over upstream Honcho `v3.0.3`. Preserve wrapper-specific lifecycle and workspace behaviour only where it materially improves local operation. Any divergence from upstream should be explicit, justified, documented, and tested.

Tech stack: Bash, Podman Compose, Dockerfile, FastAPI-based upstream Honcho `v3.0.3`, PostgreSQL, Redis, Markdown docs, shell tests.

---

## Release baseline

Validated wrapper baseline: upstream Honcho tag `v3.0.3`.

Rules:
- Use the latest upstream release/tag baseline for comparison work, not `main`.
- At present the validated wrapper/runtime baseline remains `v3.0.3`.
- When the wrapper baseline moves, rerun the upstream comparison and refresh docs/tests immediately.

---

## Current state

Completed in the current repo state:
1. Provider-aware runtime validation recognises the wrapper’s supported upstream `v3.0.3` provider paths.
2. The generated workspace runtime env now reaches `api` and `deriver` through the compose override path.
3. Degraded-stack detection requires `api` and `deriver` to be running before the stack is treated as already up.
4. Wrapper-control settings are split from the workspace runtime env template.
5. `config.toml.example` is framed as a curated wrapper-oriented subset rather than a full mirror.
6. Host-side helper requirements now explicitly include `python3` with `tomllib` support (`Python 3.11+`) for provider-aware validation.
7. `honcho-logs` now defaults to a snapshot view instead of forcing follow mode.
8. `honcho-status` behaves like a status command first and only reports API health when the stack is already running.
9. Operational commands (`status`, `logs`, `shell`, `stop`, `remove`) now reject nonexistent workspaces instead of creating new workspace trees for typos.
10. The default `HONCHO_BASE_ROOT` is now portable: `${XDG_DATA_HOME:-$HOME/.local/share}/honcho`.
11. The Dockerfile now handles arbitrary fetchable git refs safely rather than assuming branch/tag-only clone semantics.
12. Opt-in upstream-alignment and live-smoke paths exist and their assumptions match the validated baseline more closely.
13. The shell test suite is less brittle and less timing-sensitive than before.
14. Repo-local `.tmp/` artefacts are ignored and can be cleaned safely between runs.

---

## Remaining follow-up work

High-value remaining work:
1. Keep the runtime env propagation model aligned with validation and docs whenever new upstream env surfaces are added.
2. Continue reducing brittle exact-string assertions in shell tests where semantic checks are sufficient.
3. Consider parser-backed validation for example/config files in the test suite where practical.
4. Review whether `honcho-status` should gain a purely machine-readable mode for automation.
5. Review whether `api` should bind to localhost by default rather than all interfaces.
6. Re-run the upstream comparison whenever the validated baseline changes beyond `v3.0.3`.

---

## Non-goals

- Do not turn the wrapper into a fork of upstream Honcho.
- Do not duplicate the full upstream documentation locally unless necessary.
- Do not add wrapper-only abstractions that hide valid upstream `v3.0.3` behaviour.

---

## Verification checklist

Current verification path:
- `bash tests/shared/test-all.sh`
- `HONCHO_RUN_UPSTREAM_ALIGNMENT_TEST=1 bash tests/shared/test-upstream-alignment.sh`
- opt-in live smoke test when appropriate
- manual doc review for release-baseline and parity wording
- `git status --short --ignored`

Expected current result:
- core shell checks pass
- upstream alignment passes against `v3.0.3`
- repo-local `.tmp/` remains ignorable and removable

---

## Decision rules

- Prefer upstream terminology over wrapper-invented terminology.
- Prefer pass-through of valid upstream settings over local re-interpretation.
- Prefer explicit documentation of wrapper divergence over silent simplification.
- If a wrapper restriction is necessary, test it and document why it exists.
- Prefer stable behavioural tests over fragile wording/formatting checks.

---

## Expected outcome

The wrapper should:
- behave more like upstream `v3.0.3` by default
- avoid rejecting valid upstream configuration paths
- avoid misclassifying degraded or nonexistent stacks
- document its release alignment honestly
- keep wrapper-control settings separate from workspace runtime settings
- retain a repeatable path for future release-alignment checks
- remain maintainable under routine docs and shell refactors
