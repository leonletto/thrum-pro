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

Read the partial at the absolute path (resolve `$REPO` yourself first —
`thrum whoami --field worktree`, falling back to `git rev-parse --show-toplevel`):

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
> (subagents/loops/crons survived). Resume LEAN: Read this file FIRST. Expect a
> `thrum prime --light` briefing already auto-injected by the SessionStart
> hook; only run `thrum:prime-agent` if it did NOT appear. Do NOT manually run
> full `thrum prime`. Then continue from §9.

Then §1…§11 as normal, with §9 (Numbered resume plan) actionable from a
compacted (not cold) start.

### 3. Write the continuation

Per Step 3 of the partial, use the Write tool to save your composed continuation
to `${REPO}/.thrum/restart/${AGENT}.md`.

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
block re-resolves identity (the Bash tool does NOT persist shell state across
calls, so earlier steps' variables are gone), verifies the snapshot on disk, and
only then fires `/compact` — all in ONE call so nothing depends on a prior block.

```bash
REPO=$(thrum whoami --field worktree 2>/dev/null)
[ -n "$REPO" ] || REPO=$(git rev-parse --show-toplevel) || { echo "ERROR: cannot resolve worktree"; exit 1; }
AGENT=$(thrum whoami --field agent_id) || { echo "ERROR: agent not registered"; exit 1; }
SESSION_RAW=$(thrum whoami --field tmux_session)
SESSION=${SESSION_RAW%%:*}
SNAPSHOT="${REPO}/.thrum/restart/${AGENT}.md"

# mtime: choose the stat dialect explicitly. GNU `stat -f` means --file-system
# (wrong, multiline) — the `stat -f %m . || stat -c %Y` one-liner is fragile on
# Linux, so branch on which dialect this box speaks.
if stat -f %m . >/dev/null 2>&1; then
  MTIME=$(stat -f %m "$SNAPSHOT" 2>/dev/null)
else
  MTIME=$(stat -c %Y "$SNAPSHOT" 2>/dev/null)
fi
NOW=$(date +%s)
AGE=$(( NOW - ${MTIME:-0} ))

SNAPSHOT_OK=1
if [ ! -s "$SNAPSHOT" ] || [ ! -r "$SNAPSHOT" ]; then
  echo "VERIFY FAILED: snapshot missing/empty/unreadable at $SNAPSHOT"; SNAPSHOT_OK=0
elif [ "$AGE" -gt 300 ]; then
  echo "VERIFY FAILED: snapshot is ${AGE}s old — stale (prior write), not this session's"; SNAPSHOT_OK=0
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
else
  echo "HOLDING: not firing /compact. Report the VERIFY FAILED line(s) above to"
  echo "your coordinator (or the operator if you are top-level) and stop."
  exit 1
fi
```

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

1. **Read your snapshot FIRST.** `Read ${REPO}/.thrum/restart/${AGENT}.md`
   unconditionally, before anything else, so orientation survives even if the
   next step errors. Its first line is the `ON RESUME` header; execute §9 from it.
2. **Expect the light briefing to already be there.** On a healthy daemon with
   a fresh snapshot, the `SessionStart` hook auto-injects a `thrum prime --light`
   briefing zero-turn — you do not run anything for this. Only if it did not
   appear (daemon unreachable, stale/absent snapshot) run `thrum:prime-agent`
   manually as the fallback. Never manually run full `thrum prime`.
3. **Continue** from §9. Reconnect to your still-live sub-agents, loops, and
   crons rather than re-dispatching.

Two hooks fire on `/compact`: `PostCompact`
(`claude-plugin/scripts/post-compact-recover.sh`) and `SessionStart` with
`source=compact` (`inject-prime-context.sh`). On a healthy daemon the
SessionStart hook auto-injects the LIGHT `thrum prime --light` briefing
directly — you already have lean project context with no turn spent getting
it. Still Read your snapshot (step 1) for the deliberate resume plan; the
light briefing intentionally omits the full Resume Plan body and points back
at the snapshot instead.

**Read the snapshot you just saved at `${REPO}/.thrum/restart/${AGENT}.md` and
follow its instructions post-compact.**
