---
description:
  Shared generator-skill idempotency invariant consumed by config/doc
  generator skills. Not user-invocable directly.
---

# Generator Idempotency Protocol (shared partial)

Consumers: run `grep -rl _generator-idempotency-protocol claude-plugin/skills/`
for the current set — do NOT hardcode it here. A list of consumers inside the
consumed file is a second copy of a git-answerable fact and rots the moment a
skill is added or dropped.

The modes are idempotent — running the skill repeatedly on a stable project
should produce no file changes after the first run.
