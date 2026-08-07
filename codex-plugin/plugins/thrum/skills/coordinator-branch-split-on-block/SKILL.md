---
name: coordinator-branch-split-on-block
description:
  "Use when a Pass-3 merge gate (hotpath, philosophy) or dual review BLOCKS on
  ONE concern of a branch that bundles multiple independent concerns, while the
  other concern(s) are clean - on a live multi-writer shared branch. Walks the
  split-land-recut sequence - separate the blocked concern from the clean
  one(s), land the clean half first, re-cut the blocked half onto the now-moved
  base, and verify the dropped commits are NOT ancestors of the re-cut tip
  before re-gating and merging."
# source: claude-plugin/skills/coordinator-branch-split-on-block/SKILL.md
# generated-by: scripts/sync-skills.sh
---

## Coordinator: Branch-Split When One Concern Blocks a Multi-Concern Branch

### When to use

- A Pass-3 dual merge-gate (`coordinator-hotpath-merge-gate` or
  `coordinator-philosophy-merge-gate`) — or dual review — **BLOCKS on one
  identifiable concern** of a branch, while the branch also carries one or more
  genuinely independent, unrelated concerns that are clean.
- The clean concern(s) are ready to land on their own merits and gain nothing
  from waiting on the blocked concern's fix.
- The branch lives on a **live multi-writer shared branch** — other
  coordinators/agents are also pushing, so the base moves under you and a naive
  re-cut needs an explicit safety check, not just a rebase.

**Don't use when:**

- The BLOCK concern and the "clean" concern actually share code or intent — if
  splitting would require cherry-picking around interdependent commits, this is
  not an independent-concerns split; fix the blocker in place instead.
- Only one concern exists on the branch. A single-concern BLOCK just goes back
  to the implementer normally — there is nothing to separate.

### The split decision

When a gate names a BLOCKING finding scoped to one part of the diff, and the
rest of the diff is unrelated to that finding, split the branch into:

- **The clean half** — the concern(s) with zero BLOCKING findings.
- **The blocked half** — the concern the gate flagged.

State the split explicitly in the merge report before doing anything else: name
which commits belong to which half. If a commit touches both concerns, that
commit belongs to the blocked half (never guess a commit apart) or the split
isn't clean enough to attempt this play.

### Land the clean half first

Do not hold the clean half hostage to the blocked half's fix cycle. Route the
clean half through its own merge report to the merge-king (Discipline D13 — box
coordinators never self-merge) and get it merged **first**. This advances the
mainline tip by the clean half's commits.

### Re-cut the blocked half onto the now-moved base

> **This is not the banned rebase.** The project-wide ban (see
> `coordinator-dispatching-work` and `orchestrate` — "merge forward, never
> rebase") targets rebasing a still-live, in-flight branch onto a moved base as
> the pre-MERGE-READY sync step: a stale-local-ref rebase there can silently
> revert commits landed since your last fetch, with no check catching it. The
> re-cut below is a different operation on a different object — you are not
> syncing an existing branch, you are **building a new branch from scratch** out
> of only the blocked half's own unpushed commits, and the operation is made
> safe by an explicit invariant check (below), not by care alone. Rebasing (or
> cherry-picking) a branch's own local, unpushed commits onto a fresh base
> during a deliberate re-cut is legitimate; do not "fix" this section by
> replacing it with merge-forward.

Once the clean half is merged, the blocked half must be **re-cut** — not merely
rebased — onto the new tip, so it carries **only its own commits**, not a copy
of the clean half's commits riding along from the original branch-off point.
Concretely: create the new branch from the merged tip (the clean half's merge
SHA, announced per Discipline D7 — base-mover discipline, announce the new tip
by SHA unprompted), then cherry-pick or rebase only the blocked half's own
commits onto it. The goal state is a branch whose full commit range is exactly
"the blocked concern's fix," nothing else.

### The not-ancestor invariant — the load-bearing check

**Pin exactly which SHAs are the "dropped set" — this is the detail the check
lives or dies on.** The dropped set is the clean half's commits **as they
existed on the original pre-split bundled branch** — their ORIGINAL SHAs, before
the clean half was landed. It is **not** the clean half's merged form: landing
the clean half can rewrite its commits (a rebase, a squash, a merge-time
correction), which mints **new, distinct git objects** with new SHAs. Those
merged-form SHAs are _expected_, _correct_ ancestors of the re-cut tip, because
construction branched the re-cut FROM the merged tip — seeing them as ancestors
is not a failure, it's the point.

**After re-cutting, verify the ORIGINAL pre-split SHAs of the clean half's
commits are NOT ancestors of the re-cut branch's tip:**

```bash
git merge-base --is-ancestor <original-pre-split-clean-half-sha> <recut-blocked-tip>
# exit 1 (NOT an ancestor) is the PASS condition
```

Run this for every commit in the dropped set (the original pre-split SHAs), not
just the first one — and never substitute the merged-form SHAs here, or the
check inverts and fails a safe re-cut.

**Why this is the check that matters:** the risk isn't that the re-cut tip
descends from the clean half's _landed_ fix — it must, by construction. The risk
is that the re-cut branch was built sloppily (e.g. a naive rebase of the whole
original bundle instead of a cherry-pick of only the blocked half's commits) and
ended up carrying the clean half's **original, pre-correction commit objects**
as ancestors alongside the merged tip. If that happens, merging the re-cut
branch feeds those original objects into a future merge-base calculation on the
same files, and git's three-way merge can resolve back toward the older,
pre-correction content — silently reverting whatever the clean half's merge
fixed. There is no conflict, no warning, no gate that catches this by
construction: the merge just succeeds and quietly re-applies the older version.
This is exactly the D5/D6 shape — verification (ancestry) has a shelf life, and
re-deriving it AT THIS SPECIFIC HANDOFF (the re-cut) is not optional.

Run the check at **re-cut time** and again immediately before the merge-king
executes the re-cut branch's merge (the base can move again in between on a live
shared branch — re-run, don't relay a stale result).

### Three-pass re-gate on the re-cut branch

The re-cut branch is a new artifact (different base, different commit set) and
gets a full re-gate, not a diff-against-the-old-gate. Follow Discipline D1's
three-pass order, in order:

1. **UNFRAMED first** — no defect brief, read the full changed functions, flag
   anything nobody asked about. Run this before the other two; a framed pass run
   first anchors every subsequent pass to the same blind spot.
2. **CODE-DERIVED enumeration** — terms and symbols pulled from the code itself
   (not from the original defect description), enumerate every call site /
   consumer.
3. **BY-EFFECT** — assert the specific defect the original BLOCK named cannot
   occur, phrased as a checkable behavior. Example from the worked case: "an
   inconclusive liveness probe produces neither a tombstone nor a repair" — a
   concrete, testable claim, not "the fix looks right."

A code-derived enumeration is not a substitute for the unframed pass — it is
still aimed at symbols the code review chose to look at. Both are required.

### Hold the implementer's retirement until BOTH halves merge

Do not retire (agent.delete / worktree teardown) the implementer who owns this
work until **both** the clean half and the blocked half have merged. The
implementer's context on the blocked half's fix is exactly what the three-pass
re-gate cycle needs if it surfaces further findings; retiring early forces a
cold restart mid-fix-cycle.

### Worked example (q5r2x liveness/tmux-lock split, 2026-07-21/22)

`thrum-q5r2x` bundled a liveness inconclusive-signal fix (concern A) with a
tmux-lock false-completeness fix (concern B) that the gate found independently,
in the same branch. The coordinator's Pass-3 initially **falsely cleared** the
liveness blocker (Discipline D1 — the gate's Lens-8 reused the commit's own
`IsAgentLive(` grep key, which cannot match `IsAgentLiveFromStartTime`, so it
never traced the second channel that tombstones on inconclusive). The
merge-king's independent second-lens gate caught the real
tombstone-on-inconclusive defect; the coordinator's own **unframed** pass then
found a third, separate lock domain the merge-king's RPC-scoped gate hadn't
reached.

Merge-king ruled **SPLIT THE BRANCH**:

- **B (tmux-lock fix)** merged first: `424b0baa58`. Landing B took its commits
  to a corrected merged form (e.g. `5cd3a0eb9`) — a distinct object from the
  pre-split commit it replaced.
- **A (liveness fix)** re-cut onto B's now-moved merge tip (`6a4aa3fb63`),
  carrying only A's own 7 liveness commits — both of B's **original pre-split
  tmux commits** explicitly dropped from A's re-cut range (the re-cut
  legitimately descends from B's merged tip, `6a4aa3fb63`, which is expected and
  correct).
- The **not-ancestor invariant** was run against the **original pre-split
  SHAs**, not the merged form:
  `git merge-base --is-ancestor {cee4036ebc, af95b999f0} 6a4aa3fb63` — both of
  those are the ORIGINAL pre-split tmux commit SHAs (one carried a stale,
  overstated comment that B's merge corrected), not `5cd3a0eb9` (the corrected
  merged form, which _is_ an ancestor of `6a4aa3fb63` by design and would
  wrongly fail the check if used here). Both original SHAs came back
  NOT-an-ancestor — PASS — confirming A's re-cut carried none of B's
  pre-correction objects, so merging A could not silently revert B's comment
  fix.
- A was three-pass re-gated (unframed → code-derived → by-effect) and merged:
  `ca336e4c59`.
- Efficacy rows were recorded for **both** A and B (`outcome=REAL_DEFECT` for
  each), and `impl_liveness_r2` (the implementer) was retired only after both
  merges landed.

### Gate that closes it

Both halves merged, both efficacy rows recorded (Stage 10 discipline — one row
per merged branch, not one row for the original bundled branch), the
not-ancestor invariant's PASS result is part of the merge report the merge-king
relied on (not asserted after the fact).

### See also

- `dev-docs/process/2026-07-22-idea-to-merged-end-to-end-process-capture.md` —
  the full 11-stage pipeline (Stage 0 + Stages 1–10; this play is Stage 9/10)
  and Discipline D1 (gate independence / unframed-first), D5 (verification
  shelf-life), D6 (conflict-free-not-strict-ff), D7 (base-mover discipline) that
  this play composes.
- `coordinator-hotpath-merge-gate` / `coordinator-philosophy-merge-gate` — the
  Pass-3 gates whose BLOCK verdict triggers this play.
- `coordinator-running-review-cycles` — the dual-review cycle that may also
  originate a scoped BLOCK this play applies to.

### Project-specific rules (already loaded)

Project-local rules of kind `agent_rule` at `--scope role` were loaded at
session start by your preamble (see your role template's Memory model block). If
a project-local rule conflicts with this skill, the project-local rule wins;
surface the conflict in your reply so the user can decide whether to graduate or
remove the override.

If you accumulate a new rule mid-session about branch-splitting, capture it via
the `coordinator-maintaining-memory` skill — it references the
`memory-write-discipline` common for the canonical `thrum memory create` shape.
