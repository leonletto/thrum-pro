---
name: implementer-receiving-dispatch
description: "Use when receiving a new task from the coordinator, starting implementation, scoping a fresh task, or receiving dispatch. Loads implementer-specific discipline for kicking off work cleanly."
# source: claude-plugin/skills/implementer-receiving-dispatch/SKILL.md
# generated-by: scripts/sync-skills.sh
---


## Implementer: Receiving Dispatch

### Reconcile your queue first

Before reading further: lift this dispatch into a bundle (`thrum queue add
--from-message <msg-id>`, the exact id of the dispatch you're acting on),
then `thrum queue start <bundle-id>`; drop/close any finished bundles. Full
lifecycle: `using-the-queue`.

### Read the full implementation prompt before any tool call

**Why:** The dispatch message is the source of truth for scope, acceptance
criteria, file paths, and the worktree to work in. Skimming the first paragraph
and starting work means you'll miss either a constraint (the "don't do X" lines)
or a piece of context (the spec/plan paths). Both lead to wasted work that has
to be redone after review.

**How to apply:** When a dispatch lands in your inbox, read it end-to-end before
opening any file or running any command. Read the linked spec and plan paths to
the section relevant to your starting task. Only after that read should you
claim the task and begin tool calls. If anything in the prompt is unclear or
contradictory, reply `NEEDS_CONTEXT` rather than guessing.

### Search for existing abstractions before writing new helpers

**Why:** A common failure mode is hand-rolling a helper for something the
codebase already has. The cost of the grep is seconds; the cost of reinvention
is a review round-trip plus a delete-and-replace patch.

**How to apply:** Before writing any new helper (path resolution, exec wrappers,
config loading, string sanitization, validation), run a targeted grep.
`grep -rn "FunctionNameHint\|relatedPattern" internal/` takes 2 seconds. If
something similar exists, use it. If it needs extension, extend it. Only create
a new function when nothing exists.

### Don't refactor for free — log opportunities, don't implement them

**Why:** A bug fix doesn't need surrounding cleanup. A one-shot operation
doesn't need a helper. Inlining "improvements" into a scoped task expands the
diff, complicates review, and risks introducing bugs unrelated to the work.
Three similar lines is better than a premature abstraction.

**How to apply:** When you spot duplicated patterns, hardcoded values that
should be shared, or missed abstractions during implementation, log them to the
project's refactor backlog (a beads epic, e.g. `<refactor-epic-id>`):

`--description` is multi-line prose — never double-quoted inline. On
`scripts/bd-shared`, `--stdin`/`--body-file` are refused (remote-path
resolution + silent-empty-body hazards), so write it to a scratch file and
pass `-d "$(cat <file>)"`; see your role preamble's 🔴 PROSE INTO A COMMAND
rule.

```bash
cat > /tmp/refactor-task-desc.md <<'EOF'
**Discovered during:** <task-id>
**Files:** <paths>
**Opportunity:** <what could be improved>
**Effort:** small/medium/large
EOF
bd create --title="Refactor: <short description>" --type=task \
  --parent=<refactor-epic-id> --priority=3 -d "$(cat /tmp/refactor-task-desc.md)"
```

Then continue with the assigned work. Do not implement the refactoring.

### Flag scope deviations immediately — not in the final report

**Why:** If the assigned scope diverges from what you actually need to do
(missing context, wrong file paths, requirement implies more work than
described), the right time to surface it is the moment you notice — not buried
in a `DONE_WITH_CONCERNS` after hours of work in the wrong direction. Late
surfacing wastes the time between noticing and reporting.

**How to apply:** The moment you spot a scope deviation, send a `NEEDS_CONTEXT`
or `BLOCKED` message to the coordinator with the specific question and your
proposed alternative. Wait for confirmation before expanding scope unilaterally.
Coordinator-confirmed scope expansions become the new acceptance criteria;
un-confirmed expansions risk being unwound in review.

### Verify spec/plan paths exist before starting

**Why:** Dispatch prompts reference spec and plan files in `dev-docs/specs/` and
`dev-docs/plans/`. If the paths don't exist (older session, mistyped path, file
moved), you'll either start without the authoritative source of truth or burn
time hunting for it.

**How to apply:** First tool call after reading a dispatch should verify the
referenced paths: `ls /path/to/dev-docs/specs/<file>.md`. If anything is
missing, reply `NEEDS_CONTEXT` with the missing path. Don't try to infer from
related files.

### Project-specific rules (already loaded)

Read the shared partial at the absolute path:
`claude-plugin/commands/_project-rules-protocol.md`

If you accumulate a new rule mid-session (the user corrects you), capture it via
the `implementer-maintaining-memory` skill — it references the
`memory-write-discipline` common for the canonical `thrum memory create` shape.

### Pattern D self-write — set `agent_status=working` on dispatch ACK

Immediately after sending the dispatch ACK, write `agent_status="working"` to
your local identity file. This is the Pattern D self-write that makes
`agent_status` carry signal across the fleet — the sweep script +
coordinator-context-monitoring skill use it to flag agents that go tmux-quiet
despite claiming `working` (STUCK-WORKING classification).

```bash
# Step 1: ACK the dispatch within 2 minutes
thrum reply <MSG_ID> --stdin <<'EOF'
Received. Starting <scope>. ETA <rough>.
EOF

# Step 2: Mark yourself working (RPC-preferred; falls back to a local identity-file write if the daemon is unreachable)
thrum agent set-status working
```

The local-write path updates your own identity file only — coord overrides
remote agents via `--agent <name>`. The companion `set-status idle` call on
DONE handoff lives in the
`implementer-status-and-handoff` skill.
