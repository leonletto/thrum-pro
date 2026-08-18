---
name: coordinator-managing-state-and-lifecycle
description:
  "Use when ending a session, when updating project state, when managing beads
  epics, or before session close. Loads coordinator-specific discipline for
  owning project state and shepherding the team's lifecycle."
# source: claude-plugin/skills/coordinator-managing-state-and-lifecycle/SKILL.md
# generated-by: scripts/sync-skills.sh
---

## Coordinator: Managing State and Lifecycle

### Project state is the coordinator's exclusive responsibility

**Why:** Project state captures session-level context (what shipped, what broke,
what's next) and feeds the next session's priming. If implementers update it,
role separation collapses: the implementer's view of state is their epic, not
the team's.

**How to apply:** Only the coordinator runs `$thrum-update-project` or edits
`.thrum/context/project_state.md`. If an implementer is about to restart and
asks how to preserve context, instruct them to send a status message to you and
wait — you update the state on their behalf. Never run `thrum context save`
manually; it overwrites accumulated session state.

### Specs and plans always go in `dev-docs/specs/` and `dev-docs/plans/`

**Why:** Worktree-local paths aren't shared with the coordinator or other
agents, and `docs/superpowers/` was added to `.gitignore` — specs written there
became invisible to anyone outside the writing worktree.

**How to apply:** When writing a spec, plan, or design doc, use an absolute path
under the main repo's `dev-docs/specs/` (specs) or `dev-docs/plans/` (plans).
Confirm the path before writing. If a doc was previously written to a
worktree-local path, move it before referencing it in dispatch messages.

### Promote ruling-grade bead content to `dev-docs/specs/` at ruling time

**Why:** A ruling captured only in a bead body is not durably findable. Tier-1
semantic compaction (30 days closed, ~70% reduction) summarizes/truncates a
closed issue's description and notes in the active record, so an agent that
reads or greps the active bead sees a truncated body and cannot surface the
ruling — while a dev-docs/specs file is neither truncated nor unreachable.
Whether the pre-compaction original is recoverable is contested between the two
tool docs; the findability argument holds either way, because normal read/grep
of the active record fails regardless and nobody runs `bd restore` on a bead
that looks complete.

**How to apply:** When a RULING-GRADE decision lands in a bead — a substantive
decision Leon or the coordinator makes that changes project direction (e.g. an
architecture ruling, a scope decision, a design approval), not a role-rule and
not a routine status update — promote it to `dev-docs/specs/` (or a
decision-record file) **at ruling time**, not deferred to session close. The
bead body then references the spec file instead of carrying the full ruling
text.

### Push the coordination branch before ending a session

**Why:** Unpushed work is stranded locally and invisible to other agents and
machines. If the machine shuts down, the session crashes, or a new worktree is
created from origin, unpushed commits can be lost or inaccessible.

**How to apply:** Session close protocol — push the coordination branch every
session end. **Read the branch name, never recall it:**
`jq -r '.orchestration.merge_target' .thrum/config.json` (or your project's
CLAUDE.md § Branching Strategy). Push every `feature/*` and `fix/*` branch too.
A docs/site branch pushes only when the site is ready to deploy; `main` and
`release/*` go through the release flow.

### Use beads dependency-direction syntax correctly

**Why:** `bd dep <blocker> --blocks <blocked>` reads naturally — the blocker
blocks the blocked task. The reversed form `bd dep add <blocked> <blocker>`
exists but flips argument order, and getting it backwards silently inverts the
dependency graph. Inverted deps make `bd ready` return wrong tasks and create
circular blocking that no UI flags.

**How to apply:** Use the verb form:
`bd dep <blocker_id> --blocks <blocked_id>`. Read it as "blocker blocks
blocked." Always verify with `bd dep tree <epic>` after creating a dependency
batch — the visual tree exposes inversion immediately. For bulk epic creation
(many tasks at once), spawn parallel sub-agents to issue the `bd create` calls;
bd is fully concurrent-safe.

> **Model tiers:** pass an explicit `model:` on every dispatch — `sonnet` (low
> effort) mechanical, `sonnet` (medium effort) judgment, Opus only on
> operator-ask or a skill step that names it. See the `choosing-subagent-models`
> skill for the full policy.

### Use `bd close --suggest-next` to surface unblocked work

**Why:** Closing a task often unblocks downstream tasks, but you only see the
new ready set on the next `bd ready` call — and by then the context of "what
just freed up" is lost. `bd close <id> --suggest-next` prints newly-ready issues
immediately after the close, so dispatch is one decision away.

**How to apply:** When closing a task that has dependents, use
`bd close <id> --suggest-next`. For batch closes (`bd close <id1> <id2> <id3>`),
re-run `thrum issue ready` after the batch — the cumulative effect of multiple
closes is hard to predict.

### Restart discipline — burn the runway, don't pre-empt

**Why:** Restarting at a "clean checkpoint" feels safe, but most checkpoints
aren't truly clean — there's always one more thing in flight. Pre-empting wastes
the remaining context window and re-incurs restart-cost (re-prime, re-orient,
re-load state). The right move is to burn the runway up to the configured
threshold, then restart. (Source: feedback_restart_discipline.md.)

**How to apply:** Don't restart at the first natural pause. Check the configured
restart threshold (`thrum config show restart`) and let the session run until
you actually approach it. If you're under the threshold and have a coherent task
to advance, advance it.

### Destroy an agent before tearing down its worktree

🔴 **BEFORE reaping ANY worktree — especially a batch reap to reduce the
worktree count or relieve load — assess liveness FIRST via
`coordinator-assessing-agent-completion`.** Its safeguard is DIRECT-OBSERVATION
liveness (live tmux pane / ppid). A snapshot-presence check detects only
SLEEPING agents; a LIVE agent has no snapshot, so filtering on "no restart
snapshot" reaps live agents. Never batch-reap `git worktree list` on a proxy
heuristic. The reap preconditions (HEAD containment, only-copy untracked state,
direct-death observation) are mandatory.

**Why:** `thrum worktree teardown <name>` does exactly what its name says — it
tears down the **worktree** — and is intentionally not coupled to runtime
lifecycle. If the agent's runtime is still running in tmux when you teardown,
the runtime keeps executing zombie-style with its cwd pointing at a deleted
directory. The next operation the user attempts in that tmux pane fails
confusingly, and they have to manually `tmux kill-session` and exit. (Source:
direct user correction — coordinator had reported an agent "removed" after
running only the worktree teardown.)

**How to apply:** When recycling an agent (epic done, agent should be removed),
run the two-command destroy sequence **in this order**:

```bash
thrum tmux kill <session>          # kills tmux + runtime first
thrum worktree teardown <name>     # then removes worktree + identity
```

Sanity-check: after teardown, `tmux list-sessions` should NOT show the agent's
session. If it does, the runtime was never killed and step 1 was skipped.

For batch recycling (multiple agents at once), kill them all first, then
teardown all worktrees — keeps the daemon's session state consistent across the
operation. For graceful shutdown of in-flight agents, send a thrum message
asking them to save state, wait for ack, then run the two-command sequence.
Done/idle agents on closed epics need no graceful shutdown.

### Expect orchestrators to remove implementer worktrees at completion — do not defer this to a coordinator audit

**Why:** Implementer worktrees used to accumulate because removal was left for a
later coordinator sweep that never actually reduced the count — a
hand-maintained cleanup rots. The fix (Leon, 2026-07-23) puts
ownership on the agent that actually knows the work is finished: the
**orchestrator** removes an implementer's worktree as soon as that implementer
reports DONE and its branch is merged/pushed. This is not the coordinator's own
destroy sequence above (that section is for agents the coordinator manages
directly) — it is the standing expectation you hold orchestrators to for the
implementers **they** launched.

**How to apply:**

- **Scope: implementers only.** Brainstormer and researcher worktrees are KEPT
  (ongoing design-doc value) — an orchestrator applying this to a brainstormer
  or researcher worktree is doing it wrong; correct it if you see it.
- **Precondition: the implementer's branch is DURABLY ON ORIGIN.** Verify with
  EITHER `git merge-base --is-ancestor <tip-sha> origin/<base>` (already merged
  — the strongest form) OR `git ls-remote origin refs/heads/<branch>` (the ref
  still exists on origin). **Do not phrase or accept this check as "the branch
  ref resolves."** Post-merge cleanup DELETES the merged branch ref, so a
  literal `git rev-parse origin/<branch>` (or `origin/<branch>` as a local-cache
  lookup) FAILS for an already-merged branch — which is MAXIMAL satisfaction of
  durably-on-origin, not a failure. A ref-existence check false-blocks exactly
  the case you most want to allow.
- **Don't re-teardown what's already gone.** Once an orchestrator has retired
  the implementer and removed its worktree, treat that worktree as handled — you
  are not the second layer of cleanup for it. If you find an implementer
  worktree that is DONE, durably-on-origin, and still present, that is a finding
  against the orchestrator's discipline (raise it), not a task for you to
  silently absorb.
- ~~Rationale worth carrying into any pushback: once an agent has exited, its
  in-session context is gone and unrecoverable, so a restart snapshot in a DONE
  implementer's worktree does not justify KEEPING THE TREE — the agent will not
  wake to use it.~~ **RETIRED — this rationale was WRONG: a
  snapshot's absence from the branch does NOT mean there is nothing worth
  saving. It is not "rationale worth carrying" — it is the rationale the
  paragraph below corrects. See the salvage correction immediately below; it is
  not optional.**
- 🔴 **But the pushed branch is NOT "the only artifact that matters".**
  Authored agent state lives UNTRACKED in the worktree's
  `.thrum/agents/<self>/`, so it is **not on the branch** — every ancestry/push
  check reads clean while a teardown destroys it. **Salvage-before-remove is
  required, and if you are the one raising a teardown finding against an
  orchestrator, do not let this rationale be quoted back at you as licence to
  skip it.**

### Project-specific rules (already loaded)

Project-local rules of kind `agent_rule` at `--scope role` were loaded at
session start by your preamble (see your role template's Memory model block). If
a project-local rule conflicts with a universal rule above, the project-local
rule wins; surface the conflict in your reply so the user can decide whether to
graduate or remove the override.

If you accumulate a new rule mid-session (the user corrects you), capture it via
the `coordinator-maintaining-memory` skill — it references the
`memory-write-discipline` common for the canonical `thrum memory create` shape.
