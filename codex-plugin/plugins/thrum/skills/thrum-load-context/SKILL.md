---
name: thrum-load-context
description:
  Restore your session after compaction or session restart by running thrum
  prime
# source: claude-plugin/commands/load-context.md
---

# Thrum Load Context

Use this skill when the user explicitly wants the `load-context` Thrum workflow.
Prefer the umbrella `thrum` skill when the request spans multiple commands or
needs broader coordination judgment.

Run `thrum prime` to restore your session. The briefing includes your restart
snapshot, personal state, and committed-work queue.

```bash
thrum prime
```
