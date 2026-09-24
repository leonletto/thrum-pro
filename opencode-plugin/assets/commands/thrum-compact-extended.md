---
description:
  Stage a comprehensive 16-section snapshot, verify it landed, then send /compact
  to this agent's OWN tmux pane so it stays alive and resumes at low context. Use
  for designer/architect-grade work needing wire contracts, capability matrix,
  and design rationale that the standard /thrum:compact format cannot carry.
---

# Compact — Extended (16-section snapshot)

Compose a comprehensive 16-section prose continuation, write it directly to your
restart file, verify it landed, then send `/compact` to your own tmux pane. Same
in-place semantics as `/thrum:compact` — the agent stays ALIVE,
sub-agents/loops/crons survive (confirmed empirically), no session end, no tmux
kill. The only difference is snapshot grade.

## When to use extended vs standard

- **Use `/thrum:compact` (standard)** for routine in-place context relief where
  post-compact you can reconstruct from the compaction summary + a compact
  11-section snapshot.
- **Use `/thrum:compact-extended` (this variant)** for designer/architect-grade
  work: a complex brainstorm with multiple owner-decided forks, a fanout
  implementation (≥3 call sites or ≥2 epics), or any compaction where the
  post-compact summary is likely to drop wire-contract precision you cannot
  cheaply re-derive.

## Steps

### 1. Verify tmux session (Tier 1 pre-check; run BEFORE composing anything)

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

**Use the EXTENDED 16-section structure.** The structure block is `§1.` through
`§16.` with per-section guidance documented in the partial.

**Note on §3 framing:** For a compact snapshot, §3 frames as "where work stands
at compaction" — you are continuing in place, not completing and not parking.

**Your snapshot's FIRST line MUST be the compact resume header**, above §1. It
survives even if post-compact orientation fails, so it is read-first and
self-contained:

> 🔴 ON RESUME — you were COMPACTED, not restarted. Daemon binding is intact
> (subagents/loops/crons survived). Resume LEAN: Read this file FIRST. Expect a
> `thrum prime --light` briefing already auto-injected by the SessionStart
> hook; only run `thrum:prime-agent` if it did NOT appear. Do NOT manually run
> full `thrum prime`. Then continue from §16.

Then §1…§16 as normal, with §16 (immediate next actions) actionable from a
compacted (not cold) start.

### 3. Write the continuation

Per Step 3 of the partial, use the Write tool to save your composed continuation
to `${REPO}/.thrum/restart/${AGENT}.md`.

This file lives on disk and is UNAFFECTED by compaction — compaction rewrites
your conversation context, never your worktree. So the snapshot is readable after
`/compact` fires. This matters more for an extended snapshot: you are staging
wire contracts, a capability matrix, and design rationale that are expensive to
reconstruct and exist nowhere else. There is no durable-backup step (the worktree
is not torn down, so `/thrum:sleep-extended`'s teardown-loss risk does not apply).

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
REPO=$(thrum agent worktree --authoritative 2>/dev/null) || { echo "ERROR: cannot authoritatively resolve your worktree via the daemon. Refusing to fall back to cwd/git-toplevel — that would risk silently resuming from the wrong repo's snapshot. Check daemon connectivity and retry."; exit 1; }
[ -n "$REPO" ] || { echo "ERROR: thrum agent worktree --authoritative returned empty"; exit 1; }
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
  # turn regardless, so the delay costs nothing. A NONZERO exit here means
  # the daemon never even queued the command (unreachable daemon, rejected
  # call, etc.) — the async delivery described above will never happen at
  # all, so this is caught synchronously, not inferred later from silence.
  thrum tmux send "$AGENT" "/compact"
  SEND_RC=$?
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
  fi
else
  echo "HOLDING: not firing /compact. Report the VERIFY FAILED line(s) above to"
  echo "your coordinator (or the operator if you are top-level) and stop."
  exit 1
fi
```

If EITHER check fails, the block HOLDS and does not fire `/compact` — holding is
safe; compacting against an unverified snapshot loses the context this command
exists to preserve (for an extended snapshot, wire contracts and design
rationale). If BOTH checks pass but `thrum tmux send` itself exits nonzero, the
block does NOT go idle un-compacted silently — it prints the failure and falls
back to a raw, explicit-socket `tmux send-keys` retry (single call, text +
Enter together) before holding for real. After a successful send (daemon-routed
or raw fallback), the turn ends; emit no further tool calls or prose this turn.
The daemon-routed send is queued, not synchronous — it fires once your pane goes
idle, which only happens if you stop acting now; the raw fallback, when it runs,
is synchronous.

## How resume works

After `/compact` the SAME process and session survive — the daemon binding is
intact (that is why your sub-agents, loops, and crons kept running). Full
`thrum prime` rebuilds identity + binding + full briefing for a NEW session; none
of that is needed here. Resume LEAN, in this order:

1. **Read your snapshot FIRST.** `Read ${REPO}/.thrum/restart/${AGENT}.md`
   unconditionally, before anything else, so orientation survives even if the
   next step errors. Its first line is the `ON RESUME` header; execute §16 from
   it. For an extended snapshot this recovers the §7 wire contracts, §8
   capability matrix, and §9 design inventory the compaction summary is likely to
   drop.
2. **Expect the light briefing to already be there.** On a healthy daemon with
   a fresh snapshot, the `SessionStart` hook auto-injects a `thrum prime --light`
   briefing zero-turn — you do not run anything for this. Only if it did not
   appear (daemon unreachable, stale/absent snapshot) run `thrum:prime-agent`
   manually as the fallback. Never manually run full `thrum prime`.
3. **Continue** from §16. Reconnect to your still-live sub-agents, loops, and
   crons rather than re-dispatching.

Runtime-specific compaction-recovery hooks (if this runtime has any) are
documented in that runtime's own plugin tree (its hooks manifest and
the scripts it points to), not here.

**Read the snapshot you just saved at `${REPO}/.thrum/restart/${AGENT}.md` and
follow its instructions post-compact.**
