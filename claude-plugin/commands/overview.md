---
description: Combines identity, team, inbox, and sync status
---

Show a combined view of agent identity, active team members, inbox messages, and
sync status.

```bash
thrum overview               # Human-readable
thrum overview --json        # Machine-readable
```

This is equivalent to running `thrum team`, `thrum inbox`, `thrum sent`, and
`thrum sync status` together.

`thrum inbox` here only shows the default page (10, newest-first) — stale
unread sorts LAST exactly when it has waited longest. Run
`thrum message search "<term>"` to search the full backlog instead of paging.
