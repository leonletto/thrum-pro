---
name: load-context
description:
  Restore your session after compaction or session restart by running thrum prime
---

Run `thrum prime` to restore your session. The briefing includes your restart
snapshot, personal state, and committed-work queue.

```bash
thrum prime
```

If the output was truncated or you need to re-read it, run `thrum prime --to-file` (if --to-file is an unknown flag, run
plain `thrum prime` once and read its output fully)
ONCE and read that file page by page with your file-reading tool. Never re-run
`thrum prime` to page through it.
