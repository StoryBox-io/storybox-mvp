# OTIO Design Insights
_Session: 2026-05-03_

## Prompt

> Since we are starting to get into the weeds on editorial and cut order, are there any insights we can take from a project like OpenTimelineIO?

---

## OTIO Data Model (for reference)

OTIO's hierarchy: **Timeline → Stack → Track → (Clip | Gap | Transition)**

- **Stack** — parallel layers rendered simultaneously (alpha composite for video, additive for audio)
- **Track** — a sequential container of items; has a `kind` (Video or Audio)
- **Clip** — a single item referencing source media via a `MediaReference`; has a `source_range` (in/out points into the media)
- **Gap** — explicit empty time (black frames, silence); a first-class object with a duration
- **Transition** — blend between two adjacent clips; has `in_offset` / `out_offset`
- **MediaReference** — what a Clip points to: `target_url` + `available_range` (total media duration)
- **RationalTime** — all time is `(value, rate)` — frame-accurate, rate-agnostic

OTIO has no native versioning. It is a snapshot format. Versioning is external (file system, asset management).

---

## Storybox ↔ OTIO Mapping

| OTIO | Storybox equivalent |
|---|---|
| Timeline | Story |
| Stack | — (no parallel layers yet) |
| Track | ViewVersion (TreatmentVV, SequenceVV, etc.) |
| Clip | Segment with a pin |
| Gap | Segment with nil pin (implicit) |
| Transition | — (not modeled) |
| MediaReference | `pin_id` + `pin_type` |
| `source_range` | — (no in/out points) |
| `available_range` | — (no media duration) |
| RationalTime | — (position integer, not time) |

---

## Insights

### 1. Order-based vs time-based — we are at the right level

OTIO is time-based. Storybox is order-based (position integers). For pre-production story structure this is correct — at the authoring stage you're deciding *what order* beats and scenes occur, not *how long* each one is. OTIO is the production-side handoff format, not the authoring format. The gap between the two is intentional.

### 2. Gap is implicit in storybox; OTIO makes it explicit

In OTIO a Gap is a first-class object with a known duration. In storybox a nil-pin Segment is the equivalent — but it carries no duration. This is fine for now. The consequence is: if we ever export to OTIO, nil-pin segments become Gaps, and we will need a duration from somewhere (the media file, or an estimated beat length). Worth flagging as a future bridge concern, not something to solve in MVP.

### 3. Versioning is our differentiator over OTIO

OTIO has no versioning concept inside the format itself. Our `version_number` + `pin_version_at_creation` + staleness detection is genuinely more powerful for the authoring phase. OTIO snaps a moment; storybox tracks the lineage of a cut. When we eventually build an OTIO export, the latest ViewVersion becomes the OTIO Timeline — the version history stays in storybox.

### 4. Stack (parallel tracks) — not needed for story structure, but relevant later

OTIO's Stack is how you model multi-track compositions: video layer over temp music over dialogue. Storybox has no parallel track concept — ViewVersions are single ordered lists. This is correct for the story-structure layer. It would become relevant if storybox ever wants to model a scene as having simultaneous tracks (e.g., rough animatic + temp audio + script annotation). Not in scope for MVP; worth knowing the gap exists.

### 5. source_range — we pin the whole ViewVersion, not a sub-range

OTIO Clips have `source_range` (in/out points into the source). Storybox pins a whole ViewVersion — there is no concept of "use frames 10–50 of this ScriptViewVersion." For pre-production this is fine. If storybox ever needs to support trimmed cuts (e.g., a scene is too long, you want to mark a preferred section), `source_range` would be the concept to borrow.

### 6. The OTIO export path is clear when we need it

When storybox needs to hand off to an NLE:
- SequenceViewVersion → OTIO Track (Video)
- Each pinned Segment → OTIO Clip (MediaReference = rendered media for that ScriptViewVersion)
- Nil-pin Segment → OTIO Gap (duration = unknown, needs resolution)
- StoryScriptViewVersion → OTIO Timeline containing one Track per Sequence

The main blocker for that bridge is duration data — storybox has no durations today.

### 7. The rough-to-fine principle maps to OTIO derivation

OTIO supports nested compositions (a Track inside a Stack inside another Track). Our rough-to-fine hierarchy (Synopsis → Treatment → Sequence → Script) achieves something similar — each level adds specificity. The difference is ours is a *derivation chain with pinned versions*, whereas OTIO nesting is structural containment. Both express "this thing is made of smaller things."

---

## Open design questions raised by this comparison

1. **Should we ever add duration to Segments or ViewVersions?** Not for MVP, but the OTIO bridge will require it eventually. A `duration_frames` attribute on Segment (nullable) would be the minimal addition.

2. **Should nil-pin Segments be renamed or typed as "gaps"?** Currently an unresolvable Segment and a genuine gap look identical. If gaps become semantically meaningful (placeholder beat vs intentionally empty), we may want a `gap_type` attribute or a separate Segment kind.

3. **Parallel tracks**: if storybox ever models "this sequence has a temp music track alongside the animatic," what is the data model? A second ViewVersion type? A new Track concept inside ViewVersion? Not urgent but worth parking.
