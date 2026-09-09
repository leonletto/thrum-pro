---
name: memory-write-discipline
description: "Use when an agent needs to capture a new memory entry — a rule, a research finding, an observation. Loads the canonical write-command shape, body conventions, title prose convention, tags-as-slug pattern, and scope semantics. Common across all roles that write memory."
# source: claude-plugin/skills/memory-write-discipline/SKILL.md
# generated-by: scripts/sync-skills.sh
---


## Writing thrum memory entries

This skill carries the canonical write-command shape + content discipline shared
by every role that writes memory. Per-role skills
(researcher/coordinator/implementer-maintaining-memory) reference this skill for
the write-command basics and add role-specific guidance (when to write,
role-specific kinds, etc.).

### Canonical write command

```bash
cat > /tmp/memory-body.md <<'EOF'
<body — rule + Why + How to apply, or finding + cites>
EOF
thrum memory create --kind <K> --scope <S> \
  --title "<short prose title — what this entry says>" \
  --oneline "<one-line summary, ≤280 bytes>" \
  --short "@/tmp/memory-body.md" \
  --tag <slug-or-keyword> [--tag <additional-tag>]
```

`--short`/`--full` carry real prose — compose via heredoc or file, never
double-quoted inline; see the role preamble's 🔴 PROSE INTO A COMMAND rule.

Three flags are **REQUIRED** (schema NOT NULL): `--kind`, `--title`,
`--oneline`. The daemon rejects any `memory.create` call missing these.
`--short` and `--full` are optional but strongly encouraged — omitting both
surfaces the MEM-010 hint ("created without all three zoom levels") and degrades
future retrieval.

### Body shape conventions

**For role-rules (`--kind agent_rule`):**

```text
<rule statement — one sentence>

Why: <reason — past incident, project policy, or strong preference>
How to apply: <when/where this kicks in>
```

Lead with the rule itself; the `Why:` line is what future-you needs to judge
edge cases the rule doesn't literally cover. This shape matches the previous
bd-remember convention by design.

**For research notes (`--kind research_note`):**

```text
<finding statement>

Evidence: <file:line citations or external links>
Verified: YYYY-MM-DD @ <commit-sha>
```

The Verified-stamp footer enables staleness checks via git diff (see
`researcher-maintaining-memory` skill).

**For other kinds (`arch_decision`, `project_note`, `epic_status`, etc.):**
Free-form body matching the kind's semantic. Lead with the decision/observation
itself, then context.

### Title shape

**Free-form prose**, ~80 character soft limit. The title appears in every
`thrum memory list` output, so optimize for human scanability:

- GOOD: `"Coordinator must verify implementer findings before forwarding"`
- GOOD: `"safecmd.Bd 2-return signature mirrors safecmd.Tmux"`
- GOOD: `"thrum-bot Telegram group monitored by the operator"`
- AVOID slug-style or role-prefixed: `"coord-verify-findings"` — slug belongs in
  `--tag`, not title.

### Tags as the slug-style handle

Per-entry slug (kebab-case keywords describing the topic) lives in `--tag`, not
the title. This preserves the bd-key-suffix convention as a grep/filter handle:

```bash
thrum memory create --kind agent_rule --scope role \
  --title "Implementer must use safecmd.Bd not raw exec for bd calls" \
  --oneline "Daemon-adjacent bd invocations must use safecmd.Bd helper" \
  --short "..." \
  --tag safecmd-bd --tag daemon-discipline
```

Multiple tags are valid — repeat `--tag` per tag. The slug-as-tag pattern lets
`thrum memory search --tag safecmd-bd` find the entry by its conceptual key.

### Scope semantics

`--scope` accepts three values: `project | agent | role`. The CLI auto-infers
identity from the caller's daemon binding — there is NO `:role:<role-name>`
shape.

| Scope     | Use for                                           | Visibility                                                              |
| --------- | ------------------------------------------------- | ----------------------------------------------------------------------- |
| `role`    | Role-rules, role-specific guidance                | All agents sharing this role; preferred default for `agent_rule` writes |
| `agent`   | Private rules / notes for this agent instance     | Only this agent (by agent_id)                                           |
| `project` | Shared knowledge across all agents in the project | Every agent in the project                                              |

For role-rules, **always use `--scope role`**. The daemon's identity binding
ensures the entry is scoped to the caller's role automatically; no further
qualifier needed.

### Zoom-level discipline (oneline / short / full)

Per the v0.11 substrate design, memory entries support three body zoom levels:

| Field          | Length budget | Purpose                                                       |
| -------------- | ------------- | ------------------------------------------------------------- |
| `body_oneline` | ≤280 bytes    | Default search/list render — must convey the gist in one line |
| `body_short`   | ≤4 KB         | Mid-zoom — default `show <id>` render                         |
| `body_full`    | ≤256 KB       | Deep zoom — full body via `show <id> --format body`           |

Populate all three when authoring. Skipping `body_short` and `body_full`
triggers MEM-010 ("created without all three zoom levels") and degrades
retrieval quality — search ranks by all three fields, and shallow entries are
less discoverable.

For role-rules, the typical shape: `oneline` = the rule one-liner, `short` =
rule + Why + How-to-apply, `full` = `short` if no longer body needed (or omit
`full`).

### Refs to other skills

- For loading + querying memory: `memory-read-discipline`
- For deleting / editing / superseding: `memory-maintenance`
- Role-specific write triggers + extensions: invoke
  `researcher-maintaining-memory`, `coordinator-maintaining-memory`, or
  `implementer-maintaining-memory` based on your role.
