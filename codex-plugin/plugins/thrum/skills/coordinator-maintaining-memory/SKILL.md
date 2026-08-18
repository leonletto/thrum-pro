---
name: coordinator-maintaining-memory
description:
  "Use when the coordinator writes a role-rule, captures an observation about
  agent behavior, or notes a state change. Loads coordinator-specific memory
  discipline — when to write, the role-rule pattern, the kind-diversification
  roadmap (deferred to follow-up)."
# source: claude-plugin/skills/coordinator-maintaining-memory/SKILL.md
# generated-by: scripts/sync-skills.sh
---

## Coordinator memory discipline

You are the coordinator. You write role-rules (when the user corrects your
judgment), capture observations about agent behavior, and periodically note
project-state changes. Common memory operations (write command shape, body
conventions, lookup patterns, edit/delete) live in the common memory skills —
invoke them for basics. THIS skill carries coordinator-specific extensions.

### When to invoke the commons

| Situation                                            | Skill to invoke           |
| ---------------------------------------------------- | ------------------------- |
| Drafting a new role-rule or observation              | `memory-write-discipline` |
| Loading role-rules at session start, finding a topic | `memory-read-discipline`  |
| Editing, deleting, or superseding                    | `memory-maintenance`      |

### When the coordinator writes

The coordinator's primary write trigger is **user correction**. When Leon
corrects your judgment mid-session ("don't restart that agent early — they're
mid-flight"), capture the rule:

```bash
cat > /tmp/role-rule-body.md <<'EOF'
<rule>

Why: <reason — past incident, project policy, or Leon's strong preference>
How to apply: <when/where this kicks in>
EOF
thrum memory create --kind agent_rule --scope role \
  --title "<short rule prose — what you must do or not do>" \
  --oneline "<rule one-liner, ≤280 bytes>" \
  --short "@/tmp/role-rule-body.md" \
  --tag <slug>
```

`--short`/`--full` carry real prose — compose via heredoc or file, never
double-quoted inline; see your role preamble's 🔴 PROSE INTO A COMMAND rule.

Body shape uniform across all role-rule writes — see `memory-write-discipline`.

Secondary write triggers:

- **Confirmed-decision observations** — Leon explicitly affirms an approach you
  proposed ("yes, that bundled PR was the right call"). Capture as
  `kind: agent_rule` with `--tag decision-confirmation` and the same Why/How
  shape.
- **Mid-session policy clarifications** — Leon explains why an existing rule
  applies in a new context. Edit the original entry to amend the `How to apply:`
  line, rather than creating a duplicate.

### Coordinator does NOT typically write

- **Implementation findings** — ping the researcher; they own
  `kind: research_note` writes.
- **Per-task notes / TODOs** — put them in bd ticket comments or the
  conversation context; they're ephemeral.
- **Refactoring opportunities** — file under a backlog refactoring epic,
  not memory.

### Kind-diversification (deferred follow-up)

Currently the coordinator writes one kind: `agent_rule`. The v0.11 substrate
supports richer kinds:

- `arch_decision` for design decisions captured mid-session
- `project_note` for state observations
- `epic_status` for project-state updates

**Status:** Deferred per brainstorm D3, sub-Q3b. For the v0.11 ship-day cutover,
the coordinator's writes are uniform (`agent_rule`). A follow-up ticket will
teach kind-diversification post-cutover. Until then, write all coordinator
memory entries as `kind: agent_rule --scope role`.

### Session-end + project-state captures

When closing a coordination session with substantial state to preserve (e.g.,
epic progress, agent assignments, open decisions), use the existing skills:

- `thrum:update-project` — updates durable project state file (NOT a
  thrum-memory write)
- `thrum:restart` — saves conversation snapshot before restart (NOT a
  thrum-memory write)

These are separate persistence layers from memory. Memory is for atomic,
queryable rules + observations; project state is for session continuity.
