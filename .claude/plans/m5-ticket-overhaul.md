# StoryBox MVP — M5 Ticket Overhaul Plan

## Goal

Produce a complete, sequenced ticket overhaul plan for the storybox-mvp repository's M5 milestone (and downstream M6 impact). The data model has been realigned to a newly clarified canonical model. Several in-flight tickets target a schema shape that is now wrong and must close, rewrite, or be replaced.

Deliverable: a written plan that, when executed, produces a self-consistent set of GitHub issues (close/rewrite/new), milestones, blocked-by relationships, and project dates such that an implementation agent can pick up the lowest-numbered unblocked ticket and deliver work that fits coherently into the rest of the plan.

This is not a tweak — it's a structural realignment. Half-measures will require another realignment within 1–2 sprints, which is unacceptable.

## Orchestrator vs implementation boundary

Orchestrator work (model docs, design decisions, seed templating, repo housekeeping) has already been done in-session. Do NOT propose tickets for: design spikes, doc updates, the LittleWitch seed file copy, or anything else that's already in the repo. Tickets are for MVP implementation work only — Ash resources, migrations, actions, notifiers, API endpoints, LiveView UI, tests.

## Required reading (in this order)

1. `.claude/model/main.md` — model overview
2. `.claude/model/platonic_model.md` — base model: Component → View → Piece → Task; Working Vocabulary; Pinnable interface; staleness paths
3. `.claude/model/the_story_model.md` — narrative application + MVP Implementation mapping (the target shape)
4. `.claude/workflow.md` — local dev workflow, issue plan template
5. `.claude/plan.md` — current milestone status (note: lists #71/#73 as open but they're closed; treat GitHub as authoritative)
6. `lib/storybox/stories/*.ex` — current Ash resources to be restructured
7. `priv/seeds/little_witch/` — canonical seed reference (orchestrator pre-staged; the seed loader rewrite reads from here)
8. Open issues: `gh issue list --repo StoryBox-io/storybox-mvp --state open --json number,title,milestone,labels,body`

## Current state

Recently landed in M5 (in main, do not undo):

- #74 — Renames: `ScenePiece→ScriptView`, `SceneVersion→ScriptPiece`, `SequencePiece→TreatmentView`, `SequenceVersion→TreatmentPiece`, `SynopsisVersion→SynopsisView`. NOTE: the `SequencePiece→TreatmentView` and `SequenceVersion→TreatmentPiece` direction is now wrong by the new model. Code is in this state; the realignment fixes it.
- #75 — Scene Component entity. `ScriptView belongs_to :scene`, `TreatmentView` (the slot) `many_to_many :scenes` via `TreatmentViewScene`.
- Closed spikes: #70, #71, #72, #73 — partial conclusions feed the new model; several were superseded.

Already in `priv/seeds/little_witch/` (committed):

- The full Little Witch fountain reference: synopsis paragraphs, sequence prose, character profiles, world bible, scene scripts, one intentionally empty scene folder for unresolvable-ScriptView demo.

## Critical drift (the reason for this overhaul)

Compare current code against `.claude/model/the_story_model.md` §"MVP Implementation":

1. Pieces are owned by Views, not Components. `TreatmentPiece belongs_to TreatmentView`, `ScriptPiece belongs_to ScriptView` — both wrong. All Pieces must belong to Components.
2. `TreatmentView` is misnamed — current resource is per-sequence-slot. New model: `TreatmentView` is the Story-wide composition (one logical, many ViewVersions). Slot is replaced by `Sequence` thin entity.
3. `TreatmentPiece` is misnamed — should be `SequencePiece` (Story-owned; references Sequence; carries provenance to source SynopsisPiece).
4. No View/ViewVersion split — current SynopsisView is one row per version. Need split: one logical View row + many ViewVersion rows.
5. No `Sequence` entity — new connector entity (id, story_id, name, slug).
6. No `SequenceView` — script-side per-sequence composition (one per Sequence, Story-owned). ViewVersions' Segments pin Scene ScriptViews.
7. No `Story.ScriptView` — Story-wide assembled screenplay; ViewVersions' Segments pin SequenceViews (one per Sequence).
8. Notifiers #84/#85/#86 hardcode three relationships. New model: single generic computed-staleness mechanism.
9. Tasks not yet implemented. Lean Task primitive (markers polled by agents). Pull #77's intent into M5 since staleness needs Tasks to land coherently.
10. Character/World store content directly. Should be View+Piece pattern.

## Open issues to evaluate

- M5: #69 (epic), #80, #81, #82, #83, #84, #85, #86, #87
- M6: #59, #60, #61, #62, #63, #76, #77, #78

For each: decide close / rewrite / keep, with justification. Rewrites get new bodies per `.claude/workflow.md` §"Issue plan template."

## What the plan must produce

1. Per-ticket disposition table — every open ticket, decision, one-line justification.
2. New tickets — full bodies per workflow template. Must cover at minimum:
   - Schema realignment: drop current TreatmentView slot resource; rename `TreatmentPiece → SequencePiece` (Story-owned); introduce `Sequence` thin entity; refactor ScriptPiece to belong_to Story; add provenance attributes
   - View/ViewVersion split for SynopsisView, TreatmentView, ScriptView (Scene), Story.ScriptView
   - Segment + Pin polymorphic structure (one Pin per Segment; Piece-or-sub-View)
   - SynopsisView blueprint pinning SynopsisPieces by `sequence_id`
   - TreatmentView blueprint pinning SequencePieces by `sequence_id` (new)
   - SequenceView resource (new): one per Sequence, ViewVersions' Segments pin Scene ScriptView versions
   - Story.ScriptView blueprint pinning SequenceViews by `sequence_id`
   - Generic staleness mechanism (computed; replaces #84/#85/#86)
   - Lean Task primitive (pull #77's intent forward, restructured)
   - Character/World View+Piece refactor + API
   - Seed loader rewrite — `seeds.exs` reads from `priv/seeds/little_witch/` (already committed) instead of hardcoding inline content. Walk the directory; parse fountain headers (`Title:`, `Sequence:`, `Source:`); map to new schema (Sequence per unique `Sequence:` header; SynopsisPiece per `synopsis-{seq}-v{N}.fountain`; SequencePiece per `{seq}-v{N}.fountain`; ScriptPiece per `scenes/{slug}/script-v{N}.fountain`; CharacterPiece per `characters/{name}/profile-v{N}.fountain`; WorldPiece per `world/external_world/world-v{N}.fountain`); derive `version_number` from filename; set provenance fields by Sequence-name match; skip empty scenes (e.g., `scenes/ext_ruins_kestrel/.gitkeep`) so they generate Tasks via View resolvability.
3. Milestone structure — propose. Reasonable shapes:
   - Reshape M5 to be the realignment milestone
   - Move incompatible work to M6
   - Consider M5.5 if structural cleanup deserves its own retrospective
   - M6 dates almost certainly shift right
4. Dependency DAG — explicit blocked-by relationships
5. Project board fields per ticket — start date, target date, estimate (days). Today is 2026-04-27. Use the DAG to derive start dates (independent → milestone start; dependent → day after blocker target).
6. Output the plan as one document with these sections:
   1. Executive Summary
   2. Disposition Table
   3. New Tickets (full bodies)
   4. Milestone Structure
   5. Dependency DAG (Mermaid graph TD)
   6. Schedule (per-milestone tables)
   7. Open Questions

## Hard constraints (violating any means another realignment)

1. Pieces are owned by Components — never Views.
2. A View has one perspective — no overloaded Views. If a proposed View pins multiple categories serving different perspectives, split it.
3. One logical View per perspective per Component, many ViewVersions — never collapse logical entity and version into a single row.
4. Sequences are NOT Components — thin connector entities only.
5. Staleness is computed, not stored — two paths: View walk; Piece provenance comparison. No stored stale flag.
6. Tasks are lean markers — record that work is needed + which View is unresolvable, not what work. Append-only. Owned by Components.
7. Pins are polymorphic — Pin holds PieceVersion (resolved as implicit self-view) or sub-ViewVersion. Same code path. No materialized self-view rows.
8. Provenance is per-Piece metadata — SequencePiece has `source_synopsis_piece_id` + `source_version_at_creation`; ScriptPiece has `source_sequence_piece_id` + `source_version_at_creation`. No PieceDependency table.

## Workflow conventions

- Issue plan template: `.claude/workflow.md` §"Issue plan template"
- Test cases as spec: behavior descriptions referencing seed by name
- Pre-commit: `podman-compose run app mix precommit`
- Branch naming: `issue-<N>-<slug>`
- Mermaid for resource hierarchies, sequence diagrams, ERDs, state machines

## Project board (project #3, StoryBox MVP)

| Field | ID | Type |
|---|---|---|
| Start date | `PVTF_lADODn_Yk84BT0ymzhNkuc0` | date |
| Target date | `PVTF_lADODn_Yk84BT0ymzhNkuqE` | date |
| Estimate (days) | `PVTF_lADODn_Yk84BT0ymzhNku2g` | number |

Project #3 node ID: `PVT_kwDODn_Yk84BT0ym`. All issues must be added.
