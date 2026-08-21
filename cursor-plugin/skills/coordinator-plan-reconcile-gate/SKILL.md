---
name: coordinator-plan-reconcile-gate
description: "Use when N parallel plans (one researcher per program of a shared idea) are all LOCKED and about to feed project-setup, and the plans cross-talk at shared seams — an anchor contract produced by one plan and consumed by another, a shared struct field, a shared predicate. Verifies the plans COMPOSE (consistent seams, no double-build, no gap) before any bead or worktree exists. This is the multi-plan reconcile gate — the step that makes parallel plan-writing pay off instead of producing N colliding plans. It uses Fable, the single standing exception to the never-select-Fable rule — see Step 2 for the cited scope of that exception."
---

# Coordinator: Plan Reconcile Gate

## When to use

Run this gate when:

- ≥2 plans were authored **in parallel**, each for one program of a shared
  idea, and each plan touches at least one **shared seam** with a sibling
  plan (a contract, a struct, a predicate, a schema that more than one plan
  reads or writes).
- All N plans have individually passed their own dual-review
  (`coordinator-running-brainstorm-cycles` Phase 6: `verify-against-source` +
  prose-quality) and are stamped `THRUM-REVIEW: stage=plan verdict=Ready:Yes`.
- The plans are about to feed `project-setup` — beads, tasks, and worktrees
  are about to be minted from them.

**Don't use when:**

- Only one plan exists for the idea (nothing to reconcile against).
- Multiple plans exist but share no seam — genuinely disjoint programs. Verify
  disjointness explicitly (see "List the seams before writing" below) before
  skipping; "looks disjoint" is not the same as "verified disjoint."
- This is the sibling-brainstorm **coherence pass** (`coordinator-running-
  brainstorm-cycles` Phase 5) — that pass runs earlier, over brainstorms, for
  contradiction/vocabulary drift. This gate runs later, over LOCKED plans,
  specifically for seam composition. Run both when both apply; they are not
  substitutes for each other.

## Why this is a separate gate, not folded into the plan dual-review

Each plan's own dual-review (`verify-against-source`) checks that plan against
**its own** brainstorm/spec — a single-plan lens. It cannot see whether plan
①'s seam contract matches plan ②'s, because the reviewer only ever reads one
plan. Composition defects are invisible to a lens that only ever looks at one
artifact at a time — the same shape as the philosophy gate's rationale for
being a separate pass from dual review. The remedy is a **reconciler that
reads all N plans together**, plus the per-plan verify running alongside it.

## Step 1 — List the seams before writing (belongs in the plans, verify it's there)

Before this gate even runs, each plan should already carry an explicit
**owns-vs-consumes** section naming every shared seam it touches — this is a
Stage-3 (`writing-plans`) discipline this gate audits, not one it originates.
If a plan is missing this section, that is itself a BLOCKING finding: return
it to the researcher rather than attempting to infer ownership from prose.

For each seam, collect across the N plans:

- **The seam name** (e.g. "the A2 anchor contract", "the `Evidence` struct",
  "the identity-file schema", "the `PhaseOf` predicate").
- **Which plan OWNS it** — writes/defines the contract, is the single source
  of truth.
- **Which plan(s) CONSUME it** — read or call into the owner's contract
  without redefining it.

Build this as a small table before dispatching the reconciler; it is the
reconciler's primary input alongside the plans themselves.

## Step 2 — The reconcile pass (one top-level Fable agent, plans read together)

Spawn **one** top-level agent, `model: "fable"`.

This is not a self-granted exception; it is the single deliberate use of
Fable anywhere in the system, kept as an independent check-and-balance
against everything else, which runs on the sonnet ceiling.
Fable — a distinct, more-capable model — is the right instrument specifically
because a holistic cross-plan reconcile (does seam X mean the same thing in
plan ① as in plan ②?) benefits from a different model than the sonnet-run
per-plan reviews, a form of cross-document judgment a sonnet-tier pass has
been shown to miss.

This is the **one named, cited exception** to the standing "never SELECT
Fable" rule, which otherwise forbids ad-hoc Fable selection anywhere. The
exception is scoped to this gate's reconcile pass ONLY — do not select Fable
elsewhere in the pipeline, or for any other step, on the strength of this
skill. Any new use of Fable outside this gate needs its own explicit
approval, not an extension of this one.

Give the fable agent:

- All N plans, in full, in one dispatch (not summarized, not excerpted).
- The seam table from Step 1.
- The parent decisions / convergence map from Stage 1, so it has the shared
  intent the plans were decomposed from.

Ask it to verify three things and return a verdict per seam plus an overall
verdict:

1. **Shared seams are consistent** — does plan ①'s description of what it
   consumes from plan ② match what plan ② actually says it owns and produces
   (types, semantics, timing)? Prose agreement is not enough — check field
   names, ordering guarantees, and error/absence semantics too.
2. **No double-build** — do two plans both intend to implement the same
   thing, unaware of each other? This is the failure a cross-critique
   discipline exists to catch: a solo researcher cannot see a sibling's plan,
   so a duplicate build looks like sound scoping from inside either plan
   alone.
3. **No gap** — is there a seam that appears in one plan's "consumes" list
   but in NO plan's "owns" list? An unowned seam means the code that's
   supposed to produce it will not exist.

Overall verdict is one of: **YES** (compose cleanly, no fixes needed),
**YES-WITH-FIXES** (compose after named fixes — the common case), or **NO**
(fundamental seam conflict, needs re-brainstorm). Run this in parallel with
Step 3, not sequentially.

## Step 3 — Per-plan verify-against-source, run alongside the reconcile pass

Independently of the fable reconcile, run `verify-against-source` per plan
against its own brainstorm/spec (this may already exist from Stage 3 — re-run
it now if the plan changed since, so the reconcile gate is judging current
text). This catches single-plan drift the reconciler isn't chartered to catch
(the reconciler's job is composition, not per-plan fidelity). Both together
form the writing-plans gate for this stage.

## Step 4 — Fold fixes, then delta re-gate — and the delta re-gate is a REAL TEST, not a re-read

When the verdict is YES-WITH-FIXES, each named researcher folds their fix
into their plan. Once all fixes report landed, run a **delta re-gate**. This
is the single most important discipline in this skill, and it is easy to
skip because it looks redundant:

**A delta re-gate that just re-reads the revised prose only catches
transcription error** — did the researcher type the agreed sentence
correctly. It does NOT catch whether the fix actually holds structurally.
Run **different-axis checks**, not a second reading of the same axis:

- **Does the FINAL plan still carry the extension it was supposed to?** A fix
  folded into v2 can get silently dropped in a later edit pass — check the
  literal text is still present, not that it once was.
- **Struct-collision** — if two plans both mutate the same struct/schema, do
  their final field additions/changes actually coexist (no name collision, no
  contradictory type), or does only one plan's version of the struct survive
  in each plan's own text?
- **Platform-availability of a primitive** — if a plan's fix relies on some
  runtime primitive (a syscall, a PID-based read, a filesystem watch), is
  that primitive actually available on every platform the code will run on?
  A prose fix can read as complete while quietly assuming one platform.

**Each of these can return NO while all prose still reads correctly and
consistently** — that is exactly why "one artifact, two readers" is not two
instruments. Only a check that asks a *different question* of the revised
plans is a real second instrument.

## The meta-finding — why parallel-with-cross-talk beats serial

Cross-critique among the plan authors caught false positive-controls that the
per-plan review gate had already **passed**. Both the ① and ③ authors
self-caught issues in their own central deliverables that their individual
reviewers had cleared. **Any one researcher working alone would have written
an N+1th competing plan and never known it was redundant** — the cross-talk
also surfaced that the axis was NOT greenfield (four stale stamped plans
already covered part of it), collapsing what would have been fresh builds
into amend/supersede sets.

This is the entire reason to run plan authorship in parallel with cross-talk
rather than serially, and it is the reason this gate exists as a distinct
step rather than trusting each plan's own review to be sufficient. Caveat
(load-bearing, n=1 so far): the effect was observed in **coupled** pairings
(researchers who exchanged seam interpretations directly); whether it
transfers to an uncoupled solo reviewer reading all plans cold is untested —
treat the fable reconciler as necessary, not merely a formality confirming
what cross-talk already caught.

## Gate that closes it

Reconcile verdict is **YES** (after any fixes and their delta re-gate, not
before). A **NO** verdict routes back to Stage 2/3 (brainstorm or plan
rewrite) for the conflicting programs — do not attempt to patch a fundamental
seam conflict forward into project-setup.

## Handoff

Reconcile PASS → `project-setup` (Stage 5). Carry the seam table and the
fable verdict forward as context for whoever authors the impl prompts — the
seam ownership decisions are exactly what a prompt needs to state
unambiguously so an implementer doesn't re-litigate them.

## See also

- `coordinator-running-brainstorm-cycles` — Phase 5 (sibling coherence pass,
  runs earlier over brainstorms) and Phase 6 (per-plan dual-review, this
  gate's Step 3 input).

## Project-specific rules (already loaded)

Read the shared partial at the absolute path:
`claude-plugin/commands/_project-rules-protocol.md`

If you accumulate a new rule mid-session about multi-plan reconciliation,
capture it via the `coordinator-maintaining-memory` skill — it references the
`memory-write-discipline` common for the canonical `thrum memory create`
shape.
