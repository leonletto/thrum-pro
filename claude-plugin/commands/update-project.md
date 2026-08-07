---
description: Update project state with session summary and mechanical state
---

Update `.thrum/context/project_state.md` with fresh project state so a new
session can pick up exactly where this one left off.

**Do this IN YOUR OWN CONTEXT. Do NOT delegate it to a subagent.**

This is a named exception to the general dispatch discipline in your role
preamble ("delegate essentially all investigation to sub-agents to preserve
your context"). That rule is correct and stays — it protects your context from
repetitive investigation a subagent can do just as well. update-project is
different in kind: it is not investigation, it is the **serialisation of
context that exists only in your own head**. A subagent works from a brief you
hand it and can only render what the brief contains. What gets lost is exactly
what makes the artifact worth having — the rulings and their reasoning, the
corrections and *why*, which claims were VERIFIED versus merely assumed, and
which of this session's confident statements turned out WRONG. If you could
summarize those faithfully into a brief, you would already have written the
state yourself. Two more reasons this delegation is pure downside here
specifically: (1) you are already live with the session loaded — a subagent
re-processes context you already hold, at extra cost, from a summary instead
of the full session; (2) update-project runs only at session end, immediately
before a restart — there is no "later work" this session to protect, so the
usual token-saving justification for delegating does not apply.

### Step 1: Compose Your Session Summary

From YOUR context (what you already know), write a brief summary covering:

- **Session number**: Increment from the current project_state.md's session
  number (check `Phase` line or latest session heading)
- **What you worked on**: Key tasks, epics, beads progressed or closed
- **What changed**: Files modified, features shipped, bugs fixed
- **Key decisions**: Architecture choices, approach changes, investigations done
- **Current state**: What's in progress, what's blocked, what's next

This is the most valuable input — only you have the session narrative. Keep it
concise but complete (10-30 lines). You gather the mechanical state yourself in
the next step.

### Step 2: Gather Mechanical State Yourself

Run this ONE compound command directly in your own turn — do not dispatch it
to a subagent:

```bash
cd REPO_ROOT && \
echo "=== GIT LOG ===" && git --no-pager log --oneline -15 && \
echo "=== GIT STATUS ===" && git branch --show-current && git status --short && \
echo "=== BEADS STATS ===" && bd stats 2>&1 && \
echo "=== OPEN EPICS ===" && (bd list --status=open --type=epic 2>/dev/null || echo "(none)") && \
echo "=== READY ISSUES ===" && (bd ready -n 5 2>/dev/null || echo "(none)")
```

(Replace `REPO_ROOT` with the absolute path to the project root.)

### Step 3: Read the Current File

Read `REPO_ROOT/.thrum/context/project_state.md` in full, yourself, using the
Read tool.

### Step 4: Edit the File In-Place, Yourself

Use the **Edit tool** directly to make targeted updates. Do NOT rewrite the
entire file with the Write tool. Make one Edit call per section that needs
updating.

#### Sections to Update (use Edit tool for each)

1. **Header line** — Update `Last Updated` date and `Phase` status summary. Also
   derive and insert the Authored-against stamp per
   `claude-plugin/commands/_stamp-protocol.md`, placing these two lines
   immediately after the `Last Updated` line:

   **Authored-against:** `<sha>` target: `<merge_target>`

   > ⚠️ Verify base before acting: `git diff <sha>..origin/<merge_target> -- <files cited>` -- non-empty ⇒ cited code moved. (Resolve `<merge_target>` through its remote-tracking ref, never a bare local branch name — a local branch of the same name can be stale or absent.)

2. **Current State Summary — LIVE STATE ONLY, SUPERSEDED EACH SESSION.**
   Update version, branch, beads counts, and hold *only* what is currently
   in flight, owed, blocked, or pending the owner's decision. It carries
   **no session narrative** — no "what we did", no "why", no derivation.
   - **This is a SUPERSESSION, not an append.** Rewrite it to reflect
     current reality; do not add this session's items on top of last
     session's.
   - **Resolved items are DELETED, not annotated.** Do not leave a
     "~~fixed in S42~~" line — remove the line entirely. The line's absence
     *is* the record that it's resolved; the memory record (rule 4 below) is
     where the resolution's story lives.
   - **Why this is called out explicitly and not left implicit:** bounding
     only the session-index entries (rule 4/5 below) is a point fix. If
     narrative is merely blocked from `## Recent Sessions`, it reappears
     here under a different heading with no cap at all — the identical
     growth, one section over. This rule closes that sibling surface.

3. **Architecture Health table** (STRICT 10-row rolling window):
   - The table has a **Session / Date** column — format: `S<N> · YYYY-MM-DD`
     (e.g. `S32 · 2026-04-14`)
   - Add new rows for work done this session at the TOP of the table
   - Then TRIM: keep only the 10 most recent rows PLUS any row currently in a
     broken/regressed state (statuses like BROKEN, REGRESSED, BLOCKED, or a
     note explicitly describing ongoing breakage). Drop all other historical
     COMPLETE/FIXED/MOVED/UPDATED rows — they live in git history + Recent
     Sessions below
   - This is a rolling window, not an append log. If the table is at 10 and
     you add 2 new rows, remove 2 of the oldest non-broken rows
   - Do NOT add rows for routine work already covered in Recent Sessions —
     only genuinely new capabilities, architectural shifts, or broken state

4. **Recent Sessions** — EVERY session, including the one you are closing
   right now, is **exactly ONE LINE**. There is no carve-out for the most
   recent session — a prior version of this rule allowed a full prose block
   for the latest session, and that carve-out is REMOVED. No session ever
   gets a prose block.
   - For the session being closed, emit a `session_summary` memory record:
     ```
     thrum memory create \
       --kind session_summary \
       --scope project \
       --title "Session N — <title>" \
       --oneline "<one-line summary>" \
       --short "<short narrative (2-4 sentences)>" \
       --full "<full session body>"
     ```
     Capture the returned memory ID (e.g. `thrum-mem-01HQXZ...`).
   - Append a **single index line** to the `## Recent Sessions` block in
     project_state.md — no body prose, ever:
     ```
     - Session N (YYYY-MM-DD) — <what changed, ≤30 words> — [mem:<id>]
     ```
   - **The cap is on WORDS, not on newlines.** A 200-word run-on sentence
     crammed onto one physical line VIOLATES this rule just as much as a
     multi-line prose block does — line-count compliance is not the point,
     and treating it as the point is the exact loophole a previous version
     of this rule was walked through. Count words; keep the line ≤30 of
     them.
   - The full body lives in the memory record and is retrieved on demand via
     `thrum memory show <id>` or surfaced by the progressive-disclosure prime.
   - **What goes where** — the mechanical tell for sorting content: if a
     sentence contains "because", "I verified", "the mechanism was", "caught
     by", or "control fired", that sentence is DERIVATION, not state, and it
     belongs in the memory record, never in project_state.md.
     | Content | Destination |
     | --- | --- |
     | What changed | The one-line session index entry |
     | How you concluded it / verified it / why an earlier claim was wrong / what it taught | `thrum memory`, never project_state.md |
     | What's currently in flight, owed, blocked, or pending the owner | `## Current State Summary` (rule 2 above) |

   **NOTE:** `update-agent-state` (State.md surface, MI1) is a separate
   follow-on and is NOT part of this cutover. Personal State.md updates
   continue to use `thrum:update-state`.

5. **Session History Update Rule** (CRITICAL — keeps this cheap):
   - **At most TEN index entries in `## Recent Sessions`.** Older entries are
     **DELETED**, not archived in-file or moved to another section — the
     memory record IS the archive, so deleting the 11th line loses nothing.
   - **Adding this session's line and deleting the overflow line happen in
     the SAME edit / SAME commit.** Rotation has never actually been
     "broken" here — it has been *omitted*, and an omitted step that is
     someone's later intention never runs. Do not split "append now, trim
     later" into two steps; there is no later step. Emit the memory record,
     append the new index line, and delete the 11th-oldest line (if present)
     together.
   - Do NOT re-write or re-consolidate the other index lines you keep — they
     are frozen once written. The section stays compact indefinitely because
     it is bounded at 10, not because entries shrink over time.

6. **Worktree Layout** — Run `git worktree list` and rebuild the table with
   current branches. Cross-reference with `thrum team` output to annotate
   which agent is in each worktree.

7. **Open Epics / Active Work** — Replace with current epic list from beads.

8. **What's Queued / Next Steps** — Update priorities based on current state.

#### Edit Rules

- Use the Edit tool's old_string / new_string to target specific sections
- Each Edit should replace a clearly bounded section (between headings)
- Do NOT touch sections that haven't changed
- Do NOT re-write frozen `## Recent Sessions` index lines you are keeping
- Preserve all markdown formatting and heading hierarchy
- Use ABSOLUTE paths for all file operations

### Step 5: Verify Before Finishing

Run these checks yourself before reporting done — this is a required step,
not advice you may skip:

- `wc -l` the file BEFORE your edits and AFTER — report both counts.
- Count the entries under `## Recent Sessions` — must be **≤10**.
- Word-count the newly added session index line — must be **≤30 words**.
- Confirm no `## Sxxx` (or any other) prose block exists for any session —
  every entry in `## Recent Sessions` is a single index line.
- If the file GREW, state the reason. Growth is not automatically wrong
  (a legitimately new structural section can grow it), but an update that
  grows the file with no stated reason is a defect, not a style choice.

### Step 6: Report What You Changed

State directly (no subagent summary to relay):
- Which sections were edited
- Architecture Health: N rows dropped, N rows added, final count
- Recent Sessions: entry count before/after (must be ≤10), and the
  word count of the new entry (must be ≤30)
- Line count before/after (Step 5)
- Any issues encountered

## CRITICAL Rules

- Use the EDIT tool, not the Write tool — targeted changes only
- Architecture Health table is a **strict 10-row rolling window** + broken
  rows. Never let it grow beyond that
- **`## Recent Sessions` — every session is ONE LINE, no exceptions, including
  the session you are closing right now.** At most **10** entries; older ones
  are **deleted**, not archived in-file — the memory record is the archive.
  Deletion of the overflow entry happens in the **same edit** as the addition
  of the new one; it is one step, never two. The line cap is **≤30 words**,
  measured on words, not physical newlines — a long run-on sentence on one
  line still violates this.
- **`## Current State Summary` is superseded each session, never appended
  to.** It holds only what is in flight/owed/blocked/pending the owner.
  Resolved items are deleted outright, not annotated as resolved. Session
  narrative and derivation NEVER belong here — that is what `thrum memory`
  is for.
- Do NOT touch stable sections (Key Architecture Files, etc.) unless they
  changed
- Target total file size: ~150-300 lines for a SMALL project. A mature project
  will legitimately be larger and that is not bloat to be trimmed. The bounded
  part is SESSION HISTORY — those bodies now live in `session_summary` memories
  with a one-line index entry for the ~10 most recent, and older sessions are
  recoverable via `thrum memory search`. The rest (schema-compat contract,
  merge protocol, deploy state, architecture decisions, worktree layout) is
  DURABLE STRUCTURAL DATA that a restarting agent needs in order to act safely;
  shrinking it costs more than it saves. Do not trim structural sections to hit
  a line count.
- **Do not delegate any part of this to a subagent.** See the reasoning at the
  top of this file — it is a deliberate, named exception, not an oversight.
