# Data Model

## Ash Resources

### Story
```
id
title
logline
controlling_idea
through_lines:  [:array, :string]   # default ["preference"]
inserted_at
updated_at

has_many :characters
has_many :worlds
has_many :synopsis_versions
has_many :sequence_pieces
has_many :scene_pieces
belongs_to :user
```

### Character
```
id
story_id
name
essence
contradictions
voice
inserted_at

belongs_to :story
```

### World
```
id
story_id
history
rules
subtext
inserted_at

belongs_to :story
```

### SynopsisVersion
```
id
story_id
content_uri:    :string   # storybox://stories/:id/synopsis/v:n
version_number: :integer
inserted_at

belongs_to :story
```

### SequencePiece
```
id
story_id
title
act:            :string   # grouping label only
position:       :integer
approved_version_id

belongs_to :story
has_many :sequence_versions
```

### SequenceVersion
```
id
sequence_piece_id
content_uri:      :string    # storybox://stories/:id/sequences/:seq_id/v:n
version_number:   :integer
weights:          :map        # %{"preference" => 0.9} — empty = unreviewed
upstream_status:  :atom       # :current | :stale
inserted_at

belongs_to :sequence_piece
has_many :upstream_changes
```

### ScenePiece
```
id
story_id
sequence_piece_id
title
position:           :integer
approved_version_id

belongs_to :story
belongs_to :sequence_piece
has_many :scene_versions
```

### SceneVersion
```
id
scene_piece_id
content_uri:      :string   # storybox://stories/:id/scenes/:scene_id/v:n
version_number:   :integer
weights:          :map       # %{"preference" => 0.9} — empty = unreviewed
upstream_status:  :atom      # :current | :stale
inserted_at

belongs_to :scene_piece
has_many :upstream_changes
```

### ScriptSnapshot
```
id
story_id
name:    :string
entries: :map   # %{scene_piece_id => scene_version_id}
inserted_at

belongs_to :story
```

### UpstreamChange
```
id
piece_version_id
piece_version_type:       :string   # "sequence" | "scene"
component_type:           :string   # "story" | "character" | "world" | "synopsis"
component_id:             :uuid
component_version_before: :integer
component_version_after:  :integer
acknowledged:             :boolean  # true once user has seen and acted on it
inserted_at
```

---

## Derived States

**Review status** (derived from `weights` vs `story.through_lines`):
```
:unreviewed         # weights is empty
:reviewed           # has weights for all story through_lines
```

**Upstream status** (stored on version):
```
:current   # no unacknowledged upstream changes
:stale     # has unacknowledged UpstreamChanges
```

---

## Tags

Tags are named pointers on a Piece to a specific version. They are how views align to a particular state of a piece.

**`approved_version_id`** (on SequencePiece and ScenePiece):
- Points to the version considered approved for the `:approved` view
- Updated by the `:approve_version` action
- A piece may have no approved version (pointer is nil)

Publishing is not a separate state. Every version that exists is available. The `:approved` view assembles from approved pointers; `:latest` resolves to the highest version number. A `:snapshot` captures a named map of `piece_id → version_id` at a point in time.

---

## Storage Split

| Data | Store |
|---|---|
| All resource metadata | PostgreSQL |
| Piece content (.fountain files) | MinIO (S3) via URI |

Content URIs follow the pattern `storybox://stories/:story_id/:type/:id/v:n` and resolve to MinIO object paths. This abstraction prepares for the eventual hub/spoke model where content URIs resolve to local Spoke storage.

---

## Key Actions (Ash Custom Actions)

**`:create_version`** on SequencePiece / ScenePiece
- Stores content to MinIO, gets URI back
- Creates new immutable version record
- Sets `upstream_status: :current`, `weights: %{}`

**`:approve_version`** on SequencePiece / ScenePiece
- Updates `approved_version_id` to the given version
- Optionally sets `weights: %{"preference" => 1.0}` if not already reviewed

**`:propagate_change`** — triggered when Story, Character, or World is updated
- Walks downstream dependency graph
- Creates `UpstreamChange` records on all affected piece versions
- Sets `upstream_status: :stale` on those versions
