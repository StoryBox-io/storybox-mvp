# StoryBox MVP

A story project manager with versioned components, dependency tracking, and an agentic API.

This MVP validates the StoryBox story model before building the full hub/spoke platform. It is deliberately scoped: no spoke architecture, no distributed storage, no multi-tenant propagation. Those emerge from what is learned here.

---

## What It Does

StoryBox organises a story as a graph of versioned, interdependent components. Changes at the top propagate down. Every piece of content is versioned and reviewed. An API exposes the story graph to agentic workflows so agents work on bounded, scoped pieces rather than whole documents.

---

## The Story Model

Four core **Components** — modular, independently versioned, reusable across stories:

| Component | Contains | Through-line |
|---|---|---|
| **Story** | Controlling idea · Logline · Title | Beat schema — biases all sequences |
| **Character** | Essence · Contradictions · Voice | Arc — biases sequences they appear in |
| **World** | History · Rules · Subtext | State progression — biases world context |
| **Scene** | Dramatic function · Role slots | Dramatic function — biases instantiation |

Three **Views** — assemblies of components at increasing resolution:

```
Synopsis    →  story at sequence resolution (one paragraph per sequence)
Treatment   →  one versioned piece per sequence
Script      →  sequences broken into scenes (each scene versioned)
```

Changes flow **top-down only**. A synopsis change diffs against the previous version — only affected sequences become candidates for update. Unaffected sequences keep their current version untouched.

---

## Versioning Model

Every piece of content (sequence, scene) is versioned using append-only versions. No version is ever deleted.

**Scene has an approved marker** pointing to one of its versions. Versions can be added freely; moving approval is just updating the pointer.

**Script views:**
- `:latest` — dynamically resolves to the highest version of each scene
- `:approved` — assembles from each scene's approved version
- `:snapshot` — a saved, named map of scene → pinned version (a discrete mixture)

---

## Review and Weights

Every piece version has a `weights` map. A new version starts unreviewed (`weights: {}`). Once a weight is applied it is reviewed.

```
weights: %{"preference" => 0.9}
```

For MVP, one through-line weight: `preference` (0.0–1.0). A weight of 1.0 signals maximum protection — do not overwrite this. Additional through-lines (super objective alignment, character arc) will be added as the model matures.

**Upstream status** is tracked separately from review status. When an upstream component changes (e.g. controlling idea updated), all downstream piece versions are flagged `:stale` with a record of what changed. This is independent of whether the piece has been reviewed.

---

## Storage

| Store | Contains |
|---|---|
| **PostgreSQL** | All metadata — story structure, versions, weights, upstream changes, approved markers |
| **MinIO (S3)** | Piece content — raw `.fountain` files referenced by URI |

Piece content is referenced by URI: `storybox://stories/:id/sequences/:seq_id/v3`. This abstraction is designed for the eventual hub/spoke model where content moves to local Spoke storage.

---

## API

Exposes the story graph for agentic workflows. Agents query scoped slices rather than whole documents.

```
GET  /api/stories/:id/views/synopsis
GET  /api/stories/:id/views/treatment
GET  /api/stories/:id/views/treatment/sequences/:seq_id
GET  /api/stories/:id/views/treatment/diff?from=synopsis_v1&to=synopsis_v2
GET  /api/stories/:id/views/script
GET  /api/stories/:id/views/script/scenes/:scene_id
POST /api/stories/:id/views/treatment/sequences/:seq_id/versions
POST /api/stories/:id/views/script/scenes/:scene_id/versions
```

---

## Tech Stack

- **Elixir / Phoenix + LiveView** — application and UI
- **Ash Framework** — declarative resources, dependency graph, custom actions
- **PostgreSQL** — metadata store
- **MinIO** — S3-compatible local object storage for piece files
- **Podman** — containerised dev environment

---

## Dev Setup

```bash
podman-compose up -d
```

Services: `app` (Phoenix on :4000), `db` (PostgreSQL on :5432), `minio` (S3 on :9000, console on :9001).

See [docs/dev_setup.md](docs/dev_setup.md) for full setup instructions.

---

## What This MVP Is Not

- No hub/spoke distributed architecture
- No multi-user collaboration or piece propagation
- No DCC integrations
- No CG asset pipeline

These are deferred. The MVP validates the story model and agentic workflow before the platform is built around it.

---

## Docs

- [Story Model](docs/story_model.md)
- [Data Model](docs/data_model.md)
- [API Spec](docs/api.md)
- [Dev Setup](docs/dev_setup.md)
