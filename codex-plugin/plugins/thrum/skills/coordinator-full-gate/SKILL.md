---
name: coordinator-full-gate
description: "Use when running or dispatching the full gate suite — the periodic full-gate cadence (the daily or on-demand whole-tree gate), an agent run on the dedicated thrum-perf-test isolation box. Not a per-merge step and not a single make-gate command. Fires on - about to run the full gate, the scheduled or daily full-gate fire, an on-demand whole-tree gate, the full-gate-test-history cadence, a release-prep full gate, driving trunk toward green. A scoped merge is verified by coordinator-hotpath-merge-gate + coordinator-philosophy-merge-gate + a changed-package build-and-race, and must never trigger this."
# source: claude-plugin/skills/coordinator-full-gate/SKILL.md
# generated-by: scripts/sync-skills.sh
---


## Coordinator: Full-Gate Suite

The full-gate cadence — the daily or on-demand whole-tree gate. An **agent** runs
it on the dedicated isolation box, following
[`dev-docs/FULL-GATE-STEPS.md`](../../../dev-docs/FULL-GATE-STEPS.md) end-to-end
each run: wake, sync trunk and record the SHA, fail-loud preflight, the per-package
bounded sweep, classify every failure, write the report from
[`full-gate-test-history/TEMPLATE.md`](../../../dev-docs/full-gate-test-history/TEMPLATE.md)
into `full-gate-test-history/<stamp>-<sha>/result.md`, index and commit. The steps,
box preconditions, and failure classes live in that doc — follow it, do not restate
it.

### Run only on the dedicated isolation box

Run the full suite **only on the dedicated box with zero live agents**
(`thrum-perf-test` on this fleet; read the current box and its access from
project_state's dedicated-gate-box entry). Never run it on a populated box — the
tmux-sensitive lanes create fixed-name fixtures on the shared socket that collide,
produce `duplicate session` failures indistinguishable from a real regression, and
disrupt live agents.

### Not for a merge

A merge is verified by the scoped gates — `coordinator-hotpath-merge-gate` +
`coordinator-philosophy-merge-gate`, plus a build of the merged tree and a
full-package `-race` on the changed packages only. Do not run the full suite, or
its merge-base replay, for a merge.

### The deliverable is a classification, not a count

For each failure, assign one class — REAL, ENVIRONMENT, TEST-PORTABILITY,
INFRA-COLLISION, STALE-ORACLE, or TIMEOUT — from the failure text, and record what
to do about it. A run that emits pass/fail counts without classification has not
produced the deliverable. If the preflight fails, or the sweep executes no tests,
the run records `HARNESS_FAILURE` and emits no verdict.

### Consuming a run

Read the newest `result.md`, take its **"What to fix next"** list, and file or
assign the REAL and STALE-ORACLE items. ENVIRONMENT and INFRA-COLLISION are
box-provisioning follow-ups; TEST-PORTABILITY are review-gated test fixes — the
runner records and proposes, the coordinator assigns. Track the trend across runs.

### See also

- [`dev-docs/FULL-GATE-STEPS.md`](../../../dev-docs/FULL-GATE-STEPS.md) — the
  step-by-step procedure the agent follows each run.
- `dev-docs/full-gate-test-history/` — `TEMPLATE.md`, `INDEX.md`, `CLAUDE.md`.
- `coordinator-hotpath-merge-gate` · `coordinator-philosophy-merge-gate` — the
  per-merge lens gates a merge uses instead of this.
- `coordinator-merging-code` — the merge sequence that dispatches the per-merge gates.
- project_state § dedicated-gate-box — the current isolation box and its access.
