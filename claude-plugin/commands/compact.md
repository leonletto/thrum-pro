---
description:
  Stage a standard 11-section snapshot, verify it landed, then send /compact to
  this agent's OWN tmux pane so it stays alive (subagents, loops, crons survive)
  and resumes at low context. Use for in-place context relief when you do NOT
  want to kill the session.
---

# Compact — Snapshot Then Compact In Place

Compose a standard 11-section prose continuation, write it directly to your
restart file, verify it landed, then send `/compact` to your own tmux pane.
Unlike `/thrum:restart` and `/thrum:sleep`, compact does NOT end your session and
does NOT kill your tmux pane — the agent stays ALIVE. Any sub-agents, background
loops, and cron schedules you own keep running across the compaction (confirmed
empirically). After compaction you Read your snapshot by hand and re-prime lean.

## When to Use

- Your context is high and you want relief WITHOUT losing the live session —
  you own sub-agents, a background loop, or a cron that must survive.
- You are mid-task and a fresh session (which loses in-flight sub-agent handles
  and scheduler state) would be more expensive than a compaction.

For context-exhaustion or stuck-state cases where a FRESH session is the right
answer — or where the coordinator should move you — use `/thrum:restart`. For
operator-shutdown parking that kills the session, use `/thrum:sleep`. Compact is
the only one of the three that keeps the runtime process alive.

## Steps

### 1. Verify tmux session (Tier 1 pre-check; run BEFORE composing anything)

```bash
# compact SENDS /compact to your own pane, so a non-tmux agent has no pane to
# target. Fail fast before you spend a snapshot composing.
SESSION_RAW=$(thrum whoami --field tmux_session)
if [ -z "$SESSION_RAW" ]; then
  echo "ERROR: the compact command requires a tmux-managed agent session (tmux_session field is empty)."
  echo "For a non-tmux agent, run /compact yourself and Read your snapshot by hand afterward."
  exit 1
fi
```

If `tmux_session` is empty: ABORT before composing. Exit code 1.

### 2. Read the shared snapshot-composition partial

**First, persist state + queue.** Update your personal state
(`thrum state set --kind personal_state ...` — see the `using-thrum-state`
skill) and your committed work (`thrum queue` — see the `using-the-queue`
skill) BEFORE composing your snapshot below — these survive compaction
independently of the prose continuation file and are what a post-compact
render reads back.

Read the partial at the absolute path (resolve `$REPO` yourself first via
`thrum agent worktree --authoritative` — NEVER `thrum whoami --field worktree`
or `git rev-parse --show-toplevel`, both cwd-resolved and the root cause of
a documented snapshot-save loss class; there is no git fallback):

```text
${REPO}/claude-plugin/commands/_snapshot-protocol.md
```

Apply its Step 2 (compose your continuation) per the structure guidance.

**Use the STANDARD 11-section structure.** For comprehensive
designer/architect-grade snapshots, use `/thrum:compact-extended` instead.

**Note on §1 framing:** For a compact snapshot, §1 frames as "where work stands
at compaction" — you are continuing in place, not completing and not parking.

**Your snapshot's FIRST line MUST be the compact resume header**, above §1. It
survives even if post-compact orientation fails, so it is read-first and
self-contained:

> 🔴 ON RESUME — you were COMPACTED, not restarted. Daemon binding is intact
> (subagents/loops/crons survived). Resume LEAN: this file is delivered inline in the injected briefing (read it FIRST). Expect a
> `thrum prime --light` briefing already auto-injected by the SessionStart
> hook; only run `thrum:prime-agent` if it did NOT appear. Do NOT manually run
> full `thrum prime`. Then continue from §9.

Then §1…§11 as normal, with §9 (Numbered resume plan) actionable from a
compacted (not cold) start.

### 3. Write the continuation

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

Write to EXACTLY the printed `SNAPSHOT_PATH` (not a path you re-derive), and make
sure the file contains the marker below (as its final line), with the printed `SNAPSHOT_NONCE` — verify searches the whole file for it:

```text
<!-- snapshot-nonce: <SNAPSHOT_NONCE> -->
```

**Record both values** — the verify step pastes them into its verify block, which
fails closed unless the file at that exact path carries that nonce.

This file lives on disk and is UNAFFECTED by compaction — compaction rewrites
your conversation context, never your worktree. So the snapshot you write now is
readable after `/compact` fires. There is no durable-backup step (the worktree is
not torn down, so `/thrum:sleep`'s teardown-loss risk does not apply here).

### 4. Verify your snapshot, then fire /compact (ONE block)

> ✅ **Use the SINGLE-call self-send form below — it is required, not stylistic.**
> `thrum tmux send` (OD-5 = B; supersedes `thrum tmux key`,
> which is being retired) takes exactly ONE client call: the daemon
> types the text, waits a settle gap, checks for a pending dialog, and only then
> sends the confirming Enter — all server-side, in that order, within the SAME
> call. There is no separate `key --type` + `key Enter` pair to race, because
> there is no second client call: a client-side race is structurally impossible
> here, not merely avoided by convention.
> 🔴 **Never issue two separate calls (one for the text, one for Enter)** — that
> shape is what the retired `tmux key` two-step form did, and it is what
> produced a truncated `/compac` → invalid command → silent no-op (measured).
> A single `thrum tmux send "$SESSION" "<command>"` call has no such split to
> make.

On a non-Claude runtime this block sends that runtime's own compact-equivalent
command in place of `/compact` — see
`${REPO}/claude-plugin/commands/_compact-runtime-commands.md` for the cited
per-runtime table; `scripts/sync-skills.sh` applies the substitution when
syncing this file to each runtime's plugin tree.

Firing `/compact` before the Step 3 Write lands compacts a pre-write context and
resumes from a stale/blank file — the exact failure this command prevents. This
block (paste the two values printed by the Step 3 PREP block into its first two
lines) re-resolves identity (the Bash tool does NOT persist shell state across
calls, so earlier steps' variables are gone), verifies the snapshot on disk, and
only then fires `/compact` — all in ONE call so nothing depends on a prior block.

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
  # turn regardless, so the delay costs nothing.
  thrum tmux send "$SESSION" "/compact"
  SEND_RC=$?
  # Exit 3 = HELD (Enter withheld), 4 = VERDICT UNKNOWN: "/compact" is already
  # typed in the pane. Do NOT retype it (that yields "/compact/compact"); report
  # and stop so a human/coordinator can inspect the pane.
  if [ "$SEND_RC" -eq 3 ] || [ "$SEND_RC" -eq 4 ]; then
    echo "HOLDING: thrum tmux send exited ${SEND_RC} (3=Enter WITHHELD, 4=verdict unknown) — /compact is typed but not confirmed submitted. NOT retrying."
    echo "Report this to your coordinator (or the operator if you are top-level) and stop."
    exit 1
  elif [ "$SEND_RC" -ne 0 ]; then
    echo "ERROR: thrum tmux send exited ${SEND_RC} — /compact was not queued. Report and stop."
    exit 1
  fi
  # thrum-xyz: queue the RESUME PROMPT right behind /compact, on the same
  # daemon queue. Hook output is context only — it does not start a turn — so
  # without this an idle pane with an empty inbox can sit at 0% context, empty
  # composer, until a human types. The daemon dispatches it once the pane is
  # idle again AFTER the compaction (FIFO behind /compact), so it is not a
  # timer and it fires exactly once.
  RESUME_PROMPT="Compaction complete - please continue: your Resume Plan is in the auto-injected briefing (# Previous Session Context). If it is missing, read ${SNAPSHOT} or the newest *-restart.md in .thrum/agents/${AGENT}/sessions/ of the main repo, then execute its numbered resume plan."
  thrum tmux send "$SESSION" "$RESUME_PROMPT"
  RESUME_RC=$?
  if [ "$RESUME_RC" -eq 0 ]; then
    # >>> postcompact-marker
    # Runtimes with a PostCompact hook only: leave a marker the hook consumes to
    # skip its own nudge (exactly-once). Written only on a successful queue; no
    # marker => the hook nudge stays the fallback. scripts/sync-skills.sh drops
    # this block for runtimes whose hook manifest has no PostCompact hook.
    mkdir -p "${REPO}/.thrum/var" && date +%s > "${REPO}/.thrum/var/${SESSION}-compact-resume-queued"
    # <<< postcompact-marker
    :
  else
    echo "WARNING: thrum tmux send exited ${RESUME_RC} — the post-compact resume prompt was NOT queued (exit 3/4 = already typed, do NOT retype). If the pane sits idle after compaction, send it a resume prompt by hand."
  fi
else
  echo "HOLDING: not firing /compact. Report the VERIFY FAILED line(s) above to"
  echo "your coordinator (or the operator if you are top-level) and stop."
  exit 1
fi
```

**Fail-closed binding rule:** the block only passes for the exact path and nonce
the Step 3 PREP block printed. It refuses (VERIFY FAILED, no `/compact`) if the
values are empty or still placeholders, if a fresh re-resolution of your identity
yields a different path (drift), or if the file at that path lacks the nonce — a
fresh file merely sitting at the re-derived path is NOT proof you wrote it.

If EITHER check fails, the block HOLDS and does not fire `/compact` — holding is
safe; compacting against an unverified snapshot loses the context this command
exists to preserve. After a successful send, the turn ends; emit no further tool
calls or prose this turn. The send is queued, not synchronous — it fires once
your pane goes idle, which only happens if you stop acting now.

## How resume works

After `/compact` the SAME process and session survive — the daemon binding is
intact (that is why your sub-agents, loops, and crons kept running). Full
`thrum prime` rebuilds identity + binding + full briefing for a NEW session; none
of that is needed here. Resume LEAN, in this order:

1. **Your Resume Plan arrives inline — do not go looking for the file.** The
   `SessionStart` hook auto-injects a `thrum prime --light` briefing zero-turn,
   and its `# Previous Session Context` section carries your full snapshot,
   including the `ON RESUME` header; execute §9 from it. That prime ARCHIVES the
   snapshot (moves `${REPO}/.thrum/restart/${AGENT}.md` into the main repo's
   `.thrum/agents/${AGENT}/sessions/`), so the original path is normally GONE
   by the time you look — that is by design, not loss. Only if no briefing
   appeared (daemon unreachable), read the newest `*-restart.md` in that
   `sessions/` directory (or `${REPO}/.thrum/restart/${AGENT}.md` if it still
   exists) and run `thrum:prime-agent` manually as the fallback. Never manually
   run full `thrum prime` when the briefing is present.
2. **A resume prompt starts your first turn.** Step 4 queued a "Compaction
   complete - please continue" prompt on the daemon right behind `/compact`; it
   is delivered once the pane is idle after compaction, so a turn starts even
   with an empty inbox.
3. **Continue** from §9. Reconnect to your still-live sub-agents, loops, and
   crons rather than re-dispatching.

Two hooks fire on `/compact`: `PostCompact`
(`claude-plugin/scripts/post-compact-recover.sh`) and `SessionStart` with
`source=compact` (`inject-prime-context.sh`). On a healthy daemon the
SessionStart hook auto-injects the briefing directly, Resume Plan body included
— you already have your context with no turn spent getting it. The PostCompact
hook only nudges the pane if Step 4's queued resume prompt is absent (a bare
`/compact`, or a failed queue), so you are never kicked twice.

**Follow the Resume Plan in your injected `# Previous Session Context` (snapshot
saved at `${REPO}/.thrum/restart/${AGENT}.md`, archived by the prime) post-compact.**
