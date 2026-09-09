---
name: coordinator-running-autonomous-feature-development
description: "Use when the coordinator is idle or in a post-merge lull and a small, self-contained, reversible backlog item exists that could plausibly be developed and planned autonomously, with the finished plan still going to the human for go/no-go. Not for inventing work to stay busy, for cross-cutting / schema / release-gating items, for items the human flagged as theirs, or for the dispatch and execution mechanics themselves."
# source: claude-plugin/skills/coordinator-running-autonomous-feature-development/SKILL.md
# generated-by: scripts/sync-skills.sh
---


## Coordinator: Running Autonomous Feature Development

### Overview

When idle and a qualifying backlog item exists, the coordinator drives the whole
front half: scan, select, stand up a brainstormer, **drive the design Q&A on the
questions it owns**, surface only the genuine judgment calls (batched),
dual-review to a clean plan, and present the human a finished plan for go/no-go.
On approval, execution routes through a **standing orchestrator**.

This skill sequences existing coordinator skills and adds two guardrails; it
cites each sibling at its handoff and never restates their mechanics.

**Worked example:** the catch-up / anti-entropy tier — a ~12-task epic taken
scan-to-finished-plan this way.

### When to Use

**Trigger:** you are the coordinator, you have idle capacity (or just hit a
post-merge lull), **and** a real qualifying backlog item exists.

**The trigger is two conditions, not one:** _(a qualifying item exists)_ **AND**
_(idle capacity exists)_. It is **not** "invent work to stay busy." Manufactured
busywork is the failure this skill prevents — see the guardrail below.

**When NOT to use:**

- No qualifying backlog item exists → stay idle. Do not manufacture work.
- The item is cross-cutting / schema / release-gating / public-facing / touches
  the threat model or branch policy → surface to the human first (it fails
  selection — see below).
- You are mid-dispatch or running the back half (execution, code review, merge)
  → those are owned by the sibling skills, not this one.

### The loop (the winning pattern)

| Step                                  | What you do                                                                                                 | Composes (cite, don't restate)                                                                                                                          |
| ------------------------------------- | ----------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1. Scan & select                      | Find a qualifying backlog item (criteria below). Fails any criterion → surface to the human before pulling. | bd backlog / project-state "queued" notes                                                                                                               |
| 2. Stand up the brainstormer          | Spawn a brainstormer in an isolated worktree.                                                               | **`coordinator-running-brainstorm-cycles`**                                                                                                             |
| 3. Drive the Q&A yourself             | Answer design questions you own; batch the genuine judgment calls and surface that batch to the human.      | **`coordinator-running-brainstorm-cycles`**                                                                                                             |
| 4. Dual-review brainstorm & plan      | Run the load-bearing dual-review cycles to ready-to-merge.                                                  | **`coordinator-running-brainstorm-cycles`** review gates                                                                                                |
| 5. Project-setup                      | Convert the approved plan into a bd epic + tasks + impl prompt + worktree.                                  | **`thrum:project-setup`** (the researcher runs it)                                                                                                      |
| 6. Present finished plan to the human | Go/no-go on the finished, dual-reviewed plan. **Mandatory gate.**                                           | —                                                                                                                                                       |
| 7. **Handoff**                        | On the human's go → hand to dispatch. **The route-through-orchestrator guardrail is load-bearing here.**    | **`coordinator-dispatching-work`** → **`thrum:orchestrate`** → **`coordinator-running-review-cycles`** → **`coordinator-managing-state-and-lifecycle`** |

**Project-setup (step 5) is researcher-owned** — the researcher runs
`thrum:project-setup` in their own worktree; it is not coordinator-owned.

**Scope ends at step 7.** Everything past the handoff (orchestrator dispatch,
epic execution, code review, merge) is owned by the back-half siblings.

**Keep the brainstormer warm until merge.** At the handoff the brainstormer is
**not** dismissed — it stays warm as a review tie-breaker through implementation
until merge, then is torn down. It holds the design rationale and adjudicates
review disputes the implementer/reviewer can't resolve.

### Backlog selection — pull autonomously only when ALL hold

1. **Bounded blast radius** — single subsystem/package; not a cross-cutting
   protocol or schema change.
2. **Reversible** — no irreversible data migration; no public-API or release
   commitment.
3. **Narrow design space** — direction already implied by prior decisions; you
   have the domain depth to drive the Q&A.
4. **Sized** — roughly one epic, ~one orchestrator-driven cohort (one
   orchestrator running one epic wave without spawning a second). Soft guidance,
   not a task-count gate.
5. **No manufactured urgency** — not release-gating.
6. **Traceable source** — a bd backlog item, a deferred follow-up, or a
   project-state "queued" note.

**Fail any → surface to the human before pulling.** Hard escalation triggers:
schema migration, cross-version/release-line change, public-facing/website,
security/threat-model shift, branch-policy, or anything the human flagged as
theirs.

**Trigger source matters.** The 6 criteria gate **coordinator-initiated idle
scans** — those require all 6. An **explicit human-directed pull bypasses
criteria 1–6** (the human already made the selection call), **but you still run
the Q&A-vs-escalate logic and the mandatory plan-approval gate.** The human
choosing the item does not waive the finished-plan go/no-go.

### Guardrail 1 — proactive backlog, not idle-and-wait

**Default posture when idle: scan for qualifying backlog and pull it. Do not sit
waiting for instructions.**

**Never write invented discipline into a restart snapshot.** Self-imposed rules
survive restarts and propagate silently — an undocumented invented rule can
outlive its author and later be enforced as if it were the human's mandate.

| Rationalization                                                                     | Reality                                                                                                                                                |
| ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| "I lack explicit authorization to pull this, so I should wait."                     | **WRONG** — the skill authorizes scan-and-pull when all 6 criteria hold. Idle-and-wait is the exact failure mode this skill prevents.                  |
| "I'll write a 'do not manufacture work' rule into my snapshot to stay disciplined." | **WRONG** — that invented rule propagates across restarts unchallenged. Never write invented discipline into a snapshot. |

### Guardrail 2 — ALWAYS route through a standing orchestrator

**NEVER stand up a dedicated implementer yourself. ALWAYS route implementation
through a standing orchestrator.**

The reason, in one line: orchestrators own the implementer lifecycle and the
`--model sonnet` pin; standing one up yourself risks the implementer inheriting
opus. Your lane is dispatch-decision + gate + merge. Full dispatch mechanics
live in **`coordinator-dispatching-work`**.

**Recovery:** if an implementer was ever stood up directly, **tear it down
before handing to the orchestrator.** Do not let the orchestrator adopt a
coordinator-spawned implementer — it may carry the wrong model.

| Rationalization                                                      | Reality                                                                                                                                                                                                                                                                                                   |
| -------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| "I'll just stand up the implementer myself, it's faster."            | **WRONG** — route through a standing orchestrator. |
| "The orchestrator can just adopt the implementer I already spawned." | **WRONG** — it may carry opus. Tear it down first; let the orchestrator spawn its own with the sonnet pin.                                                                                                                                                                                                |

### Coordinator-run Q&A vs escalate

Drive far, surface little.

**Answer yourself when** the question is a technical/design detail inside a
subsystem you understand, has a clear best answer given prior decisions, and is
reversible / low-stakes.

**Escalate to the human when** the answer changes user-visible behavior/shape,
touches philosophy/policy (threat model, release strategy, branch policy),
creates an irreversible commitment, or has multiple defensible options with
material **product** tradeoffs.

**Default behavior:** drive as far as possible, then **batch** the genuine
judgment calls into ONE surfacing — don't interrupt per-question.

**Mid-brainstorm fork:** if a genuinely contentious design fork surfaces
mid-brainstorm on an item that already passed selection, **escalate
immediately** (batch to the human) — do **not** retroactively un-select the
item. Also surface to the human that the **selection criteria failed to catch
the fork**, so the criteria can be tightened.

### Runway management

A refinement of the Q&A rule — how to surface questions without burning your own
context.

- **Default — batch-surface.** The brainstormer surfaces its **full question
  agenda**; you answer in one batch, not per-question round-trips. This is the
  runway-efficient default.
- **Per-question inline** is the variant for short brainstorms (few questions;
  you are the domain driver).
- **Escalate to human-joins-the-pane** when your context crosses the ~50% tier
  **or** the human signals they want to drive — then you step out.

### Human gate

**Mandatory human-in-the-loop:**

1. **Plan approval before implementation dispatch** — go/no-go on the finished,
   dual-reviewed plan (step 6).
2. **Backlog-item selection when the item fails the selection criteria.**
3. **The batched judgment calls** from the Q&A rule, as needed.

**Optional / informational:** progress status, final merge report (the merge
report itself is produced by **`coordinator-managing-state-and-lifecycle`**).

**Do not over-gate.** Once the human approves the plan, **execute and report —
do not re-ask.**

### Red Flags — STOP

- "I'll just stand up the implementer myself." → Route through a standing
  orchestrator.
- "I lack authorization to pull this, so I'll wait." → Scan-and-pull when all 6
  criteria hold.
- "I'll note in my snapshot not to manufacture work." → Never write invented
  discipline into a snapshot.
- "The human picked this item, so I can skip the plan-approval gate." →
  Human-directed pull still hits the mandatory go/no-go.
- "This fork is contentious, so the item was a bad pick — un-select it." →
  Escalate the fork; keep the item in flight.
- "It's a schema/release/public change but small, I'll just pull it." → Fails
  selection. Surface first.
- "The plan is approved, I can dismiss the brainstormer now." → Keep it warm as
  a review tie-breaker until merge.

### Common Mistakes

- **Standing up the implementer directly** — the single most-corrected misstep.
  Always the orchestrator.
- **Surfacing every question** instead of driving and batching — burns the
  human's attention; defeats the pattern.
- **Re-gating approved work** — re-asking after go/no-go. Execute and report.
- **Dismissing the brainstormer at handoff** — keep it warm as a tie-breaker
  until merge.
- **Restating sibling mechanics** here — cite the sibling skill; this skill is
  the spine, not a copy.
