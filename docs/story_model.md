# Story Model

## Components

Four independently versioned building blocks. Each is a Platonic ideal — it exists independent of any specific story output.

### Story
- Controlling idea (the argument the story makes)
- Logline
- Title
- Through-lines defined on the story (default: `["preference"]`)

### Character
- Essence, contradictions, voice
- Reusable across stories
- Through-line: arc (biases every sequence they appear in)

### World
- History, rules, subtext
- Conditions before the story begins
- Through-line: state progression

### Scene (Template)
- Dramatic function
- Role slots (type-constrained — a role defines what kind of character can fill it)
- Character-agnostic until instantiated at Script level
- Through-line: dramatic function

---

## Views (Assemblies)

Views are not stored as documents. They are resolved on demand from their component pieces.

### Synopsis
- Story at sequence resolution
- One paragraph per sequence
- First assembly: makes sequences visible as discrete units
- Assembles from Story + Character + World, shaped by all their through-lines

### Treatment
- One versioned sequence piece per synopsis beat
- The sequence is the atomic unit: the thing you version, review, and cherry-pick
- A Treatment version is a map: `synopsis_ref + [{sequence, piece_version}]`
- Only sequences touched by a synopsis diff are candidates for update

### Script
- Sequences broken into scenes
- Each scene: location, role participants, action, dialogue (.fountain format)
- Three resolution modes: `:latest`, `:approved`, `:snapshot`

---

## Dependency Direction

Changes propagate top-down only. You interface at the top; refinements flow down.

```
Story (controlling idea)
  └── Synopsis
        └── Treatment (sequence pieces)
              └── Script (scene pieces)

Character ──────────────────────────────┤  feed into Synopsis
World ───────────────────────────────────┘  and bias sequences they touch
```

When any component changes, downstream pieces are flagged `:stale` with a record of what changed.

---

## Versioning

Every piece version is immutable and append-only. No version is ever deleted.

**Approved marker**: each Scene and Sequence has an `approved_version_id` pointing to one of its versions. Moving approval updates the pointer — other versions are unaffected.

**Script snapshot**: a saved, named map of `scene_id → version_id`. Captures a specific mixture of versions at a point in time.

---

## Through-Lines

Through-lines are evaluation criteria, not data inputs. They score piece versions — they do not assemble into views.

A piece version is reviewed when it has weights for all through-lines currently defined on the story. Adding a new through-line to a story marks all existing piece versions as partially reviewed — they are missing that dimension.

**MVP through-line**: `preference` (0.0–1.0). Value of 1.0 = maximum protection.

**Future through-lines**: super objective alignment, character arc, world consistency.

---

## Acts

Acts are grouping labels on sequences — they have no content of their own. A turning point (Syd Field) is metadata on the sequence that functions as the hinge between acts.

```
Act I
  └── Sequence: Prologue
  └── Sequence: Cottage
Act II
  └── Sequence: Settling
  └── Sequence: Kestrel's Game
Act III
  └── Sequence: Reckoning
```
