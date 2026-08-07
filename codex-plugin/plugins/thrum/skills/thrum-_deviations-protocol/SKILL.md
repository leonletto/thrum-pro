---
name: thrum-_deviations-protocol
description:
  Shared Deviations-from-Source protocol — canonical block format, the
  required-even-when-empty rule, and derivation discipline. Not user-invocable
  directly.
# source: claude-plugin/commands/_deviations-protocol.md
# generated-by: scripts/sync-skills.sh
---

# Thrum \_deviations Protocol

This is a shared partial, not a user-invocable skill. Sibling Thrum skills
consume it as a protocol reference; do not invoke it directly.

## Deviations from Source Protocol (shared partial)

This file is the canonical source-of-truth for the "Deviations from Source"
block emitted by planning-loop artifacts (plans, implementation prompts). Do NOT
invoke this file directly; it has no terminal action.

(To find what currently points here:
`grep -rn "_deviations-protocol.md" claude-plugin/` — a hand-listed consumer
roster in this file would rot the moment a new emitter or reader is added, so
none is kept here.)

### Purpose

Dilution is a deletion: when a reviewer's feasibility objection causes a
requirement to be quietly dropped or weakened while converting one artifact into
the next (spec → plan → prompt), the loss leaves no artifact — you cannot grep
for an absence. Every downstream step remains internally consistent with the
step directly above it, so every review passes even though intent was lost
several steps back.

The fix is the same move as pairing every zero with a control: since an absence
cannot be verified, force it to be STATED. An artifact that dropped or weakened
nothing must say so explicitly ("No deviations from source."); an artifact that
is silent on deviations is untrustworthy by construction and FAILS the gate,
whether or not it actually dropped anything.

### Format (emitted artifact — verbatim)

Every plan and implementation prompt carries this heading, placed immediately
after its Authored-against stamp block (see `_stamp-protocol.md`):

```
## Deviations from Source

No deviations from source.
```

If anything was dropped or weakened relative to the declared source artifact(s),
replace the single line above with one bullet per deviation:

```
## Deviations from Source

- DROPPED: <requirement, quoted or closely paraphrased from the source> —
  why: <reason it was dropped/weakened> — source: <file:line or section ref>
  — attribution: <"owner decision" | "reviewer objection unresolved">
```

**The heading is REQUIRED even when the list is empty.** "No deviations from
source." is not boilerplate — it is a claim a human made that a reviewer can
check against the actual diff between artifact and source. An artifact missing
this heading entirely has not been checked and must fail the gate that looks for
it (see `project-setup/SKILL.md` Phase 0).

### Derivation rule

Derive the block by DIFFING the artifact against its actual, currently-read
source document or decision list — never by recalling from memory what was
probably dropped. This mirrors the discipline `thrum-m43mk`'s stamp already
established for a different axis (does the cited CODE still match), applied here
to a different axis (what did the AUTHOR consciously drop vs. the source) — no
git diff can see an absence, so the author must state it directly, freshly
re-derived at authoring time, not carried forward from a prior cycle.

### Attribution values

Each deviation item is attributed to exactly one of:

- `owner decision` — the intent-owner explicitly agreed to cut or weaken the
  requirement.
- `reviewer objection unresolved` — a reviewer raised a feasibility objection
  that has NOT yet been resolved by the intent-owner; this attribution is a
  FLAG, not a resolution, and must route to the intent-owner per the
  feasibility-escalation rule (see
  `coordinator-running-brainstorm-cycles/SKILL.md`) rather than being folded in
  silently.

### Format conventions

The `## Deviations from Source` heading is grep -F-matchable: exact case, exact
text, no variant headings. `project-setup/SKILL.md` Phase 0 gates on its literal
presence with `grep -F '## Deviations from Source'`. Do not reword, recase, or
relocate the heading.
