---
name: coordinator-philosophy-merge-gate
description: "Use when ABOUT TO START a philosophy Pass-3 gate - a gate has been dispatched to you, you are picking up a queued gate, you are the Gate Runner beginning a gate - and when a coordinator is about to run git merge on any new feature or large bug fix after dual review came back clean. Loads the gate-runner restart rule (restart at ~50 percent, at a seam BETWEEN gates) plus the FULL .thrum/philosophy.md anti-pattern list and red-flags checklist, walked as a distinct pass rather than folded into the dual review. NEVER skipped except for a one-line config change, a typo, or a test-only diff."
---

# Coordinator: Philosophy Merge Gate

## Before you start this gate — restart if you cannot finish it

**Finish the gate you are in. Never restart mid-gate.** A finding that exists only
in your context is one restart from gone.

**Then restart at the seam — after the report is delivered, before taking anything
else.** Do not carry context across a gate boundary.

**Do not START a new gate above ~50% context.** A full dual gate costs roughly 14%.
Starting one you cannot finish is how a gate ends thin on its own verdict.

**Why the boundary is the gate and not a number - a gate runner is static.** Each gate
is scoped, evidenced, and delivered self-contained; State.md carries what must persist.
Nothing accumulates across gates, so context held past a gate boundary buys nothing and
costs money.

**This is NOT the orchestrator rule.** An orchestrator is building something and its
context is the work - it pushes through until its current plan is implemented and
restarts then, at 30% or at 60%. Interrupting an implementation to hit a number is the
wrong move. A gate is short and self-contained, so its boundary comes often and costs
nothing to take.

**The coordinator may overrule either rule for a sustained campaign** - a push to get trunk
green, an incident, a release cutover - where continuity across many units is worth more than
a clean seam. That is an explicit decision, stated at the time. It is never drift.

**Measure by pane, in the same command block that reports the number.** A figure carried
forward from earlier in the session is a memory, not a measurement.



## Why this is a separate pass, not a dual-review finding class

`code-review` and `verify-against-plan` are general-purpose passes — correctness
and spec-compliance. The anti-patterns in `.thrum/philosophy.md` are
project-specific structural rules that require a different lens: not "is this
code correct?" but "does this diff introduce a pattern the project has
explicitly ruled out?" Folding these into dual review dilutes both the general
review and the specialized lenses. This gate is the third, sequential pass — run
it after dual review is clean, before `git merge`.

**How to apply: DISPATCH THIS GATE TO THE GATE RUNNER. Do not walk the lenses in
your own context.**

The gate runner is a standing agent whose entire purpose is to hold gate work
OUTSIDE the coordinator's context — resolve the current one from `thrum team` by
its `gate` ROLE, never by a remembered name. It runs the lenses in an ephemeral worktree, produces
a verdict, and tears the worktree down. **You write the dispatch, consolidate the
verdict, and decide. You do not run the lenses.**

**This is the default for EVERY diff size.** Diff size changes what you ask for;
it never changes who runs it. A coordinator that walks the lenses inline burns
the one resource it cannot replace and leaves no durable verdict artifact.

**Only run it yourself when there is NO gate-role agent available**, and say so
explicitly in the merge record so the gap is visible rather than invisible.

**Verdicts are artifacts:** the runner saves them to
`dev-docs/gate-reports/<ISO-week>/<date>/<gate-slug>/` and commits them BEFORE
removing any worktree. A verdict that exists only in a message cannot be audited
later.

## Gate dispatch preamble

Mandatory checklist handed to the GATE RUNNER (and to any sub-agent it spawns in
turn) at dispatch time. Each
rule below currently lives only as prose warnings scattered through
`dev-docs/hotpath-gate-efficacy.md` and gets re-learned per session — hand this
list to the sub-agent verbatim at dispatch time instead of relying on it
rediscovering these the hard way:

1. Read code via `git show <target-sha>:<path>`, NEVER the working tree —
   tree state != the SHA under review. A plain `Read`/`grep` against the
   working tree can silently return pre-merge code that looks entirely
   normal if the repo is checked out on a different branch than the one
   under review.
2. Build/test ONLY in a throwaway detached worktree
   (`git worktree add <tmp> <sha> --detach`), never the shared checkout.
3. RUN any test you make a claim about — never judge from reading it; a
   test that looks like a genuine regression guard can be failing.
4. Diff against `merge-base`, never two-dot against tip — a two-dot diff
   against tip pulls in unrelated lines from sibling branches and
   manufactures a false regression signal.
5. Run `git merge-base --is-ancestor` as an explicit gate condition (the
   fast-forward check) — git silently deduplicates content-identical commits
   on both sides of a rebase, so a tree that "builds clean" can still be
   carrying dupes instead of the real content.
6. Run full-package `-race`, not targeted `-run` — a targeted race run
   misses cross-test races that only a full-package run surfaces.
7. Build+test the MERGED-tree result as a SEPARATE condition — neither gate
   currently runs a build of the actual post-merge tree; a clean pre-merge
   build/test does not prove the merged result compiles or passes.
7b. **GATE ON OUTPUT, NOT ON EXIT STATUS — and NEVER take `$?` after a pipe**
    (`cmd | tail; echo $?` reports *tail's* status, not cmd's).
    **Do NOT "fix" this with `${PIPESTATUS[0]}` — that is BASH-ONLY and this fleet
    runs zsh 5.9, where it expands to an EMPTY STRING.** Verified empirically:
    `zsh -c 'false | true; echo "${PIPESTATUS[0]}"'` → `` (empty), because zsh
    names the array `pipestatus` (lowercase) AND indexes from 1, so the bash form
    is wrong twice over. The failure direction is what makes it dangerous: an
    empty rc in a typical `[ -z "$rc" ] || [ "$rc" = 0 ]` guard reports SUCCESS,
    so **the remedy for the silent-false-green class is itself a silent false
    green.** In priority order:
    (a) gate on OUTPUT — shell-agnostic, and the thing that actually catches
        real failures (e.g. read the "OK — copies match source" line, not the rc);
    (b) if a status is genuinely needed, run it with NO PIPE:
        `cmd >/dev/null 2>&1; echo $?`;
    (c) only if a pipeline is unavoidable, use `${pipestatus[1]}` on zsh /
        `${PIPESTATUS[0]}` on bash — and STATE WHICH SHELL, because the same
        string means different things in each.
8. Use `rm -r`, NEVER `rm -rf`, and use `git worktree remove --force` to drop
   a worktree. A broad `ask` rule on `rm -rf *` outranks any narrow `/tmp`
   allow, so `rm -rf` raises a human permission prompt EVERY time regardless
   of path and stalls gate sub-agents mid-run waiting on a keystroke. `rm -r`
   runs free. Do NOT widen the ask rule to work around this; that entry is
   the only deletion protection on the box.
9. Create throwaway worktrees under `/private/tmp`, NEVER `/tmp` — a merge
   worktree under `/tmp` false-FAILs worktree-ancestor tests on macOS via the
   symlink, producing a confident wrong gate result.
10. Your report reaches the coordinator ONLY as your final returned text.
    Side-channel output is discarded. Put the whole verdict in the return value.
11. **NEVER run `git stash`, `git checkout`, `git reset`, or any working-tree
    mutation in the SHARED repo.** Do read-only inspection there (`git show
    <sha>:<path>`, `git log`, `git diff`) and do every build/test in a throwaway
    detached worktree. Two reasons, both proven in production:
    (a) **`git stash` is a SINGLE SHARED STACK across every worktree of a repo.**
    A stash taken in one worktree is visible and poppable from all of them, so
    "cleaning up after myself" can strand or clobber another agent's live work.
    (b) The shared repo is POPULATED — live agents hold UNCOMMITTED working-tree
    state there (State.md files they are actively re-authoring). A checkout or
    stash silently reverts EVERY agent's uncommitted work, not just the file you
    were looking at.
    If you believe you must mutate the shared tree, STOP and report instead —
    that is always a finding, never a step.
12. **TEAR DOWN YOUR THROWAWAY WORKTREE WHEN THE GATE ENDS — after two checks,
    in this order.** A required final step, not cleanup etiquette. Each
    abandoned worktree pins its HEAD commit against `gc` and adds a
    `.git/worktrees` admin entry, so the object store grows monotonically.
    Before removing:
    (a) `git -C <wt> status --porcelain` — if NON-EMPTY, **STOP and report it
        instead of removing.** Uncommitted work in a throwaway worktree exists
        NOWHERE else; this is the category that actually loses work.
    (b) `git branch -a --contains $(git -C <wt> rev-parse HEAD)` — if EMPTY,
        HEAD is a gate-produced merge reachable from no ref and removal orphans
        it. Usually fine (a gate merge is reproducible by redoing it) but say so
        in your report rather than doing it silently.
    Then `git worktree remove --force <wt>` (see rule 8 on `rm -r`). Rule 11's
    hazard notice on its own — teardown can destroy uncommitted state — reads
    as a reason NOT to tear down. A warning without a procedure does not
    produce caution; it produces paralysis plus litter.

## Walk 1 — The project's ruled-out anti-patterns

**Walk the anti-patterns in `.thrum/philosophy.md` at gate time, in file order,
however many there are.** That file is the source of truth; this skill reprints
none of it, so an anti-pattern added or retired there needs no edit here.

Read § Anti-Patterns via `git show <target-sha>:.thrum/philosophy.md` (preamble
rule 1 — never the working tree). For each `### N. <title>` entry, in order:

1. Read its BAD / GOOD shape and **Why** — the BAD block is the pattern to
   check for.
2. Check the surface the entry names — usually the diff (against merge-base,
   preamble rule 4), on content the branch INTRODUCES or MATERIALLY CHANGES,
   not content it touches incidentally (see § Scope discipline). A few
   anti-patterns name a different surface: AP#7 is checked against the
   preceding dual-review reports, not the diff.
3. Apply the severity the entry states. A BLOCKING condition hit on new work
   fails the gate; a judgment call gets judgment and a recorded reason.
4. Record an inapplicable entry as walked-and-N/A with a one-line reason —
   never a silent skip.

Cite an anti-pattern finding as `ph<N>` (matching the efficacy-log `lens=`
token); cite a meta-check finding (below) as `ph-metaA` / `ph-metaB` /
`ph-metaC`.

**AP#1 and AP#8 overlap the hot-path gate** (`subprocess_hot_path` +
`shared_resource_poisoning`; `pattern_divergence` "typed RPC handler"). Walk
them here regardless — the hot-path gate's subprocess/SQL and typed-handler
checks are hot-path-file-scoped, while AP#1 governs all daemon-path code plus
the fallible-call-outside-a-seam generalization. Do not re-file a finding the
hot-path gate already raised; do cover what its scope misses.

**AP#10 keeps its dedicated detection procedure (Lens 10 below)** — its
detection is the 10a/10b/10d probe set, not a single grep.

## Lens 10 — Conflated multi-responsibility service (Anti-Pattern #10)

This lens uses three sub-procedures from the single-responsibility standing rule
(`dev-docs/decisions/2026-07-09-single-responsibility-standing-rule.md`).

### 10a — Structural backstop (grep before you trust prose review)

For any new/changed function in the diff that looks decision-shaped, grep its
signature for a plural parameter of its own subject type:

```bash
# Heuristic — look for a decision-shaped func taking []T or map[K]T of the
# same type it's named after (adjust the pattern to the touched package).
grep -nE 'func \([a-zA-Z]+ \*?[A-Za-z]+\) [a-z][A-Za-z]*\(ctx[^)]*\[\][A-Za-z]|func \([a-zA-Z]+ \*?[A-Za-z]+\) [a-z][A-Za-z]*\(ctx[^)]*map\[' <changed-file>.go
```

A hit on something named like a decision (`reconcile*`, `resolve*`, `verdict*`,
`evaluate*`) is the signature this rule is built to catch. A hit on a legitimate
scheduler/fanout layer is not a fail — use judgment. **This backstop is scoped
honestly: it only catches the plural-subject conflation shape (facet 1). It is
blind to the per-call cost problem, which only 10d catches.**

### 10b — Naming test (can you name it with one verb?)

For every new or materially-changed exported function/method that **decides**
something (computes a verdict, mutates core state, resolves an identity), try to
name it with a single verb over a single subject. If the honest name needs an
"And" — `reconcileAndSchedule`, `listAndScan`, `snapshotOrFallBack`,
`launchAndCommit` — it is conflated by construction. Split the decision core
from the scheduling/batching/fallback wrapper; the core keeps the verb name, the
wrapper (or the existing scheduler) does the looping.

### 10d — Cost gate (bounded per call, or off the lock?)

For every touched unit on a hot path (RPC handler, list/fanout endpoint,
anything called per-request or per-agent): does it do work proportional to N
(worktrees, agents, rows), spawn a subprocess, or block on I/O — per call? Does
it hold a shared lock (`state.mu`) across any of that, or across a drain/loop?
If yes to either, the cost must move off the hot path (cache + background
refresh — the `peercred.CachingAgentLister` pattern is the canonical fix) or out
from under the lock. A bounded-per-call answer is required before merge.

**Note:** 10b and 10d are orthogonal probes. A unit can pass 10b (single verb,
singular signature) and still fail 10d (hidden O(N) or lock-across-I/O cost). Do
not merge them into one question.

### 10 Scope discipline

Apply lenses 10a/10b/10d to code the merging branch **introduces or materially
changes** (edits the decision logic or scheduling logic of an existing unit). Do
NOT flag existing conflated units the branch merely calls or touches
incidentally. Note incidental finds in the merge report as "touch-soon"
candidates if they are actively wedging something; otherwise leave them.

Do not apply Lens 10 to shared-substrate issues (lock scope, pool sizing,
checkpoint timing, driver behavior) — a flawless single-responsibility unit can
still wedge on those, and splitting units makes it worse. If a finding looks
like write-pool serialization, checkpoint races, or pooled-conn poisoning, route
it as its own bug.

## Meta-check A — A new return value / sentinel is only as safe as its WORST consumer

**When a diff introduces a new return value, sentinel, error value, or enum
member, ENUMERATE EVERY PRODUCTION CONSUMER and CLASSIFY EACH BY ITS
COMPARISON. Safety is a property of the comparison at each call site, NOT of the
value itself — so it CANNOT be certified at one call site, and a test at one
consumer proves nothing about the others.**

The comparison shape determines the fail direction:

- `x != ""` — a new non-empty sentinel makes this TRUE → treated as "something
  detected" → typically **fail-CLOSED** (safe).
- `x != "some-specific-string"` — a new sentinel ALSO makes this true → treated
  as "not the thing I was waiting for" → typically **fail-OPEN** (dangerous:
  cancels, deletes, clears, or proceeds).
- `x` passed through verbatim into a message, reason field, or log — check
  whether ANY downstream parses it as structured data before ruling it cosmetic.

Procedure, and do not shortcut it: grep the bare identifier of the producing
function (NOT `func Name` — that is blind to methods, the receiver sits between),
list every production call site, and for each one write down the comparison and
its resulting action. A consumer you did not enumerate is a consumer you did not
clear.

**Worked example:** a new sentinel with 4 consumers — 1 fixed, 1
fail-opened+cancelled a nudge, 1 mislog, 1 leak — from one constant. A point
fix leaves a sibling SURFACE, not merely a sibling case; enumeration is what
converts "the consumer I noticed" into "the consumers that exist."

## Meta-check B — Shipped executable instructions were never executed

**If the diff ships a command, a field lookup, or a lookup-key construction that
an agent or script will execute, that invocation MUST have been run against a
REAL target before merge. Prose review does not satisfy this lens.**

This applies to commands embedded in skills, runbooks, restart/sleep snapshots,
generated scripts, templates, role preambles, and prompts — anywhere the artifact
tells someone (human or agent) to run something. It applies whether the command
is in a fenced block, inline, or assembled from variables at runtime.

Check, per shipped invocation:

1. **Does every field lookup return what the surrounding code assumes?** Run it.
   `thrum whoami --field <x>` and friends return real values with real shapes —
   read the actual output, not the flag's documentation.
2. **Does the constructed key actually resolve at the target?** Values get
   transformed in transit (sanitized, normalized, truncated, case-folded). A key
   built from a lookup that is *correct* can still miss because the consumer
   rewrites it.
3. **Is an unresolvable target a HOLD, or does it proceed at a wrong target?**
   Failing to resolve must stop the action, not fall through to a default.

**Worked example:** a self-restart feature shipped non-functional because a
field lookup returned a pane-qualified target while the consumer expected a
sanitized session name — both gates had returned zero findings, because
neither gate's question was "does this command, executed by a real agent,
hit its own session?" A spec defect is invisible to spec-compliance review
by construction: a faithful implementation of an incomplete spec passes the
review that exists to catch wrongness. Only executing the thing closes that
hole.

**Corollary — A DOUBLE-ZERO IS A PROMPT, NOT A CLEARANCE.** Two clean gates on a
lifecycle or guidance change is *too little friction*, and is exactly when to ask
what neither gate could see by construction. The question that found it was
cheap and mechanical: **when shipped guidance contains a command, run the
command.**

Probe safely: exercise the derivation against a **nonexistent** target first so
nothing live is disturbed, and read the error text — it distinguishes "not found"
(you passed the wrong argument) from a mangled key (the consumer rewrote it).

## Meta-check C — Test the branch's own unmeasured claim

**Find the claim in the branch that its own author did not verify, then test it
directly.** Every branch asserts something — in a commit message, the bead
body, or a code comment — that reads as established fact but was never
independently checked. Locate that sentence. It almost always has one of four
shapes:

- a **TOTALITY** ("these are the only paths that do X")
- a **COMPLETENESS** ("all call sites now route through Y")
- a **SAFETY** ("the guard prevents Z")
- a **SCOPE** ("this cannot reach W")

**How to apply:** Find the claim (grep commit messages and the bead
description for absolute language — "only", "all", "never", "cannot", "the
sole"). Then independently verify it with an enumeration or trace whose **zero
is controlled** — a control that MUST return non-zero on the same command
shape, so a silent empty result cannot be mistaken for a clean one. Report the
verdict explicitly as **COMPLETE** or **INCOMPLETE** — do not fold it into a
vaguer note.

**This lens is not an accusation, and must not be written as one.** It
applies equally when the claim holds. **Worked example:** an "ONLY
mechanism" claim in this codebase was independently enumerated and turned
out to be FOUR defective paths, not one; a later re-verification of a
related claim, aimed the same way, returned COMPLETE — a real, repeated
verification, not an assumption carried over from the last check.
**"Claim verified, here is the enumeration and its control" is a full,
successful result** — a lens that only ever produces findings is one
reviewers learn to discount.

## Red-flags checklist pass

After the anti-pattern walk, scan the diff against `.thrum/philosophy.md`
§ Red Flags via `git show <target-sha>:.thrum/philosophy.md` — not a copy here.
Any hit on new code the branch introduces is a gate fail. Red flags marked
**MANDATORY on every merge, no scope exemption** are checked on every diff
whatever it appears to touch.

Two red-flag-grade checks are not in `.thrum/philosophy.md` — they are above as
**Meta-check B** (a shipped command / lookup-key never executed against a real
target) and **Meta-check C** (a totality / completeness / safety / scope claim
never enumerated with a controlled-zero check). Include both.

## Scope discipline (gate-wide)

This gate governs NEW work unconditionally and EXISTING code only on a
fix-on-contact basis — don't carve out an unrelated existing violation because
you noticed it while reviewing an adjacent change. "No manufactured urgency"
applies here the same as anywhere else.

## At merge time — COMMIT ACCUMULATED AGENT STATE (Leon, 2026-07-20)

**Every coordinator, on every merge: stage and commit accumulated agent state
under `.thrum/agents/` along with the merge.** Session snapshots, `State.md`
files, salvage directories. This is a standing rule for ALL coordinators on ALL
boxes, not a primary-only habit.

**Why this is a rule and not housekeeping:** uncommitted agent state exists in
exactly ONE place — a working tree. Anything that touches that tree destroys it,
and several things routinely do:

- A `git checkout` / `stash` / `reset` in the shared repo reverts every agent's
  uncommitted state at once (this reverted an orchestrator's `State.md` to a
  stale version on a populated box, 2026-07-20).
- `git stash` is a SINGLE SHARED STACK across every worktree of a repo, so a
  stash taken anywhere can strand or clobber state everywhere.
- A worktree teardown takes its uncommitted state with it, permanently.

Committed state survives all three. **The state IS the agent's memory across
restarts** — losing it is not losing a file, it is losing an agent's ability to
wake up knowing what it was doing.

Check before you merge (expect a non-trivial count on an active box; if it is
zero, confirm that is real rather than a wrong path):

```bash
git status --porcelain -- .thrum/agents/ | wc -l
git add .thrum/agents/
```

Two cautions, so this rule does not cause its own incident:

1. **Never `git add -f`.** If something under `.thrum/` is gitignored it stays
   out of git — that is deliberate, not an obstacle to route around.
2. **Do not commit another agent's state mid-write** as a substitute for asking
   it to save. Committing what is on disk is protective; it is not a snapshot
   command, and a half-written `State.md` committed is still half-written.

## If it fails

Send it back as a normal review finding — same channel as dual-review output,
folded into the same numbered list if dual review is still open, or as its own
short reply if dual review already passed. Cite the offending function/file and
which anti-pattern (`ph<N>`), meta-check, or Lens 10 sub-probe it failed. Do
NOT block on Lens 10d findings that are
genuinely disclaimed substrate issues (see Lens 10 scope discipline above); DO
block on any Lens 10b or 10d finding on NEW work.

## See also

- `coordinator-branch-split-on-block` — when this gate BLOCKs on one concern
  of a branch that bundles multiple independent concerns, while the other
  concern(s) are clean.

## Reference

- `.thrum/philosophy.md` — canonical source for all anti-patterns and red flags
  checked by this gate
- `dev-docs/decisions/2026-07-09-single-responsibility-standing-rule.md` — full
  standing rule with the three-class scope model, enforcement architecture
  (3a/3b/3c/3d), and worked examples of previously-traced conflated services

## Project-specific rules (already loaded)

Project-local rules of kind `agent_rule` at `--scope role` were loaded at
session start by your preamble (see your role template's Memory model block). If
a project-local rule conflicts with a universal rule above, the project-local
rule wins; surface the conflict in your reply so the user can decide whether to
graduate or remove the override.

If you accumulate a new rule mid-session (the user corrects you), capture it via
the `coordinator-maintaining-memory` skill — it references the
`memory-write-discipline` common for the canonical `thrum memory create` shape.
