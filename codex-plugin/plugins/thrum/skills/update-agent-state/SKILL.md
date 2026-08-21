---
name: update-agent-state
description: "Use at end of work / wrap up session / save agent state — records the just-completed session into the scheduled agent's state.md history. The 4 verbatim + 3 blocks of 5 = 19-session sliding window is enforced by the `thrum agent state update` CLI command (CLI-invoked at session end, NOT a daemon background process; hand-editing state.md bypasses it entirely); the agent's job is to author a one-line summary that will be the verbatim entry."
# source: claude-plugin/skills/update-agent-state/SKILL.md
# generated-by: scripts/sync-skills.sh
---


## Thrum: Update Agent State

Record the just-completed session into `.thrum/agents/<agent-id>/state.md` so
the NEXT wake's `$thrum-prime-agent` invocation has continuity.

This skill is the wake-loop counterpart to `$thrum-prime-agent`. Run this at the
END of every scheduled-agent session, before exiting.

### When to use this skill

- You're a SCHEDULED AGENT (woken by an `agent.wake` message)
- You're about to exit / end the session
- You have a coherent one-line summary of what shipped

If you're an operator-spawned agent (coordinator, on-demand task), use
`$thrum-update-project` instead — that updates the project- wide state.md, not
the per-agent state.md this skill targets.

### Verify before you write

Read the shared partial at
`claude-plugin/commands/_verify-before-write-protocol.md` before composing
your summary or narrative fields — it is the canonical source for the
verify-before-you-write invariant, applied here to your summary and
narrative fields.

### Step 1: Compose your one-line summary

Write a single sentence that names what shipped this session. Examples:

> Locked the spec with 5 approvals and 1 item deferred to impl-time.
>
> Closed epic phase N. 2 blocking + 5 important + 10 minor findings.
> All three load-bearing traps PASSed.
>
> Investigated a race; confirmed the fix and filed it with supporting evidence.

Be specific. Future-you skimming the verbatim queue will skim these one-liners
first — vague entries ("worked on the project") waste the verbatim slot.

### Step 2: Run the update command

```bash
SESSION_ID=$(thrum whoami --field session_id)
thrum agent state update \
  --session-id "${SESSION_ID}" \
  --summary "<your one-line summary from Step 1>"
```

The CLI:

1. Reads `.thrum/agents/<your-agent-id>/state.md` (or creates an empty one on
   first wake).
2. Prepends your new entry to the verbatim queue (slot #1).
3. Promotes the displaced #4 entry into the most-recent summary block
   (sliding-window rules), opening a new block + dropping the oldest if the
   cap is reached.
4. Writes the updated `state.md` atomically (temp-file + rename).

The strict 4-verbatim / 3-block / 5-per-block invariants are enforced by this
CLI command, not the daemon. Enforcement only fires when you actually run `thrum agent state
update`; nothing watches or rewrites the file in the background. You can't
accidentally break the format by running this command, but hand-editing
`state.md` yourself is NOT supported (the parser will reject a manually-
mangled file at the next recovery cycle) and does not go through this
enforcement at all.

### Step 3: Optional — replace narrative sections

If this session changed your "Last worked on" or "Planning next" paragraphs
(e.g., closed an open thread, identified a new follow-up), pass them as flags:

```bash
thrum agent state update \
  --session-id "${SESSION_ID}" \
  --summary "<one-liner>" \
  --last-worked-on "Closed the update-state work. Open thread: recovery skill still needs its escalation wiring." \
  --planning-next "Next wake should pick up the escalation wiring — it is the load-bearing piece."
```

Without these flags, the previous "Last worked on" / "Planning next" paragraphs
are preserved. Skill `$thrum-prime-agent` will surface them on next wake
regardless.

### Step 4: Verify the write

The CLI prints a one-line confirmation:

```text
Updated /path/to/.thrum/agents/<id>/state.md (verbatim: N, summary blocks: M)
```

Where N ∈ [1, 4] and M ∈ [0, 3]. If N or M fall outside those ranges, something
is wrong — the format invariants are enforced in code; an out-of-range count
indicates a code bug — file it.

### What this skill does NOT do

- Does NOT update `last_seen_skills.txt` (that's `$thrum-update-agent-state`'s
  sibling responsibility; current implementation does not bump the file).
- Does NOT trigger the next wake (cron / scheduler dispatch is daemon-driven;
  this skill just records what already shipped).
- Does NOT recover from a malformed `state.md` — if the parser rejects the
  existing file, run `$thrum-recover-agent-state` first to clear the corruption
  flag.
