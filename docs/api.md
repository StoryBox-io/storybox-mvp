# API Spec

The API exposes the story graph for agentic workflows. Agents receive scoped, bounded context — a single sequence with its component dependencies pinned — rather than whole documents.

All endpoints require bearer token authentication.

---

## Views

### Synopsis

```
GET /api/stories/:story_id/views/synopsis
```

Returns the latest synopsis version with metadata.

```json
{
  "story_id": "uuid",
  "version": 2,
  "content": "...",
  "through_lines": ["preference"],
  "inserted_at": "2026-04-06T..."
}
```

---

### Treatment

```
GET /api/stories/:story_id/views/treatment
```

Returns all sequences at their current approved versions with weights and upstream status.

```json
{
  "synopsis_version": 2,
  "sequences": [
    {
      "id": "uuid",
      "title": "Kestrel's Game",
      "act": "Act II",
      "position": 5,
      "approved_version": {
        "version_number": 3,
        "weights": { "preference": 0.9 },
        "upstream_status": "current",
        "status": "approved"
      }
    }
  ]
}
```

```
GET /api/stories/:story_id/views/treatment/sequences/:seq_id
```

Returns a specific sequence piece with its content resolved from MinIO, plus pinned component dependencies (characters, world) for agent context.

```json
{
  "id": "uuid",
  "title": "Kestrel's Game",
  "version_number": 3,
  "content": "...",
  "weights": { "preference": 0.9 },
  "upstream_status": "current",
  "component_context": {
    "characters": [...],
    "world": {...}
  }
}
```

```
GET /api/stories/:story_id/views/treatment/diff?from=synopsis_v1&to=synopsis_v2
```

Returns which sequences are affected by a synopsis change — the only sequences an agent should touch.

```json
{
  "affected": ["uuid", "uuid"],
  "unaffected": ["uuid", "uuid"],
  "new": [],
  "removed": []
}
```

---

### Script

```
GET /api/stories/:story_id/views/script
```

Query params:
- `mode=latest` (default) — highest version of each scene
- `mode=approved` — approved version of each scene
- `mode=snapshot&snapshot_id=uuid` — pinned snapshot

```json
{
  "mode": "approved",
  "scenes": [
    {
      "id": "uuid",
      "sequence_id": "uuid",
      "title": "INT. PRISON CELL - NIGHT",
      "position": 1,
      "version_number": 2,
      "weights": { "preference": 1.0 },
      "upstream_status": "current"
    }
  ]
}
```

```
GET /api/stories/:story_id/views/script/scenes/:scene_id
```

Returns scene content resolved from MinIO.

---

## Writing New Versions

```
POST /api/stories/:story_id/views/treatment/sequences/:seq_id/versions
```

Agent submits a new sequence version. Content is stored to MinIO; version record created with `weights: {}` (unreviewed).

```json
{
  "content": "...",
  "status": "draft"
}
```

```
POST /api/stories/:story_id/views/script/scenes/:scene_id/versions
```

Same pattern for scene versions.

---

## Upstream Status

```
GET /api/stories/:story_id/upstream_changes
```

Returns all unacknowledged upstream changes across the story — what is stale and why.

```json
{
  "changes": [
    {
      "piece_type": "scene",
      "piece_id": "uuid",
      "component_type": "character",
      "component_id": "uuid",
      "changed_at": "2026-04-06T..."
    }
  ]
}
```
