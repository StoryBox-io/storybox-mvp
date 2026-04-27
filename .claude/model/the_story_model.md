# The Story Model

> Mirrored from `pandaChest/projects/development/storybox/model/story_model/the_story_model.md` — see [README.md](README.md) for sync notes.

A story is built in layers. Each layer is a view of the same material at a different resolution.

---

## Components

Story, Character, World, and Scene are the four core **Components** — modular, independently evolving creative ideals. Each is an evolving ideal — not a fixed form, but a living creative intention that exists through and grows with its manifestations. A Character exists independent of any single story that borrows them; a World can underpin multiple stories set in the same universe.

*For the full philosophical grounding see [platonic_model.md](platonic_model.md).*

**Story** — the superobjective. Controlling idea, logline, title. Everything else is accountable to it.

**Character** — essence, contradictions, voice. Exists independently of any story. Reusable across projects.

**World** — the field of forces. History, rules, physical conditions — the logic that makes the Story's conflicts necessary and its resolutions meaningful. Exists before any particular story begins and can participate in many. In the MVP, represented as a single world bible View.

**Scene** — dramatic function and role slots. The most abstract Component — a pattern rather than a thing. Character-agnostic: a Scene template defines what a dramatic action requires (roles, beats, function) without specifying who fills the roles. Characters are injected at instantiation.

---

## Through-Lines

Every Component carries a **through-line** — a guide that biases how Views should manifest it. Through-lines are evaluation criteria, not data inputs. They score sequences against an expected shape; they don't assemble into Views.

| Component | Through-line | Scope |
|---|---|---|
| Story | Beat schema (Syd Field, Hero's Journey, etc.) | All sequences |
| Character | Arc | Every sequence they appear in |
| World | State progression | World context across all sequences |
| Scene | Dramatic function | How the template is instantiated |

A single sequence is evaluated against all through-lines that apply to it simultaneously. When through-lines conflict — character arc wants one thing, beat schema wants another — that is where editorial judgment lives.

**Sub-stories and subplots** follow the same pattern: a nested Story Component with its own beat schema, applied to the subset of sequences it runs through.

---

## Acts and Sequences

An **act** is a major phase of the story, defined by the turning points that bookend it. Acts are grouping labels (a string field on `Sequence`), not entities.

A **sequence** is a series of scenes unified by a single dramatic question, with its own mini beginning, middle, and end. "Kestrel's Game" is a sequence: *will Kestrel successfully manipulate Fleur?*

**A sequence is not a Component.** It is a thin connector entity — a `Sequence` row that gives a logical sequence stable identity across the views and pieces that reference it. A `Sequence` carries identity-level metadata only:

- `id`, `story_id`, `name`, `slug`
- (no content, no version history of its own, no Views or Pieces owned)

A sequence appears as a Segment in multiple ViewVersions, all referencing the same `Sequence` row by `sequence_id`:

- In `SynopsisView`: a Segment with `sequence_id = X`, Pin → `SynopsisPiece` for that sequence (one paragraph)
- In `TreatmentView`: a Segment with `sequence_id = X`, Pin → `SequencePiece` for that sequence (dramatic prose)
- In `Story.ScriptView`: a Segment with `sequence_id = X`, Pin → `SequenceView` for that sequence (the scenes in order)

Reordering a sequence = reordering its Segments in a new ViewVersion. Cutting a sequence = removing the relevant Segments from new ViewVersions (the `Sequence` row and old ViewVersions preserve the cut sequence's history).

Turning points (Syd Field) are Segment-level metadata on the relevant ViewVersion's Segments, tagging which Segment functions as the hinge between acts.

---

## Views — by Component

Each View is owned by one Component and carries one perspective. Per the design rule, a View must have a singular vantage point — overloaded Views are split.

### Story Views

`Story` owns three Story-wide Views, each one logical instance with many ViewVersions:

- **`SynopsisView`** — Story at sequence resolution. ViewVersion's Segments pin one `SynopsisPiece` per Sequence (one paragraph each). Shaped by Story, Character, and World through-lines simultaneously.
- **`TreatmentView`** — Story at sequence resolution, prose-only. ViewVersion's Segments pin one `SequencePiece` per Sequence (the dramatic prose for that sequence). Pure prose composition; does not pin scenes.
- **`Story.ScriptView`** — Story at action resolution: the assembled screenplay. ViewVersion's Segments pin one `SequenceView` per Sequence. Sequence ordering snapshotted from `TreatmentView` at the time the blueprint is cut.

Story also owns one **`SequenceView`** per `Sequence` (script-side per-sequence composition). ViewVersion's Segments pin Scene `ScriptView` versions in order — the scenes that play out the sequence. SequenceView holds `sequence_id` so it can be addressed as "the SequenceView for sequence X."

### Scene Views

`Scene` owns one **`ScriptView`**. ViewVersion's Segments typically pin a single `ScriptPiece` (the fountain content for that scene). Multi-Pin SceneScriptViews are possible (e.g., scene-with-overlay) but not used in the MVP.

### Character Views

`Character` owns one **`CharacterView`**. ViewVersion typically pins a single `CharacterPiece` (essence, voice, contradictions). Single-Pin in the MVP.

### World Views

`World` owns one **`WorldView`**. ViewVersion typically pins a single `WorldPiece` (history, rules, physical conditions). Single-Pin in the MVP.

---

## Dependency Direction and Version Tracking

Changes propagate **top-down only**. You interface at the top (synopsis) and refinements flow down (sequence prose, scene scripts).

### Provenance

Downstream Pieces carry light provenance attributes naming the upstream Piece they were derived from, including the upstream version pinned at creation time:

- `SequencePiece` carries `source_synopsis_piece_id` + `source_version_at_creation`
- `ScriptPiece` carries `source_sequence_piece_id` + `source_version_at_creation`

Provenance is per-Piece metadata, not a generalized dependency graph.

### Staleness

Computed, not stored. Two paths:

1. **View staleness** — a ViewVersion is stale when one of its Pin references is older than the latest version of that referent.
2. **Piece staleness via provenance** — a Piece is stale when its source Piece's latest version is greater than its `source_version_at_creation`.

When a SynopsisPiece advances, only the matching SequencePiece (via provenance) goes stale. Other sequences are untouched. Same chain runs from SequencePiece down to ScriptPieces. Staleness triggers a `:refinement` Task; the creator decides whether to refine, supersede, or accept divergence.

### Re-pin, not rewrite

A new ViewVersion is a re-pin, not a rewrite. The `TreatmentView v_n+1` blueprint may keep most Segment Pins from `v_n` unchanged and update only the affected ones. Cut sequences are not deleted — they remain in older ViewVersions, just absent from the new one. Pieces are immutable and persist regardless.

```
TreatmentView v3 (blueprint):
  segments (ordered by position, grouped by act_label):
    Act I:
      segment 1 → sequence_id: Prologue,        pin: SequencePiece "Prologue"  v2  (refined after synopsis change)
      segment 2 → sequence_id: Cottage,         pin: SequencePiece "Cottage"   v2
    Act III:
      segment 6 → sequence_id: Fire,            pin: SequencePiece "Fire"          v1  (untouched — prior pin preserved)
      segment 7 → sequence_id: KestrelChoice,   pin: SequencePiece "Kestrel Choice" v1
```

This is what prevents good work from being overwritten when upstream changes are made. Only sequences touched by an upstream diff are candidates for refinement; the rest are preserved by their existing pins in older ViewVersions.

---

## Assembly

Each View is a composition of Pin references at a specific resolution. The Component is the evolving ideal; the View is the perspective on it; the ViewVersion is an immutable blueprint snapshot of that perspective.

**Component → View → Piece → Task** applies at every layer (see [platonic_model.md](platonic_model.md) §"Working Vocabulary" for the full primitive set):

- **Component** — the evolving ideal (Story, Scene, Character, World). Owns Views, Pieces, Tasks.
- **View / ViewVersion** — perspective at a specific resolution. One logical View per perspective per Component, with many immutable ViewVersions over time.
- **Piece / PieceVersion** — content (SynopsisPiece, SequencePiece, ScriptPiece, etc.). Owned by a Component, immutable once written, versioned, may carry provenance attributes.
- **Segment + Pin** — within a ViewVersion: a Segment is an ordered position; a Pin is its polymorphic reference (to a PieceVersion or another ViewVersion).
- **Task** — a marker for work needed to make a View resolvable. Owned by the Component whose View needs the work.

In addition, the Story Model uses one **non-Component** entity:

- **`Sequence`** — thin connector. Stable identity for a logical sequence; referenced by `SynopsisPiece`, `SequencePiece`, `SequenceView`, and the relevant Story-Wide ViewVersions' Segments. Not a Component (owns no Views/Pieces/Tasks).

---

## MVP Implementation (storybox-mvp)

The MVP implements the narrative layer. Resource names align with the Working Vocabulary ([platonic_model.md](platonic_model.md)).

### Components

Components own their Views, Pieces, and Tasks.

| Component | Resource | Owns |
|---|---|---|
| Story | `Story` | SynopsisPieces, SequencePieces, ScriptPieces, SynopsisView, TreatmentView, Story.ScriptView, SequenceViews, Sequences, Tasks, Scenes, Characters, World |
| Scene | `Scene` | ScriptView |
| Character | `Character` | CharacterView, CharacterPieces |
| World | `World` | WorldView, WorldPieces |

### Sequence (thin connector — not a Component)

| Resource | Fields | Role |
|---|---|---|
| `Sequence` | `id`, `story_id`, `name`, `slug` | Stable identity for a logical sequence. Referenced by `SynopsisPiece`, `SequencePiece`, `SequenceView`, and the Story-wide ViewVersions' Segments via `sequence_id`. |

### Pieces (content)

All Pieces belong to a Component. All carry `version_number` and tag state. Provenance attributes link downstream Pieces to upstream sources.

| Piece | Resource | Owner | Provenance |
|---|---|---|---|
| Synopsis paragraph | `SynopsisPiece` | Story | none (top of chain) |
| Sequence dramatic prose | `SequencePiece` | Story | `source_synopsis_piece_id` + `source_version_at_creation` |
| Scene script (fountain) | `ScriptPiece` | Story (portable; hung onto a Scene via ScriptView Pin) | `source_sequence_piece_id` + `source_version_at_creation` |
| Character profile content | `CharacterPiece` | Character | none |
| World bible content | `WorldPiece` | World | none |

`SynopsisPiece` and `SequencePiece` carry a `sequence_id` FK identifying which logical Sequence they're for. `ScriptPiece` is Story-scoped and not bound to a Sequence at the Piece level — its association comes from the `SequenceView` that pins it.

### Views (compositions)

Each View is one logical entity per perspective per Component, with many immutable ViewVersions. Each ViewVersion has ordered Segments; each Segment carries a Pin.

| View | Resource | Owner | What its ViewVersion's Segments pin |
|---|---|---|---|
| Synopsis | `SynopsisView` | Story (one) | one `SynopsisPiece` per Segment, keyed by `sequence_id` |
| Treatment | `TreatmentView` | Story (one) | one `SequencePiece` per Segment, keyed by `sequence_id` (prose only — no scenes) |
| Assembled Screenplay | `Story.ScriptView` | Story (one) | one `SequenceView` per Segment, keyed by `sequence_id`; Sequence ordering snapshotted from `TreatmentView` at cut time |
| Sequence Script Composition | `SequenceView` | Story (one per `Sequence`) | ordered Scene `ScriptView` Pins (the scenes that play out the sequence) |
| Scene Script | `ScriptView` | Scene (one) | typically one `ScriptPiece` (single-Pin View) |
| Character Profile | `CharacterView` | Character (one) | typically one `CharacterPiece` (single-Pin View) |
| World Bible | `WorldView` | World (one) | typically one `WorldPiece` (single-Pin View) |

### Tasks

`Task` is a lean marker:

| Field | Type | Notes |
|---|---|---|
| `id` | uuid | |
| `component_type` | atom | `:story`, `:scene`, `:character`, `:world` |
| `component_id` | uuid | Owner Component |
| `target_view_id` | uuid | The unresolvable View |
| `target_view_version_id` | uuid | The specific ViewVersion that's unresolvable |
| `type` | atom | `:creation`, `:refinement`, `:review` |
| `status` | atom | `:pending`, `:in_progress`, `:complete` |
| `triggered_by_piece_id` | uuid (nullable) | The upstream Piece whose change generated this Task (for refinements) |
| `triggered_by_piece_version` | integer (nullable) | The version of the upstream Piece at trigger time |

Tasks are append-only. A new trigger (e.g., upstream change after completion) generates a new Task; the original stays as historical record. Agents poll `GET /api/tasks?status=pending` and evaluate the target View at execution time.

### Staleness

Computed, not stored. Two paths:

1. **View staleness** — a ViewVersion is stale when one of its Pin references is older than the latest version of that referent.
2. **Piece staleness via provenance** — a Piece is stale when its source's latest version is greater than its `source_version_at_creation`.

Either condition surfaces a `:refinement` Task on the affected Component.

---

## Story as Control Net / Scene as Generative Piece

The Story Component — through its `SynopsisView`, `TreatmentView`, and through-lines — functions as a **control net**: it defines the dramatic shape, the positive and negative charges the story must hit, and the scoring criteria that evaluate whether a Scene serves the story's intent. It constrains the generative space without prescribing it.

Scenes are the **generative pieces** — modular, reusable. Many `ScriptPieces` can exist for the same beat; most won't make the cut. A single sequence might be served by three candidate Scenes; only one (or a chosen subset, in chosen order) gets pinned into the `SequenceView` blueprint at a given ViewVersion. Scenes are portable: a Scene Component that earns its place in one Story can be referenced from another.

**Approval lives in the ViewVersion, not on the Piece.** A `ScriptPiece` carries a tag state (`:unreviewed`, `:approved`, etc.), but endorsement of that Piece for a specific Story lives in the `SequenceView` ViewVersion that pins it (and transitively the `Story.ScriptView` ViewVersion that pins the SequenceView). The same `ScriptPiece` can be approved in Story A's assembly and unreviewed in Story B's — the tag records production state; the ViewVersion records curatorial intent.

---

*See also: [platonic_model.md](platonic_model.md) — base model*
