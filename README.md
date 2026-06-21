# StoryBox MVP

A story project manager with a versioned story graph and an agentic HTTP API. This is a
Phoenix/Ash application and **one instance** of the StoryBox story model — the model itself
is maintained as a separate living spec and is out of scope for this README, which covers
working *in this codebase*.

## Tech stack

- **Elixir / Phoenix + LiveView** — application and web UI
- **Ash 3 / AshPostgres 2** — domain modelling, resources, and the PostgreSQL data layer
- **AshAuthentication** — user accounts and story-scoped API tokens
- **PostgreSQL** — structural metadata
- **MinIO** — S3-compatible object storage for piece content, referenced by URI
- **Podman** — containerised dev environment

## Architecture (as-built)

Two Ash domains (`config :storybox, ash_domains: [...]`):

- **`Storybox.Accounts`** — users and authentication.
- **`Storybox.Stories`** — the story graph; resources in `lib/storybox/stories/` (`Story`,
  `Character`/`World`/`Scene` with their `*View` / `*ViewVersion` / `*Piece` resources,
  `Sequence`, `Segment`, the synopsis/treatment/script views, and `Task`), with cross-cutting
  logic alongside (`staleness.ex`, `task_generation.ex`, `changes/`).

Layers:

- **Data layer** — Ash resources over PostgreSQL via AshPostgres; schema is defined on the
  resources (see [AGENTS.md](AGENTS.md) for the resource/migration workflow).
- **Content storage** — piece bodies live in MinIO, referenced from Postgres by URI
  (`lib/storybox/storage.ex`); the database holds structure and metadata only.
- **Web layer** — `StoryboxWeb`: a JSON API (`controllers/api_controller.ex`) for agentic
  workflows, plus LiveView screens (`StoryListLive`, `StoryOverviewLive`) as a viewer.

## Dev setup & running

Containerised with Podman — see **[docs/dev_setup.md](docs/dev_setup.md)** for full
instructions (services, ports, env vars, seeding, local API testing). In short:

```bash
podman compose -f podman-compose.yml up -d                                    # app :4000, db, minio
podman compose -f podman-compose.yml run --rm app mix run priv/repo/seeds.exs
```

## Build & test

```bash
podman compose -f podman-compose.yml run --rm -e MIX_ENV=test app mix precommit
```

`mix precommit` runs compile (warnings-as-errors), `ash_postgres.generate_migrations --check`,
unused-deps check, format, and the test suite. The `MIX_ENV=test` override is required in the
Podman dev env (the `app` service pins `MIX_ENV=dev`).

## API surface

A story-scoped JSON API for agentic authoring, under `/api` (authoritative routes:
`lib/storybox_web/router.ex`):

- **Auth** — `POST /api/auth/token` issues a story-scoped bearer token (`email`, `password`, `story_id`).
- **Reads** — resolved `GET .../views/synopsis` and `.../views/script`; characters; world; task list.
- **View cuts** — `POST .../views/{synopsis,treatment,story_script}/cut`,
  `.../sequences/:seq_id/views/sequence/cut`, `.../scenes/:scene_id/views/script/cut`.
- **Piece writes** — new versions of scene, character, and world pieces.
- **Tasks & weights** — advance tasks (`in_progress` / `complete`); set sequence / script-piece weights.

Every `/api/stories/:story_id/*` route requires the bearer token and is scoped to that story
(a token for one story returns 403 on another).

## Scope

This codebase deliberately excludes the hub/spoke distributed architecture, multi-user
collaboration/propagation, DCC integrations, and a CG asset pipeline.

## Conventions

Contributor and agent conventions — branch naming, the precommit gate, the Ash
resource/migration workflow, and the Phoenix/LiveView rules — live in **[AGENTS.md](AGENTS.md)**.
