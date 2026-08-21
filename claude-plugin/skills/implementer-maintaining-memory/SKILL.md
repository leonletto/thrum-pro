---
name: implementer-maintaining-memory
description: "Use when the implementer writes a role-rule after user correction, or looks up implementer rules at session start. Loads implementer-specific memory discipline — single write path (agent_rule), refactoring opportunities go to bd not memory, stay minimal."
---

# Implementer memory discipline

You are the implementer. Your memory discipline is intentionally narrow: you
READ rules at session start and you WRITE rules when the user corrects your judgment
mid-implementation. Refactoring opportunities, lessons learned, design questions
— those flow elsewhere. Common memory operations live in the common memory
skills — invoke them for basics. THIS skill carries implementer-specific
extensions only.

## When to invoke the commons

| Situation                           | Skill to invoke           |
| ----------------------------------- | ------------------------- |
| Drafting a new role-rule            | `memory-write-discipline` |
| Loading role-rules at session start | `memory-read-discipline`  |
| Editing or deleting a stale rule    | `memory-maintenance`      |

## Single write path: role-rules

When the user corrects your behavior mid-implementation, capture an
implementer-rule:

```bash
cat > /tmp/role-rule-body.md <<'EOF'
<rule>

Why: <reason>
How to apply: <when/where>
EOF
thrum memory create --kind agent_rule --scope role \
  --title "<short rule prose — what you must do or not do>" \
  --oneline "<rule one-liner>" \
  --short "@/tmp/role-rule-body.md" \
  --tag <slug>
```

`--short`/`--full` carry real prose — compose via heredoc or file, never
double-quoted inline; see your role preamble's 🔴 PROSE INTO A COMMAND rule.

Body shape is uniform across all role-rule writes — see
`memory-write-discipline`. The `Why:` line is load-bearing: future-you needs the
reason to judge edge cases the rule doesn't literally cover.

## Implementer does NOT write

- **Refactoring opportunities discovered mid-task** → file under the project's
  refactoring epic, e.g. `<refactor-epic-id>`, NOT memory. Memory is for AGENT
  BEHAVIOR rules; bd tracks code work.
- **Research findings about the codebase** → ping the researcher; they own
  `kind: research_note` writes.
- **Per-task notes / scratch state** → use the conversation context or task
  description. Ephemeral.
- **Project-state updates** → coordinator's job; do not touch project_state.md.

## Triggering condition for an implementer write

Capture a user correction as a NEW rule only when BOTH conditions hold:

1. The correction applies broadly — next time you encounter the same situation,
   you should behave differently.
2. The correction is non-obvious from the code — the WHY is project context, not
   derivable from reading files.

If the correction is one-off (specific to this task only) OR obvious from the
code (a syntax fix, a typo), do NOT capture it as a memory entry. Memory
accumulates load; write only when the rule has durable value.

## Session-start read

At session start, load implementer role-rules:

```bash
thrum memory list --kind agent_rule --scope role
```

The `--scope role` filter auto-infers your role via daemon identity binding.
Scan the returned `body_oneline` summaries; pull full bodies via
`thrum memory show <id>` only for rules whose one-liner doesn't fully convey the
constraint.
