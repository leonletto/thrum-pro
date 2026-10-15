---
name: memory-current-rule
description: "Use BEFORE writing or editing ANY memory - thrum memory create/update, thrum state set, a file-based memory, a memory index line (MEMORY.md), or a restart snapshot. A memory states only the CURRENT rule, never a timeline of rulings, corrections and reversals. Also use to audit or rewrite existing memories; written so a helper agent can apply it with no other context."
---

# A memory states the current rule, never its history

A memory written as a timeline ("X; later corrected to Y; exception Z; Z
reversed") is worse than no memory. The reader has to rebuild what is true now,
often rebuilds it wrong, and then acts on a rule that no longer holds.
Exceptions are fine. Reversals, and layers of revisions, are not.

This applies to every store: `thrum memory`, `thrum state`, file-based memories
and their indexes, and restart snapshots.

## Every time you touch a memory

Whenever you create, edit, append to or merge a memory, examine the WHOLE memory,
not just your change. If any part of it is a timeline, a stale version of a rule,
or a summary that disagrees with the body, rewrite the whole memory to the
current rule in the same edit.

## The shape

```text
<Rule, present tense, one or two sentences, with its full scope:
 which roles, runtimes, repos, peers, boxes or paths it covers.>
<Exceptions as part of the rule: "except X, where Y". An exception that ends
 on a condition says so: "until <bead/event>; check it before applying".>
Owner, date and one short quote of the CURRENT ruling (optional).

Why: <the reason, short>
How to apply: <as many bullets as the rule needs: every still-current
 precondition, command, control and bound>
```

A memory that carries several independent rules (a reader could need one without
the others) keeps each as its own headed section in this shape, or is split into
separate memories that link to each other. Never collapse independent rules into
one sentence, and never drop a rule because it is not the title's rule.

## What stays and what goes

Stays:
- The current rule, its full scope words, and its current exceptions.
- The current ruling's owner, date and one short quote.
- The reason. A past incident stays only if, without it, the Why would be empty
  or the rule would look optional; keep it to two lines.
- Every still-current precondition, command, control and bound.

Goes:
- Replaced statements, their quotes and their dates.
- "First X, then Y" narratives of how the rule changed.
- An exception that no longer applies.
- Evidence (file:line, probes, controls) that only supported a replaced
  statement. Never keep evidence for a rule that no longer holds.
- Markers: "UPDATE", "CORRECTED", "SUPERSEDED", "REVERSED", "STRICKEN",
  "later", "(late)", strikethrough.

## Scope is part of the rule

Never shorten scope words (which repo, role, runtime, peer, box, path). A rule
that loses its scope is a different rule. For anything about authorization,
peering, capability or access, read the project's security model before
rewriting and keep every scope qualifier word for word.

## Every summary must agree with the body

A memory can have several summaries; find them all and make each match the
rewritten body:
- File memory: its front-matter `description:`, its line in the main index
  (e.g. MEMORY.md), and its line in any secondary index (e.g.
  MEMORY-reference.md). Grep the file name in every index.
- `thrum memory`: its `--title` and `--oneline`. Find related entries with
  `thrum memory search <topic>`; rewrite with `thrum memory update <id>`.
- `thrum state`: the value of every key that restates the rule. When a file
  memory names a state key, read it and keep the two identical.

In an index, one entry is one `[text](file.md)` link. Rewrite only that entry's
text; never touch the entries that share its line. Follow any format contract the
index states about itself (caps, demotion), except that an index entry which
annotates a memory as superseded or corrected is itself a timeline and must be
rewritten or removed.

## Rewriting a memory, step by step

1. Read the memory in full, every memory it links to, and every memory on the
   same topic (search by topic, not only by title). If it names a live source
   (a config key, skill, template, bead), read that too: when the live source is
   newer, it decides the current rule, and the memory should say "read X at the
   moment of use" instead of restating X.
2. List, privately, every distinct statement it makes, with its date or position.
3. Decide the current rule POINT BY POINT, not file by file. For each point,
   take the latest owner statement on that point. A later statement REPLACES an
   earlier one only when it covers the same scope. If it covers a narrower scope,
   it is an exception, and the earlier statement still governs everywhere else.
   If two statements have the same scope and no clear order, mark the memory
   AMBIGUOUS, change nothing, and report the exact question for the owner.
4. Rewrite the memory in the shape above, one section per independent rule.
5. Rewrite every summary (see above) to match.
6. If another memory states the same rule: move every still-current point from
   it into the memory you keep, then reduce it to a one-line body
   ("Merged into <name>.") and re-point or remove its index entries. Never reduce
   a memory to a pointer before its current points have moved.
7. Self-check (all must be yes):
   - A reader could act correctly after reading only the first section.
   - Each rule is stated once, with no earlier version beside it.
   - Every summary says the same thing as the body.
   - No other memory states a different version of the rule.
   - No scope word, current exception, precondition or reason was lost.
8. Report each memory as REWRITTEN, MERGED INTO x, AMBIGUOUS (question) or
   UNCHANGED (why), with one line saying which rules were kept, dropped (and
   why) or moved (and where).

Never invent a rule. When unsure whether a statement is still current, ask.

## Auditing a store

Grep the store for the markers above and for topics that more than one memory
covers, then follow the steps for each hit. Grep finds only marked memories, so
also read memories that share a topic with a hit.
