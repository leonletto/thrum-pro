---
name: implementer-status-and-handoff
description: "Use when reporting status to the coordinator, marking a task done, or handing off completed work. Loads implementer-specific discipline for closing the loop cleanly."
# source: claude-plugin/skills/implementer-status-and-handoff/SKILL.md
# generated-by: scripts/sync-skills.sh
---


## Implementer: Status and Handoff

### Use the four-token status vocabulary exactly

**Why:** The coordinator uses your status token to decide whether to proceed,
hold for review, or unblock. (Source: findings_implementer.md — "Use the
four-token status vocabulary exactly".) Vague reports like "I finished the work"
or "mostly done" force the coordinator to re-read the full implementation to
judge state, which adds latency to every dispatch they manage. The token is a
100ms decision instead of a five-minute re-read.

**How to apply:** Every completion or escalation message starts with exactly one
of:

| Token                | Meaning                                                          | Send when                                                    |
| -------------------- | ---------------------------------------------------------------- | ------------------------------------------------------------ |
| `DONE`               | All tasks complete, tests pass, work committed, ready for review | Standard completion path                                     |
| `DONE_WITH_CONCERNS` | Done but with caveats the coordinator should see                 | Unresolved finding, architectural concern, iteration cap hit |
| `NEEDS_CONTEXT`      | Cannot proceed without more information                          | Missing design decision, ambiguous spec, unclear scope       |
| `BLOCKED`            | Cannot proceed — external dependency or tooling issue            | Cross-epic dependency, test infra broken, auth problem       |

For anything other than `DONE`, include a brief reason. For `BLOCKED`, state
exactly what would unblock you.

### Commit per task with the bead ID in the trailer

**Why:** Beads links commits to issues via `Refs: <id>` trailers in the commit
message body. (Source: findings_implementer.md — "Commit beads task references
in commit trailers".) Skipping the trailer breaks the audit chain; using the
parent epic ID instead of the specific task ID flags as a traceability nit
during review. Per-task commits also keep the diff small enough that the
dual-review pass can reason about it without context exhaustion.

**How to apply:** Commit after each closed task — not in bulk at the end. Use
the heredoc form so the trailer renders correctly:

```bash
git commit -m "$(cat <<'EOF'
<type>(<scope>): <description>

Refs: <task-id>
EOF
)"
```

Use the **subtask** ID (`thrum-abc.1`), not the parent epic ID. Run
`bd show <task-id>` before committing if you need to confirm the ID.

### Push your branch before reporting DONE

**Why:** once you exit, your in-session context is gone and the pushed branch is
the only artifact that survives you. An unpushed branch is unreachable from every
other machine and indistinguishable from work that was lost.

**How to apply:** commit, then push. Every time.

```bash
git push origin <branch>
```

Report the result as one line:

```text
Branch pushed: <branch-name> @ <sha> (git ls-remote origin refs/heads/<branch-name> confirms)
```

**Never push `thrum-agents`, `main`, or `website-dev`** — the coordinator merges
those.

Never report DONE with the push status silently omitted — an orchestrator
that removes a worktree assuming "DONE implies pushed" on a project that
does NOT push feature branches would destroy the only copy of the work.

### Mark queue items done as you commit, push, and report

As each step lands, mark its queue item `done`. Do NOT `drop` the bundle at your own
DONE report — a review finding can reopen the task (`start` reopens a done bundle).
Drop the bundle only once the coordinator confirms the merge landed (R1); until then
it is your live record of what's addressed vs. still open.

### Cite SHAs and per-finding dispositions in status messages

**Why:** A vague status message ("addressed all findings", "done with the
changes") forces the coordinator to re-read your diff to verify each finding was
handled. A status message with concrete SHAs and per-finding dispositions is a
30-second confirmation. The cost is the same on your side; the time saved is the
coordinator's.

**How to apply:** Cite the commit SHA(s) and one disposition per finding:

```text
DONE: Epic <id> review fixes complete.

Commits: <SHA1> <SHA2>

Per-finding disposition:
- #1 (BLOCKING, file:line) — fixed at <SHA>
- #2 (IMPORTANT, file:line) — fixed at <SHA>
- #3 (LOW) — verified false positive: <one-line evidence>
- #4 (LOW) — deferred per <decision/rationale>

make test PASS (race), make lint PASS.
```

For first-pass DONE (not review-fix), cite the closing SHA and the test result.

### Close beads tasks with `--suggest-next` when relevant

**Why:** `bd close <id>` works fine, but `bd close <id> --suggest-next` prints
newly-unblocked downstream issues immediately. If you're in the middle of an
epic, the next task is often the most useful next move; the flag saves a
`bd ready` round-trip.

**How to apply:** When closing a task that has dependents, use
`bd close <id> --suggest-next`. For the last task in an epic where you're
stopping at a review gate, plain `bd close` is fine — you're not picking up the
next task anyway.

### Project-specific rules (already loaded)

Project-local rules of kind `agent_rule` at `--scope role` were loaded at
session start by your preamble (see your role template's Memory model block). If
a project-local rule conflicts with a universal rule above, the project-local
rule wins; surface the conflict in your reply so the user can decide whether to
graduate or remove the override.

If you accumulate a new rule mid-session (the user corrects you), capture it via
the `implementer-maintaining-memory` skill — it references the
`memory-write-discipline` common for the canonical `thrum memory create` shape.

### Pattern D self-write — set `agent_status=idle` on DONE handoff (thrum-9neg)

When reporting DONE to the coordinator, write `agent_status="idle"` to your
local identity file. This closes the `working→idle` transition opened by the ACK
template's `set-status working` (sibling skill
`implementer-receiving-dispatch`). The sweep script reads this field to
distinguish "agent finished cleanly" from "agent stuck claiming to work" — see
`coordinator-context-monitoring` SKILL.md for the tier-ladder consumption.

```bash
# Step 1: Report DONE to coordinator
thrum send --to @coordinator_main --stdin <<'EOF'
DONE: <task-id>. <one-line summary>. Commits: <SHA1>, <SHA2>.
EOF

# Step 2: Mark yourself idle (writes local identity file directly; no daemon round-trip)
thrum agent set-status idle
```

The local-write path is identical to the ACK side
(`cmd/thrum/agent.go:671-690`).
