# Little Witch

**Controlling Idea**: True power is earned through hard work. There are no shortcuts. There is no gift.

**Status**: V5 working draft

---

## Folder Structure

This repo is a direct representation of the StoryBox model — each folder is a Component entity, each file is a Piece belonging to that entity. Views (SynopsisView, TreatmentView, ScriptView) are defined in the data model, not the file structure.

```
LittleWitch/
├── synopsis-{sequence}-v{N}.fountain   SynopsisPiece — one paragraph per sequence
├── {sequence}-v{N}.fountain            SequencePiece — dramatic prose for one sequence
│
├── characters/
│   └── {name}/
│       └── profile-v{N}.fountain       CharacterPiece
│
├── world/
│   └── external_world/
│       └── world-v{N}.fountain         WorldPiece
│
└── scenes/
    └── {scene_slug}/
        └── script-v{N}.fountain        ScriptPiece
```

**Pieces live flat under their Component** — no `treatment/` or `pieces/` wrapper folders. Synopsis, Treatment, and Script are Views; their pieces belong to the Story or Scene Component directly. The `Sequence` entity (id + name) is a thin connector that gives a logical sequence stable identity across pieces and views.

---

## Sequences

Each row is a `Sequence` entity. SynopsisPiece and SequencePiece both reference the Sequence by `sequence_id`.

| # | Sequence | Act | SequencePiece | SynopsisPiece |
|---|---|---|---|---|
| 1 | Prologue | — | prologue-v1.fountain | synopsis-prologue-v1.fountain |
| 2 | The Cottage | I | cottage-v1.fountain | synopsis-cottage-v1.fountain |
| 3 | The Summoning | I | summoning-v1.fountain | synopsis-summoning-v1.fountain |
| 4 | Settling — Silas's Way | II | settling-v1.fountain | synopsis-settling-v1.fountain |
| 5 | Kestrel's Game | II | kestrel_game-v1.fountain | synopsis-kestrel_game-v1.fountain |
| 6 | The Tug of War | II | tugowar-v1.fountain | synopsis-tugowar-v1.fountain |
| 7 | Reckoning — Kestrel's Choice | III | reckoning-v2.fountain *(latest)* | synopsis-reckoning-v1.fountain |

`reckoning-v1.fountain` is the earlier draft — kept to demonstrate versioning and staleness in seed data.

---

## Scenes (ScriptViews)

| Scene | Sequence | Script Piece | State |
|---|---|---|---|
| int_cottage_night | Summoning | script-v1.fountain | approved |
| ext_cottage_night | Summoning | script-v1.fountain | approved |
| ext_ruins_dawn | Summoning | script-v1.fountain | approved |
| ext_coronation_fire | Reckoning | script-v1.fountain | approved |
| ext_ruins_kestrel | Reckoning | *(none)* | unresolvable → Task |

The empty `scenes/ext_ruins_kestrel/` directory demonstrates an unresolvable ScriptView — no ScriptPiece exists, which should generate a Task in the StoryBox model.

---

## Characters

Fleur · Kestrel · Silas · Flame Demon · Alderman

Each has a `profile-v{N}.fountain` in their character subfolder.

---

*See the StoryBox model docs for the model this structure represents.*
