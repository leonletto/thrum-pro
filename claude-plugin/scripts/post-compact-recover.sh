#!/usr/bin/env bash
# PostCompact hook: clear persisted context-window record (compatibility) + emit orientation
# prompt + re-arm listener (multi-agent only)
set -euo pipefail

THRUM_HOME="${THRUM_HOME:-.}"
THRUM_CONFIG="$THRUM_HOME/.thrum/config.json"

# Always emit orientation prompt. The SessionStart hook now auto-injects a
# zero-turn light briefing (`thrum prime --light`) in the normal case, so
# this is a manual fallback for when that auto-injection didn't fire or failed
# (e.g. daemon unreachable) — not the primary post-compact action.
echo "You were just compacted. The SessionStart hook should auto-inject a light briefing shortly — if you don't see one (e.g. daemon unreachable), read \`.thrum/restart/<your-agent>.md\` and run \`thrum:prime-agent\` manually as a fallback." >&2

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
  COMPACT_SNAPSHOT="$THRUM_HOME/.thrum/restart/${IDENTITY_AGENT_ID}.md"

  if [ -s "$COMPACT_SNAPSHOT" ]; then
    # Quoted heredoc ('MSGEOF') — no command substitution ever runs on this
    # body, per this project's CLAUDE.md heredoc rule. The dynamic snapshot
    # path is spliced in afterward via plain parameter-expansion string
    # replacement, never by re-opening the heredoc to shell expansion.
    COMPACT_MSG=$(cat <<'MSGEOF'
You've been compacted. Please read your snapshot at __SNAPSHOT_PATH__.
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

# Skip listener check for tmux-managed agents (daemon nudges directly)
TMUX_SESSION=$(THRUM_AGENT_ID="$AGENT_ID" \
  thrum whoami --field tmux_session 2>/dev/null)
if [ -n "$TMUX_SESSION" ]; then
  exit 0
fi

PID_FILE="$THRUM_HOME/.thrum/var/${AGENT_ID}-listener.pid"
if [ ! -f "$PID_FILE" ]; then
  echo "No listener running. Spawn a new listener." >&2
  exit 0
fi

LISTENER_PID=$(jq -r '.pid // empty' "$PID_FILE" 2>/dev/null)
if [ -z "$LISTENER_PID" ] || ! kill -0 "$LISTENER_PID" 2>/dev/null; then
  echo "Listener process dead. Spawn a new listener." >&2
  rm -f "$PID_FILE"
fi

exit 0
