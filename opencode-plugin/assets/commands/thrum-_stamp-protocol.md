---
description:
  Shared Authored-against stamp protocol — canonical format, derivation
  commands, and never-type rule. Not user-invocable directly.
---

# Authored-against Stamp Protocol (shared partial)

This is the canonical source-of-truth for the Authored-against stamp: its format,
derivation commands, and the never-type rule. Consuming files point here instead of
restating the recipe. Do NOT invoke this file directly; it has no terminal action.
(To find what currently points here: `grep -rn "_stamp-protocol.md" claude-plugin/`
— a hand-listed consumer roster in this file would rot the moment a new emitter or
reader is added, so none is kept here.)

## Purpose

A date alone cannot tell a reader whether the tree moved since an artifact was
authored. The Authored-against stamp embeds the exact commit SHA the author was
looking at and the configured merge target at authoring time. A reader can later
run the stamped diff command to detect whether any cited file has changed —
converting a qualitative suspicion ("is this stale?") into a falsifiable check.

## Stamp format (emitted artifact — verbatim)

Place these two lines at the appropriate location in the artifact (immediately
after its own date/frontmatter for brainstorm/plan/prompt; immediately after the
`Last updated` line for State.md and project_state.md):

```text
**Authored-against:** `<sha>` target: `<merge_target>`

> ⚠️ Verify base before acting: `git diff <sha>..origin/<merge_target> -- <files cited>` -- non-empty ⇒ cited code moved. (Resolve `<merge_target>` through its remote-tracking ref, never a bare local branch name — a local branch of the same name can be stale or absent.)
```

Always resolve `<merge_target>` through its remote-tracking ref
(`origin/<merge_target>`), never a bare local branch name, in every recipe in
this file — a local branch of the same name can be stale (last fetched days
ago) or simply absent on the reader's machine, while `origin/<merge_target>`
is only ever what's actually on the remote. Fetch before running any of these
diffs if the remote-tracking ref might be stale.

## Derivation commands (run at authoring time)

```bash
# SHA of the current HEAD
git rev-parse HEAD

# Configured merge target
jq -r '.orchestration.merge_target' .thrum/config.json
```

The author must never type or remember either value by hand — both come from the
shell commands above, run at authoring time.

If either command returns empty or `null`, STOP and report — do NOT emit a stamp
with a null/empty field. An artifact with no stamp is honest; an artifact stamped
`null` is a lie the reader cannot detect (the string "null" still matches the
reader's regex, so it reads as a valid stamp instead of UNVERIFIABLE, and the
resulting `git diff <sha>..null` then errors).

Before emitting the stamp, also verify the derived `<sha>` actually resolves:

```bash
git cat-file -e <sha>
# or: git rev-parse --verify <sha>^{commit}
```

If this fails, STOP and report — do NOT emit a stamp citing an unresolvable SHA.
This is the same failure class as the null/empty check above (a stamp the
reader cannot trust), catching a different way to get there: `git rev-parse
HEAD` itself can't produce a bad SHA, but a stamp isn't always freshly derived
this way — it can be hand-typed, copied from a stale source, or otherwise
introduced without running the command above. Treat this resolve-check as a
mandatory guard regardless of how the SHA was obtained, not an optional sanity
check.

## Format conventions

The stamp follows the same literal-match convention as the `THRUM-REVIEW` marker
(canonical form documented in `coordinator-running-brainstorm-cycles` skill
§ "Footer → commit → stamp"): fixed field order, case-sensitive, ASCII-only —
parseable with `grep -F` semantics without regex. The reader-side regex in
`verify-against-plan` anchors on this fixed format; do not reorder or recase any
field.

## Read-time provenance re-derivation

Both checks below are computable from the two fields the stamp already carries
(`<sha>` and `<merge_target>`) — no new stamped field is needed. A reader running
either check for the first time, or re-running it on an artifact read before,
must run them in this exact order; the second is undefined if the first fails
(short-circuit):

1. **SHA-resolves** — `git cat-file -e <sha>` (or
   `git rev-parse --verify <sha>^{commit}`). If this fails, the stamp cites a
   FABRICATED or mistyped SHA — flag RED immediately and do NOT attempt check 2.
   Merge-status has no defined answer for a SHA that does not exist.

2. **Merge-status** — only once check 1 has passed:
   `git merge-base --is-ancestor <sha> origin/<merge_target>`. If this succeeds
   (the SHA IS already an ancestor of the merge target) AND the artifact's own
   prose describes that SHA's work as still open ("in-progress", "awaiting a
   gate", "not yet merged", or similar), flag the claim STALE — the work
   described has already landed; whatever gate the artifact was waiting on
   already happened, or was never blocking to begin with.

This re-derivation must run EVERY TIME the artifact is read, not only once at
authoring time — the same diff-at-read discipline this file already establishes
for the base stamp (`git diff <sha>..origin/<merge_target>`). A check that only
ran once at write time cannot catch drift that accumulates afterward, as the
tree keeps moving.

Concrete motivating incident: a restart snapshot described an already-merged,
month-old commit as the agent's own in-progress work, still awaiting a gate that
no longer existed by the time the snapshot was read — an idle agent block that a
re-derived merge-status check would have caught immediately on the very next
read.
