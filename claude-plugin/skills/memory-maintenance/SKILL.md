---
name: memory-maintenance
description: "Use when an agent needs to update, delete, supersede, or audit an existing memory entry — e.g., after verification, when a finding becomes stale, or when a rule needs amendment. Loads the edit/delete/history protocol + when to retire vs amend."
---

# Maintaining thrum memory entries

This skill carries the canonical lifecycle operations on existing memory entries
— edit, delete, supersede, history audit.

## Editing an existing entry

To update a memory entry's body, title, tags, or zoom levels:

```bash
cat > /tmp/memory-edit-body.md <<'EOF'
<updated body>
EOF
thrum memory edit <id> --short "@/tmp/memory-edit-body.md"
thrum memory edit <id> --title "<updated title>"
thrum memory edit <id> --add-tag <new-tag>    # appends (repeatable); --rm-tag removes
```

Edits create a **history record** — the daemon retains the prior version. View
edit history:

```bash
thrum memory history <id>
```

Each history row shows the field changed, the prior value, and the timestamp.

## When to edit vs supersede

| Situation                                                                                  | Action                                                                                               |
| ------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------- |
| Small correction (typo, clarification, tag refinement)                                     | **Edit** — preserves the entry's identity + tracks the change in history                             |
| The fact has changed but the topic is still relevant (e.g., updated rule, refined finding) | **Edit** — same topic, evolving content                                                              |
| The entry is superseded by a fundamentally different fact / a redirected understanding     | **Supersede** — write a new entry, delete the old, optionally tag the new with `supersedes:<old-id>` |

## Deletion

```bash
thrum memory delete <id>
```

Soft-delete by default — the entry is marked deleted but retained in the
underlying store (recoverable via the daemon's tombstone protocol). To
hard-purge:

```bash
thrum memory delete <id> --hard --confirm "DELETE <id>"
```

`--hard` is irreversible — it issues `memory.purge` instead of `memory.delete`,
removing the row + tags + edges + FTS shadow and authorizing JSONL compaction on
next sync. The `--confirm` token must equal `DELETE <id>` exactly; omitting
`--confirm` falls through to an interactive `Type DELETE <id> to confirm:`
prompt on stderr, which hangs in non-interactive contexts. Use only when the
entry contains content that must be physically removed (e.g., credentials
accidentally captured).

## Staleness review

For research notes that carry a `Verified: YYYY-MM-DD @ <commit-sha>` footer,
periodic staleness review is the researcher's discipline (see
`researcher-maintaining-memory` skill for the git-diff-based protocol). For
role-rules, staleness is event-driven: when your behavior is corrected or
project policy changes, edit the entry to update the `Why:` line.

## Audit trail

Every memory entry has a creation timestamp + a `created_by` field tracking the
authoring agent. Edits append to history; deletions create a tombstone. The
audit trail is queryable via:

```bash
thrum memory history <id>
thrum memory show <id> --format json    # includes created_at, created_by, edit_count
```

## Refs to other skills

- For writing new entries (including supersedes): `memory-write-discipline`
- For finding entries by ID or topic: `memory-read-discipline`
- Role-specific maintenance patterns (staleness checks, index file updates):
  invoke your role's `*-maintaining-memory` skill.
