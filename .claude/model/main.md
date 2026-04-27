# Model

> Mirrored from `pandaChest/projects/development/storybox/model/main.md` — see [README.md](README.md) for sync notes.

This directory contains the conceptual architecture of StoryBox — the ideas that underpin all design and implementation decisions.

It is structured in two layers: a base model that applies universally, and domain-specific models that apply it to particular creative disciplines.

---

## [The Platonic Model](platonic_model.md)

The base model. Format-agnostic, domain-agnostic.

StoryBox is built on the idea that any creative work can be described as an evolving ideal that manifests through perspectives. We borrow vocabulary from Platonic philosophy — Form, View, Piece — but apply an Aristotelian correction: the ideal is not fixed and transcendent. It exists within and through its manifestations, evolving as they evolve.

**The four levels:**

- **Component** — the evolving creative ideal (a character, a story, an environment, a scene). Owns its Views, Pieces, and Tasks.
- **View** — a recipe for perceiving the Component at a specific resolution or format (script, storyboard, game level, rendered image). One logical View per perspective per Component, with many immutable ViewVersions.
- **Piece** — the actual content on disk (a text file, an image, a 3D asset). Versioned, immutable once written, may carry light provenance attributes pointing to upstream Pieces.
- **Task** — a marker for work needed to make a View resolvable. Owned by the Component whose View needs the work.

A ViewVersion is composed of ordered **Segments**, each carrying a polymorphic **Pin** that references either a PieceVersion (treated as a self-view) or a sub-ViewVersion. The shared interface is **Pinnable**.

This model applies at every scale and across every medium StoryBox supports: film, animation, games, interactive. It is the common language across all domain models. The full primitive set is documented in [platonic_model.md](platonic_model.md) §"Working Vocabulary."

---

## [The Story Model](the_story_model.md)

The narrative application of the base model.

Applies Component → View → Piece → Task specifically to written narrative: the structure of a story in acts and sequences, the views a story produces (synopsis, treatment, script), and how components (Story, Character, World, Scene) participate in those views.

This is the foundation of the current MVP (`storybox-mvp`), which implements the narrative layer in Elixir/Phoenix/Ash.

---

## Relationship to the Project

**StoryBox is a framework for building pipelines, not a pipeline itself.**

A studio-specific USD pipeline (like Animal Logic's ALab) is a particular application of a particular set of tools for a particular medium. StoryBox is the layer beneath that: it provides the model — Component, View, Piece, Task — that any such pipeline can be built on top of. The base model makes no assumptions about USD, Fountain, game engines, or any other format. Domain models (the Story Model, a future CG Model, a future Game Model) are applications of the base model to specific disciplines.

This distinction is why the base model is designed to be medium-agnostic. It is not a simplification — it is the point.

The base model exists so that future domain models (CG pipeline, game design, interactive media) follow the same architecture without inheriting narrative-specific assumptions. A character's Hero Rig View and a scene's Script View are the same concept at different resolutions and formats.

Implementation decisions in any StoryBox repository should be traceable back to this model. When something feels unclear or in conflict, this is the reference point.
