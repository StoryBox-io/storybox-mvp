# StoryBox Model — Repo Copy

This folder is a synced copy of the canonical StoryBox model docs. Use these files as the source of truth for any planning or implementation work in this repository.

## Files

- [main.md](main.md) — Overview of the model directory
- [platonic_model.md](platonic_model.md) — The base model (format-agnostic, domain-agnostic): Component → View → Piece → Task with Working Vocabulary
- [the_story_model.md](the_story_model.md) — The narrative application of the base model, including the MVP implementation mapping for this repo

## Canonical source

These files are mirrored from the project planning vault (`pandaChest`, on the project lead's local Drive):

- `pandaChest/projects/development/storybox/model/main.md`
- `pandaChest/projects/development/storybox/model/platonic_model.md`
- `pandaChest/projects/development/storybox/model/story_model/the_story_model.md`

When the model is updated in `pandaChest`, the changes are re-synced here so all planning agents (local CLI and cloud sessions like `/ultraplan`) see the same source of truth. Obsidian-specific elements (canvases, wikilink syntax) have been simplified for repo readability — the diagrams live in the source vault only.

## When to read these

- Before drafting any planning doc in `.claude/issues/`
- Before proposing schema, resource, or action changes
- Before writing or rewriting an issue body that touches the data model
- Whenever a design decision references "the model"
