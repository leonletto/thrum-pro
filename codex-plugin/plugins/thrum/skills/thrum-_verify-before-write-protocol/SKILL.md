---
name: thrum-_verify-before-write-protocol
description: Shared "Verify before you write" invariant consumed by state-writing skills. Not user-invocable directly.
# source: claude-plugin/commands/_verify-before-write-protocol.md
# generated-by: scripts/sync-skills.sh
---

# Thrum _verify Before Write Protocol

This is a shared partial, not a user-invocable skill. Sibling Thrum skills
consume it as a protocol reference; do not invoke it directly.


## Verify Before You Write Protocol (shared partial)

Consumers: run `grep -rl _verify-before-write-protocol claude-plugin/skills/`
for the current set — do NOT hardcode it here. A list of consumers inside the
consumed file is a second copy of a git-answerable fact and rots the moment a
skill is added or dropped.

A written fact is TRUE at the moment it's recorded and can silently become
FALSE later — the reader can't tell, because a note doesn't present itself as
a time-bound claim. Before writing anything:

- Only write what you've verified against current state — not what you
  remember, assume, or were told once.
- A note recording an UNEXPLAINED artifact must carry the unexplained-ness
  forward — "not mine, cause unknown, nobody has traced this" — rather than
  resolving it to a disposition like "ignore it." The note isn't wrong to cope
  with noise you can't act on; the defect is closing the question when
  nothing is actually known. "Ignore it" is unfalsifiable by construction —
  an instruction to not look can't be caught by looking, because diligence is
  exactly what it switches off — and it can silently train every future
  session to stop looking at the one visible symptom of a live bug.
