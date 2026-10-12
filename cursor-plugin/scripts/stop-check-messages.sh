#!/bin/bash
# Stop hook: check for unread thrum messages before allowing the agent to stop.
# If unread messages exist, block the stop and direct the agent to check inbox.
# If no unread messages, exit 0 to let the agent stop normally.
#
# Dependencies: jq 1.6+ (for now/fromdate), thrum CLI
# This is an instant check (no blocking wait) — runs in <1s per turn.

# Start the runtime's 15-second Stop budget before input or preflight.
SECONDS=0

# Read hook input JSON — we need stop_hook_active to prevent infinite loops
INPUT=$(cat)
PROJECT_DIR="${CURSOR_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

write_idle() {
  bash "${SCRIPT_DIR}/stop-set-idle.sh" "$PROJECT_DIR" "${AGENT_ID:-}" "$((15 - SECONDS - 1))"
}

# Bound each daemon-facing preflight inside the same Stop allowance. Run the
# real CLI as the captured child PID so KILL also works if it ignores TERM.
bounded_preflight() {
  local work_dir="$1" output_file="$2" available cli_pid watchdog_pid cli_rc
  shift 2
  available=$((15 - SECONDS - 1))
  ((available >= 2)) || return 124
  (
    cd "$work_dir" || exit 1
    exec "$@"
  ) >"$output_file" 2>/dev/null &
  cli_pid=$!
  (
    sleeper_pid=
    trap '[[ -z "$sleeper_pid" ]] || kill "$sleeper_pid" 2>/dev/null || true; exit 0' TERM INT
    sleep "$((available - 2))" &
    sleeper_pid=$!
    wait "$sleeper_pid" || exit 0
    kill -TERM "$cli_pid" 2>/dev/null || true
    sleep 1 &
    sleeper_pid=$!
    wait "$sleeper_pid" || exit 0
    kill -KILL "$cli_pid" 2>/dev/null || true
  ) &
  watchdog_pid=$!
  cli_rc=0
  wait "$cli_pid" 2>/dev/null || cli_rc=$?
  kill -TERM "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true
  return "$cli_rc"
}

# Check if we're already in a stop-hook continuation cycle
# Try both Claude's stop_hook_active and generic patterns
STOP_HOOK_ACTIVE=$(echo "$INPUT" | grep -o '"stop_hook_active":\s*true' || true)
if [ -n "$STOP_HOOK_ACTIVE" ]; then
  AGENT_ID="${THRUM_AGENT_ID:-${THRUM_NAME:-}}"
  write_idle
  exit 0
fi

# Bail out if thrum isn't available or daemon isn't running
if ! command -v thrum &>/dev/null; then
  exit 0
fi
if ! bounded_preflight . /dev/null thrum daemon status; then
  exit 0
fi

THRUM_CONFIG="${PROJECT_DIR}/.thrum/config.json"

# Early exit: no thrum workspace
if [ ! -f "$THRUM_CONFIG" ]; then
  exit 0
fi

# This hook needs jq for the unread count and the listener PID parse. Without
# it those two checks are skipped (say so once on stderr); a genuinely missing
# listener PID file is still reported below, but an existing PID file is not
# second-guessed (an empty PID would be misreported as "invalid PID file").
if ! command -v jq >/dev/null 2>&1; then
  echo "thrum stop-check-messages.sh: jq is required but was not found on PATH; unread-message check and listener PID validation are NOT active. Install jq (apt install jq / brew install jq)." >&2
fi

# Early exit: single-agent mode
if command -v jq >/dev/null 2>&1; then
  SAM=$(jq -r '.daemon.single_agent_mode // false' "$THRUM_CONFIG" 2>/dev/null)
  if [ "$SAM" = "true" ]; then
    AGENT_ID="${THRUM_AGENT_ID:-${THRUM_NAME:-}}"
    write_idle
    exit 0
  fi
fi

# Phase 1: Resolve agent identity — must happen before inbox check so the
# query is scoped to this agent only (resolveLocalAgentID checks THRUM_AGENT_ID).
AGENT_ID="${THRUM_AGENT_ID:-${THRUM_NAME:-}}"
if [ -z "$AGENT_ID" ]; then
  # Without jq there is no safe way to parse a resolved identity or unread
  # count. Keep Stop permissive, but do not write an unknown agent's status.
  command -v jq >/dev/null 2>&1 || exit 0
  PREFLIGHT_OUTPUT=$(mktemp "${TMPDIR:-/tmp}/cursor-stop.XXXXXX") || exit 0
  trap 'rm -f "$PREFLIGHT_OUTPUT"' EXIT
  bounded_preflight "$PROJECT_DIR" "$PREFLIGHT_OUTPUT" thrum whoami --json || exit 0
  AGENT_ID=$(jq -r '.agent_id // empty' "$PREFLIGHT_OUTPUT" 2>/dev/null) || exit 0
  [ -n "$AGENT_ID" ] || exit 0
fi

# Phase 2: Check unread messages scoped to this agent
if command -v jq >/dev/null 2>&1; then
  if [ -z "${PREFLIGHT_OUTPUT:-}" ]; then
    PREFLIGHT_OUTPUT=$(mktemp "${TMPDIR:-/tmp}/cursor-stop.XXXXXX") || { write_idle; exit 0; }
    trap 'rm -f "$PREFLIGHT_OUTPUT"' EXIT
  fi
  if ! THRUM_AGENT_ID="$AGENT_ID" bounded_preflight "$PROJECT_DIR" "$PREFLIGHT_OUTPUT" thrum inbox --unread --json; then
    # Inbox is indeterminate; existing Stop behavior is permissive. A genuine
    # turn end may still clear only this registered agent's working status.
    write_idle
    exit 0
  fi
  MSG_COUNT=$(jq -r '.unread // 0' "$PREFLIGHT_OUTPUT" 2>/dev/null) || { write_idle; exit 0; }
  case "$MSG_COUNT" in ''|*[!0-9]*) write_idle; exit 0 ;; esac
  if [ "$MSG_COUNT" -gt 0 ]; then
    echo "ACTION REQUIRED: You have $MSG_COUNT unread message(s). Run \`thrum inbox --unread\` now to read and respond to them. Then mark them read: \`thrum message read <id> [<id>...]\` for the ids shown, or \`thrum message read --all\` (dry run) followed by \`thrum message read --all --force\` to clear everything — so this hook doesn't fire again on old messages." >&2
    exit 2
  fi
fi

# Skip listener check for tmux-managed agents (daemon nudges directly).
# If tmux_session is set in the identity file, the agent was launched via tmux.
# The session may have died, but if so the agent wouldn't be running this hook
# either (it runs inside the tmux pane). So field presence is sufficient here.
if [ -z "${PREFLIGHT_OUTPUT:-}" ]; then
  PREFLIGHT_OUTPUT=$(mktemp "${TMPDIR:-/tmp}/cursor-stop.XXXXXX") || { write_idle; exit 0; }
  trap 'rm -f "$PREFLIGHT_OUTPUT"' EXIT
fi
if ! THRUM_AGENT_ID="$AGENT_ID" bounded_preflight "$PROJECT_DIR" "$PREFLIGHT_OUTPUT" thrum whoami --field tmux_session; then
  # Listener state is unknown after a failed identity lookup; allow Stop and
  # attempt only the conditional status write within the remaining budget.
  write_idle
  exit 0
fi
TMUX_SESSION=$(cat "$PREFLIGHT_OUTPUT")
if [ -n "$TMUX_SESSION" ]; then
  write_idle
  exit 0
fi

# Phase 3: Check if listener process is alive via PID file
THRUM_DIR="${THRUM_HOME:-$PROJECT_DIR}"
PID_FILE="$THRUM_DIR/.thrum/var/${AGENT_ID}-listener.pid"

if [ ! -f "$PID_FILE" ]; then
  echo "Your background message listener is not running. Start it now." >&2
  exit 2
fi

# PID file exists but cannot be parsed without jq: allow Stop and clear status.
if ! command -v jq >/dev/null 2>&1; then
  write_idle
  exit 0
fi
LISTENER_PID=$(jq -r '.pid // empty' "$PID_FILE" 2>/dev/null || true)
if [ -z "$LISTENER_PID" ]; then
  echo "Your background message listener is not running (invalid PID file). Start it now." >&2
  exit 2
fi

if ! kill -0 "$LISTENER_PID" 2>/dev/null; then
  echo "Your background message listener has stopped (stale PID file). Restart it." >&2
  rm -f "$PID_FILE"
  exit 2
fi

# All stop gates passed: clear only a still-working status within the remaining
# Stop allowance. The helper treats daemon latency and failed writes as skips.
write_idle

# No unread messages and listener is healthy — let the agent proceed normally
exit 0
