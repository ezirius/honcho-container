# Honcho container usage

## Workflow

Recommended one-step workflow:

1. Create the workspace directory and copy the env template into `honcho-home`:
   `mkdir -p "$HONCHO_BASE_ROOT/ezirius/honcho-home" "$HONCHO_BASE_ROOT/ezirius/workspace" && cp config/containers/.env.template "$HONCHO_BASE_ROOT/ezirius/honcho-home/.env"`
2. Add your LLM provider keys to the workspace `.env`
3. Start the local Honcho stack for a workspace:
   `./scripts/shared/bootstrap ezirius`

`bootstrap` runs `honcho-build`, then `honcho-upgrade`, then `honcho-start`, then waits for the API to become healthy and prints the local access details.

If the workspace stack is already running, `honcho-start` reports that and leaves it alone. If it exists but is stopped, `honcho-start` starts it again with `compose up -d`. If it does not exist yet, `honcho-start` creates it.

`honcho-build` is intentionally workspace-independent so the local wrapper stays thin and the shared image stays close to upstream Honcho.
By default it resolves the latest upstream Honcho GitHub release and fails clearly if no upstream release is available.
That automatic `latest-release` resolution currently expects `HONCHO_REPO_URL` to point at a GitHub repository URL.
`honcho-upgrade` also compares a local wrapper build fingerprint so Dockerfile and Compose image-recipe changes trigger a rebuild even when the upstream Honcho ref stays the same.
In practice, repeated `bootstrap` runs are the normal maintenance path: `honcho-build` is no-op when the image exists, while `honcho-upgrade` re-checks both the upstream source and the local wrapper image recipe before deciding whether to rebuild.

## Workspace model

You pass a workspace name such as `ezirius`.

Workspace names resolve under `HONCHO_BASE_ROOT`.

Default base root:

`~/Documents/Ezirius/.applications-data/Honcho`

For a named workspace such as `ezirius`, the host layout becomes:

- workspace root -> `~/Documents/Ezirius/.applications-data/Honcho/ezirius`
- `honcho-home/` -> `~/Documents/Ezirius/.applications-data/Honcho/ezirius/honcho-home`
- `.env` -> `~/Documents/Ezirius/.applications-data/Honcho/ezirius/honcho-home/.env`
- optional `config.toml` -> `~/Documents/Ezirius/.applications-data/Honcho/ezirius/honcho-home/config.toml`
- `postgres-data/` -> `~/Documents/Ezirius/.applications-data/Honcho/ezirius/honcho-home/postgres-data`
- `redis-data/` -> `~/Documents/Ezirius/.applications-data/Honcho/ezirius/honcho-home/redis-data`
- `workspace/` -> `~/Documents/Ezirius/.applications-data/Honcho/ezirius/workspace`

Container mounts are:

- optional `honcho-home/config.toml` -> `/app/config.toml`
- `honcho-home/postgres-data/` -> PostgreSQL data directory
- `honcho-home/redis-data/` -> `/data`
- `workspace/` -> `/workspace` for `api` and `deriver`
- `honcho-home/.env` is consumed as Compose/service runtime data, not sourced into the wrapper shell

## Services

The default stack includes:

- `api`
- `deriver`
- `database`
- `redis`

## Ports

- API host port -> container port `8000`
- Postgres host port -> container port `5432` if `HONCHO_DB_HOST_PORT` is set
- Redis host port -> container port `6379` if `HONCHO_REDIS_HOST_PORT` is set

By default, the API is reachable from other machines and Postgres/Redis remain internal.

If you set `HONCHO_DB_HOST_PORT` or `HONCHO_REDIS_HOST_PORT`, those services are also exposed on all host interfaces. Only do that when you explicitly want network access to them.

## Environment overrides

- `HONCHO_REPO_URL`
  - upstream Honcho repo used during image build
  - `latest-release` resolution derives the GitHub owner/repo from this URL
- `HONCHO_BASE_ROOT`
  - base directory used when you pass a workspace name
  - default: `~/Documents/Ezirius/.applications-data/Honcho`
- `HONCHO_REF`
  - upstream branch or tag to build from
  - default: `latest-release`
  - `latest-release` resolves the latest upstream Honcho release tag and fails clearly if no release entry is available
  - `honcho-upgrade` re-checks this and rebuilds when either the requested upstream source or the local wrapper image recipe changed
- `HONCHO_GITHUB_API_BASE`
  - GitHub API base used to resolve `latest-release`
  - default: `https://api.github.com`
- `HONCHO_IMAGE_NAME`
  - local image name used by build and compose
- `HONCHO_PROJECT_PREFIX`
  - prefix used when deriving the compose project name from the workspace
- `HONCHO_API_HOST_PORT`
  - API host port
  - default: `8000`
- `HONCHO_DB_HOST_PORT`
  - optional Postgres host port
  - default: empty (internal only)
- `HONCHO_REDIS_HOST_PORT`
  - optional Redis host port
  - default: empty (internal only)
- `HONCHO_REMOVE_VOLUMES`
  - set to `1` to remove the Postgres and Redis data directories in `honcho-remove`

## Commands

- `./scripts/shared/honcho-build`
- `./scripts/shared/honcho-upgrade`
- `./scripts/shared/honcho-start <workspace-name>`
- `./scripts/shared/honcho-status <workspace-name>`
- `./scripts/shared/honcho-logs <workspace-name> [compose log args...]`
- `./scripts/shared/honcho-shell <workspace-name>`
- `./scripts/shared/honcho-stop <workspace-name>`
- `./scripts/shared/honcho-remove <workspace-name>`

All wrapper scripts support `--help` and document their argument contracts there.

## Notes

- Honcho runs locally in containers, but the LLMs still use remote provider APIs.
- `honcho-build` takes no positional arguments.
- `honcho-upgrade` takes no positional arguments and rebuilds when the requested upstream source changed or when the local wrapper image recipe changed.
- `honcho-shell` opens into the `api` container by default.
- `honcho-logs` shows all services by default.
- `honcho-remove` preserves workspace data directories by default and only removes the Postgres/Redis service data directories when `HONCHO_REMOVE_VOLUMES=1` is set.
- Workspace-scoped commands require exactly one workspace name, except `honcho-logs`, which accepts optional extra compose log arguments after the workspace.
- The scripts create the workspace root, `honcho-home`, `workspace`, `postgres-data`, and `redis-data` directories automatically. You still need to create the workspace `.env` file yourself at `honcho-home/.env`.
- `api`, `deriver`, `database`, and `redis` all use restart policy `unless-stopped`, so crashes and host reboots recover automatically while a manual stop stays stopped.
- Editing `honcho-home/.env` or `honcho-home/config.toml` does not require an image rebuild; a stack stop/start is enough to apply those runtime changes.
- Workspace env values do not override wrapper control vars such as image name, base root, or upstream repo/ref selection.
- `ensure_required_runtime_env()` only requires at least one provider API key, but the default upstream Honcho configuration typically uses:
  - OpenAI -> `text-embedding-3-small` for embeddings
  - Gemini -> `gemini-2.5-flash-lite` for deriver and lower dialectic levels, plus `gemini-2.5-flash` for summaries
  - Anthropic -> `claude-haiku-4-5` for higher dialectic levels and specialist reasoning, plus `claude-sonnet-4-20250514` for dreaming
- If you keep those defaults, you will usually want OpenAI, Gemini, and Anthropic API keys. If you change the providers in your config, fewer keys can be enough.
- Apps and SDKs normally connect to local Honcho at `http://localhost:8000`, while the Claude Code Honcho plugin documents local mode as `http://localhost:8000/v3`.
