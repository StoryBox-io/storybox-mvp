# Dev Setup

## Prerequisites

- [Podman](https://podman.io/) v5+ (the built-in `podman compose` subcommand replaces the legacy `podman-compose` Python wrapper; commands below pass `-f podman-compose.yml` because the file uses that name rather than the default `compose.yml`)
- (The Elixir app runs inside the container — no local Elixir install needed)

## Start Services

```bash
podman compose -f podman-compose.yml up -d
```

This starts three services:
- **app** — Phoenix on http://localhost:4000
- **db** — PostgreSQL on localhost:5432
- **minio** — S3-compatible storage, API on http://localhost:9000, console on http://localhost:9001

## MinIO Console

http://localhost:9001
- User: `storybox`
- Password: `storybox_secret`

Create a bucket named `storybox-pieces` on first run (or via the setup task once the app is scaffolded).

## Database

```
host:     localhost
port:     5433
database: storybox_dev
user:     storybox
password: storybox
```

> Port 5433 is used on the host to avoid conflict with any local PostgreSQL installation.
> Inside the Podman network, the app container connects to `db:5432` as normal.

## App Setup (once scaffolded)

```bash
podman compose -f podman-compose.yml run app mix setup
podman compose -f podman-compose.yml run app mix phx.server
```

## Environment Variables

Set in `podman-compose.yml`. Override locally by creating a `.env` file (gitignored).

| Variable | Default | Description |
|---|---|---|
| `DATABASE_URL` | `postgres://storybox:storybox@db:5432/storybox_dev` | PostgreSQL connection |
| `MINIO_ENDPOINT` | `http://minio:9000` | MinIO S3 endpoint |
| `MINIO_ACCESS_KEY` | `storybox` | MinIO access key |
| `MINIO_SECRET_KEY` | `storybox_secret` | MinIO secret key |
| `MINIO_BUCKET` | `storybox-pieces` | Bucket for piece files |
| `PHX_HOST` | `localhost` | Phoenix host |
| `SECRET_KEY_BASE` | dev value | Change in production |

## Seeding Dev Data

```bash
podman compose -f podman-compose.yml run --rm app mix run priv/repo/seeds.exs
```

Idempotent — safe to re-run. Creates the dev user and the seeded stories, including a fully-loaded Little Witch.

## Local API Testing

For running a PR's API test plan against the local stack.

- **Base URL**: `http://localhost:4000` (app container `storybox-mvp-app-1`, port 4000)
- **Dev seed account**: `dev@storybox.test` / `Password1!` (created by `priv/repo/seeds.exs`)
- **`POST /api/auth/token`** requires `email`, `password`, **and `story_id`** in the JSON body — tokens are story-scoped, so a token for one story returns 403 on another story's endpoints. The response is `{"token": "..."}`; pass it as `Authorization: Bearer <token>`.
- **Look up story IDs** (the seed assigns fresh UUIDs each run):
  ```bash
  podman exec storybox-mvp-db-1 psql -U storybox -d storybox_dev -t -c "SELECT id, title FROM stories ORDER BY title;"
  ```
- The seeded stories are `Little Witch` (fully populated), `Beneath the Surface`, and `Echo Chamber` — use a second story's token to exercise cross-story 403 checks.
- **Caveat**: write-endpoint tests (`POST .../pieces`) mutate the dev seed (bump Piece versions). Re-run the seed to restore clean state.
