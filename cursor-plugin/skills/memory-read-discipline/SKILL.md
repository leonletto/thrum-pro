---
name: memory-read-discipline
description: "Use when an agent needs to find existing memory entries - load role-rules at session start, recall a topic mid-session, or pull the full body of a specific entry. Loads the canonical 3-step zoom-escalation read pattern (scan index, triage short, fetch full on confirm) and covers the list / search / show verbs. For advanced FTS5 plus embedding search options, see also the memory-search-advanced skill."
---

# Reading thrum memory entries

This skill carries the canonical read-command patterns shared by every role.
Three distinct use cases map to three distinct verbs, all following the same
**3-step zoom escalation**: scan the index first, triage at short zoom, fetch
full only when confirmed.

## Canonical Memory Read Flow (3 steps)

1. **SCAN the index** — get onelines for all relevant records:

   ```
   thrum memory index [--scope <scope>] [--kind <kind>]
   ```

   or

   ```
   thrum memory list --zoom oneline [--scope <scope>] [--kind <kind>]
   ```

   Review titles and onelines. This is cheap — no body content loaded.

2. **TRIAGE with short** — for records that look promising after the scan:

   ```
   thrum memory show <id> --zoom short
   ```

   or

   ```
   thrum memory list --zoom short --kind <kind>
   ```

   The short body (a paragraph summary) lets you confirm relevance before
   pulling the full content.

3. **FETCH full only when confirmed** — only when the short tier confirms the
   record is what you need:
   ```
   thrum memory show <id> --zoom full
   ```
   or
   ```
   thrum memory show <id>
   ```
   (default zoom = full)

**Rule:** Never jump straight to `--zoom full` or `--format body` without first
scanning and triaging. The index + short tiers exist to save context tokens.

## Use case 1: Session-start enumeration of role-rules

To load all role-rules at session start (scope + kind known in advance):

```bash
# Step 1: scan index
thrum memory list --zoom oneline --kind agent_rule --scope role
```

The `--scope role` filter auto-infers your role via daemon identity binding (no
`:role:<role-name>` qualifier needed). Output shows one record per line with
`body_oneline` only — scannable.

To narrow further by tag (`list` has no tag filter; use `search`):

```bash
thrum memory search --kind agent_rule --scope role --tag <slug>
```

If a specific rule looks relevant after the index scan, triage it:

```bash
thrum memory show <id> --zoom short
# If still not enough detail:
thrum memory show <id> --zoom full
```

## Use case 2: Topic-driven recall

For a topic without a known specific entry, follow all 3 steps:

```bash
# Step 1: scan
thrum memory search "<topic keywords>"

# Step 2: triage promising hits
thrum memory show <id> --zoom short

# Step 3: fetch confirmed entries
thrum memory show <id> --zoom full
```

`search` invokes FTS5 + (when wired) embedding search. Multi-word queries are
honored. Optional filters:

```bash
thrum memory search "<topic>" --kind research_note    # filter by kind
thrum memory search "<topic>" --tag <slug>            # filter by tag
thrum memory search "<topic>" --since 30d             # filter by recency
```

Default render: ranked summaries, each showing `body_oneline` only. The deeper
zoom levels are NOT polluted into search results — triage with `--zoom short`
before fetching full.

## Use case 3: Pulling the full body of a specific entry

When you already know the entry ID (e.g. from a prior search or the index):

```bash
# Step 2: triage (skip if you already know this is the right entry)
thrum memory show <id> --zoom short

# Step 3: fetch full body
thrum memory show <id> --zoom full
# equivalently:
thrum memory show <id>
```

Default format (text) renders metadata fields (ID, Kind, Status, Scope, Agent,
Created, Updated, Tags, Parent) plus all zoom levels present in the entry
(title, oneline, short, full). To pull just the body:

```bash
thrum memory show <id> --zoom full  # preferred — explicit zoom
thrum memory show <id> --format json | jq -r '.body_full'  # JSON extraction
```

## Cross-scope reads

Default scope filter (when `--scope` is omitted) returns all scopes the caller
can access. To explicitly read other roles' rules:

```bash
thrum memory list --zoom oneline --kind agent_rule --scope role          # YOUR role (identity-inferred)
thrum memory list --zoom oneline --kind agent_rule --scope project       # project-wide rules
thrum memory list --zoom oneline --kind agent_rule                       # all visible scopes
```

The CLI does not expose `--scope role:<other-role>` filtering. To inspect
another role's rules, query the broader scope and grep the result (or narrow
with `thrum memory search --tag <slug>`).

## Output discipline

Default multi-record output (from `list` and `search`) prints `body_oneline`
only — this is the right zoom level for scanning a result set. Don't pull deeper
zoom levels for a whole result set; use `show <id> --zoom short` then
`show <id> --zoom full` for specific entries you need.

## Refs to other skills

- For writing new entries: `memory-write-discipline`
- For deleting / editing / superseding entries: `memory-maintenance`
- For advanced FTS5 + embedding search options: `memory-search-advanced`
- Role-specific read patterns (session-start sequences, etc.): invoke your
  role's `*-maintaining-memory` skill.
