---
name: coordinator-merging-code
description: "Use the moment code is presented for merge - a merge report arrives, an agent says MERGE-READY or RECOMMEND MERGE or the branch is ready, you are asked to approve or land or ship a branch, you are about to run git merge, or you are consolidating review findings before a merge. Loads the full merge sequence - dual review as a PRECONDITION not the gate, the mechanical merge-worthiness pre-gate, DISPATCHING both Pass-3 gates to the Gate Runner rather than walking the lenses yourself, tripwire checks, gating the MERGED tree, the committed verdict artifact, the efficacy row, and branch disposal."
---

# Coordinator: Merging Code — the full sequence, every time

**Check whether you are the merge king for THIS branch before running this
sequence.** Do not assume — read it from config:

```bash
jq -r --arg b "$(git branch --show-current)" \
  '.orchestration.merge_kings[$b] // "unset"' .thrum/config.json
```

If it names you, you are the merge king for this branch — proceed with the
sequence below. If it names someone else, route the merge to them instead of
running it yourself. Nothing lands except through this sequence, run by
whichever coordinator the map names.

**`orchestration.merge_kings` may not be populated for every branch yet** (the
jq command above will print `unset` in that case). An `unset` result does NOT
mean "nobody is merge king, proceed" — it means the map hasn't caught up to
this branch. Fall back to whichever coordinator has actually been the merge
authority for this branch in practice (check with your team, or your
project's own operational convention); if that is not you, route the merge
to them the same as if the map had named them explicitly.

> 🔴 **THE ONE THING MOST OFTEN GOT WRONG: YOU DO NOT RUN THE GATES. YOU DISPATCH
> THEM TO THE GATE RUNNER.** See §3. A coordinator that walks the lenses inline
> burns the one resource it cannot replace and leaves **no auditable verdict** —
> and it will feel like diligence the entire time.

## 0. What this skill is, and what it is not

This is the **coordinator-facing index and running order.** The lens content lives
in the two gate skills; the runner's own discipline lives in the `gate` role
preamble.

**Do not duplicate lens definitions here.** Point at them and keep the order.

## 1. PRECONDITION — dual review, and it is NOT the gate

Two axes, run in parallel, on the branch: **code-quality** and **spec-compliance /
verify-against-plan**.

**Before treating dual review as clean, confirm BOTH axes EMITTED** — name the
agent and either one finding or an explicit zero, per axis. **An absent report and
a clean report are different things**, and silence defaults to the reading you
want. If an axis goes silent twice, re-route it rather than re-spawning.

**A verdict attaches to an OBJECT.** If the branch takes a new commit after review
— including a merge-forward — the prior verdicts do not transfer. **Re-dispatch the
axes on the delta.** A fix produced in response to a finding is exactly where the
next defect lives.

**Consolidate into ONE numbered list** across all severities before anything goes
back to the implementer. Never send partial findings; they fix batch 1 and miss
batch 2.

**Verify a finding against source before forwarding it, and verify pushback the
same way.** Reviewers misread files. Pushback is a feature, not insubordination —
and a trace-correction from an implementer is welcome.

## 2. MECHANICAL MERGE-WORTHINESS PRE-GATE — run every time, in this order

```bash
# 1. FETCH BRANCH-EXPLICITLY. A bare `git fetch` is not enough.
git fetch origin 'refs/heads/<branch>:refs/remotes/origin/<branch>'

# 2. RESOLVE FROM ORIGIN, NOT THE LOCAL CACHE. `origin/<branch>` is a cache of your
#    last fetch and will happily report a branch that never left the submitter's box.
git ls-remote origin <branch>

# 3. PROVE THE OBJECT EXISTS *BEFORE* ANY ANCESTRY CLAIM. A fabricated sha and an
#    unfetched one produce IDENTICAL not-ancestor output.
git cat-file -t <sha>

# 4. ANCESTRY — MIND WHICH PAIR. Doubtful thing on the RIGHT, known base on the LEFT.
git merge-base --is-ancestor <base> <tip>
# CONTROL: an invented/all-zeros sha must FAIL the same check.
```

🔴 **`--is-ancestor <merge-base> <tip>` is TRUE BY DEFINITION — a vacuous green.**
When you supply SHAs anywhere, **say which PAIR to test**: the tree WITHOUT the
change and the tree WITH it.

**Assert HEAD is attached** (`git symbolic-ref -q HEAD`) and that you are on the
merge target before merging.

## 3. PASS-3 GATES — DISPATCH BOTH TO THE GATE RUNNER

**Resolve the Gate Runner from `thrum team` by its `gate` ROLE — never by a
remembered agent name.** A name in a skill goes stale exactly like a copied model
tier.

Record the dispatch on your own queue (`thrum queue assign <bundle>
<gate-runner>`) per `coordinator-dispatching-work`'s queue step before
sending the gate dispatch.

🔴 **WHERE THE LONG / tmux-SENSITIVE LANES RUN — a DEDICATED NON-FLEET gate box, never
a populated one.** The integration lane and the rpc race suite create FIXED-NAME tmux
fixtures on the shared fleet socket; on any box with live agents they COLLIDE, and every
such red is a FALSE positive you then burn effort classifying as "pre-existing/env." Run
them where the verdict is TRUE — a box with zero live agents. The value is a CLEAN verdict,
NOT speed (wall-clock is not faster; lane invocation serializes regardless of the
parallelism flags). **The specific box + ssh/access for THIS fleet is in project_state
(`DEDICATED GATE BOX`), not here — this rule is general.** If you catch yourself dispatching
the gate to a populated box "because the runner lives there," that is the exact forgetting
this line exists to stop.

| Gate | Skill | Skippable? |
|---|---|---|
| Hot-path | `coordinator-hotpath-merge-gate` | **Only** if the diff touches zero `trigger_directories` |
| Philosophy | `coordinator-philosophy-merge-gate` | **NEVER** |

**Read the trigger directories and the lens count FROM `.thrum/hotpath-gate.json`,
at the tree under gate — never from prose, including this file.**

⚠️ **If your trigger-dir query returns EMPTY, treat it as a broken key until
proven otherwise.** A typo'd `jq` path and a clean skip are byte-identical in the
output.

**Skip BOTH only for a one-line config change, a typo, or a test-only diff.**

**Dispatch is the default at every diff size.** Diff size changes what you ask
for; it never changes who runs it. Only run a gate yourself when **no** gate-role
agent exists — and then say so explicitly in the merge record, so the gap is
visible rather than invisible.

### What the dispatch must contain

The gate answers the question you ask it. Four required sections:

1. **The enumeration key AND any output filter.** A gate can narrow the key
   without touching the key — widest grep, then filter the *output* on incidental
   vocabulary — and produce an identical confident "none" about a population it
   silently excluded.
2. **"VERIFICATION EXECUTED — every command + its EXIT, or the words NONE RAN."**
   A CLEAN that never states its support is **unfalsifiable** and silently
   defaults to the lane-backed reading. A static-only CLEAN is legitimate and is a
   DIFFERENT CLAIM.
3. **Name ONE test runner, or serialize the lane.** Parallelism is free for
   reading and unsafe for executing. The rpc suite creates FIXED-NAME tmux
   fixtures on the SHARED FLEET SOCKET; the resulting `duplicate session` failure
   is indistinguishable from a genuine branch regression.
4. **Diff each gate's proposed efficacy line against its own report body** before
   it lands. One contradicted itself precisely in the half a busy runner pastes
   unread.

Also supply **the SHA pair**, **specific questions** (a gate briefed with "review
this" returns generic coverage), and **the pre-cleared non-findings list** — things
already ruled zero-diff on purpose.

**Fence: split it.** The runner gets `commit`/`push` path-fenced to its own gate
worktree; its sub-agents get READ-ONLY git. `checkout`/`reset`/`restore`/`stash`/
`clean`/`rebase` forbidden in **every** directory for both. Give an escape hatch
for instrument-and-undo (a `cp` copy, or edit-then-revert) or the careful agent
breaches the fence doing good work. **Use `rm -r`, NEVER `rm -rf`.**
**Pasting a fence is not enforcing it.**

## 4. THE EXECUTED VERIFY — SCOPED TO THE CHANGE

The §3 lens gates (hotpath + philosophy) are the judgement half. The per-merge
executed half is **scoped to the change**:

- Build the merged tree (`go build ./...`).
- Full-*package* `-race` on the **changed packages only** — full-package, never
  targeted `-run` (a targeted run misses cross-test races), but only what the diff
  touches.
- The fast structural checks on the merged tree — `gate-ban-check`,
  `gate-omitempty-check`, `gate-lockspan-check`, `gate-marker-diff`,
  `gate-stamp-protocol-check` (seconds each; they catch banned flags, `omitempty`
  drift, lock-span, marker and stamp drift regardless of the change).
- The `merge-base --is-ancestor` fast-forward check (§6).
- Any `*_tripwire_test.go` the change touches must stay green or the diff must
  state why its premise changed; a tripwire edited to accommodate the change is a
  finding, not a fix.

**Establish branch-attributable vs pre-existing from the changed-package `-race`
result** — a regression adds failures the same packages did not have before. Do
not classify a scoped change by replaying the whole known-red suite.

🔴 **Do NOT run the full all-lanes `make gate` for a merge.** The full suite —
every package across lanes A/B/C/D, the integration lane, `gate-ci-mutation-check`,
the UI lane, the full tripwire/boxstate reconciliation — is the **periodic
full-gate cadence**, an agent run on the dedicated isolation box, and it is its own
skill: **`coordinator-full-gate`**. A merge never triggers it, and its merge-base
replay is not a per-merge step. Running it per merge is ~2h that on a common-mode-
red trunk fails on the baseline every time.

🔴 **Never kill a test run to stop a collision.** Killing skips Go's cleanup, which
leaks fixed-name tmux fixtures onto the shared socket and breaks that suite box-
wide. Let it finish, tell the other runner its results are contaminated, re-run
after.

## 5. GATE THE MERGED TREE, NOT THE BRANCH

A clean pre-merge build does not prove the merged result compiles or passes.
**Merge locally, then build and test, then push — guarded on the merge's exit
status, never on having reached the line.**

🔴 **A `//go:embed`-ed ASSET IS A TEST SURFACE. Run the embedding package's suite
on the merged tree even when the diff contains ZERO lines of Go.** "Docs-only" is
not a risk category; "compiled into the binary" is. Both static gates are blind to
this by construction — only execution sees it.

**Ask "did anything under an embed path change", never "did any `.go` change".
Carry the command, never the list:**

```bash
git grep -l -E '^//go:embed' <sha> -- '*.go'   # anchored ^ — unanchored pulls in prose
```

The role templates are not the risky entry — **skill files, references and
strategy docs are compiled in too**, so every skill edit and strategy-doc edit is
a code change, and those are exactly the diffs routed as low-risk `docs:`.

⚠️ **"Comment-only" is not a safe carve-out in Go.** `//go:embed`, `//go:build`
and `//nolint` are comments with semantics. A diff with zero non-comment changed
lines can still change what is compiled in. Assert zero changed lines matching
`//(go:|nolint|\+build)`, **with a control proving the key can fire.**

**Redirect test output to a FILE and read the file. Never pipe a test through
`tail`** — `$?` after a pipeline is `tail`'s status, so a FAILED run reports
success, and the dropped lines include the goroutine dump that separates a
deadlock from an assertion failure.

**When a suite is red, establish pre-existing vs introduced by running the same
suite at the merge-base** in a throwaway detached worktree — check the
discriminator, don't assume from the platform: `[ -L /tmp ]`. macOS (symlink)
needs `/private/tmp`; Linux (real dir) uses `/tmp` (`/private/tmp` may not
exist there and must not be created) — and **compare failing sets BY NAME, not
by count.** Sets differing in both directions indicate flakiness; a regression
adds failures without removing any.

## 6. RE-DERIVE ANCESTRY IN THE SAME TURN AS THE MERGE

**An ancestry check from ten minutes ago is not a check.** Trunk moves. Bind the
re-derivation to the irreversible ACT, not to a ceremony earlier in the sequence.

Resolve trunk through its **remote-tracking ref**, and prefer two instruments
agreeing (`rev-parse origin/<branch>` and `ls-remote`). **Assert the branch TIP**
— ancestry proves a merge EXISTS, never WHAT landed.

## 7. AFTER THE MERGE — four things, none optional

1. **The verdict artifact.** The runner saves verdicts to
   `dev-docs/gate-reports/<ISO-week>/<date>/<gate-slug>/` and **commits them
   BEFORE removing any worktree.** Save → commit → then destroy. A verdict that
   exists only in a message cannot be audited later.
2. **The efficacy row**, in `dev-docs/hotpath-gate-efficacy.md` — required for
   **every** trigger-dir merge, including `SKIPPED_WITH_EVIDENCE` rows and
   orchestrator-run merges. The log measures gate **coverage**, not just outcomes.
   Record `FALSE_POSITIVE=0` explicitly on a clean run so the zero is a
   measurement rather than an absence.
3. **Commit accumulated agent state** under `.thrum/agents/` along with the merge.
   Uncommitted agent state exists in exactly one working tree, and it IS the
   agent's memory across restarts. **Never `git add -f`.**
4. **Delete the merged branch AND drop its queue bundle — one ritual, at merge
   time**, after the push is verified. `feature/*` and `fix/*` are one-shot —
   delete freely. **`agent/*`, `salvage/*`, `website-dev` and `release/*` are
   ongoing or archival — do NOT delete.** Then, in the same turn: `thrum queue
   done <bundle>` + `thrum queue drop <bundle>` for the bundle that tracked this
   branch, and `bd close <id>` any beads this merge closed. A merge is not
   complete until the branch ref AND its queue bundle are both gone — the same
   act that lands the code retires its tracking.

## 7a. BEFORE YOU ACCEPT A VERDICT — CONFIRM THE RUNNER TORE ITS OWN THINGS DOWN

A gate leaves behind worktrees, agents AND tmux sessions. The worktree half is
covered in the runner's preamble; the agent/session half needs the same check.

**Ask for it in the verdict, and verify it yourself — it is one command:**

```bash
thrum tmux status | grep -E '^\s*g[0-9]+'    # gate sessions, agentless ones included
```

🔴 **`thrum team` and `thrum agent list` CANNOT SEE an agentless session.** Five of
those nine had no registered agent, so a registry-based enumeration returns a
confident answer that omits most of the population. **Enumerate sessions, not
agents.**

🔴 **AND WATCH FOR `--force` IN THE TEARDOWN REPORT. `git worktree remove` REFUSES at rc=128 on untracked files — THE REFUSAL IS THE PROTECTION, NOT THE ENUMERATION.** A clean enumeration therefore *invites* the flag that removes it. **Any `--force` must arrive as an OVERRIDE with a justification, never as a pass**, and a clean guard result is not a justification.

**A verdict is not complete until its runtime is gone.** Accept the finding, then
ask: which worktrees, which agents, which sessions, and what does the count read
now. **Never run `thrum agent cleanup --force`** to tidy up — its "orphans"
include live agents fleet-wide.

## 8. MERGED != INSTALLED != RUNNING

Three facts; only the third is behaviour. A merged fix to any `//go:embed`-ed
template or skill is **dead until a binary carrying it runs**, and the running
binary may rewrite generated files from its own stale embedded copy meanwhile.
**A generated file is never admissible evidence of what is merged.**

Say which of the three you verified. "Deployed" that silently covers all three
hides staleness.

## 9. Red flags — STOP

- Walking the Pass-3 lenses yourself when a gate-role agent exists.
- Treating dual review as the gate.
- Carrying a prior verdict onto a new SHA.
- An efficacy row that contradicts its own report body.
- Reading `--is-ancestor <merge-base> <tip>` as a check.
- A zero from a trigger-dir query, accepted without a control.
- `go test … | tail`, or `$?` read after any pipe.
- Pushing without guarding on the merge's exit status.
- Declaring a class closed on a count you did not re-derive.
- Deleting `agent/*`, `salvage/*`, `website-dev` or `release/*`.
- Pushing a merge without dropping the queue bundle that tracked it.

## See also

- `coordinator-hotpath-merge-gate` · `coordinator-philosophy-merge-gate` — the lenses
- `coordinator-running-review-cycles` — the dual-review cycle feeding §1
- `coordinator-branch-split-on-block` — when a gate blocks one concern of a bundled branch
- `dev-docs/gate-reports/README.md` — the artifact contract
- `.thrum/hotpath-gate.json` · `.thrum/philosophy.md` — the configs; read these, not prose

## Project-specific rules (already loaded)

Read the shared partial at the absolute path:
`claude-plugin/commands/_project-rules-protocol.md`

If you accumulate a new rule mid-session (the user corrects you), capture it via
the `coordinator-maintaining-memory` skill — it references the
`memory-write-discipline` common for the canonical `thrum memory create` shape.
