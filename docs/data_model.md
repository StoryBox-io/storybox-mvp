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
has_many :synopsis_views
has_many :treatment_views
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

### SynopsisView
```
id
story_id
content_uri:    :string   # storybox://stories/:id/synopsis/v:n
version_number: :integer
inserted_at

belongs_to :story
```

### TreatmentView
```
id
story_id
title
act:            :string   # grouping label only
position:       :integer
approved_version_id

belongs_to :story
has_many :treatment_pieces
has_many :script_views
```

### TreatmentPiece
```
id
treatment_view_id
content_uri:      :string    # storybox://stories/:id/sequences/:view_id/v:n
version_number:   :integer
weights:          :map        # %{"preference" => 0.9} — empty = unreviewed
upstream_status:  :atom       # :current | :stale
inserted_at

belongs_to :treatment_view
has_many :upstream_changes
```

### ScriptView
```
id
treatment_view_id
title
position:           :integer
approved_version_id

belongs_to :treatment_view
has_many :script_pieces
```

### ScriptPiece
```
id
script_view_id
content_uri:      :string   # storybox://stories/:id/scenes/:view_id/v:n
version_number:   :integer
weights:          :map       # %{"preference" => 0.9} — empty = unreviewed
upstream_status:  :atom      # :current | :stale
inserted_at

belongs_to :script_view
has_many :upstream_changes
```

### ScriptSnapshot
```
id
story_id
name:    :string
entries: :map   # %{script_view_id => script_piece_id}
inserted_at

belongs_to :story
```

### UpstreamChange
```
id
piece_version_id
piece_version_type:       :atom     # :treatment_piece | :script_piece
component_type:           :atom     # :story | :character | :world
component_id:             :uuid
version_before:           :string
version_after:            :string
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

Tags are named pointers on a View to a specific piece. They are how views align to a particular state of a piece.

**`approved_version_id`** (on TreatmentView and ScriptView):
- Points to the piece considered approved for the `:approved` view
- Updated by the `:approve_version` action
- A view may have no approved piece (pointer is nil)

Publishing is not a separate state. Every piece that exists is available. The `:approved` view assembles from approved pointers; `:latest` resolves to the highest version number. A `:snapshot` captures a named map of `view_id → piece_id` at a point in time.

---

## Storage Split

| Data | Store |
|---|---|
| All resource metadata | PostgreSQL |
| Piece content (.fountain files) | MinIO (S3) via URI |

Content URIs follow the pattern `storybox://stories/:story_id/:type/:id/v:n` and resolve to MinIO object paths. This abstraction prepares for the eventual hub/spoke model where content URIs resolve to local Spoke storage.

---

## Key Actions (Ash Custom Actions)

**`:create_version`** on TreatmentView / ScriptView
- Stores content to MinIO, gets URI back
- Creates new immutable piece record (TreatmentPiece / ScriptPiece)
- Sets `upstream_status: :current`, `weights: %{}`

**`:approve_version`** on TreatmentView / ScriptView
- Updates `approved_version_id` to the given piece
- Optionally sets `weights: %{"preference" => 1.0}` if not already reviewed

**`:propagate_change`** — triggered when Story, Character, or World is updated
- Walks downstream dependency graph
- Creates `UpstreamChange` records on all affected pieces
- Sets `upstream_status: :stale` on those pieces
