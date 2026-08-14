---
name: coordinator-dispatching-work
description: "Use when starting an epic, dispatching to an implementer, creating a worktree for an agent, or spawning a sub-agent. Loads coordinator-specific discipline for kicking off implementation work."
# source: claude-plugin/skills/coordinator-dispatching-work/SKILL.md
# generated-by: scripts/sync-skills.sh
---


## Coordinator: Dispatching Work

### Use `thrum tmux launch` — not raw send-keys

**Why:** Manual `tmux send-keys 'claude'` followed by `$thrum-prime` skips
identity registration and produces silent CWD drift. The
`thrum tmux launch <name>` flow registers the agent against the worktree path
correctly and gives the daemon a real PID to track. (Source:
findings_coordinator.md — "Use thrum tmux launch — not send-keys — to start a
runtime".)

**How to apply:** Whenever you need to start a runtime in an existing tmux pane,
use `thrum tmux launch <session_name>` even if you've already typed the runtime
command yourself. If you've already started one wrong, kill the pane and
re-launch via the daemon. If the pane doesn't exist yet, use
`thrum tmux start <name>` (creates, launches, primes, attaches in one command).

### Recycling an agent: destroy then teardown

**Why:** The inverse of dispatch is removal, and it has the same "two-step
ritual or things break silently" property as dispatch via tmux launch + thrum
send. See `coordinator-managing-state-and-lifecycle` § "Destroy an agent before
tearing down its worktree" for the canonical sequence (`thrum tmux kill` BEFORE
`thrum worktree teardown`). The dispatching skill mentions it here so you find
the cross-reference when planning a wave recycle, not just when reading the
lifecycle skill end-to-end.

### Never spawn sub-agents into worktrees where Thrum agents are running

**Why:** Sub-agents (Agent tool) and Thrum agents (`thrum send`) are different
coordination mechanisms. A sub-agent spawned into a worktree where a Thrum agent
already sits competes for files, identity, and tmux state — the result is
identity drift, broken nudges, and silent message loss. (Source:
findings_coordinator.md — "No sub-agents into live worktrees".)

**How to apply:** Run `thrum team` before spawning any Agent tool call. If a
worktree shows a registered agent, communicate with it via
`thrum send --to @<agent_name> --body-file msg.md` instead. Sub-agents are for
research/explore, code review, and message listeners running in the main repo —
never for implementation work in another agent's worktree.

### Dispatch via `thrum send` after launch — not via tmux send-keys

**Why:** After `thrum tmux launch`, all coordination flows through the inbox +
daemon nudge: `thrum send` enters the message in the daemon's state, the daemon
nudges the pane, the agent reads the inbox and starts work. Injecting the prompt
with `thrum tmux send` or `tmux send-keys` bypasses the inbox entirely, breaks
the nudge for future messages, and strands the agent without a recorded message.
(Source: findings_coordinator.md — "Dispatch via thrum send after tmux launch,
not via tmux send-keys".)

**How to apply:** Correct flow: `thrum tmux launch <name>` → agent auto-primes →
`thrum send --to @agent_name --body-file prompt.md` (body: work prompt) → daemon
nudges the pane → agent reads inbox and begins work. Never inject the prompt as
raw keystrokes.

### Always dispatch sub-agents in the background — never block the coordinator

Set `run_in_background: true` on every Agent/Explore call, without exception.
The coordinator is long-lived and must never block on a result — after
dispatching, continue with inbox checks, task tracking, or the next dispatch
draft; slot the result in when notified (even if it's "needed before" the next
step). Account token cost is irrelevant; preserving coordinator context is the
optimization.

### Subagent model selection

> **Model tiers:** pass an explicit `model:` on every dispatch — `sonnet`
> (low effort) mechanical, `sonnet` (medium effort) judgment, Opus only on
> operator-ask or a skill step that names it. See the
> `choosing-subagent-models` skill for the full policy.

### Check the target's queue before you dispatch (R3)

Before dispatching, confirm the agent isn't already loaded: `thrum queue list --agent
<target>` (message it to confirm if its state is unclear). An empty result does NOT
mean free — it also shows for an agent that keeps no queue or that you mis-named;
confirm by message before assigning. `assign` appends to `assigned_to` with no
duplicate check, so this pre-dispatch read is the only guard against double-loading a
busy agent. Record the handoff on your own queue with `thrum queue assign <bundle>
<target>`, then send the real dispatch via `thrum send`.

One bundle per epic/branch handed out — keep it reconciled as the work moves
(`start` → review → merge-gate → torn down), per `using-the-queue`.

### Bundle adjacent open issues into every dispatch

**Why:** Priority order and code locality are INDEPENDENT axes, and sequencing by
priority alone silently optimizes the wrong one. The expensive part of any task is
loading the context — the package, the call paths, the invariants. Once an
implementer has paid that cost, a second bead two files away is nearly free. Ship
them one at a time to cold implementers and you pay full context load for each,
while a P0 sits in the queue purely because it sorted into a different row.

Most backlogs are far more adjacent than their titles suggest. Bundling collapses
the queue fast; one-at-a-time dispatch is the wasteful default that feels orderly.

**How to apply — the coordinator half:**

Before sending ANY dispatch, run an adjacency pass. Delegate it (it is a wide read
across beads and packages — exactly what should not burn coordinator context):

1. Determine each item's CODE AREA — package, subsystem, files. Derive it from
   `bd show <id>` **plus reading the code**, never from the bead title. Two beads
   with similar titles may live in different packages; two with unrelated titles
   may share a file.
2. Find OPEN issues touching those same areas — **including higher-priority ones**.
   A P0 adjacent to a P2 you are dispatching is the whole point of this pass.
3. Name the inverse too: which open issues have NO adjacency to this batch. That
   set is what genuinely stays unstaffed, and stating it stops a later reader from
   mistaking an un-surfaced issue for a deliberately parked one.
4. **You make the ride-along call.** The sub-agent reports adjacency and evidence;
   it does not rank, prioritize, or decide.

Do this at SEQUENCING time, before dispatch messages go out. Afterwards the routing
is committed and folding an item in costs more than the pass saves.

> 🔴 **NEVER run `bd list --all`** while doing this, in any form — `--all --limit N`
> is STILL unbounded (the limit is discarded) and has twice driven a box to seconds
> from swap exhaustion. Get ground truth from `bd stats`, bound above that count,
> and **verify the printed `Total:` is not equal to your limit** — equal means you
> are at the ceiling and were silently truncated. Put these rules in the sub-agent's
> brief; it cannot see the damage from where it runs.

**How to apply — the orchestrator half (this is where validity gets checked):**

Do NOT try to verify the adjacent items are still valid yourself. You are cold, and
your list goes stale between the pass and the dispatch. **The orchestrator cuts its
branches from the CURRENT tip and merges forward onto it (never rebases) before
handoff**, so it is working against today's code — which makes validity checking
nearly free at exactly the moment it is accurate.

So dispatch adjacent items as CANDIDATES and say so explicitly. The orchestrator's
own skill (`orchestrate`, Phase 1 Step 2b) defines what that word obligates; you do
not need to restate the procedure in the dispatch, only to mark the items clearly
and give each one its bead ID.

What comes back: still-valid candidates get folded into the warm implementer;
already-fixed ones return to you as COMPLETED with evidence so **you close the
bead** — draining the queue with nobody implementing anything; ambiguous ones
return as questions. You should receive a disposition for EVERY candidate,
including the folded-in ones.

**Expect returns, and act on them.** A candidate returned as already-fixed is only
half-drained until you actually close the bead.

### Prompt construction for implementers

**Why:** Implementer agents work better with a structured handoff than a
free-form request. Inconsistent dispatch produces inconsistent reports and
re-dispatch overhead.

**How to apply:** Every dispatch prompt should include:

1. The epic/task title and bead ID
2. One-paragraph scope (what to build, what NOT to build)
3. Acceptance criteria as bullets
4. The worktree path the work happens in
5. An explicit reminder to pass `model:` on any sub-agents the implementer
   spawns (sonnet-low for mechanical, sonnet-medium for judgment)
6. Spec/plan paths to read before starting
7. **Adjacent candidate beads** from the adjacency pass above, labeled as
   CANDIDATES with their validity explicitly unverified — plus the instruction to
   check them against the merged-forward tip and either fold them in or return
   them as completed

### Never rename an agent tied to a worktree

**Why:** Agent identity is bound to the worktree, not the epic. Re-registering
`@implementer_api` as `@implementer_billing` mid-flight creates two identity
files in the same worktree, causing persistent stop-hook misfires and routing
failures. (Source: findings_coordinator.md — "Never rename an agent tied to a
worktree".)

**How to apply:** Run `thrum team` before assigning new work to confirm the
existing identity name. Send work to that name. Do not use `thrum quickstart`
with a new name in a worktree that already has an identity. If you absolutely
need a fresh identity, kill the existing tmux session and register a new one
with a different name — do not rename in place.

### Propagate model-selection discipline downward

**Why:** Sub-agents inherit the parent model by default. A coordinator on Opus
that spawns an unspecified sub-agent gets Opus-cost work for tasks that need
sonnet-low. The same trap repeats inside an implementer's worktree: if the
implementer doesn't propagate the discipline, their own sub-agents silently
inherit too. Cost compounds across a session. (Source: findings_coordinator.md —
"Always pass explicit model on sub-agent spawns".)

**How to apply:** Every dispatch prompt should include the model-selection rule
explicitly: "When you spawn your own sub-agents, pass explicit `model:` —
`sonnet` (low effort) for mechanical work (lint, tests, find/replace), `sonnet`
(medium effort) for judgment work (review, complex implementation), `opus`
only when justified. Default to sonnet over opus." Audit the dispatch prompt before sending.

### The impl-prompt review stamp satisfies pre-dispatch review

**Why:** When the planning-skill review loop runs, its final gate reviews the
implementation prompt against the plan — which IS the pre-dispatch review.
Re-running a pre-dispatch prose review on a prompt that already passed the loop
double-reviews the same artifact and wastes a cycle.

**How to apply:** At dispatch, grep the impl-prompt for the loop's verdict stamp
(case-sensitive, literal):

```bash
# Anchored, NOT -F: `verdict=Ready:Yes-with-residual` satisfies a bare
# substring match and skips the pre-dispatch review entirely.
grep -E 'THRUM-REVIEW: stage=prompt verdict=Ready:Yes([[:space:]]|-->|$)' "$PROMPT_FILE" \
  || grep -E 'THRUM-REVIEW: stage=prompt verdict=OVERRIDE([[:space:]]|-->|$)' "$PROMPT_FILE"
```

- **Stamp present** → the pre-dispatch review is already satisfied; SKIP
  re-running it and dispatch.
- **Stamp absent** → fall through to the normal pre-dispatch dual review. Do NOT
  block dispatch on the stamp — it is a shortcut that lets you skip a redundant
  review, not a new hard requirement (pre-feature prompts and prompts from other
  flows won't carry it).

This is the prose side of the boundary; the post-DONE dual-review (which reviews
the implementer's CODE, a different artifact) always runs separately. The prompt
is never reviewed twice. (See `coordinator-running-review-cycles` for the
post-DONE side.)

### Dispatching to an Orchestrator (Manager-Tier Flow)

When the fleet has standing orchestrators and the work is a full plan execution:

#### Step 1: Select an orchestrator

```bash
thrum team  # identify free orchestrators
# Read State.md for each free orchestrator to check affinity:
cat .thrum/agents/<orchestrator_name>/State.md | head -50
```

#### Step 2: Send the plan

```bash
thrum send --to @<orchestrator_name> --stdin <<'EOF'
Plan assigned: <plan-file-path>
Summary: <one-line>
Merge target: <branch>
Epic count: N
Invoke $thrum-orchestrate to begin.
EOF
```

#### Step 3: Your role during execution

- You receive the orchestrator's merge report when all epics complete.
- Run your merge-approval gate (see Merge Approval Gate in your preamble).
- Monitor the orchestrator's status updates; escalate to Leon only for genuine
  judgment calls (architectural pivot, scope change, budget concern).

### See also

- `dev-docs/process/2026-07-22-idea-to-merged-end-to-end-process-capture.md`
  — the full idea-to-merged pipeline; this skill covers Stage 5 (dispatch).

### Project-specific rules (already loaded)

Project-local rules of kind `agent_rule` at `--scope role` were loaded at
session start by your preamble (see your role template's Memory model block). If
a project-local rule conflicts with a universal rule above, the project-local
rule wins; surface the conflict in your reply so the user can decide whether to
graduate or remove the override.

If you accumulate a new rule mid-session (the user corrects you), capture it via
the `coordinator-maintaining-memory` skill — it references the
`memory-write-discipline` common for the canonical `thrum memory create` shape.
