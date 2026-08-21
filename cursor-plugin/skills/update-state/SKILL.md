---
name: update-state
description: "Use to update your personal State.md — 'update your State.md', 'save personal state', 'significant checkpoint', 'sleep gate directive'. Any role (coordinator / implementer / researcher). Lightweight personal counterpart to thrum:update-project. Call any time; idempotent."
---

# Thrum: Update Personal State

Compose your resume-state directly from in-context knowledge — NO subagent
spawn, NO git log / bd stats / worktree list — and write it via
`thrum agent state write-personal`. Completes in seconds. Overwrite in place.

**Use this, not `thrum:update-project`**, for YOUR OWN state. `update-project`
is project-wide, coordinator-owned, and heavy. This is personal and instant.
Distinct from `thrum:update-agent-state` (that writes a 19-session
sliding-window archive to lowercase `state.md` via `thrum agent state
update`; this writes YOUR freeform personal `State.md` — capital S — via
`thrum agent state write-personal`).

**🔴 `thrum agent state write-personal` is the ONLY sanctioned way to write
State.md.** Never `cat`/heredoc/Edit the file directly. This is not a style
preference: the CLI is what actually enforces the rules in this skill —
rejecting an invented section, checking the size cap. A raw file write
bypasses both silently, which is exactly how State.md files grow
unbounded. If you find yourself reaching for
`cat > State.md` or the Edit tool on this file, stop — that is the failure
this skill exists to prevent, not an equally-valid alternative.

---

## Verify before you write

Read the shared partial at
`claude-plugin/commands/_verify-before-write-protocol.md` before writing
anything into State.md — it is the canonical source for the
verify-before-you-write invariant, applied here to State.md.

---

## Step 1 — Nothing to resolve; the CLI does it

`thrum agent state write-personal` resolves your agent id and the
`.thrum/redirect`-pointed write target internally — the same way `thrum agent
state update` already does for lowercase `state.md`. **This applies to every
agent that keeps a State.md, regardless of role or lifespan.** A short
implementer today can become a long-lived one; the write path does not know
or care which it's talking to.

Re-deriving that resolution by hand in a skill is the wrong layer for it:
the CLI command already needs to get it right to find your `state.md`
sibling file, so this skill just calls it rather than duplicating the
logic error-prone-ly.

**Your job ends at the write.** You write your own State.md via the command
below; you do not commit it. This holds even for agents without git write
access to the shared root. Committing accumulated `.thrum/agents/` state is
the coordinator's standing job (see the coordinator's repo-root state
hygiene duty), not something an implementer, researcher, or watcher should
reach for git to finish.

## Step 2 — Compose and write State.md (pointers-only, ≤ ~60 lines)

Compose the body directly from in-context knowledge. Two layers; no session
history; **only the six sections below — the write is REFUSED if you invent
a new one** (see "Schema is enforced, not just recommended" below).

**🔴 If a State.md already exists and is over ~60 lines, its current shape is
not a template to imitate — it IS the failure this skill exists to prevent.**
An oversized file got that way by being read as a precedent: each session's
author saw a long file and produced another entry in the same style, because
matching the surrounding convention feels safer than a bare instruction to
compress. Rebuild from the template below, not from the existing file's
sections, headings, or sentence length. If the existing file holds
information that seems too valuable to drop, that is a signal it belongs in
`thrum memory` (see size rules below) — not a reason to keep the file long.

```markdown
# Agent State — <agent_id>

> Personal state for @<agent_id>. TWO layers: (1) CURRENT STATE — what I'm in
> the middle of right now. (2) DURABLE / STRUCTURAL FACTS — permanent
> self-tracked facts. NO session history here — past sessions live in sessions/
> and are findable.

**Last updated:** <date + approximate time>

**Authored-against:** `<sha>` target: `<merge_target>`

> ⚠️ Verify base before acting: `git diff <sha>..origin/<merge_target> -- <files cited>` -- non-empty ⇒ cited code moved. (Resolve `<merge_target>` through its remote-tracking ref, never a bare local branch name — a local branch of the same name can be stale or absent.)

## Identity

- agent_id `<agent_id>` · role <role> · module <module>

## Current state (live threads)

- <active task / epic with status, e.g. "thrum-XXXX Phase 2 in progress — …">
- <pending decisions or blockers, if any>
- <active collaborators and what they're doing>

## Immediate next actions

1. <next concrete step>
2. <following step>

## Durable / structural facts

- **Home / CWD:** <repo path>, branch <branch>, tmux <session>
- **Key file locations:** <State.md path, worktree paths, spec/plan paths>
- **Build / deploy:** <relevant make targets or deploy commands>
- **Ownership / standing rules:** <standing facts unique to this agent>
- **Reach collaborators:** <how to ping coordinator, the project owner, etc.>

## Personal-relevance memory index

<!-- IDs of role/group/project memories this agent finds valuable.           -->
<!-- Cold-wake bundle auto-injects agent-scoped memories; State.md           -->
<!-- rides the bundle so the agent can pull exactly the broader ones it wants.-->

- `<memory-id>` — <one-line label>
- `<memory-id>` — <one-line label>

## Cold-successor note

<!-- Fill if leaving work mid-flight or handing off. Drop section if not needed. -->

- Current task: <ticket + phase>
- Key context: <one-sentence briefing for a cold successor>
- Unread inbox items to action: <message IDs or "none">

---

**⚠️ The information in this file may be stale — verify it against current
state before acting on it.**
```

When filling in the `Last updated` line, also write the standalone
`**Authored-against:** ...` stamp block on its own two lines right underneath it
(never fused into the `Last updated` line — the shared reader regex anchors at
line start, so a fused line would silently become undiffable). Derive and emit
the stamp per `claude-plugin/commands/_stamp-protocol.md`. This is the
mechanical enforcement of the "Verify before you write" invariant above: it
stamps exactly what tree the state was authored against so a reader can later
check whether cited code has moved.

Do NOT write a self-check/size-warning header yourself — `thrum agent state
write-personal` prepends one automatically on every successful write, so it
is present regardless of what template you started from. Anything you add by
hand here would be redundant with, and could drift from, the one the CLI
renders.

**Now write it:**

```bash
thrum agent state write-personal <<'EOF'
# Agent State — <agent_id>
...(the body you composed above)...
EOF
```

(A double-quoted heredoc or a raw argument would run command substitution on
`` ` `` / `$( )` / `${ }` in your shell before the content is ever sent — the
quoted `'EOF'` delimiter is what makes the body inert. Never drop the quotes.)

## Schema is enforced, not just recommended

`thrum agent state write-personal` REFUSES the write (nonzero exit, nothing
written) if the body contains any `## ` heading outside the six above (the
Durable/structural-facts section matches loosely — "Durable facts" or
"Structural facts" both count, not only the exact canonical spelling). This
is enforcement, not prose: prose ("no session-history section, ever") did
not stop agents inventing sections, because a genuine short-cycle
continuity need had no schema destination.

**If the CLI refuses your write:**

- **Unknown section** — it names the offending heading and, if a canonical
  section is a plausible match (a typo, a near-spelling), suggests it. If
  you have short-cycle/per-run observations to record (a watcher-style
  need), they do NOT belong in State.md at all — State.md is read into
  every prime/wake, so it must hold only current state, never a log; a
  rotating log destination for that need lives under `.thrum/var/log/` and
  is a separate mechanism, not this file.
- **Over cap** — it names the largest non-durable section so you trim
  there specifically, never "cut until the number drops," and never by
  cutting a Durable / structural fact (those are exempt, not merely
  allotted more room).

Retry after fixing. Do not work around a refusal by reaching for a raw file
write — see the warning at the top of this skill.

## Size rules (mandatory)

| Rule                           | What to do                                                          |
| ------------------------------ | ------------------------------------------------------------------- |
| Long prose belongs in a memory | `thrum memory add --scope agent "…"` → paste ID into index          |
| Personal-relevance index       | list memory IDs you want the cold-wake bundle to pull               |
| No session history             | past sessions → `sessions/` archive, never in State.md              |
| Hard cap                       | ≤ ~60 non-durable lines, **enforced by `thrum agent state write-personal`** (refuses the write over cap); anything longer signals content that belongs elsewhere |
| Per-entry cap                  | ≤ ~25 words per bullet. **The cap is on content, not on line breaks** — a single physical line stuffed with a 200-word run-on sentence violates this exactly as much as a wrapped paragraph would. If a bullet needs more than ~25 words, the extra belongs in `thrum memory`, not in a longer line. |
| Corrections replace, they don't accumulate | When a fact in "Current state" or "Durable / structural facts" changes, overwrite the bullet in place. Do not leave the old value beside the new one ("~~was X~~ now Y") — the *story* of how/why it was wrong is derivation, and derivation goes to `thrum memory`, never State.md. See the mechanical tell below. |
| Mechanical tell for what goes in memory, not here | If a sentence you're about to write contains "because", "I verified", "the mechanism was", "caught by", or "control fired" — that sentence is derivation, not current state. Write it to `thrum memory` and leave only the resulting fact (with a `[mem:<id>]` pointer if useful) in State.md. |
| Durable facts are exempt from trimming | The "Durable / structural facts" section is NOT session history and is not subject to the per-entry/hard-cap pressure above in the sense of being deleted to save space — a standing fact (home dir, build command, an ownership rule) stays as long as it's true. Trim it only when a fact stops being true, never merely to hit a line count. Cutting a real standing fact to satisfy the cap is worse than leaving the file a few lines over. |

## Step 3 — Verify before finishing

The command's own success line reports the final line count:

```text
Wrote /path/to/.thrum/agents/<id>/State.md (N lines)
```

That N includes the CLI-rendered self-check block (a few fixed lines) plus
your body — it is not the number the size-cap check gated on (that
count excludes the self-check block and the Durable section), so do not
compare it directly against 60. Still worth a glance:

- Confirm the command exited 0 (a refusal means nothing was written —
  your previous State.md, if any, is untouched).
- Spot-check the longest line you wrote for the per-entry word cap (~25
  words) — the CLI does not enforce this one; a compliant line count with
  one 200-word line is not a pass.
- If N looks surprisingly large for what you wrote, re-read your own body —
  a big N with few sections usually means one section (commonly "Current
  state") accumulated more bullets than intended.

## Sleep-gate handshake

When the lifecycle sleep ceremony sends a **sleep-gate directive** (a message
asking you to refresh your State.md before the sleep proceeds):

1. Run Steps 1–2 above — the write itself already updates the file's mtime,
   so there is no separate touch step.
2. Reply to the sleep-gate message with the single word: **done**

The sleep gate waits for that reply before proceeding. Without it the ceremony
stalls. If `write-personal` refuses your composed body (unknown section,
over cap) and you cannot fix it in the moment, do not silently send **done**
without writing anything — reply with what's blocking you instead so the
gate does not proceed on stale state; escalate to your dispatcher if you
are genuinely stuck.
