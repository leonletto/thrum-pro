---
name: thrum-_project-rules-protocol
description: Shared project-specific-rules protocol consumed by role skills. Not user-invocable directly.
# source: claude-plugin/commands/_project-rules-protocol.md
# generated-by: scripts/sync-skills.sh
---

# Thrum _project Rules Protocol

This is a shared partial, not a user-invocable skill. Sibling Thrum skills
consume it as a protocol reference; do not invoke it directly.


## Project-Specific Rules Protocol (shared partial)

Consumers: run `grep -rl _project-rules-protocol claude-plugin/skills/` for the
current set — do NOT hardcode it here. A list of consumers inside the consumed
file is a second copy of a git-answerable fact and rots the moment a skill is
added or dropped.

Project-local rules of kind `agent_rule` at `--scope role` were loaded at
session start by your preamble (see your role template's Memory model block).
If a project-local rule conflicts with a universal rule above, the
project-local rule wins; surface the conflict in your reply so the user can
decide whether to graduate or remove the override.
