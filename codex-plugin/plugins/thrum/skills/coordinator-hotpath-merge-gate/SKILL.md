---
name: coordinator-hotpath-merge-gate
description: "Use when ABOUT TO START a hot-path Pass-3 gate - a gate has been dispatched to you, you are picking up a queued gate, you are the Gate Runner beginning a gate, you are about to walk hot-path lenses - and when a coordinator is about to run git merge after dual review came back clean. Loads the gate-runner restart rule (restart at ~50 percent, at a seam BETWEEN gates) plus the hot-path and perf lenses read from .thrum/hotpath-gate.json. Trigger-scoped lenses skip on a mechanical zero-match against the configured trigger directories, paired with a firing positive control, for branches touching RPC handlers, projection writers, storage openers, sync code, peer dial paths, or daemon boot paths - not CLI helpers, tests-only, docs, or website. Any lens flagged always_run in the config runs on EVERY commit regardless of directory, including the master-giant-process batch-decomposition lens."
# source: claude-plugin/skills/coordinator-hotpath-merge-gate/SKILL.md
# generated-by: scripts/sync-skills.sh
---


## Coordinator: Hot-Path Merge Gate

### Before you start this gate — restart if you cannot finish it

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



### Why this is a separate pass, not a philosophy-gate lens

`coordinator-philosophy-merge-gate` catches general structural anti-patterns
(raw `exec.Command`, shell passthrough, SRP violations). This gate catches
**hot-path/perf-specific** anti-patterns — silent fail-open, unconditional
writes in dual-source paths, shared-resource poisoning, pattern divergence,
coincidence- detector tests, incomplete-class-fixes, dead-row pre-filter gaps,
and peer-dial circuit-breaker gaps — that the philosophy gate does not cover.
See the config's per-lens `context` prose for the project's incident history and
what the philosophy gate caught vs. missed.

Where the two gates overlap (subprocess-in-hot-path,
dispatch-goroutine-blocking, pattern divergence, coincidence-tests), this gate
goes deeper with specific detection rules. If the philosophy gate already
flagged a finding, this gate should **upgrade** it with the deeper analysis, not
duplicate it. The coordinator consolidates findings from both gates into one
numbered list.

### Config-driven design

This skill reads `.thrum/hotpath-gate.json` at invocation time. The config
provides:

- **Trigger directories** — which directories in the diff activate this gate
- **Pattern fields** — grep strings, function names for automated triage
- **Reference patterns** — established working patterns to check divergence
  against
- **Context prose** — incident descriptions, fix patterns for the LLM reviewer's
  judgment

The lenses below are codebase-agnostic. All project-specific values come from
the config. The companion `project-hotpath-gate` skill generates/updates the
config from codebase inspection (like `project-philosophy` generates
`.thrum/philosophy.md`). If no config exists, fail with guidance to run
`project-hotpath-gate` first.

**How to apply: DISPATCH THIS GATE TO THE GATE RUNNER. Do not walk the lenses in
your own context.**

The gate runner is a standing agent whose entire purpose is to hold gate work
OUTSIDE the coordinator's context — resolve the current one from `thrum team` by
its `gate` ROLE, never by a remembered name. It runs the lenses in an ephemeral worktree, produces
a verdict, and tears the worktree down. **You read `.thrum/hotpath-gate.json` to
build the dispatch, then you consolidate the verdict and decide. You do not run
the lenses.**

**This is the default for EVERY diff size.** Diff size changes what you ask for;
it never changes who runs it. A coordinator that walks the lenses inline burns
the one resource it cannot replace and leaves no durable verdict artifact.

**Only run it yourself when there is NO gate-role agent available**, and say so
explicitly in the merge record so the gap is visible rather than invisible.

**Verdicts are artifacts:** the runner saves them to
`dev-docs/gate-reports/<ISO-week>/<date>/<gate-slug>/` and commits them BEFORE
removing any worktree. A verdict that exists only in a message cannot be audited
later.

### Gate dispatch preamble

Mandatory checklist handed to the GATE RUNNER (and to any sub-agent it spawns in
turn) at dispatch time. Each
rule below currently lives only as prose warnings scattered through
`dev-docs/hotpath-gate-efficacy.md` and gets re-learned per session — hand this
list to the sub-agent verbatim at dispatch time instead of relying on it
rediscovering these the hard way:

1. Read code via `git show <target-sha>:<path>`, NEVER the working tree — tree
   state != the SHA under review.
2. Build/test ONLY in a throwaway detached worktree
   (`git worktree add <tmp> <sha> --detach`), never the shared checkout.
3. RUN any test you make a claim about — never judge from reading it.
4. Diff against `merge-base`, never two-dot against tip — a two-dot diff
   against tip pulls in unrelated lines from sibling branches and
   manufactures a false regression signal.
5. Run `git merge-base --is-ancestor` as an explicit gate condition (the
   fast-forward check) — git silently deduplicates content-identical commits
   on both sides of a rebase, so a tree that "builds clean" can still be
   carrying dupes instead of the real content.
6. Run full-package `-race`, not targeted `-run` — a targeted race run misses
   cross-test races.
7. Build+test the MERGED-tree result as a SEPARATE condition — neither gate
   currently runs a build of the actual post-merge tree; a clean pre-merge
   build/test does not prove the merged result compiles or passes.
8. Use `rm -r`, NEVER `rm -rf`, and use `git worktree remove --force` to drop a
   worktree. A broad `ask` rule on `rm -rf *` outranks any narrow `/tmp` allow,
   so `rm -rf` raises a human permission prompt EVERY time regardless of path —
   it stalls gate sub-agents mid-run waiting on a keystroke. `rm -r` runs free. Do NOT widen the ask rule
   to work around this; that entry is the only deletion protection on the box.
9. Check the discriminator before picking a scratch path, don't assume from
   the platform: `[ -L /tmp ]`. macOS (symlink) — create throwaway worktrees
   under `/private/tmp`; a worktree under `/tmp` false-FAILs worktree-ancestor
   tests via the symlink, producing a confident wrong gate result. Linux (real
   dir) — `/tmp` is correct; `/private/tmp` may not exist there and must not
   be created.
10. Your report reaches the coordinator ONLY as your final returned text.
    Side-channel output is discarded. Put the whole verdict in the return value.
11. **NEVER run `git stash`, `git checkout`, `git reset`, or any working-tree
    mutation in the SHARED repo.** Do read-only inspection there (`git show
    <sha>:<path>`, `git log`, `git diff`) and do every build/test in a throwaway
    detached worktree. `git stash` is a SINGLE SHARED STACK across every
    worktree of a repo, so "cleaning up after myself" can strand or clobber
    another agent's live work; and the shared repo is POPULATED — live agents
    hold uncommitted `State.md` they are actively re-authoring.
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
    Then `git worktree remove --force <wt>`.

### Trigger-directory skip logic

Before walking the lenses, check if the diff touches any directory in
`config.trigger_directories`. If not, skip the trigger-scoped lenses and run
only the philosophy gate — EXCEPT any lens carrying `"always_run": true` in its
config entry (see `lens_scope_semantics` in the config), which still runs on
every diff regardless of trigger directories. If the config has no
`trigger_directories`, fail with guidance to run `project-hotpath-gate`.

### Delta re-gate continuity — walk the whole branch, read the whole function

**Why:** A commit introducing a lock can be an ancestor of a delta-re-gate's
base and never appear in any walked diff, even when a later commit edits the
gating condition on that call. Root cause: the gate is delta-scoped. The diff
hunk showing the edited condition never revealed the enclosing locked span
above it.

**Rules:**

- The FIRST gate run on a branch walks `merge-base(target, tip)..tip`, NOT a
  recent delta.
- A delta re-gate MUST state the prior gated SHA and assert continuity:
  `prior-gated-sha == delta-base`, verified via `git merge-base --is-ancestor`
  or direct SHA equality. If the prior-gated SHA is NOT the delta base,
  re-walk from `merge-base` — there is unwalked history between the two.
- Lens 1 (subprocess hot path) and Lens 2 (dispatch-blocking) greps run at
  changed-FILE scope, then READ THE FULL ENCLOSING FUNCTION — a diff hunk
  inside a locked span cannot show you the `Lock()` above it. A changed line
  whose semantics depend on a lock/defer/subprocess further up the function is
  only visible at function scope, never at hunk scope.

### Lens 1 — Subprocess in the per-request hot path

**Why:** The single most recurring wedge class. Per-request or per-heartbeat
work that forks a subprocess, compounding under fleet scale.

**Relationship to philosophy gate:** Cross-refs Philosophy Lens 1 (raw
`exec.Command` in daemon code) — goes deeper by checking per-RPC path membership
and mitigation patterns.

**How to apply:** Read `config.lenses.subprocess_hot_path`. Grep changed files
for `subprocess_patterns`. For each hit, check if the calling function is
reachable from a `hot_path_indicators` function in a `hot_path_files` path —
follow one call-level into changed helpers (subprocess calls may live one call
below the handler). If yes, verify three mitigations: (1)
`pre_flight_guard_pattern` before the fork, (2) `non_blocking_read_pattern`
before blocking extraction, (3) consider `native_alternatives`. Read the
`context` prose.

**Severity:** Missing all three mitigations on a new hot-path subprocess call —
**BLOCKING**.

**Triage:**
`git diff main...HEAD --name-only | xargs grep -ln '{subprocess_patterns}'`

### Lens 2 — Dispatch-goroutine-blocking on expensive work

**Why:** Blocking the request-dispatch goroutine on expensive I/O starves other
requests. A shared lock held across I/O is the overarching contention point.

**Relationship to philosophy gate:** Cross-refs Philosophy Lens 10d (cost gate:
shared lock across I/O or drain) — goes deeper by checking
Peek+background-refresh and lock-hold-time minimization.

**How to apply:** Read `config.lenses.dispatch_blocking`. For any new/changed
handler: does it acquire a `lock_patterns` lock? Is I/O performed under the
lock? Is the lock released before `post_commit_pattern` work? For new caches: is
there a `cache_peek_pattern`? Is extraction moved to
`background_detach_pattern`? Is there `singleflight_pattern` coalescing? For
per-item loops: batched or per-item lock? Also check: does a new scheduler/cron
job emit durable-lane events at a rate that could saturate the write pool? Read
the `context` prose.

**Severity:** New handler holds lock across I/O, or lacks Peek+background for
expensive cacheable data — **BLOCKING**.

**Triage:** `git diff main...HEAD --name-only | xargs grep -n '{lock_patterns}'`

### Lens 3 — Silent fail-open instead of fail-closed

**Why:** Missing/mismatched data silently falls through to wrong-but-plausible
data instead of erroring. The second most common wedge class.

**Relationship to philosophy gate:** No philosophy.md equivalent — new pattern.

**How to apply:** Read `config.lenses.silent_fail_open`. For any function
resolving identity/path/state: does it have a fallback when the target is
missing? Does the fallback return a _different_ identity/path than requested?
For identity resolution: does it hard-error on mismatch (check
`identity_validation_patterns`)? For liveness computation: does it use
`canonical_predicate` or compute ad-hoc? For file writes to shared resources:
does it use `append_patterns` instead of truncate-with-guard? Read the `context`
prose.

**Severity:** Silently adopts wrong data on missing/mismatched input —
**BLOCKING**. Falls back to default without erroring — **IMPORTANT**.

**Triage:**
`git diff main...HEAD --name-only | xargs grep -n '{fallback_patterns}'`

### Lens 4 — Unconditional write in a shared dual-source path

**Why:** A shared apply path handling both local writes AND sync-merged events.
Writers without timestamp guards allow older sync events to clobber newer local
edits.

**Relationship to philosophy gate:** No philosophy.md equivalent — new pattern.

**How to apply:** Read `config.lenses.unconditional_write_dual_source`. For any
new/changed writer in `shared_apply_path`: does it use
`unconditional_write_patterns` (e.g. `INSERT OR REPLACE`, bare
`UPDATE`/`DELETE`)? Must use `conflict_guard_patterns`. Are side effects gated
on `side_effect_gating_pattern` (e.g. `RowsAffected() > 0`)? Does it mirror
`reference_guarded_writers`? Read the `context` prose.

**Severity:** Writer in shared apply path lacks conflict guards — **BLOCKING**.
Side effects not gated on RowsAffected — **BLOCKING**.

**Triage:**
`git diff main...HEAD --name-only | xargs grep -n '{unconditional_write_patterns}'`

### Lens 5 — Shared-resource poisoning by an auxiliary code path

**Why:** A secondary code path (backup, CLI helper, hook) mutates a shared
resource in a way that corrupts the primary path's state. Looks correct in
isolation.

**Relationship to philosophy gate:** No philosophy.md equivalent — new pattern.

**How to apply:** Read `config.lenses.shared_resource_poisoning`. For any
resource open in a non-primary path: does it use `read_write_db_open_patterns`
when the consumer only reads? Must use `read_only_db_open`. Follow
`reference_read_only` pattern. Check `wal_checkpoint_patterns` — any
`PRAGMA wal_checkpoint` or explicit checkpoint call on the daemon path. Check
`raw_sql_patterns` — raw `db.Query`/`db.Exec` bypasses `safedb_wrapper`'s 522/
malformed retry. For file writes to shared resources: does it use
`append_patterns`? Must use truncate-with-ownership-guard or
`atomic_write_patterns`. Read the `context` prose.

**Severity:** Auxiliary path opens shared resource read-write when read-only
suffices — **BLOCKING**. Raw `sql.DB` on daemon path bypassing safedb —
**BLOCKING**. Writes to shared file without ownership guard — **BLOCKING**.

**Triage:**
`git diff main...HEAD --name-only | xargs grep -n '{read_write_db_open_patterns}|{wal_checkpoint_patterns}|{raw_sql_patterns}'`

### Lens 6 — Pattern divergence from established working pattern

**Why:** A new feature introduces a code path that omits a pattern the existing
code already got right — because the pattern wasn't enforced structurally.

**Relationship to philosophy gate:** Partial thematic overlap with Philosophy
Lenses 10b (naming test) and 10d (cost gate) — but this lens is about structural
pattern mirroring, not naming or cost. No duplication risk.

**How to apply:** Read `config.lenses.pattern_divergence.reference_patterns`.
For each reference pattern, check if the diff introduces a new code path that
should follow it. Does the new code match the `check` description? Does it use
`current_pattern` (not `legacy_pattern` where one is specified)? Is there a
`tripwire_test`? Read each pattern's `context` prose.

**Severity:** Divergence from a proven-incident reference pattern (in the
config's `reference_patterns` list) — **BLOCKING**. Divergence from a convention
not in the proven-incident list — **IMPORTANT**.

**Triage:** For each reference pattern, grep changed files for its
`legacy_pattern` (if present) or its `current_pattern` to verify usage.

### Lens 7 — Coincidence-detector test

**Why:** Green tests that don't assert the actual invariant provide false
confidence at merge time — worse than no tests.

**Relationship to philosophy gate:** Partial thematic overlap with Philosophy
Lens 6 (trusting documented behavior) — but this lens is about trusting
**tests** that pass without proving the invariant, not trusting comments/docs.
No duplication risk.

**How to apply:** Read `config.lenses.coincidence_detector_tests`. For any new
test (files matching `test_file_pattern`): does it assert the actual invariant
(not just "no error")? Would it fail if the behavior were wrong? Does it rely on
ambient shell state? For regression tests: does it assert the specific fix? Is
it a tripwire (check `tripwire_patterns`)? For tests using only
`assertion_free_patterns`: flag as potentially coincidence-detecting. For
modified tests: was an assertion weakened? Read the `context` prose.

**Severity:** Test would pass even if the behavior it claims to test were broken
— **IMPORTANT**. A regression test that doesn't assert the specific anti-pattern
is prevented — **IMPORTANT**. A coincidence-detector test that is the **sole
regression guard** for a previously-fixed Category A–F wedge — **BLOCKING**.

**Triage:**
`git diff main...HEAD --name-only | grep '{test_file_pattern}' | xargs grep -l '{tripwire_patterns}'`

### Lens 8 — Incomplete-class-fix: enumerate-all-siblings

**Why:** A fix that guards a SUBSET of writers to a shared resource, leaving
siblings via other code paths unguarded. The unguarded sibling silently retains
the bug.

**Relationship to philosophy gate:** No philosophy.md equivalent — new pattern.

**How to apply:** Read `config.lenses.incomplete_class_fix.shared_resources`.
For any fix touching a shared-resource writer: does the fix NAME the sites it
touches? Does it PROVE there is no N+1? Run the `grep` pattern in `directory` to
enumerate ALL write sites. Diff against what the fix touched — any gap is a
sibling. Acceptable proof: grep enumeration with each site accounted for,
compile-time tripwire, or cited enumeration comment. Read the `context` prose.

**Severity:** Fix touches a shared-resource writer without enumerating all
siblings — **BLOCKING**.

**Triage:** For each shared_resource, run its `grep` in its `directory` to
enumerate all write sites; diff against what the fix touched.

### Lens 9 — Dead-row pre-filter before per-row cost

**Why:** A per-row-expensive hot-path loop (subprocess / DB / IO per candidate)
that admits dead/retired/non-live rows into the candidate set. Dead rows incur
the full per-row cost (which fails anyway), starving the dispatch goroutine.
This was the ACTUAL root cause of the gitctx cold-cache fork-storm.

**Relationship to philosophy gate:** No philosophy.md equivalent — new pattern.

**How to apply:** Read `config.lenses.dead_row_prefilter`. For any new/changed
candidate query or per-row loop in a hot path: does the candidate selection use
`candidate_query_patterns` (e.g. `ended_at IS NULL`, open-session alone) as the
liveness proxy? This is WEAKER than the `canonical_predicate`
(`phaseFor`/`PhaseOf`). The candidate set MUST be pre-filtered to live agents
(phases in `live_phases`) with existing worktrees (`worktree_exists_check`)
BEFORE any per-row cost. A candidate query selecting on open-session alone,
feeding a per-row-expensive loop, is this anti-pattern. Read the `context`
prose.

**Severity:** Candidate query uses a weaker liveness proxy than the canonical
predicate, feeding a per-row-expensive loop — **BLOCKING**.

**Triage:**
`git diff main...HEAD --name-only | xargs grep -n '{candidate_query_patterns}'`

### Lens 10 — Peer-dial circuit-breaker for dispatch-reachable network calls

**Why:** A synchronous peer/network call (peer dial, cross-daemon RPC,
wait_pairing) reachable from a dispatch/fanout handler with no deadline AND no
circuit-breaker stalls the dispatch goroutine when the peer is unreachable or
stale.

**Relationship to philosophy gate:** No philosophy.md equivalent — new pattern.

**How to apply:** Read `config.lenses.peer_dial_circuit_breaker`. For any
new/changed peer call matching `peer_call_patterns`: is it reachable from a
`dispatch_handler_patterns` function? If yes, verify two mitigations: (1)
deadline- bounded via `timeout_patterns` (`context.WithTimeout`/`WithDeadline`),
AND (2) circuit-broken via `circuit_breaker_patterns` so an unreachable/stale
peer never stalls dispatch. A timeout alone is insufficient — a dead peer still
occupies a slot until the timeout fires. Read the `context` prose.

**Severity:** Peer call reachable from dispatch with no timeout AND no
circuit-breaker — **BLOCKING**. Peer call with timeout but no circuit-breaker —
**IMPORTANT**.

**Triage:**
`git diff main...HEAD --name-only | xargs grep -n '{peer_call_patterns}'`

### Cross-gate consolidation with the philosophy gate

This gate runs **in parallel** with `coordinator-philosophy-merge-gate` (both
are Pass 3, after dual review is clean, before `git merge`). The coordinator
runs both independently and consolidates findings from both into one numbered
list.

**Overlap rule:** If the philosophy gate already flagged a finding (e.g., raw
`exec.Command` in daemon code), this gate should **upgrade** it with the deeper
hot-path-specific analysis (is it in a per-RPC path? Is there a pre-flight
guard? Is there a Peek+background-refresh?), not duplicate it.

**Skip rule:** Skip the trigger-scoped lenses if the diff touches no configured
trigger directories — but any lens with `"always_run": true` in the config
still runs regardless of directories touched. Never skip the philosophy gate.
Skip everything, including always-run lenses, only for trivial diffs (one-line
config, typo, test-only).

### Scope discipline (gate-wide)

This gate governs NEW work unconditionally and EXISTING code only on a
fix-on-contact basis — don't carve out an unrelated existing violation because
you noticed it while reviewing an adjacent change. Note incidental finds in the
merge report as "touch-soon" candidates if they are actively wedging something;
otherwise leave them.

### If it fails

Send it back as a normal review finding — same channel as dual-review output,
folded into the same numbered list if dual review is still open, or as its own
short reply if dual review already passed. Cite the offending function/file,
which lens it failed, and the config value that triggered the finding.

### Efficacy tracking (v1 acceptance requirement)

After every gate run, record the outcome in `dev-docs/hotpath-gate-efficacy.md`
(created lazily on first run). This is a durable, committed, grep-queryable log
that measures v1's real-world efficacy so we can iterate to v2 with data.

**Format (structured header):** a structured header line, with
essay content moved to an indented notes block underneath it:

```
- YYYY-MM-DD | lens=<hpN,phN,...> | bead=<id> | merged=<sha> | gate=<hotpath|philosophy|both> | outcome=<OUTCOME>
  notes: branch=<branch>, lenses_run=10, findings=B:N I:N M:N, FALSE_POSITIVE=<0|N>. <brief prose>
```

`lens=<hpN,phN,...>` names the specific lens numbers that were load-bearing for
the outcome (not just "10"), each prefixed by its gate — `hp<n>` for a
hotpath-gate.json lens, `ph<n>` for a philosophy.md anti-pattern.
`FALSE_POSITIVE=0` is recorded explicitly even on a clean/uneventful run ("no
findings overturned on pushback this run") so the zero is a measurement, not an
absence.

**Coverage mandate:** a row is required for EVERY trigger-dir merge — not just
gates the coordinator itself runs. This includes SKIPPED-with-evidence rows and
orchestrator-run merges; the log measures gate COVERAGE, not just
coordinator-run outcomes. Do not fabricate a per-merge outcome you cannot
verify — if a past merge is missing a row and the outcome can't be
reconstructed, record a single honest coverage-gap note instead of inventing
rows.

**Outcomes:**

| Outcome                 | Meaning                                                    |
| ----------------------- | ---------------------------------------------------------- |
| `CLEAN`                 | Gate ran, zero findings, merge proceeded                   |
| `REAL_DEFECT`           | Gate caught a genuine hot-path/perf anti-pattern           |
| `FALSE_POSITIVE`        | Gate flagged something correct — record which lens and why |
| `SLIPPED`               | A wedge occurred AFTER merge that the gate did not catch   |
| `SKIPPED_WITH_EVIDENCE` | Gate deliberately skipped (no trigger dirs), evidence cited |

**Retrospective reclassification:** When triaging a new wedge or incident, grep
`dev-docs/hotpath-gate-efficacy.md` for the merged branch/date. If the gate
previously logged `CLEAN` for that branch, append a follow-up line referencing
the original entry:
`- YYYY-MM-DD | branch=<branch> | RECLASSIFIED: CLEAN->SLIPPED | notes=<what the gate missed + which lens should have caught it>`.
This closes the feedback loop — a `CLEAN` that later becomes `SLIPPED` is the
most valuable data point for v2 lens improvement.

Review the log quarterly (or after any `SLIPPED` outcome) to identify config
gaps and lens improvements for the next version.

### Reference

- `.thrum/hotpath-gate.json` — project-specific config (trigger directories,
  patterns, reference functions, incident prose)
- `project-hotpath-gate` — the companion builder skill that generates/reconciles
  the config (analog of `project-philosophy`)
- `dev-docs/brainstorms/hotpath-merge-gate/` — the locked brainstorm (evidence,
  gap analysis, lens details, decisions)
- `coordinator-philosophy-merge-gate` — the companion general-structural gate
  (runs in parallel)
- `.thrum/philosophy.md` — canonical source for general anti-patterns (cross-
  referenced by Lenses 1–2, 6–7 where they overlap)
- `dev-docs/hotpath-gate-efficacy.md` — running efficacy log (created lazily on
  first gate run, appended after each run)

<!-- THRUM-GATE: stage=skill next=review -->
<!-- THRUM-REVIEW: stage=skill verdict=Ready:Yes cycle=2 date=2026-07-10 -->
