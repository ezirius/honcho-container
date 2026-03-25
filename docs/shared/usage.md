# Honcho container usage

## Workflow

Recommended one-step workflow:

1. Create the workspace directory and copy the env template there:
   `mkdir -p "$HONCHO_BASE_ROOT/ezirius" && cp config/containers/.env.template "$HONCHO_BASE_ROOT/ezirius/.env"`
2. Add your LLM provider keys to the workspace `.env`
3. Start the local Honcho stack for a workspace:
   `./scripts/shared/bootstrap ezirius`

`bootstrap` runs `honcho-build`, then `honcho-upgrade`, then `honcho-start`, then waits for the API to become healthy and prints the local access details.

`honcho-build` is intentionally workspace-independent so the local wrapper stays thin and the shared image stays close to upstream Honcho.
By default it resolves the latest upstream Honcho tagged release. If the upstream releases endpoint is unavailable, it falls back to the latest upstream tag.
That automatic `latest-release` resolution currently expects `HONCHO_REPO_URL` to point at a GitHub repository URL.

## Workspace model

You pass a workspace name such as `ezirius`.

Workspace names resolve under `HONCHO_BASE_ROOT`.

Default base root:

`~/Documents/Ezirius/.applications-data/Honcho`

For a named workspace such as `ezirius`, the host layout becomes:

- workspace root -> `~/Documents/Ezirius/.applications-data/Honcho/ezirius`
- `.env` -> `~/Documents/Ezirius/.applications-data/Honcho/ezirius/.env`
- optional `config.toml` -> `~/Documents/Ezirius/.applications-data/Honcho/ezirius/config.toml`
- `postgres-data/` -> `~/Documents/Ezirius/.applications-data/Honcho/ezirius/postgres-data`
- `redis-data/` -> `~/Documents/Ezirius/.applications-data/Honcho/ezirius/redis-data`

Container mounts are:

- optional `config.toml` -> `/app/config.toml`
- `postgres-data/` -> PostgreSQL data directory
- `redis-data/` -> `/data`

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
  - base directory used when you pass a workspace name instead of an absolute path
  - default: `~/Documents/Ezirius/.applications-data/Honcho`
- `HONCHO_REF`
  - upstream branch or tag to build from
  - default: `latest-release`
  - `latest-release` resolves the latest upstream Honcho release tag, with a fallback to the latest upstream tag when no release entry is available
- `HONCHO_GITHUB_API_BASE`
  - GitHub API base used to resolve `latest-release`
  - default: `https://api.github.com`
- `HONCHO_IMAGE_NAME`
  - local image name used by build and compose
- `HONCHO_PROJECT_NAME`
  - compose project name
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
- `./scripts/shared/honcho-logs <workspace-name>`
- `./scripts/shared/honcho-shell <workspace-name>`
- `./scripts/shared/honcho-stop <workspace-name>`
- `./scripts/shared/honcho-remove <workspace-name>`

## Notes

- Honcho runs locally in containers, but the LLMs still use remote provider APIs.
- `honcho-build` takes no positional arguments.
- `honcho-upgrade` takes no positional arguments and rebuilds only when the requested upstream source changed.
- `honcho-shell` opens into the `api` container by default.
- `honcho-logs` shows all services by default.
- `honcho-remove` preserves workspace data directories by default and only removes the Postgres/Redis service data directories when `HONCHO_REMOVE_VOLUMES=1` is set.
- Workspace-scoped commands require exactly one workspace name, except `honcho-logs`, which accepts optional extra compose log arguments after the workspace.
- The scripts create the workspace root, `postgres-data`, and `redis-data` directories automatically. You still need to create the workspace `.env` file yourself.
- `ensure_required_runtime_env()` only requires at least one provider API key, but the default upstream Honcho configuration typically uses:
  - OpenAI -> `text-embedding-3-small` for embeddings
  - Gemini -> `gemini-2.5-flash-lite` for deriver and lower dialectic levels, plus `gemini-2.5-flash` for summaries
  - Anthropic -> `claude-haiku-4-5` for higher dialectic levels and specialist reasoning, plus `claude-sonnet-4-20250514` for dreaming
- If you keep those defaults, you will usually want OpenAI, Gemini, and Anthropic API keys. If you change the providers in your config, fewer keys can be enough.
- Apps and SDKs normally connect to local Honcho at `http://localhost:8000`, while the Claude Code Honcho plugin documents local mode as `http://localhost:8000/v3`.
