# Dev Setup

## Prerequisites

- [Podman](https://podman.io/) + podman-compose
- (The Elixir app runs inside the container — no local Elixir install needed)

## Start Services

```bash
podman-compose up -d
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
podman-compose run app mix setup
podman-compose run app mix phx.server
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
