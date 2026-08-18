---
name: memory-audit-recover
description: "Use when investigating change history (`memory history`), recovering a soft-deleted memory, recovering the losing side of a concurrent edit (MEM-009 LWW loser), or running a confirmed hard-delete. Loads the audit walk, LWW conflict-resolution semantics, undelete flow, and the `Type DELETE <id>` hard-delete gate."
allowed-tools: "Bash(thrum memory:*)"
version: "0.11.0"
author: "Leon Letto <https://github.com/leonletto>"
license: "Apache-2.0"
---

# memory-audit-recover — history, undelete, hard-delete

Load this sub-skill from `thrum-memory` (umbrella) when you need to look back at
what changed or recover something that was deleted or overwritten.

## The JSONL is the audit log

Every event (`memory.create`, `memory.edit`, `memory.delete`, `memory.edge.add`,
`memory.edge.remove`, `memory.purge_executed`) appends to the author's
`memories/<agent_id>.jsonl`. Replay rebuilds the projection; the JSONL itself
never mutates. That makes the audit trail authoritative.

Walk the history of one memory:

```bash
thrum memory history <id>            # all events touching this memory, chronological
thrum memory history <id> --diff     # unified diff of each edit's fields
```

Projection stores `created_at` (first-event ts), `updated_at` (latest-event ts),
`created_by` (first-event author), and `last_edited_by` (latest-event author).
The full event timeline always comes from JSONL replay — per-memory event count
is typically <10, so replay is cheap.

Provenance now lives in the durable `memory-events-v2/` lane and is read by
`memory history` directly — it survives events.jsonl compaction and cold boot.

## Conflict resolution (LWW by event ULID)

Memories use last-write-wins by event ULID — **not** semantic priority. ULID is
monotonic-ish and globally comparable; the larger ULID wins.

| Scenario                                                                        | Result                                                   |
| ------------------------------------------------------------------------------- | -------------------------------------------------------- |
| Concurrent edits to disjoint fields                                             | Both apply (no conflict).                                |
| Concurrent edits to the SAME field                                              | Larger-ULID event wins. Loser preserved in JSONL.        |
| Concurrent tombstones                                                           | Idempotent. One delete-event wins by ts; status=purged.  |
| Edit + delete, delete-ULID > edit-ULID                                          | Final `status=purged`.                                   |
| Edit + delete, edit-ULID > delete-ULID AND edit explicitly sets `status=active` | Edit wins → `status=active` (undelete).                  |
| Edit + delete, edit-ULID > delete-ULID AND edit does NOT touch `status`         | Patch applies to body/tags but `status=purged` persists. |

LWW is acceptable here because memories aren't a high-write-conflict surface
(single agent typically authors; cross-clone edits to the same field within a
sync window is a corner case). Audit preserves both edits so loss is recoverable
in practice.

### Detecting and recovering a MEM-009 LWW loser

When `memory.edit` projection detects that LWW chose someone else's value, the
response surfaces hint `MEM-009: memory.edit.lww-loser`. (Trigger lights up when
LWW-loser surfacing lands in the projection response — code path exists today;
emission is the deferred half.)

Recovery:

```bash
thrum memory history <id> --diff
```

Find the losing edit in the diff stream; the JSONL preserves its body. Lift the
wanted value out and re-apply as a new edit:

```bash
thrum memory edit <id> --short @rescued-short.md
```

The new edit becomes the latest ULID, so it wins the next read. If both sides
actually had useful changes, consider a `comment` child memory recording the
alternative wording instead of overwriting.

## Soft delete and undelete

Default delete is soft — `status` flips to `purged` but the JSONL keeps every
event:

```bash
thrum memory delete <id>             # default soft
```

Soft-deleted memories are excluded from default search. Re-surface with
`--include-purged` (or `--status all`). Edges remain in place.

Undelete by writing `status=active`:

```bash
thrum memory edit <id> --status active
```

Undelete works regardless of who won the concurrent edit/delete race (see LWW
table above). The audit history is intact, so the recovered memory carries its
full provenance.

## Hard delete (`--hard`)

Hard delete is irreversible after the next sync compaction. It reuses thrum's
`purge_metadata` mechanism (proven for messages) — `memory.delete --hard` emits
a `memory.purge_executed` event the existing purge logic recognizes; on next
sync compaction, the JSONL entries for that memory are physically removed across
all peers.

Mandatory confirmation gate:

```bash
thrum memory delete <id> --hard
Type DELETE <id> to confirm: DELETE <id>
```

The exact token (`DELETE <id>`) must be typed back — matches beads'
`DESTROY-<prefix>` pattern. There is no `--yes` bypass.

| Mode            | Mechanism                                                      | Recovery                                 |
| --------------- | -------------------------------------------------------------- | ---------------------------------------- |
| Soft (default)  | `memory.delete` → projection `status=purged`                   | `thrum memory edit <id> --status active` |
| Hard (`--hard`) | `memory.purge_executed` → physical JSONL removal at compaction | Not recoverable post-compaction          |

## When NOT to hard-delete

Default to soft delete. The audit trail is the value memories add over ad-hoc
notes; hard-deleting throws it away.

Reach for `--hard` only when:

- The body contains secrets (API keys, credentials, customer PII) that must not
  survive in JSONL or any clone.
- A misfire of `memory.create` recorded clearly wrong content the team agrees
  should leave no trace.
- A legal/compliance requirement mandates physical removal.

For everything else — wrong tags, outdated decisions, deprecated rules — prefer
one of:

- Edit with the corrected content (audit preserves the original).
- Supersede with a new memory and let the old one go to `status=superseded`.
- Soft-delete; the audit trail stays.

## Memory-history quick reference

```bash
thrum memory history <id>             # chronological events touching <id> (durable lane)
thrum memory history <id> --diff      # with unified field-level diff
```

The events that show up: `memory.create`, `memory.edit`, `memory.delete`,
`memory.edge.add`, `memory.edge.remove`, `memory.purge_executed`. Each carries
`author`, ULID timestamp, and (for edits) the field-level patch.
