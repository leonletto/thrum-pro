---
name: coordinator-hotpath-merge-gate
description: "Use when a hot-path merge gate is dispatched to you or you are its Gate Runner, or before a coordinator runs git merge after a clean dual review. Loads the gate-runner restart rule and the hot-path lenses from the hotpath gate config."
---

# Coordinator: Hot-Path Merge Gate

## Before you start this gate — queue it, take it in order

- **Queue every gate request on arrival** with `thrum queue add --title "gate <branch>@<short sha>"`, and reply to
  the requester with the bundle ID. A request that lives only in a message is lost at your next compaction.
  Without a Pro licence (`not entitled` / `requires a license`), skip this write and track it in the message thread instead.
- **Reconcile your queue before starting a gate** (`thrum queue list`) and take the oldest pending item in the
  coordinator's order. Only an explicit "jumps the queue" reorders it.
- **A gate stopped part-way keeps a note** of what ran and what did not (`thrum queue note <id> --stdin`), for
  example "norace PASS, race NOT RUN", and stays `in_progress`.

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



## Why this is a separate pass, not a philosophy-gate lens

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

## Config-driven design

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

**Verdicts are one log line:** the runner appends ONE line (date, gate, candidate SHA,
target SHA, verdict, one short reason) to `dev-docs/gate-log.md` and commits it. That
line is the only record a gate keeps; the verdict itself travels in the report message.
Never commit per-gate report directories, logs, archives or evidence (owner ruling 2026-10-17:
once a gate has decided and the candidate is landed or rejected, its output is deleted).

## Gate dispatch preamble

Mandatory checklist handed to the GATE RUNNER (and to any sub-agent it spawns in
turn) at dispatch time. Each
rule below currently lives only as prose warnings scattered through
older gate records and gets re-learned per session — hand this
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
6. A PER-LANDING gate is non-race (build, vet, norace on touched packages,
   structural checks) plus the change's OWN focused race selectors
   (the project's race runner on that package with a `--run` selector), only for a
   concurrency change. Never run a full-package race per landing: the full
   race runs on trunk in batches before any deploy, which is what catches
   cross-test races. A focused `--run` race on a package item 7 marks as too slow is not
   a monolithic run (item 7 is about the unfiltered package).
7. **A package your project marks as too slow to run monolithically is never run monolithically at gate time, in
   either lane.** If `.thrum/gate-config.json` or `.thrum/hotpath-gate.json` names a sharded runner or a timeout
   classifier for such a package, the gate's OUTPUT must show that runner actually executed for it, not just that some
   test in it ran. A bound-timeout with ZERO test failures is a FALSE RED, not a finding: distinguish it from a
   genuine hang or deadlock with the project's timeout classifier before reporting it as a regression, and send an
   unclassified result to human review. If the config names none, a timeout with no failing test is neither red nor
   green: re-run that package on a wider bound and report it as a bound failure. If a gate's own command line invokes
   a bare monolithic path for such a package, that is a gate defect, not a passing lane.
8. Build+test the MERGED-tree result as a SEPARATE condition — neither gate
   currently runs a build of the actual post-merge tree; a clean pre-merge
   build/test does not prove the merged result compiles or passes.
9. Use `rm -r`, NEVER `rm -rf`; use plain `git worktree remove` to drop a worktree, never
   `--force` as the default (see item 13 below). A broad `ask` rule on `rm -rf *` outranks any narrow `/tmp` allow,
   so `rm -rf` raises a human permission prompt EVERY time regardless of path —
   it stalls gate sub-agents mid-run waiting on a keystroke. `rm -r` runs free. Do NOT widen the ask rule
   to work around this; that entry is the only deletion protection on the box.
10. Check the discriminator before picking a scratch path, don't assume from
    the platform: `[ -L /tmp ]`. macOS (symlink) — create throwaway worktrees
    under `/private/tmp`; a worktree under `/tmp` false-FAILs worktree-ancestor
    tests via the symlink, producing a confident wrong gate result. Linux (real
    dir) — `/tmp` is correct; `/private/tmp` may not exist there and must not
    be created.
11. Your report reaches the coordinator ONLY as your final returned text.
    Side-channel output is discarded. Put the whole verdict in the return value.
12. **NEVER run `git stash`, `git checkout`, `git reset`, or any working-tree mutation in the SHARED repo.** Do
    read-only inspection there (`git show <sha>:<path>`, `git log`, `git diff`) and do every build/test in a throwaway
    detached worktree. `git stash` is a SINGLE SHARED STACK across every worktree of a repo, so "cleaning up after
    myself" can strand or clobber another agent's live work; and the shared repo is POPULATED — live agents hold
    uncommitted `State.md` they are actively re-authoring. If you believe you must mutate the shared tree, STOP and
    report instead — that is always a finding, never a step.
13. **TEAR DOWN YOUR THROWAWAY WORKTREE WHEN THE GATE ENDS — after two checks,
    in this order.** A required final step, not cleanup etiquette. Each
    abandoned worktree pins its HEAD commit against `gc` and adds a
    `.git/worktrees` admin entry, so the object store grows monotonically.
    Before removing:
    (a) `git -C <wt> status --porcelain --untracked-files=all --ignored -- .thrum` — if NON-EMPTY, **STOP and report it
        instead of removing.** Uncommitted work in a throwaway worktree exists
        NOWHERE else; this is the category that actually loses work.
    (b) `git branch -a --contains $(git -C <wt> rev-parse HEAD)` — if EMPTY,
        HEAD is a gate-produced merge reachable from no ref and removal orphans
        it. Usually fine (a gate merge is reproducible by redoing it) but say so
        in your report rather than doing it silently.
    Then `git worktree remove <wt>` — **plain, no `--force`.** Its rc=128 refusal backstops
    ONLY untracked/modified content (see rule 9 on `rm -r`) — it does NOT cover gitignored
    content, which git removes silently with no refusal; a clean rc=0 is not proof nothing of
    value was in there (see coordinator-assessing-agent-completion's reap procedure). `--force`
    is a justified override only, never the default (see coordinator-merging-code §7a).

## Trigger-directory skip logic

Before walking the lenses, check if the diff touches any directory in
`config.trigger_directories`. If not, skip the trigger-scoped lenses and run
only the philosophy gate — EXCEPT any lens carrying `"always_run": true` in its
config entry (see `lens_scope_semantics` in the config), which still runs on
every diff regardless of trigger directories. If the config has no
`trigger_directories`, fail with guidance to run `project-hotpath-gate`.

## Invariant-ratchet lenses

A lens may declare `mandatory_test_command` (see `census_classification_coverage`
and `write_owner_bypass_ratchet` in `.thrum/hotpath-gate.json`) instead of
(or alongside) a pattern-match `question`/`required_evidence` pair. When
present, PASS/FAIL is the command's own exit code — never a judgment call
from reading the diff. This is the shape for any invariant that already has
a mechanical detector: wire the detector as an `always_run` lens with a
monotonic budget (a count that may only decrease, or an explicit
waiver-tagged exception), so a diff cannot silently re-widen the invariant
in the same change that appears to narrow it. `write_owner_bypass_ratchet`
is the reference instance: it fails a merge that bumps a
ceiling/aggregate in the ledger file without a `RATCHET-WAIVER:` tag, even
when the ledger-equality test alone would pass.

## Delta re-gate continuity — walk the whole branch, read the whole function

**When a delta re-gate exists at all:** only after a gate found a failing test
or a blocking finding that the change itself causes, and the author pushed a
fix for it. Then the gate reruns only the lanes that were red plus the packages
the fix touches. A delta re-gate is NEVER asked for because trunk moved, because
the branch merged trunk, because a generated file was regenerated, or because a
minor finding was fixed: a green run lands as it is (coordinator-merging-code,
"LAND ON GREEN").

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

## Lens 1 — Subprocess in the per-request hot path

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

## Lens 2 — Dispatch-goroutine-blocking on expensive work

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

## Lens 3 — Silent fail-open instead of fail-closed

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

## Lens 4 — Unconditional write in a shared dual-source path

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

## Lens 5 — Shared-resource poisoning by an auxiliary code path

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

## Lens 6 — Pattern divergence from established working pattern

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

## Lens 7 — Coincidence-detector test

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

## Lens 8 — Incomplete-class-fix: enumerate-all-siblings

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

## Lens 9 — Dead-row pre-filter before per-row cost

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

## Lens 10 — Peer-dial circuit-breaker for dispatch-reachable network calls

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

## Test impact selection plan (per-merge gate)

Owner ruling, verbatim: "default ON as soon as it lands, no side-by-side; safety net = daily full gate + a load/regression test before deploy".

Run the per-merge test lanes through the repository's test-impact-selection plan wrapper (the gate role's documented
command, taking `--base`, `--head` and `--lane`), not the bare full-lane runner. It runs the plan, prints the `TIS_PLAN` line, and passes `--producer-rc` to the runner. Quote the `TIS_PLAN` line in the
verdict. FULL (`decision=FULL RUN`) is the normal fallback: a plan error or any fail-closed reason runs the whole lane.
For a per-landing gate, a FULL RUN fallback means the full NON-race lane, never race-all.

## Lens 11 — Census classification coverage (mandatory test, not a pattern check)

**Why:** `go test ./...` never runs in the merge gates — test impact selection
(the plan wrapper) is scoped to files the diff touches, and `internal/daemon/rpc/testcensus` is an ad
hoc test target nothing routes to. A merge that adds a `state.NewState(...)`
call site in an `internal/daemon/rpc/*_test.go` file (test-fixture setup, not a
handler) can leave it unclassified and desync the frozen census snapshot with
no gate catching it — trunk went RED post-merge on 573mo v87 for exactly this
reason.

**Relationship to Lenses 1–10:** every other lens in this file is an
LLM-judgment pattern check — grep a pattern, read the surrounding code, apply
judgment. This lens is MECHANICAL: run the command, read PASS/FAIL. It shares
its evidentiary discipline with the philosophy gate's coincidence-detector-tests
lens and preamble rule 3 (RUN any test you make a claim about) rather than with
Lenses 1–10's pattern-matching shape.

**Own narrower trigger — this lens does NOT fire on every gate run.**
`internal/daemon/` is already a gate-wide `trigger_directories` entry, so this
gate already RUNS on any `internal/daemon/rpc/` diff. This lens carries its OWN
trigger on top of that (see `config.lenses.census_classification_coverage` and
`lens_scope_semantics`): it fires only when the diff (against merge-base,
preamble rule 4) either (a) touches `internal/daemon/rpc/testcensus/**`
directly, or (b) touches an `internal/daemon/rpc/*_test.go` file AND an
added/changed line matches `trigger_content_pattern` (bare `NewState(`,
alias-agnostic on purpose — a renamed import of the state package would defeat
a `state.`-prefixed match, and over-firing here costs one fast test run while
under-firing reproduces the exact hole this lens exists to close). A diff
elsewhere under `internal/daemon/` (state/, safedb/, scheduler/, or an
`rpc/*_test.go` edit that never touches a `NewState(` call) fires the GATE but
not THIS lens — record it walked-and-N/A. A non-test `.go` change in
`internal/daemon/rpc/` alone (e.g. a handler edit with no test change) does not
fire this lens either: `census.go`'s `Run()` only scans `*_test.go` source
non-recursively, so a handler-only edit cannot desync the census by
construction.

**How to apply:** Read `config.lenses.census_classification_coverage`. Check
the trigger per the paragraph above. If it fires, run
`config.lenses.census_classification_coverage.mandatory_test_command` in the
gate's throwaway worktree (preamble rule 2) and record the literal output.

**Gates `TestCensusClassificationCoverage` ONLY — deliberately NOT the whole
package.** `mandatory_test_command` is `-run`-scoped to
`^TestCensusClassificationCoverage$`. The sibling test in the same package,
`TestCensusRegeneration`, is an orthogonal count-snapshot drift detector — it
reds on ANY new top-level test function added anywhere in
`internal/daemon/rpc`, unrelated to whether any `NewState` site is classified.
Gating the whole package would false-block the next unrelated census-surface
diff on `TestCensusRegeneration`'s brittleness with zero added
defect-prevention (`ClassificationCoverage` alone already catches the defect
this lens exists for). `TestCensusRegeneration`'s own staleness is tracked
separately (nd2j1/P1 owns the classification data; the brittle count-snapshot
assertion itself is a distinct open question — "make advisory or drop the
raw-count assertion"), not by this lens.

**Severity:** Trigger fires and `mandatory_test_command` was not run before
merge, OR was run and is RED — **BLOCKING**. A RED result means an unclassified
`NewState` site: confirm `testdata/classifications.json` was regenerated per
`internal/daemon/rpc/testcensus/README.md` and re-committed on the same branch
before merge.

**Triage:**
```bash
git diff <merge-base>...<tip> --name-only | grep -E 'internal/daemon/rpc/testcensus/|internal/daemon/rpc/.*_test\.go$'
# for any *_test.go hit outside testcensus/, confirm content match:
git diff <merge-base>...<tip> -- <file> | grep -E '^\+.*NewState\('
```

## Cross-gate consolidation with the philosophy gate

This gate runs **in parallel** with `coordinator-philosophy-merge-gate` (both
are the merge gates, after dual review is clean, before `git merge`). The coordinator
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

## Scope discipline (gate-wide)

This gate governs NEW work unconditionally and EXISTING code only on a
fix-on-contact basis — don't carve out an unrelated existing violation because
you noticed it while reviewing an adjacent change. Note incidental finds in the
merge report as "touch-soon" candidates if they are actively wedging something;
otherwise leave them.

## If it fails

For a genuine hot-path/perf defect, a production-behaviour change, or a design
judgment call: send it back as a normal review finding — same channel as
dual-review output, folded into the same numbered list if dual review is still
open, or as its own short reply if dual review already passed. Cite the
offending function/file, which lens it failed, and the config value that
triggered the finding.

For mechanical bookkeeping only (census/shard regen via the tool, line-number
or key refreshes, ledger totals/ceilings where the arithmetic is derivable, a
per-entry waiver or citation comment recording a classification already
established elsewhere (never a new safety judgment of your own), a nosec
baseline hash for an already-reviewed pattern, comment wording, stale test
expectations that merely follow a landed change): fix it yourself as a
`GATE-AUTHORED` commit on your
`gate/` branch, re-run ONLY the lens(es) the fix affects, and report
`CLEAN-WITH-GATE-FIXES` listing each fix instead of bouncing it to the owner.
When unsure which bucket a finding falls in, ask the coordinator with the exact
diff — don't bounce reflexively.

## Unmeasured findings

A gate finding with no failing test or reproduction can never block. Label it UNMEASURED, state the
likely cost, and name the test that would prove it. The coordinator forwards it only if the fix is
clearly worth the cost, never as a 'real risk', and the owner can decline it.

## Post-verdict record

The only post-verdict record is the one line in dev-docs/gate-log.md (gate output is deleted after the verdict).

## Reference

- `.thrum/hotpath-gate.json` — project-specific config (trigger directories,
  patterns, reference functions, incident prose)
- `project-hotpath-gate` — the companion builder skill that generates/reconciles
  the config (analog of `project-philosophy`)
- the hotpath-merge-gate brainstorm record — the locked brainstorm (evidence,
  gap analysis, lens details, decisions)
- `coordinator-philosophy-merge-gate` — the companion general-structural gate
  (runs in parallel)
- `.thrum/philosophy.md` — canonical source for general anti-patterns (cross-
  referenced by Lenses 1–2, 6–7 where they overlap)
- `dev-docs/gate-log.md` — the one-line-per-verdict gate log

<!-- THRUM-GATE: stage=skill next=review -->
<!-- THRUM-REVIEW: stage=skill verdict=Ready:Yes cycle=2 -->
