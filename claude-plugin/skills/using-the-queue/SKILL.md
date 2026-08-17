---
name: using-the-queue
description: "Use when an agent tracks its own committed work or needs to see who is doing what - keeping a task list of what you are working on, recording work someone assigned you, promoting a backlog bead or issue into active work, lifting an assignment out of a message you received, routing work to another agent, checking what another agent has on its plate, or moving a task through pending / in_progress / blocked / done. Also use when you reach a lull, go idle, or finish a thread and are about to conclude 'nothing pending' - reconcile your committed work against the queue before deciding you are done. Covers the full thrum queue CLI - bundles, embedded items, status, assignment provenance, and reading another agent's queue."
---

# Using the Thrum Queue

## Overview

`thrum queue` is a per-agent, local-only, daemon-resident list of the work an
agent has committed to. One queue per `agent_id`; you EDIT your own, anyone may
READ any queue. It is not beads and not a message inbox - beads is the shared
backlog of what COULD be done; the queue is the private, short-lived list of
what an agent IS doing right now, and it is gone when the agent is deleted.

**One rule governs everything else: the queue never crosses agents by itself.**
You only ever write your OWN queue. Assigning, handing off, and cross-box status
all travel as MESSAGES; the receiving agent adds the work to its own queue. No
command writes another agent's queue.

## When to Use

- You need a task list of what you are actively working on.
- Someone messaged you an assignment and you want it tracked as committed work.
- You are promoting a backlog item (a bead / thrum-issue) into active work.
- You are a coordinator/orchestrator routing work and want to record who you
  handed a bundle to.
- You need to see what another agent is working on or how loaded it is.
- You are moving a task between pending / in_progress / blocked / done, or
  clearing finished work out.

## Mental Model

- **Bundle** = one unit of committed work (the only top-level record). Carries a
  title, optional backlog `refs`, a status, a priority, and provenance.
- **Item** = a short checklist entry EMBEDDED inside a bundle. Items are never
  standalone and never linked across bundles. There is no nesting - a bundle
  holds items, nothing deeper.
- **`title` carries the whole content** - there is no body field (40 KB cap).
- **Local-only**: `.thrum/var/queue/<agent>.jsonl`, projected to SQLite, rebuilt
  on cold boot, included in `thrum backup`. Never peer-synced.

## Who-is-doing-what (read this if that is your goal)

Three distinct fields, do not conflate them:

- **`assigned_by`** - provenance: which agent assigned this to me. Auto-filled
  when a bundle/item is created with `--from-message` (from the message author).
  Answers "who gave me this."
- **`assigned_to`** - routing metadata I put on MY OWN bundle via
  `thrum queue assign`. It is informational only. **It does NOT write the
  named agent's queue and does NOT hand the work off.** Answers "who I intend
  this for." The actual handoff is a separate `thrum send`; that agent runs
  `thrum queue add --from-message` to pull it into its own queue.
- **`thrum queue list --agent <id>` / `show <id> --agent <id>`** - read another
  agent's queue directly. Answers "what is agent X working on / how loaded is
  it." Read-only, no permission gate.

## Quick Reference

| Command | Does |
|---|---|
| `thrum queue add --title "..."` | Create a bundle in your queue |
| `thrum queue add --from-message <msg_id>` | Special case: lift ONE specific message you received (content->title, author->assigned_by, refs->refs). Use the exact msg-id you're acting on - never head-1 of the inbox |
| `thrum queue add --ref bead:<id>` | Promote a backlog item into active work |
| `thrum queue list [--status <s>] [--agent <id>]` | List your queue (or another agent's) |
| `thrum queue show <bundle-id> [--agent <id>]` | Full detail for one bundle |
| `thrum queue start <bundle-id>` | -> in_progress (clears block_reason) |
| `thrum queue block <bundle-id> [--reason "..."]` | -> blocked (records the reason) |
| `thrum queue done <bundle-id>` | -> done (TEMPORARY waypoint, not deleted; `start` reopens it; clears block_reason) |
| `thrum queue drop <bundle-id>` | DELETE bundle + all its items, any status (the one destructive verb - drop promptly once a done bundle's record stops being useful) |
| `thrum queue assign <bundle-id> <agent-id>...` | Append agent(s) to assigned_to (routing metadata only) |
| `thrum queue item add <bundle-id> --title "..."` | Add one embedded item |
| `thrum queue item batch-add <bundle-id> --title "..." --title "..."` | Add several items in one call (shared --ref/--priority) |
| `thrum queue item start/block/done <bundle-id> <item-id>` | Item-level status (start/done clear the item's block_reason) |

Optional: `--ref <type>:<value>` (repeatable), `--priority N` (higher sorts
first), and `--from-message` (special case, below). `add` / `item add` require at
least one of `--title` or `--from-message`; explicit `--title` wins over
`--from-message`. **`--title` is the normal way to add work.**

## Common Flows

**Add work you're taking on (the normal case):**
```
thrum queue add --title "Ship the X migration"
```

**Promote a backlog bead into active work:**
```
thrum queue add --title "Ship the X migration" --ref bead:thrum-abc12 --priority 5
```

**Lift a SPECIFIC message you received** (special case - mainly an
orchestrator/agent taking a dispatch it was handed):
```
thrum queue add --from-message <msg_id>
```
Copies the message's content into the bundle title, its author into
`assigned_by`, its refs into `refs`, then discards the message ID. 🔴 Pass the
EXACT id of the assignment you are acting on, matched to its sender - NEVER pipe
`inbox --unread | head -1`, which grabs whatever is newest (often a monitor
alert or an unrelated message) and stores it as your title. For anything you
create yourself, use `--title`.

**Hand work to another agent** (two steps, in this order - there is no one-shot):
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

**Finish vs discard:** `done` is a WAYPOINT, not a resting place - it marks a
bundle done and KEEPS it visible (`start` reopens it), but it is not where
finished work should live. `drop` DELETES it and every item inside, regardless
of status. Reconcile at session start and natural breakpoints: `done` then a
prompt `drop` is the normal close-out; `drop` alone is fine too. Don't let a
done bundle outlive your next reconcile unless you deliberately keep it.

**Close on a TRIGGER, not a reminder.** The moment a bundle's branch merges into
trunk, OR its last referenced bead closes, `done` + `drop` it in that same turn -
closure is part of the merge/close act, exactly as `add` is part of dispatch. A
bundle whose branch is an ancestor of trunk, or whose beads are all closed, is
completed-but-open rot; do not leave it for "later". `add` has a natural trigger
(dispatch) and gets done reliably; the close has no trigger unless you make the
merge/close BE the trigger.

**Reconcile is a bounded sweep, not a review.** At session start / breakpoint,
close only the bundles a check proves done, and skip the rest. Two checks only:
- branch is an ancestor of trunk (`git merge-base --is-ancestor <tip> origin/<trunk>`) -> `done` + `drop`
- every `bead:` ref is closed (`bd show <id>`) -> `done` + `drop`

Do NOT read each bundle's full history - the sweep is those two checks against
merged/closed state, nothing more.

## Common Mistakes

- **Piping a guessed id into `--from-message` (e.g. `inbox --unread | head -1`).**
  That grabs whatever is newest - often a monitor alert or an unrelated message -
  and stores it as your bundle title. `--from-message` takes the EXACT id of the
  assignment you are lifting, matched to its sender; for anything self-created use
  `--title`.
- **Expecting `assign` to put work in the other agent's queue.** It does not -
  it only tags your own bundle. Always follow it with a `thrum send`; the
  recipient adds it themselves via `--from-message` (with that message's exact id).
- **Leaving done bundles to pile up.** `done` never removes anything - the
  bundle stays, and only `drop` deletes it. Drop each done bundle promptly once
  its record stops being useful; a queue full of undropped done bundles is the
  primary rot mode.
- **Reaching for a `remove`/`rename`/item-`drop` verb.** They do not exist by
  design: removal happens only at the bundle level via `drop`; titles are set at
  creation and not edited.
- **Trying to edit another agent's queue.** Impossible by design - you only
  write your own. Cross-agent work is messaging plus the recipient's own `add`.
- **Treating the queue as durable/shared history.** It is local, private, and
  deleted with the agent. Anything that must survive belongs in beads or a
  committed doc, referenced from the bundle via `--ref`.
