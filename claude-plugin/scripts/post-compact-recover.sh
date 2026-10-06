#!/usr/bin/env bash
# PostCompact hook: clear persisted context-window record (compatibility) + emit orientation
# prompt + re-arm listener (multi-agent only)
set -euo pipefail

# jq is optional for this hook (every use below is guarded), but without it the
# identity self-message, context-window reset and listener PID validation are skipped, so
# say so once instead of skipping silently.
if ! command -v jq >/dev/null 2>&1; then
  echo "thrum post-compact-recover.sh: jq was not found on PATH; self-message, context-window reset and listener PID validation are SKIPPED. Install jq (apt install jq / brew install jq)." >&2
fi

THRUM_HOME="${THRUM_HOME:-.}"
THRUM_CONFIG="$THRUM_HOME/.thrum/config.json"

# Always emit orientation prompt. The SessionStart hook now auto-injects a
# zero-turn briefing (`thrum prime --light`: a light render for light-eligible roles, a full render for the rest) in the normal case, so
# this is a manual fallback for when that auto-injection didn't fire or failed
# (e.g. daemon unreachable) — not the primary post-compact action.
# thrum-xyz: the restart file is MOVED into sessions/ by the prime that the
# SessionStart hook runs, so never point at .thrum/restart/ alone.
echo "You were just compacted. The SessionStart hook should auto-inject a briefing shortly (your Resume Plan is in its '# Previous Session Context' section) — if you don't see one (e.g. daemon unreachable), read your snapshot (\`.thrum/restart/<your-agent>.md\`, or once archived the newest \`*-restart.md\` in the main repo's \`.thrum/agents/<your-agent>/sessions/\`) and run \`thrum:prime-agent\` manually as a fallback." >&2

# Self-message: tell the agent (via `thrum send`) that it was just compacted
# and name its restart snapshot. Owner requirement: "the post-compact hook
# should read the identity file to find the agent's ID and send the agent a
# thrum message ... It runs within
# the agent's worktree so this can work reliably." — i.e. resolve the ID from
# the LOCAL identity file, not a live `thrum whoami` RPC round-trip, since
# this hook fires at compaction time when a round-trip may be less reliable
# than a local file read. Placed first (immediately after the orientation
# echo) because it signals the compaction event itself, independent of the
# context-window-reset / single-agent / listener checks below.
#
# Best-effort throughout, matching the rest of this hook: any failure here
# (no identity file, no jq, `thrum send` itself failing) logs to stderr and
# falls through to the remaining steps — it must never abort the hook.
IDENTITIES_DIR="$THRUM_HOME/.thrum/identities"
IDENTITY_AGENT_ID=""
if command -v jq >/dev/null 2>&1 && [ -d "$IDENTITIES_DIR" ]; then
  for _id_file in "$IDENTITIES_DIR"/*.json; do
    [ -f "$_id_file" ] || continue
    _name=$(jq -r '.agent.Name // empty' "$_id_file" 2>/dev/null || true)
    if [ -n "$_name" ]; then
      IDENTITY_AGENT_ID="$_name"
      break
    fi
  done
fi

if [ -z "$IDENTITY_AGENT_ID" ]; then
  echo "post-compact-recover: no identity file found under $IDENTITIES_DIR — skipping self-message." >&2
else
  # Strip backticks defensively before interpolating (same hardening as
  # inject-prime-context.sh's AGENT_ID handling) — the identity validator
  # already blocks backticks upstream, so this is belt-and-suspenders.
  IDENTITY_AGENT_ID="${IDENTITY_AGENT_ID//\`/}"

  # Mirror inject-prime-context.sh's snapshot-path convention:
  # <worktree>/.thrum/restart/<agent_id>.md — the hook's worktree root here
  # is $THRUM_HOME (this hook has no whoami-derived AGENT_WORKTREE).
  #
  # thrum-xyz: the SessionStart prime MOVES that file into the MAIN repo's
  # .thrum/agents/<id>/sessions/<ts>-restart.md, so by the time this hook runs
  # the restart/ copy is normally gone. Resolve what exists AT NUDGE TIME and
  # name that exact path. A still-present restart/ file is the freshest (an
  # archived copy is always older), so it wins; otherwise the newest archived
  # copy. Best-effort: every command is guarded so set -e can never abort.
  COMPACT_SNAPSHOT=""
  _restart_file="$THRUM_HOME/.thrum/restart/${IDENTITY_AGENT_ID}.md"
  if [ -s "$_restart_file" ]; then
    COMPACT_SNAPSHOT="$_restart_file"
  else
    # A worktree's .thrum/redirect names the main repo's .thrum directory.
    _main_thrum="$THRUM_HOME/.thrum"
    if [ -f "$THRUM_HOME/.thrum/redirect" ]; then
      _redir=$(head -n 1 "$THRUM_HOME/.thrum/redirect" 2>/dev/null | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' || true)
      # A relative redirect resolves against the worktree root, not the hook's cwd.
      case "$_redir" in ""|/*) ;; *) _redir="$THRUM_HOME/$_redir" ;; esac
      if [ -n "$_redir" ] && [ -d "$_redir" ]; then _main_thrum="$_redir"; fi
    fi
    _sessions_dir="$_main_thrum/agents/${IDENTITY_AGENT_ID}/sessions"
    if [ -d "$_sessions_dir" ]; then
      _newest=$(ls -1t "$_sessions_dir"/*-restart.md 2>/dev/null | head -n 1 || true)
      if [ -n "$_newest" ] && [ -s "$_newest" ]; then COMPACT_SNAPSHOT="$_newest"; fi
    fi
  fi

  if [ -n "$COMPACT_SNAPSHOT" ]; then
    # Quoted heredoc ('MSGEOF') — no command substitution ever runs on this
    # body, per this project's CLAUDE.md heredoc rule. The dynamic snapshot
    # path is spliced in afterward via plain parameter-expansion string
    # replacement, never by re-opening the heredoc to shell expansion.
    COMPACT_MSG=$(cat <<'MSGEOF'
You've been compacted. Your Resume Plan is in the auto-injected briefing (# Previous Session Context). If it is missing, read your snapshot at __SNAPSHOT_PATH__ (use the Read tool).
MSGEOF
)
    COMPACT_MSG="${COMPACT_MSG//__SNAPSHOT_PATH__/$COMPACT_SNAPSHOT}"
  else
    COMPACT_MSG=$(cat <<'MSGEOF'
You've been compacted. No snapshot found — please re-prime normally.
MSGEOF
)
  fi

  if command -v thrum >/dev/null 2>&1; then
    if ! printf '%s\n' "$COMPACT_MSG" \
        | thrum send --to "@${IDENTITY_AGENT_ID}" --stdin >/dev/null 2>&1; then
      echo "post-compact-recover: thrum send failed (daemon down?) — continuing." >&2
    fi
  else
    echo "post-compact-recover: thrum not on PATH — skipping self-message." >&2
  fi
fi

# Clear the persisted context-window record for this session. With the
# producer-only design lower in-range used_percentage values are already
# accepted — Reset is retained for compatibility and explicit clearing but
# is not required for a post-compaction drop to land. Best-effort:
# a missing/unparseable session_id, or a Reset failure, must never abort the
# rest of this hook (orientation + listener re-arm below still matter).
INPUT=$(cat 2>/dev/null || true)
if command -v jq >/dev/null 2>&1; then
  SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
  if [ -n "$SESSION_ID" ]; then
    thrum context reset-window --session "$SESSION_ID" >/dev/null 2>&1 || true
  fi
fi

# Pane nudge: the daemon nudges a pane only when an ordinary message arrives
# for it; a compaction event produces no message, so without this the pane
# can sit idle after compacting even though the SessionStart auto-briefing
# above already restored its context. Placed here — BEFORE the single-agent,
# empty-AGENT_ID, and tmux-managed-skip early exits below — so every one of
# those paths still reaches the nudge first; none of them is a reason to
# skip nudging the pane itself. Resolved independently of THRUM_AGENT_ID /
# THRUM_NAME (a hook may run without either set) via a plain `thrum whoami`
# call, which resolves identity from THRUM_HOME/cwd on its own since this
# hook runs inside the agent's own worktree.
#
# Best-effort and fully guarded: if `thrum` is missing or the tmux session
# can't be resolved, the whole block is skipped silently. De-duplication
# uses an atomic `mkdir` lock rather than a time-window check (simpler, no
# arithmetic, portable): a near-simultaneous second hook firing for the same
# session finds the lock dir already there and skips; the backgrounded
# subshell removes the lock once its nudge attempt finishes, so a later,
# genuinely separate compaction can still nudge again.
NUDGE_VAR_DIR="$THRUM_HOME/.thrum/var"
# thrum-xyz: a skipped or failed nudge must NEVER be silent — a compaction
# that never gets a first turn looks identical to a healthy idle pane.
nudge_log() {
  mkdir -p "$NUDGE_VAR_DIR" 2>/dev/null || true
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$NUDGE_VAR_DIR/postcompact-nudge.log" 2>/dev/null || true
  echo "post-compact-recover: $1" >&2
}

NUDGE_TMUX_SESSION=$(thrum whoami --field tmux_session 2>/dev/null) || NUDGE_TMUX_SESSION=""
if [ -z "$NUDGE_TMUX_SESSION" ] && [ -n "${TMUX_PANE:-}" ] && command -v tmux >/dev/null 2>&1; then
  # whoami could not name the session (daemon slow/down); the hook runs inside
  # the agent's own pane, so tmux itself knows it.
  NUDGE_TMUX_SESSION=$(tmux display-message -p -t "$TMUX_PANE" '#S' 2>/dev/null) || NUDGE_TMUX_SESSION=""
fi
NUDGE_TMUX_SESSION="${NUDGE_TMUX_SESSION%%:*}"

# Exactly-once kickoff: /thrum:compact already queued the resume prompt on the
# daemon (queued-send, dispatched when the pane goes idle) and left a marker.
# Consume it and skip this nudge so the agent is not kicked twice. A bare
# /compact (no marker) or a stale marker still gets the nudge below.
NUDGE_MARKER="$NUDGE_VAR_DIR/${NUDGE_TMUX_SESSION}-compact-resume-queued"
NUDGE_ALREADY_QUEUED=0
if [ -n "$NUDGE_TMUX_SESSION" ] && [ -f "$NUDGE_MARKER" ] \
    && [ -n "$(find "$NUDGE_MARKER" -maxdepth 0 -mmin -15 2>/dev/null)" ]; then
  NUDGE_ALREADY_QUEUED=1
  rm -f "${NUDGE_MARKER:?}" 2>/dev/null || true
fi

if [ -z "$NUDGE_TMUX_SESSION" ]; then
  nudge_log "no tmux session resolved (whoami empty and no TMUX_PANE) — post-compact resume nudge SKIPPED; the pane may sit idle until a message or human input arrives"
elif [ "$NUDGE_ALREADY_QUEUED" -eq 1 ]; then
  nudge_log "resume prompt already queued by /thrum:compact for session ${NUDGE_TMUX_SESSION} — nudge not repeated"
elif command -v thrum >/dev/null 2>&1; then
  NUDGE_LOCK_DIR="$NUDGE_VAR_DIR/${NUDGE_TMUX_SESSION}-postcompact-nudge.lock"
  mkdir -p "$NUDGE_VAR_DIR" 2>/dev/null || true
  if [ -d "$NUDGE_LOCK_DIR" ]; then
    # A lock older than ~1 minute means the backgrounded job that created it
    # died before it could clean up (OOM-kill, tmux kill-server, reboot) --
    # without this reap, every future nudge for this session name would
    # silently no-op forever since mkdir keeps failing.
    if [ -n "$(find "$NUDGE_LOCK_DIR" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
      rm -r "${NUDGE_LOCK_DIR:?}" 2>/dev/null || true
    fi
  fi
  if mkdir "$NUDGE_LOCK_DIR" 2>/dev/null; then
    # `thrum tmux send` IS the daemon's queued send: it waits for the pane to
    # go idle, so no fixed sleep is needed for readiness (default delay 0;
    # THRUM_POSTCOMPACT_NUDGE_DELAY stays only as a test/override knob).
    # Bounded retry on a plain failure (rc 1: daemon busy/unreachable); rc 3/4
    # mean the text is already typed in the pane, so retyping would corrupt it.
    ( sleep "${THRUM_POSTCOMPACT_NUDGE_DELAY:-0}"
      _attempt=1
      while [ "$_attempt" -le 3 ]; do
        # `|| _rc=$?` keeps a failing send from tripping this file's `set -e`.
        _rc=0
        thrum tmux send "$NUDGE_TMUX_SESSION" "Compaction complete - please continue with your resume plan" >/dev/null 2>&1 || _rc=$?
        if [ "$_rc" -eq 0 ]; then break; fi
        if [ "$_rc" -eq 3 ] || [ "$_rc" -eq 4 ]; then
          nudge_log "tmux send rc=${_rc} for ${NUDGE_TMUX_SESSION}: text typed but Enter withheld/unknown — NOT retrying; inspect the pane"
          break
        fi
        if [ "$_attempt" -eq 3 ]; then
          nudge_log "tmux send failed rc=${_rc} after 3 attempts for ${NUDGE_TMUX_SESSION} — post-compact resume nudge NOT delivered"
          break
        fi
        _attempt=$((_attempt + 1))
        sleep 2
      done
      rm -r "${NUDGE_LOCK_DIR:?}" 2>/dev/null || true
    ) >/dev/null 2>&1 &
    disown 2>/dev/null || true
  fi
else
  nudge_log "thrum not on PATH — post-compact resume nudge SKIPPED"
fi

# Check single-agent mode — if so, done
if [ -f "$THRUM_CONFIG" ] && command -v jq >/dev/null 2>&1; then
  SAM=$(jq -r '.daemon.single_agent_mode // false' "$THRUM_CONFIG" 2>/dev/null)
  if [ "$SAM" = "true" ]; then
    exit 0
  fi
fi

# Multi-agent: check if listener is alive via PID file
AGENT_ID="${THRUM_AGENT_ID:-${THRUM_NAME:-}}"
if [ -z "$AGENT_ID" ]; then
  exit 0
fi

# Skip listener check for tmux-managed agents. The daemon only nudges a pane
# when an ordinary message arrives for it; it has no signal that a
# compaction happened, which is exactly why the pane nudge block above
# exists — this skip is solely about the listener-liveness check below, not
# about whether the agent gets nudged.
TMUX_SESSION=$(THRUM_AGENT_ID="$AGENT_ID" \
  thrum whoami --field tmux_session 2>/dev/null) || TMUX_SESSION=""
if [ -n "$TMUX_SESSION" ]; then
  exit 0
fi

PID_FILE="$THRUM_HOME/.thrum/var/${AGENT_ID}-listener.pid"
if [ ! -f "$PID_FILE" ]; then
  echo "No listener running. Spawn a new listener." >&2
  exit 0
fi

# Without jq the PID cannot be read; keep the hook non-failing and leave the
# PID file alone (the jq note above already explained why).
command -v jq >/dev/null 2>&1 || exit 0
LISTENER_PID=$(jq -r '.pid // empty' "$PID_FILE" 2>/dev/null)
if [ -z "$LISTENER_PID" ] || ! kill -0 "$LISTENER_PID" 2>/dev/null; then
  echo "Listener process dead. Spawn a new listener." >&2
  rm -f "$PID_FILE"
fi

exit 0
