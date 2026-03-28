# Honcho container

This repository builds and manages a local self-hosted Honcho stack with Podman Compose.

Honcho itself runs locally in containers, while LLM calls still use remote provider APIs configured through environment variables.

## Layout

- `config/containers/` contains the Honcho image build, compose stack, env template, config example, and database init SQL
- `docs/shared/usage.md` documents the shared container workflow and environment overrides
- `lib/shell/common.sh` contains shared shell helpers and defaults
- `scripts/shared/` contains the shared bootstrap, build, upgrade, start, status, logs, shell, stop, and remove commands
- `tests/shared/` contains aggregate, helper, argument-contract, layout, ref-resolution, and runtime checks

## Quickstart

1. Create the workspace directory, copy the env template into `honcho-home`, and add your LLM API keys:

   `mkdir -p "$HOME/Documents/Ezirius/.applications-data/Honcho/ezirius/honcho-home" "$HOME/Documents/Ezirius/.applications-data/Honcho/ezirius/workspace" && cp config/containers/.env.template "$HOME/Documents/Ezirius/.applications-data/Honcho/ezirius/honcho-home/.env"`

2. Run the full local stack for a workspace such as `ezirius`:

   `./scripts/shared/bootstrap ezirius`

`bootstrap` builds the shared local Honcho image from the latest upstream GitHub release by default, upgrades it if the requested upstream source changed or the local wrapper image recipe changed, starts the stack for the selected workspace, waits for the API to become healthy, and then prints the local access details.

## Workspace layout

Each workspace is expected to use this host layout under `HONCHO_BASE_ROOT`:

- workspace root
- `honcho-home/`
- `workspace/`

For example:

`~/Documents/Ezirius/.applications-data/Honcho/ezirius`

with:

- `~/Documents/Ezirius/.applications-data/Honcho/ezirius/honcho-home/.env`
- `~/Documents/Ezirius/.applications-data/Honcho/ezirius/honcho-home/config.toml`
- `~/Documents/Ezirius/.applications-data/Honcho/ezirius/honcho-home/postgres-data`
- `~/Documents/Ezirius/.applications-data/Honcho/ezirius/honcho-home/redis-data`
- `~/Documents/Ezirius/.applications-data/Honcho/ezirius/workspace`

The scripts create and use the service data directories under `honcho-home`:

- `postgres-data`
- `redis-data`

The runtime mounts are:

- `honcho-home/config.toml` -> `/app/config.toml` for `api` and `deriver` when present
- `honcho-home/postgres-data` -> PostgreSQL data directory
- `honcho-home/redis-data` -> `/data` for Redis
- `workspace/` -> `/workspace` for `api` and `deriver`

The wrapper keeps its own control-plane settings outside the workspace env file. The workspace `honcho-home/.env` is treated as runtime data for Compose and the Honcho services, so values there do not override wrapper image selection, repo/ref tracking, or base-root resolution.

## Services

The default local stack includes:

- `api`
- `deriver`
- `database`
- `redis`

## Ports

- API host port -> container port `8000`
- Postgres host port -> container port `5432` only if set in `honcho-home/.env`
- Redis host port -> container port `6379` only if set in `honcho-home/.env`

By default, the API is exposed and the database and Redis stay internal.

If you set `HONCHO_DB_HOST_PORT` or `HONCHO_REDIS_HOST_PORT`, those services are also exposed on all host interfaces.

## Container rules

- Podman Compose is the orchestration method
- The API is exposed on all host interfaces by default using `HONCHO_API_HOST_PORT`
- Postgres and Redis are internal by default and are only exposed if their host-port variables are set
- `honcho-build` ensures the shared image exists
- `honcho-upgrade` rebuilds the shared image when the requested upstream source changed or when the local wrapper image recipe changed
- `honcho-start` starts or reuses the local stack only
- `bootstrap` performs the full `build -> upgrade -> start -> health check` flow
- by default, `honcho-build` and `honcho-upgrade` resolve the latest upstream Honcho release tag and fail clearly if no upstream release is available
- in practice, repeated `bootstrap` runs are the normal way to stay current: `honcho-build` is no-op when the image exists, while `honcho-upgrade` re-checks both the upstream release and the local wrapper build fingerprint before deciding whether to rebuild
- `api`, `deriver`, `database`, and `redis` all use restart policy `unless-stopped`, so crashes and host reboots recover automatically while a manual stop remains stopped

Stack lifecycle details:

- if the workspace stack is already running, `honcho-start` reports that and leaves it alone
- if the workspace stack exists but is stopped, `honcho-start` starts it again with `compose up -d`
- if the stack does not exist yet, `honcho-start` creates it with `compose up -d`

Scripts that take no positional arguments reject them explicitly. Workspace-scoped scripts require exactly one workspace name, except `honcho-logs`, which accepts a workspace name plus optional compose log arguments.

Because the stack is workspace-scoped, the runtime scripts use a workspace name under `HONCHO_BASE_ROOT` rather than arbitrary absolute paths.

## Useful commands

- `./scripts/shared/honcho-build`
- `./scripts/shared/honcho-upgrade`
- `./scripts/shared/honcho-start <workspace-name>`
- `./scripts/shared/honcho-status <workspace-name>`
- `./scripts/shared/honcho-logs <workspace-name> [compose log args...]`
- `./scripts/shared/honcho-shell <workspace-name>`
- `./scripts/shared/honcho-stop <workspace-name>`
- `./scripts/shared/honcho-remove <workspace-name>`

All wrapper scripts support `--help` and document their argument contracts there.

## GitHub setup on Maldoria

This repo is configured to use the repo-specific SSH alias:

- `github-maldoria-honcho-container`

If `git push` says it cannot resolve that hostname, the repo remote is already correct but your host SSH config has not been materialised yet. On Maldoria, run the managed setup from inside this repo:

`/workspace/Development/OpenCode/installations-configurations/scripts/macos/git-configure`

That workflow writes the matching `Host github-maldoria-honcho-container` block into `~/.ssh/config`, exports the public key file `~/.ssh/maldoria-github-ezirius-honcho-container.pub`, and points the repo remote at the alias.

After that, test SSH auth with:

`ssh -T git@github-maldoria-honcho-container`

## Data preservation

`honcho-remove` preserves workspace data directories by default.

The scripts create the workspace root, `honcho-home`, `workspace`, `postgres-data`, and `redis-data` directories automatically. You still need to create the workspace env file yourself at `honcho-home/.env`.

In practice that means:

- editing `honcho-home/.env` or `honcho-home/config.toml` does not require an image rebuild
- stopping and starting the stack is enough for Compose and the Honcho services to pick up the updated runtime config
- rebuilding is only needed when the requested upstream Honcho source changed or when the local wrapper image recipe changed

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

## Verification

Run `tests/shared/test-all.sh` to execute the repository shell checks in one command.
