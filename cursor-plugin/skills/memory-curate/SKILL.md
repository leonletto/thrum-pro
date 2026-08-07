---
name: memory-curate
description: "Use when managing relationships between memories — adding/removing edges, superseding old decisions, threading comments, walking hierarchies, or deciding whether to unlink, supersede, or both. Loads edge kinds, status-driven read semantics, cycle and single-parent rules, and the unlink-supersede footgun."
version: "0.11.0"
author: "Leon Letto <https://github.com/leonletto>"
license: "MIT"
---

# memory-curate — edges, status, hierarchy

Load this sub-skill from `thrum-memory` (umbrella) when relationships between
memories matter — supersession, parent/child structure, comment threads, or
related-context grouping.

## Edge kinds and when to use each

| Kind           | Meaning                                                        | When to use                                                                                               |
| -------------- | -------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `supersedes`   | A replaces B. Adding the edge ALSO sets `B.status=superseded`. | A new `arch_decision` overrides an older one. A consolidated session summary replaces several stale ones. |
| `child_of`     | A is a sub-piece of B; forms a tree. Single-parent.            | A `worktree_status` row is `child_of` a `session_summary`. A `comment` is `child_of` its parent memory.   |
| `related_to`   | A and B share context; symmetric, advisory.                    | Two `arch_decision`s touching the same subsystem.                                                         |
| `derived_from` | A was generated or distilled from B.                           | A `short` summary `derived_from` the `full` body when an LLM expanded it.                                 |

Edge kind is an open string (same hybrid pattern as memory kind). Future edges
like `blocks`, `duplicates`, or `parent-child` can be added without schema
change.

Add and remove edges:

```bash
thrum memory link <a> supersedes <b>
thrum memory link <child> child_of <parent>
thrum memory unlink <a> supersedes <b>
```

## Status-driven read semantics

When A supersedes B, the supersede event writes B's status to `superseded` **in
addition to** creating the edge. Default assembly and `memory search` filter on
`status=active`. Edges are pure structural metadata; the answer to "is this
memory current" is always the status field, never an edge walk.

**Why it matters:** this avoids the "do I respect the edge or trust the status
field" ambiguity at read time. The status field wins.

## The unlink-supersede footgun

Removing a supersede edge via `memory unlink` does **NOT** automatically restore
the superseded memory to active. The edge disappears but the `status=superseded`
set by the original supersede event persists.

Agents who try to "undo" a supersede by unlinking the edge will see the edge
gone while the memory stays hidden from default search and assembly.

To genuinely undo a supersede:

```bash
thrum memory unlink <new-id> supersedes <old-id>
thrum memory edit <old-id> --status active
```

Both steps are required. If you only need to keep the historical link but
re-surface the old memory, just run the `--status active` edit and leave the
edge in place.

## Cycle prevention

| Edge kind      | Cycle policy                             |
| -------------- | ---------------------------------------- |
| `supersedes`   | Acyclic — write-time DFS reject.         |
| `child_of`     | Acyclic — write-time DFS reject.         |
| `derived_from` | Acyclic — write-time DFS reject.         |
| `related_to`   | Symmetric / undirected — cycles allowed. |

Cycle detection runs a bounded DFS from the proposed edge's target node up the
existing graph in the same edge-kind direction, looking for the source. Bounded
by `memory.limits.edge_depth` (default 32) — worst-case O(32) per write,
constant-time in corpus size.

A chain that exceeds the depth limit returns `ErrMemoryEdgeChainTooDeep` with
the chain length, the configured limit, and a hint suggesting either
consolidation via `supersedes` or raising the limit in config.

## Single-parent constraint for `child_of`

`child_of` is enforced single-parent at write-time. A memory has at most one
parent.

| Edge kind      | Plurality                                                 |
| -------------- | --------------------------------------------------------- |
| `related_to`   | Multiple — and obviously so.                              |
| `supersedes`   | Multiple — A supersedes B AND C in a consolidation merge. |
| `child_of`     | **One** — enforced.                                       |
| `derived_from` | Multiple — a summary distilling several sources.          |

If a v2 use case ever needs "comments threaded across multiple memories," the
single-parent constraint will need to be revisited. Not a v1 use case.

## Comments-as-memories pattern

A comment on memory X is just another memory:

```bash
thrum memory create --kind comment \
  --title "Note on Tailscale sync" \
  --oneline "Confirmed leaving git a-sync removes the dual-consumer conflict." \
  --parent <X-id>
```

`--parent` shorthand creates the `child_of` edge in the same operation. Author =
`agent_id`, timestamp = `created_at`. Threading walks via the daemon's
`memory.listByEdge` RPC on the parent.

No separate `comments` table exists. All the search predicates, audit history,
edges, and embeddings apply to comments just like any other memory kind.

## Hierarchy navigation

Edge WRITES are CLI-exposed (`link`, `unlink`, `create --parent`). Edge READS
are daemon-RPC-only today: `memory.listByEdge` walks one hop along an edge kind
(`direction`: `inbound` finds rows pointing AT an id, `outbound` finds rows the
id points TO), but no `thrum memory` subcommand exposes it yet and
`thrum memory show` does not render edges. Until a CLI read surface ships,
navigate hierarchies by convention instead: give children a shared `--tag` (e.g.
the parent's slug) at create time and walk with
`thrum memory search --tag <slug>`.

## Edge limits

| Limit                      | Default     | Configurable via                 |
| -------------------------- | ----------- | -------------------------------- |
| Edge depth (acyclic kinds) | 32          | `memory.limits.edge_depth`       |
| Edges per memory           | 64 outbound | `memory.limits.edges_per_memory` |

Raise per deployment if a genuine workflow needs more — both bounds exist to
prevent pathological hierarchies and fan-out abuse, not to constrain real use.
