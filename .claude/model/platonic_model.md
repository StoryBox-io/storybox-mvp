# The StoryBox Model

> Mirrored from `pandaChest/projects/development/storybox/model/platonic_model.md` — see [README.md](README.md) for sync notes.

---

## Philosophical Grounding

StoryBox draws from both Platonic and Aristotelian philosophy — but adapts them to the reality of creative work.

**The Platonic starting point**: a creative work exists as an ideal before it becomes a film, a game, an animation, or anything else. We borrow Plato's vocabulary — Form, manifestation, perspective — but not his metaphysics.

**The Aristotelian correction**: in Plato's model, the Form is transcendent and fixed — particular things are imperfect shadows of a perfect Truth that exists elsewhere. StoryBox's creative ideal is not like this. It is not static, not resolved, not "out there." The ideal **exists within and through its manifestations**, and evolves as they evolve. It shapeshifts. Feedback refines it. The "Truth" is always approaching, never arrived.

**Views are perspectives, not copies.** A rough sketch is not a degraded version of the final render — it is a perspective on the same Component at an earlier resolution. A storyboard and a rendered image sequence are not ranked by truth. They are different lenses on the same evolving creative intention. Ideal and views co-evolve through the creative dialectic.

---

## The Four Levels

**Component → View → Piece → Task**

### Component — The Evolving Ideal

A Component is a creative building block — any named thing with its own identity, intent, and lifecycle. Components are modular and can participate in other Components.

**A Component owns its Views, Pieces, and Tasks.** It is self-surfacing: it expresses itself through its own Views. This is the test for whether something is a Component — not whether it has a name, but whether it has an independent ideal that it surfaces through its own interface. If something only appears as a position or grouping within another Component's View, it is a structural unit, not a Component.

Every Component carries **through-lines**: evaluation criteria that bias how Views should manifest it. Through-lines score; they do not prescribe. When through-lines conflict, that is where editorial judgement lives.

### View — The Recipe / Perspective

A View is an assembly recipe that defines how a Component can be perceived at a specific resolution or format. The same Component can have many Views simultaneously — each is a different way of seeing the same ideal.

- **Format-agnostic**: a View declares what it needs and what it produces, not how
- **Versioned**: each View version is a blueprint snapshot — an ordered set of pinned Piece or sub-View references at specific tag states
- **Resolvable**: a View is resolvable when all referenced Pieces exist at the required tag state; unresolvable Views generate Tasks
- **Composable**: Views can reference other Component Views, building hierarchies of perspectives

**Creating a new View version is an approval act.** You are explicitly choosing which manifestations to include in this perspective. The blueprint IS the approval.

### Piece — The Manifestation

Pieces are the actual content on disk: text files, images, audio, 3D assets — any file a View assembles from. They are the particular things through which the ideal is expressed.

- **Owned by a Component**: every Piece belongs to a Component (the Component owns its content)
- **Immutable once written**: new content = new version (append-only)
- **Tagged**: each version carries tag states — production state lives here
- **Portable**: a Piece exists independently of any View; it can be referenced by zero, one, or many Views
- **Provenance (optional)**: a Piece may carry light attributes naming the upstream Piece(s) it was derived from, including the upstream version pinned at creation. Provenance is per-Piece metadata, not a generalized dependency graph.

**The relationship between View and Piece**: both belong to a Component, both are versioned, both carry tag state. A Piece is content; a View is composition. A Piece is referenceable wherever a View is expected — it is treated as its own implicit single-pin **self-view**. The shared interface is **Pinnable** (see Working Vocabulary below).

### Task — The Work

Tasks are markers for work that needs to be done. They are deliberately lean: a Task records *that* work is needed and *which* View is unresolvable, not what specific work is required. Agents poll for Tasks and decide the work at evaluation time.

- **Owned by a Component** (the Component whose View needs the work)
- **Generated** when a View is unresolvable: missing Pin, stale Pin, or downstream Piece needs refinement
- **Typed**: `:creation`, `:refinement`, `:review` — broad work categories
- **Assignable** to a human creator or an AI agent
- **Append-only**: completed Tasks remain as historical record; new triggers generate new Tasks (a refinement Task does not re-open the original creation Task)
- **Completion** produces a new PieceVersion linked back to the Task

---

## Working Vocabulary

The Four Levels are realised in implementations as the following primitives. The shared interface across them is **Pinnable**: any immutable, versioned, tagged thing that another composition can reference.

| Term | Layer | Role | Owned by |
|---|---|---|---|
| Component | Structural | Owns Views, Pieces, Tasks | (top of tree) |
| Piece / PieceVersion | Structural | Content atom — file/blob | Component |
| View / ViewVersion | Structural | Composition recipe — ordered Pin list | Component |
| Segment + Pin | Structural | Position + polymorphic reference inside a ViewVersion | ViewVersion |
| Task | Action | Marker for work needed to make a View resolvable | Component |

**View vs Piece.** A Piece is the atom (single content blob); a View is the molecule (composition of Pins). Both are owned by a Component. Both are versioned. Both carry tag state. Both can be referenced as Pins.

**Self-view.** A Piece is referenceable wherever a View is expected: it is treated as its own implicit single-pin self-view. The self-view is implicit (no separate row in storage); the Pin's polymorphism handles the resolution.

**Pinnable.** A Pin holds either a PieceVersion (resolved as a self-view) or a sub-ViewVersion. The same code path resolves either.

---

## Tag States

Tag states live on Piece versions. Multiple tags can coexist across different versions simultaneously.

| Tag | Meaning |
|---|---|
| `:latest` | Most recent version — computed, always present |
| `:unreviewed` | Created but not yet evaluated |
| `:reviewed` | Evaluated against through-lines — awaiting approval |
| `:approved` | Explicitly approved — the canonical manifestation |
| named tags | Arbitrary branching labels for exploration and alternate paths |

A View version pins references at a specific tag state. The View becomes stale when a referenced Piece has a newer version beyond the pinned state.

---

## Staleness is a Signal, Not a Mandate

Staleness is computed, not stored. Two paths:

1. **View staleness** — a ViewVersion is stale when one of its Pins references a version older than the latest available version of that referent. Detected by walking the Pin list against the current heads.

2. **Piece staleness via provenance** — a Piece carrying provenance attributes is stale when its source Piece's latest version is greater than the source-version pinned at creation. Detected by comparing versions; no stored "stale" flag.

In both cases staleness is a signal, not a mandate. A stale View or Piece does not mean the previous one is wrong — it means a newer manifestation exists upstream. Staleness triggers Task generation; the creator reviews and decides whether to refine, supersede, or accept divergence. The creative ideal evolves through deliberate choice, not automatic cascade.

---

## The Model is Fractal

Component → View → Piece → Task applies at every level of scale. A film, a scene, a character, a prop — each is a Component with its own Views, its own Pieces, its own Tasks. Components participate in other Components, and Views compose from sub-Component Views.

Not everything named in a creative work is a Component. Acts and sequences in a screenplay, chapters in a novel, shots in a sequence — these are structural positions within a Component's Views, not independent ideals. They appear inside an assembly but cannot surface themselves. The fractal applies to things that own their own interface; structural units are how that interface is organised inside.

The same four levels run at every scale and across every medium StoryBox supports.

*Domain-specific applications of this model — narrative, CG pipeline, game design — are documented in their respective model directories.*

---

## View Versioning

A ViewVersion is not content — it is an immutable structural snapshot. Its composition (the ordered Pin list across its Segments) IS its blueprint:

```
Component.SomeView v2
  state: :approved
  segments (ordered by position):
    segment 1 → pin → SubComponent1.SomeView v1     (sub-view reference)
    segment 2 → pin → SubComponent2.SomePiece v3    (piece reference, treated as self-view)
    segment 3 → pin → SubComponent3.SomePiece v1
```

Two structural facts:

- **A Segment is a position within a ViewVersion.** It carries a position index and exactly one Pin. Segments do not exist outside a ViewVersion.
- **A Pin is the polymorphic reference held by a Segment.** It points to either a PieceVersion (resolved via the implicit self-view) or a ViewVersion. The same code path resolves either.

**The blueprint IS the approval.** A new ViewVersion is created when the editorial decision changes — different references, different ordering, or different pinned tag states. ViewVersions are append-only.

---

*See also: [the_story_model.md](the_story_model.md) — narrative application of this model*
