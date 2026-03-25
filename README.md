# Honcho container

This repository builds and manages a local self-hosted Honcho stack with Podman Compose.

Honcho itself runs locally in containers, while LLM calls still use remote provider APIs configured through environment variables.

## Layout

- `config/containers/` contains the Honcho image build, compose stack, env template, config example, and database init SQL
- `docs/shared/usage.md` documents the shared container workflow and environment overrides
- `lib/shell/common.sh` contains shared shell helpers and defaults
- `scripts/shared/` contains the shared bootstrap, build, upgrade, start, status, logs, shell, stop, and remove commands
- `tests/shared/` contains aggregate, helper, argument-contract, and layout checks

## Quickstart

1. Create the workspace directory, copy the env template there, and add your LLM API keys:

   `mkdir -p "$HOME/Documents/Ezirius/.applications-data/Honcho/ezirius" && cp config/containers/.env.template "$HOME/Documents/Ezirius/.applications-data/Honcho/ezirius/.env"`

2. Run the full local stack for a workspace such as `ezirius`:

   `./scripts/shared/bootstrap ezirius`

`bootstrap` builds the shared local Honcho image from the latest upstream tagged release by default, upgrades it if the requested upstream source changed, starts the stack for the selected workspace, waits for the API to become healthy, and then prints the local access details.

## Workspace layout

Each workspace is expected to use this host layout under `HONCHO_BASE_ROOT`:

- workspace root
- `.env`
- optional `config.toml`
- `postgres-data/`
- `redis-data/`

For example:

`~/Documents/Ezirius/.applications-data/Honcho/ezirius`

with:

- `~/Documents/Ezirius/.applications-data/Honcho/ezirius/.env`
- `~/Documents/Ezirius/.applications-data/Honcho/ezirius/config.toml`
- `~/Documents/Ezirius/.applications-data/Honcho/ezirius/postgres-data`
- `~/Documents/Ezirius/.applications-data/Honcho/ezirius/redis-data`

The scripts create and use the service data directories under the workspace root:

- `postgres-data`
- `redis-data`

## Services

The default local stack includes:

- `api`
- `deriver`
- `database`
- `redis`

## Ports

- API host port -> container port `8000`
- Postgres host port -> container port `5432` only if enabled in `config/containers/.env`
- Redis host port -> container port `6379` only if enabled in `config/containers/.env`

By default, the API is exposed and the database and Redis stay internal.

If you set `HONCHO_DB_HOST_PORT` or `HONCHO_REDIS_HOST_PORT`, those services are also exposed on all host interfaces.

## Container rules

- Podman Compose is the orchestration method
- The API is exposed on all host interfaces by default using `HONCHO_API_HOST_PORT`
- Postgres and Redis are internal by default and are only exposed if their host-port variables are set
- `honcho-build` ensures the shared image exists
- `honcho-upgrade` rebuilds the shared image only when the requested upstream source changed
- `honcho-start` starts or reuses the local stack only
- `bootstrap` performs the full `build -> upgrade -> start -> health check` flow
- by default, `honcho-build` and `honcho-upgrade` resolve the latest upstream Honcho release tag; if the releases endpoint is unavailable, they fall back to the latest upstream tag

Scripts that take no positional arguments reject them explicitly. Workspace-scoped scripts require exactly one workspace name, except `honcho-logs`, which accepts a workspace name plus optional compose log arguments.

Because the stack is workspace-scoped, the runtime scripts use a workspace name under `HONCHO_BASE_ROOT` rather than arbitrary absolute paths.

## Useful commands

- `./scripts/shared/honcho-status`
- `./scripts/shared/honcho-logs`
- `./scripts/shared/honcho-shell`
- `./scripts/shared/honcho-stop`
- `./scripts/shared/honcho-remove`
- `./scripts/shared/honcho-upgrade`

## Data preservation

`honcho-remove` preserves workspace data directories by default.

The scripts create the workspace root, `postgres-data`, and `redis-data` directories automatically. You still need to create the workspace `.env` file yourself.

The stack requires at least one provider API key to start, but the default upstream Honcho configuration typically uses:

- OpenAI for embeddings -> `text-embedding-3-small`
- Google Gemini for deriver and summary -> `gemini-2.5-flash-lite` and `gemini-2.5-flash`
- Anthropic for higher-level dialectic and dreaming -> `claude-haiku-4-5` and `claude-sonnet-4-20250514`

If you keep those defaults, you will usually want all three provider keys.

Where more than one default model exists for a provider, the rough preference is:

- OpenAI: embeddings only by default
- Gemini: lighter day-to-day background work first (`gemini-2.5-flash-lite`), then richer summaries (`gemini-2.5-flash`)
- Anthropic: `claude-haiku-4-5` for medium/high/max dialectic and specialist reasoning, `claude-sonnet-4-20250514` for dreaming

To remove the service data directories for Postgres and Redis as well, set:

```bash
HONCHO_REMOVE_VOLUMES=1 ./scripts/shared/honcho-remove ezirius
```
