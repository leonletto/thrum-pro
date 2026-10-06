---
name: thrum-compact-extended
description:
  Stage a comprehensive 16-section snapshot, verify it landed, then send
  /compact to this agent's OWN tmux pane so it stays alive and resumes at low
  context. Use for designer/architect-grade work needing wire contracts,
  capability matrix, and design rationale that the standard $thrum:thrum-compact
  format cannot carry.
# source: claude-plugin/commands/compact-extended.md
# generated-by: scripts/sync-skills.sh
---

# Thrum Compact Extended

Use this skill when the user explicitly wants the `compact-extended` Thrum
workflow. Prefer the umbrella `thrum` skill when the request spans multiple
commands or needs broader coordination judgment.

## Compact — Extended (16-section snapshot)

Compose a comprehensive 16-section prose continuation, write it directly to your
restart file, verify it landed, then send `/compact` to your own tmux pane. Same
in-place semantics as `$thrum:thrum-compact` — the agent stays ALIVE,
sub-agents/loops/crons survive (confirmed empirically), no session end, no tmux
kill. The only difference is snapshot grade.

### When to use extended vs standard

- **Use `$thrum:thrum-compact` (standard)** for routine in-place context relief
  where post-compact you can reconstruct from the compaction summary + a compact
  11-section snapshot.
- **Use `$thrum:thrum-compact-extended` (this variant)** for
  designer/architect-grade work: a complex brainstorm with multiple
  owner-decided forks, a fanout implementation (≥3 call sites or ≥2 epics), or
  any compaction where the post-compact summary is likely to drop wire-contract
  precision you cannot cheaply re-derive.

### Steps

#### 1. Verify tmux session (Tier 1 pre-check; run BEFORE composing anything)

```bash
# compact SENDS /compact to your own pane, so a non-tmux agent has no pane to
# target. Fail fast before you spend a snapshot composing.
SESSION_RAW=$(thrum whoami --field tmux_session)
if [ -z "$SESSION_RAW" ]; then
  echo "ERROR: the compact-extended command requires a tmux-managed agent session (tmux_session field is empty)."
  echo "For a non-tmux agent, run /compact yourself and Read your snapshot by hand afterward."
  exit 1
fi
```

If `tmux_session` is empty: ABORT before composing. Exit code 1.

#### 2. Read the shared snapshot-composition partial

**First, persist state + queue.** Update your personal state
(`thrum state set --kind personal_state ...` — see the `using-thrum-state`
skill) and your committed work (`thrum queue` — see the `using-the-queue` skill)
BEFORE composing your snapshot below — these survive compaction independently of
the prose continuation file and are what a post-compact render reads back.

Invoke the $thrum:snapshot-protocol skill and follow it, starting with its Step
1 (resolve your worktree ONLY via `thrum agent worktree --authoritative` — NEVER
`thrum whoami --field worktree` or `git rev-parse --show-toplevel`, both
cwd-resolved and the root cause of a documented snapshot-save loss class; there
is no git fallback).

Apply its Step 2 (compose your continuation) per the structure guidance.

**Use the EXTENDED 16-section structure.** The structure block is `§1.` through
`§16.` with per-section guidance documented in the partial.

**Note on §3 framing:** For a compact snapshot, §3 frames as "where work stands
at compaction" — you are continuing in place, not completing and not parking.

**Your snapshot's FIRST line MUST be the compact resume header**, above §1. It
survives even if post-compact orientation fails, so it is read-first and
self-contained:

> 🔴 ON RESUME — you were COMPACTED, not restarted. Daemon binding is intact
> (subagents/loops/crons survived). Resume LEAN: this file is delivered inline
> in the injected briefing (read it FIRST). Expect a `thrum prime --light`
> briefing already auto-injected by the SessionStart hook; only run
> `thrum:prime-agent` if it did NOT appear. Do NOT manually run full
> `thrum prime`. Then continue from §16. If you must re-read this file (no
> briefing appeared): read the NEWEST
> `.thrum/agents/<your-id>/sessions/*-restart.md` in the MAIN repo (the prime
> ARCHIVES the snapshot there); fall back to `.thrum/restart/<your-id>.md` only
> if it still exists. Find the newest with:
> `R=$(git rev-parse --show-toplevel); ls -1t "$(cat "$R/.thrum/redirect" 2>/dev/null || echo "$R/.thrum")"/agents/<your-id>/sessions/*-restart.md | head -1`
> (`$R/.thrum/redirect` in a worktree names the main repo's `.thrum`; using `$R`
> keeps this independent of your current directory). Open it with the Read tool
> (not Bash sed/cat). The `sessions/` file lives under the repo's `.thrum`, so
> that is allowed.

Then §1…§16 as normal, with §16 (immediate next actions) actionable from a
compacted (not cold) start.

#### 3. Write the continuation

First run this PREP block (it mints the path and a per-run nonce), then use the
Write tool per Step 3 of the partial:

```bash
# The Bash tool does NOT persist shell state across calls, so this block
# re-resolves identity itself. Fail closed: no cwd/git fallback.
REPO=$(
  thrum agent worktree --authoritative 2>/dev/null
) || { echo "ERROR: cannot authoritatively resolve your worktree via the daemon. Refusing to fall back to cwd/git-toplevel — that would risk silently saving this snapshot to the wrong repo. Check daemon connectivity and retry."; exit 1; }
[ -n "$REPO" ] || { echo "ERROR: thrum agent worktree --authoritative returned empty"; exit 1; }
AGENT=$(thrum whoami --field agent_id) || { echo "ERROR: agent not registered"; exit 1; }
[ -n "$AGENT" ] || { echo "ERROR: empty agent_id"; exit 1; }
mkdir -p "${REPO}/.thrum/restart"
SNAPSHOT="${REPO}/.thrum/restart/${AGENT}.md"
NONCE="zn6fx-$(date +%s)-$$-${RANDOM}${RANDOM}"
echo "SNAPSHOT_PATH=${SNAPSHOT}"
echo "SNAPSHOT_NONCE=${NONCE}"
```

Write to EXACTLY the printed `SNAPSHOT_PATH` (not a path you re-derive), and
make sure the file contains the marker below (as its final line), with the
printed `SNAPSHOT_NONCE` — verify searches the whole file for it:

```text
<!-- snapshot-nonce: <SNAPSHOT_NONCE> -->
```

**Record both values** — the verify step pastes them into its verify block,
which fails closed unless the file at that exact path carries that nonce.

This file lives on disk and is UNAFFECTED by compaction — compaction rewrites
your conversation context, never your worktree. So the snapshot is readable
after `/compact` fires. This matters more for an extended snapshot: you are
staging wire contracts, a capability matrix, and design rationale that are
expensive to reconstruct and exist nowhere else. There is no durable-backup step
(the worktree is not torn down, so `$thrum:thrum-sleep-extended`'s teardown-loss
risk does not apply).

#### 4. Verify your snapshot, then fire /compact (ONE block)

> ✅ **Use the SINGLE-call self-send form below — it is required, not
> stylistic.** `thrum tmux send` (OD-5 = B; supersedes `thrum tmux key`, which
> is being retired) takes exactly ONE client call: the daemon types the text,
> waits a settle gap, checks for a pending dialog, and only then sends the
> confirming Enter — all server-side, in that order, within the SAME call. There
> is no separate `key --type` + `key Enter` pair to race, because there is no
> second client call: a client-side race is structurally impossible here, not
> merely avoided by convention. 🔴 **Never issue two separate calls (one for the
> text, one for Enter)** — that shape is what the retired `tmux key` two-step
> form did, and it is what produced a truncated `/compac` → invalid command →
> silent no-op (measured). A single `thrum tmux send "$SESSION" "<command>"`
> call has no such split to make.

Firing `/compact` before the Step 3 Write lands compacts a pre-write context and
resumes from a stale/blank file — the exact failure this command prevents. This
block (paste the two values printed by the Step 3 PREP block into its first two
lines) re-resolves identity (the Bash tool does NOT persist shell state across
calls, so earlier steps' variables are gone), verifies the snapshot on disk, and
only then fires `/compact` — all in ONE call so nothing depends on a prior
block.

```bash
SNAPSHOT="<PASTE SNAPSHOT_PATH FROM STEP 3>"
NONCE="<PASTE SNAPSHOT_NONCE FROM STEP 3>"
# Fresh authoritative re-resolution; must agree with the path you actually wrote.
REPO=$(
  thrum agent worktree --authoritative 2>/dev/null
) || { echo "ERROR: cannot authoritatively resolve your worktree via the daemon. Refusing to fall back to cwd/git-toplevel — that would risk silently resuming from the wrong repo's snapshot. Check daemon connectivity and retry."; exit 1; }
[ -n "$REPO" ] || { echo "ERROR: thrum agent worktree --authoritative returned empty"; exit 1; }
AGENT=$(thrum whoami --field agent_id) || { echo "ERROR: agent not registered"; exit 1; }
[ -n "$AGENT" ] || { echo "ERROR: empty agent_id"; exit 1; }
SESSION_RAW=$(thrum whoami --field tmux_session)
SESSION=${SESSION_RAW%%:*}
EXPECTED="${REPO}/.thrum/restart/${AGENT}.md"
BIND_OK=1
if [ -z "$SNAPSHOT" ] || [ -z "$NONCE" ] || [[ "$SNAPSHOT$NONCE" == *"<PASTE"* ]]; then
  echo "VERIFY FAILED: SNAPSHOT/NONCE not filled in — paste SNAPSHOT_PATH and SNAPSHOT_NONCE from Step 3. SNAPSHOT_OK=0"; BIND_OK=0
elif [ "$SNAPSHOT" != "$EXPECTED" ]; then
  echo "VERIFY FAILED: identity/worktree DRIFT between write time and verify time. Written path: $SNAPSHOT — re-resolved path: $EXPECTED. SNAPSHOT_OK=0"; BIND_OK=0
fi

# mtime: choose the stat dialect explicitly. GNU `stat -f` means --file-system
# (wrong, multiline) — the `stat -f %m . || stat -c %Y` one-liner is fragile on
# Linux, so branch on which dialect this box speaks.
if stat -f %m . >/dev/null 2>&1; then
  MTIME=$(
    stat -f %m "$SNAPSHOT" 2>/dev/null
  )
else
  MTIME=$(
    stat -c %Y "$SNAPSHOT" 2>/dev/null
  )
fi
NOW=$(date +%s)
AGE=$(( NOW - ${MTIME:-0} ))

SNAPSHOT_OK=1
if [ "$BIND_OK" = 0 ]; then
  SNAPSHOT_OK=0   # binding failure already reported above
elif [ ! -s "$SNAPSHOT" ] || [ ! -r "$SNAPSHOT" ]; then
  echo "VERIFY FAILED: snapshot missing/empty/unreadable at $SNAPSHOT"; SNAPSHOT_OK=0
elif [ "$AGE" -gt 300 ]; then
  echo "VERIFY FAILED: snapshot is ${AGE}s old — stale (prior write), not this session's"; SNAPSHOT_OK=0
elif ! grep -qF -- "$NONCE" "$SNAPSHOT"; then
  echo "VERIFY FAILED: nonce not found in $SNAPSHOT — file at that path is not this session's write"; SNAPSHOT_OK=0
else
  echo "VERIFY OK: snapshot non-empty, readable, written ${AGE}s ago"
fi

SESSION_OK=1
if [ -n "$SESSION" ] && tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "VERIFY OK: tmux session '$SESSION' resolves"
else
  echo "VERIFY FAILED: tmux session '$SESSION' (from '$SESSION_RAW') does not resolve"; SESSION_OK=0
fi

if [ "$SNAPSHOT_OK" = 1 ] && [ "$SESSION_OK" = 1 ]; then
  # ONE call: `thrum tmux send` queues this text+Enter delivery on the daemon
  # (internal/daemon/rpc.HandleQueue -> sendQueuedCommand). The daemon waits
  # for your own pane to go idle (this turn ending is what makes it idle —
  # emit nothing further after this call), types the command, pauses a settle
  # gap, checks the pane for a pending dialog, and ONLY THEN sends Enter. If a
  # dialog is showing at that moment, the daemon withholds Enter itself
  # (queuedPaneShowsDialogFn / ErrPaneShowsDialog) — a HOLD happens
  # server-side, automatically, with no separate client-side check needed
  # here. There is no second client call for Enter, so there is nothing to
  # race: the old two-step `key --type` + `key Enter` truncation class
  # (measured: a timed-out type left a separate Enter to submit "/compac")
  # cannot occur when text+Enter are ONE call.
  #
  # This dispatch is ASYNC, not instant: it typically fires within a few
  # seconds of your pane going idle, not in the same instant this call
  # returns. That is expected — you are not emitting anything further this
  # turn regardless, so the delay costs nothing. A NONZERO exit here means
  # the daemon never even queued the command (unreachable daemon, rejected
  # call, etc.) — the async delivery described above will never happen at
  # all, so this is caught synchronously, not inferred later from silence.
  thrum tmux send "$AGENT" "/compact"
  SEND_RC=$?
  # Exit 3 = HELD, exit 4 = VERDICT UNKNOWN (thrum tmux send --help). In both
  # the "/compact" text is ALREADY TYPED into this pane and Enter was withheld
  # or unconfirmed. NEVER fall through to the raw retry below: it would append a
  # second "/compact" to the typed one ("/compact/compact") and press Enter into
  # whatever dialog the daemon just judged to be open. Surface it and stop.
  if [ "$SEND_RC" -eq 3 ] || [ "$SEND_RC" -eq 4 ]; then
    echo "HOLDING: thrum tmux send exited ${SEND_RC} (3=Enter WITHHELD, 4=verdict unknown) — /compact is typed but not confirmed submitted. NOT retrying."
    echo "Report this to your coordinator (or the operator if you are top-level) and stop; a human or coordinator must inspect the pane and submit or clear it."
    exit 1
  fi
  RESUME_PROMPT="Compaction complete - please continue: your Resume Plan is in the auto-injected briefing (# Previous Session Context). If it is missing, read ${SNAPSHOT} or the newest *-restart.md in .thrum/agents/${AGENT}/sessions/ of the main repo, then execute its numbered resume plan."
  if [ "$SEND_RC" -ne 0 ]; then
    echo "ERROR: thrum tmux send exited ${SEND_RC} — the daemon-routed self-send failed; it will NOT queue or deliver /compact."
    # Fail-loud fallback, NOT silent idle: attempt the compact command
    # directly via a raw tmux send-keys call, but only after asserting an
    # EXPLICIT socket. Never a bare/default-socket tmux operation here —
    # TMUX_TMPDIR does not reliably isolate a fleet box's tmux server from
    # the DEFAULT one, and a bare op under that condition has previously
    # taken down a shared fleet server. $TMUX is the one source that is not
    # a guess: tmux itself sets it, in THIS exact pane's own shell
    # environment, to "<socket_path>,<server_pid>,<window_index>" — so
    # splitting it gives the socket this pane is ACTUALLY connected
    # through, not an assumed default.
    RAW_TMUX_SOCK="${TMUX%%,*}"
    if [ -z "$RAW_TMUX_SOCK" ] || [ ! -S "$RAW_TMUX_SOCK" ]; then
      echo "HOLDING: cannot resolve/verify this pane's own tmux socket (\$TMUX unset, or the socket path is stale/missing) — refusing a bare-default-socket tmux fallback (fleet-safety)."
      echo "Report the ERROR line above to your coordinator (or the operator if you are top-level) and stop."
      exit 1
    fi
    if ! tmux -S "$RAW_TMUX_SOCK" has-session -t "$SESSION" 2>/dev/null; then
      echo "HOLDING: session '$SESSION' does not resolve on socket $RAW_TMUX_SOCK — refusing the raw fallback."
      echo "Report the ERROR line above to your coordinator (or the operator if you are top-level) and stop."
      exit 1
    fi
    echo "Retrying via raw tmux send-keys on explicit socket $RAW_TMUX_SOCK..."
    # ONE call: text + the Enter keystroke (C-m) together, same
    # single-call discipline as the daemon-routed path above — a two-call
    # split (send text, THEN a separate Enter call) is the exact shape
    # that produced a truncated "/compac" -> invalid command -> silent
    # no-op in the prior incident this file already documents. Do not
    # split this into two `tmux send-keys` invocations.
    tmux -S "$RAW_TMUX_SOCK" send-keys -t "${SESSION}:0.0" "/compact" C-m
    FALLBACK_RC=$?
    if [ "$FALLBACK_RC" -ne 0 ]; then
      echo "HOLDING: raw tmux send-keys fallback ALSO failed (exit ${FALLBACK_RC})."
      echo "Report the ERROR line(s) above to your coordinator (or the operator if you are top-level) and stop."
      exit 1
    fi
    echo "Raw fallback send-keys succeeded on socket $RAW_TMUX_SOCK."
    # The daemon route is known-dead here (that is why this is the
    # fallback), and on several runtimes no hook fires at all after
    # compaction — so queue the resume prompt on the same explicit socket,
    # same single-call text+C-m discipline. Without this the pane idles
    # after compaction with an empty composer until a human types.
    tmux -S "$RAW_TMUX_SOCK" send-keys -t "${SESSION}:0.0" "$RESUME_PROMPT" C-m
    RAW_RESUME_RC=$?
    if [ "$RAW_RESUME_RC" -eq 0 ]; then
      :
    else
      echo "WARNING: raw resume-prompt send-keys exited ${RAW_RESUME_RC} — the post-compact resume prompt was NOT queued. If the pane sits idle after compaction, send it a resume prompt by hand."
    fi
  fi
  # resume-prompt: queue the RESUME PROMPT right behind /compact — on the daemon
  # queue when the daemon-routed send succeeded (dispatched once the pane is
  # idle again AFTER the compaction, FIFO behind /compact: not a timer, fires
  # exactly once), or via the raw explicit-socket send above when the raw
  # fallback carried /compact. Hook output is
  # context only — it does not start a turn — so without this an idle pane with
  # an empty inbox can sit at 0% context, empty composer, until a human types.
  # The daemon dispatches it once the pane is idle again AFTER the compaction
  # (FIFO behind /compact), so it is not a timer and it fires exactly once.
  if [ "$SEND_RC" -eq 0 ]; then
    thrum tmux send "$AGENT" "$RESUME_PROMPT"
    RESUME_RC=$?
    if [ "$RESUME_RC" -eq 0 ]; then
      :
    else
      echo "WARNING: thrum tmux send exited ${RESUME_RC} — the post-compact resume prompt was NOT queued (exit 3/4 = already typed, do NOT retype). If the pane sits idle after compaction, send it a resume prompt by hand."
    fi
  fi
else
  echo "HOLDING: not firing /compact. Report the VERIFY FAILED line(s) above to"
  echo "your coordinator (or the operator if you are top-level) and stop."
  exit 1
fi
```

**Fail-closed binding rule:** the block only passes for the exact path and nonce
the Step 3 PREP block printed. It refuses (VERIFY FAILED, no `/compact`) if the
values are empty or still placeholders, if a fresh re-resolution of your
identity yields a different path (drift), or if the file at that path lacks the
nonce — a fresh file merely sitting at the re-derived path is NOT proof you
wrote it.

If EITHER check fails, the block HOLDS and does not fire `/compact` — holding is
safe; compacting against an unverified snapshot loses the context this command
exists to preserve (for an extended snapshot, wire contracts and design
rationale). If `thrum tmux send` exits 3 (Enter WITHHELD) or 4 (verdict
unknown), `/compact` is already typed in the pane: the block holds and does NOT
retype it. If BOTH checks pass but `thrum tmux send` itself exits nonzero (any
other code), the block does NOT go idle un-compacted silently — it prints the
failure and falls back to a raw, explicit-socket `tmux send-keys` retry (single
call, text + Enter together) before holding for real. After a successful send
(daemon-routed or raw fallback), the turn ends; emit no further tool calls or
prose this turn. The daemon-routed send is queued, not synchronous — it fires
once your pane goes idle, which only happens if you stop acting now; the raw
fallback, when it runs, is synchronous.

### How resume works

After `/compact` the SAME process and session survive — the daemon binding is
intact (that is why your sub-agents, loops, and crons kept running). Full
`thrum prime` rebuilds identity + binding + full briefing for a NEW session;
none of that is needed here. Resume LEAN, in this order:

1. **Your Resume Plan arrives inline — do not go looking for the file.** The
   `SessionStart` hook auto-injects a `thrum prime --light` briefing zero-turn,
   and its `# Previous Session Context` section carries your full snapshot,
   including the `ON RESUME` header; execute §16 from it. That prime ARCHIVES
   the snapshot (moves `${REPO}/.thrum/restart/${AGENT}.md` into the main repo's
   `.thrum/agents/${AGENT}/sessions/`), so the original path is normally GONE by
   the time you look — that is by design, not loss. Only if no briefing appeared
   (daemon unreachable), read the NEWEST `*-restart.md` in that `sessions/`
   directory, e.g.
   `ls -1t "$(cat "${REPO}/.thrum/redirect" 2>/dev/null || echo "${REPO}/.thrum")"/agents/${AGENT}/sessions/*-restart.md | head -1`
   (fall back to `${REPO}/.thrum/restart/${AGENT}.md` only if it still exists;
   use the Read tool, not Bash sed/cat, on `~/.claude` paths) and run
   `thrum:prime-agent` manually as the fallback. Never manually run full
   `thrum prime` when the briefing is present.
2. **A resume prompt starts your first turn.** Step 4 queued a "Compaction
   complete - please continue" prompt on the daemon right behind `/compact`; it
   is delivered once the pane is idle after compaction, so a turn starts even
   with an empty inbox.
3. **Continue** from §16. Reconnect to your still-live sub-agents, loops, and
   crons rather than re-dispatching.

Runtime-specific compaction-recovery hooks (if this runtime has any) are
documented in that runtime's own plugin tree (its hooks manifest and the scripts
it points to), not here.

**Follow the Resume Plan in your injected `# Previous Session Context` (snapshot
saved at `${REPO}/.thrum/restart/${AGENT}.md`, archived by the prime)
post-compact.**
