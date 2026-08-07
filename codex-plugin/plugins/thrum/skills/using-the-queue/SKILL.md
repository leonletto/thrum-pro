---
name: using-the-queue
description:
  "Use when an agent tracks its own committed work or needs to see who is doing
  what - keeping a task list of what you are working on, recording work someone
  assigned you, promoting a backlog bead or issue into active work, lifting an
  assignment out of a message you received, routing work to another agent,
  checking what another agent has on its plate, or moving a task through pending
  / in_progress / blocked / done. Covers the full thrum queue CLI - bundles,
  embedded items, status, assignment provenance, and reading another agent's
  queue."
# source: claude-plugin/skills/using-the-queue/SKILL.md
# generated-by: scripts/sync-skills.sh
---

## Using the Thrum Queue

### Overview

`thrum queue` is a per-agent, local-only, daemon-resident list of the work an
agent has committed to. One queue per `agent_id`; you EDIT your own, anyone may
READ any queue. It is not beads and not a message inbox - beads is the shared
backlog of what COULD be done; the queue is the private, short-lived list of
what an agent IS doing right now, and it is gone when the agent is deleted.

**One rule governs everything else: the queue never crosses agents by itself.**
You only ever write your OWN queue. Assigning, handing off, and cross-box status
all travel as MESSAGES; the receiving agent adds the work to its own queue. No
command writes another agent's queue.

### When to Use

- You need a task list of what you are actively working on.
- Someone messaged you an assignment and you want it tracked as committed work.
- You are promoting a backlog item (a bead / thrum-issue) into active work.
- You are a coordinator/orchestrator routing work and want to record who you
  handed a bundle to.
- You need to see what another agent is working on or how loaded it is.
- You are moving a task between pending / in_progress / blocked / done, or
  clearing finished work out.

### Mental Model

- **Bundle** = one unit of committed work (the only top-level record). Carries a
  title, optional backlog `refs`, a status, a priority, and provenance.
- **Item** = a short checklist entry EMBEDDED inside a bundle. Items are never
  standalone and never linked across bundles. There is no nesting - a bundle
  holds items, nothing deeper.
- **`title` carries the whole content** - there is no body field (40 KB cap).
- **Local-only**: `.thrum/var/queue/<agent>.jsonl`, projected to SQLite, rebuilt
  on cold boot, included in `thrum backup`. Never peer-synced.

### Who-is-doing-what (read this if that is your goal)

Three distinct fields, do not conflate them:

- **`assigned_by`** - provenance: which agent assigned this to me. Auto-filled
  when a bundle/item is created with `--from-message` (from the message author).
  Answers "who gave me this."
- **`assigned_to`** - routing metadata I put on MY OWN bundle via
  `thrum queue assign`. It is informational only. **It does NOT write the named
  agent's queue and does NOT hand the work off.** Answers "who I intend this
  for." The actual handoff is a separate `thrum send`; that agent runs
  `thrum queue add --from-message` to pull it into its own queue.
- **`thrum queue list --agent <id>` / `show <id> --agent <id>`** - read another
  agent's queue directly. Answers "what is agent X working on / how loaded is
  it." Read-only, no permission gate.

### Quick Reference

| Command                                                              | Does                                                                                                             |
| -------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `thrum queue add --title "..."`                                      | Create a bundle in your queue                                                                                    |
| `thrum queue add --from-message <msg_id>`                            | Lift an assignment out of a received message (keystone - copies content->title, author->assigned_by, refs->refs) |
| `thrum queue add --ref bead:<id>`                                    | Promote a backlog item into active work                                                                          |
| `thrum queue list [--status <s>] [--agent <id>]`                     | List your queue (or another agent's)                                                                             |
| `thrum queue show <bundle-id> [--agent <id>]`                        | Full detail for one bundle                                                                                       |
| `thrum queue start <bundle-id>`                                      | -> in_progress (clears block_reason)                                                                             |
| `thrum queue block <bundle-id> [--reason "..."]`                     | -> blocked (records the reason)                                                                                  |
| `thrum queue done <bundle-id>`                                       | -> done (RESTING - not deleted; clears block_reason)                                                             |
| `thrum queue drop <bundle-id>`                                       | DELETE bundle + all its items, any status (the one destructive verb)                                             |
| `thrum queue assign <bundle-id> <agent-id>...`                       | Append agent(s) to assigned_to (routing metadata only)                                                           |
| `thrum queue item add <bundle-id> --title "..."`                     | Add one embedded item                                                                                            |
| `thrum queue item batch-add <bundle-id> --title "..." --title "..."` | Add several items in one call (shared --ref/--priority)                                                          |
| `thrum queue item start/block/done <bundle-id> <item-id>`            | Item-level status (start/done clear the item's block_reason)                                                     |

Optional everywhere they appear: `--from-message`, `--ref <type>:<value>`
(repeatable), `--priority N` (higher sorts first). `add` / `item add` require at
least one of `--title` or `--from-message`; explicit `--title` wins over
`--from-message`.

### Common Flows

**Take an assignment someone messaged you** (the keystone primitive):

```
thrum queue add --from-message <msg_id>
```

One command lifts the message's content into a bundle title, its author into
`assigned_by`, and its refs into `refs` - then discards the message ID (no
stored link back).

**Promote a backlog bead into active work:**

```
thrum queue add --title "Ship the X migration" --ref bead:thrum-abc12 --priority 5
```

**Hand work to another agent** (two steps, in this order - there is no
one-shot):

```
thrum queue assign <bundle-id> @impl_foo      # record intent on YOUR bundle
thrum send --to @impl_foo --stdin <<'EOF'      # actually route it
Assigned you <bundle>: <what + refs>. Add it with: thrum queue add --from-message <this msg id>
EOF
```

**See what an agent has on its plate:**

```
thrum queue list --agent @impl_foo --status in_progress
```

**Finish vs discard:** `done` marks a bundle done and KEEPS it (resting state,
still visible). `drop` DELETES it and every item inside, regardless of status.
`done` then later `drop` is the normal close-out; `drop` alone is fine too.

### Common Mistakes

- **Expecting `assign` to put work in the other agent's queue.** It does not -
  it only tags your own bundle. Always follow it with a `thrum send`; the
  recipient adds it themselves via `--from-message`.
- **Using `done` to clear clutter.** `done` never removes anything - the bundle
  stays. Use `drop` to actually delete.
- **Reaching for a `remove`/`rename`/item-`drop` verb.** They do not exist by
  design: removal happens only at the bundle level via `drop`; titles are set at
  creation and not edited.
- **Trying to edit another agent's queue.** Impossible by design - you only
  write your own. Cross-agent work is messaging plus the recipient's own `add`.
- **Treating the queue as durable/shared history.** It is local, private, and
  deleted with the agent. Anything that must survive belongs in beads or a
  committed doc, referenced from the bundle via `--ref`.
