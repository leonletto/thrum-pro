---
description: Check message inbox
---

List messages in your inbox. Messages are auto-marked as read when displayed.

```bash
thrum inbox                  # All recent messages (auto-marks as read)
thrum inbox --unread         # Unread only (does not mark as read)
thrum inbox --json           # Machine-readable
thrum sent --unread          # Check sent items with unread recipients
thrum message read --all     # Mark all messages as read
```

**Search — do not page through it.** The default page is 10, newest-first, so
stale unread sorts LAST exactly when it has been waiting longest.

```bash
thrum message search "<term>"      # full-text across all messages
thrum inbox -q "<term>"            # same full-text search, scoped to your inbox
thrum message reindex              # rebuild the FTS index if search looks wrong
```
