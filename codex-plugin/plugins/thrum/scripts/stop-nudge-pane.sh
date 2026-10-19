#!/bin/bash
# Stop-hook helper: queue ONE nudge to a tmux-managed agent's own pane instead
# of blocking the stop. `thrum tmux send` is the daemon's queued send: it waits
# for the pane to go idle, types the text and submits it. Always exits 0 and
# prints nothing on stdout, so the runtime never renders it as Stop feedback.
#
# The nudge is queued at stop time but delivered later, by which point the agent
# has usually read its mail. So the helper waits (one bounded call) for the pane
# to be ready, re-runs the hook's unread count, and sends ONLY if something is
# still unread; the text carries the fresh count. A failed or timed-out wait
# sends nothing.
#
# Usage: stop-nudge-pane.sh <agent_id> <unread_count> [project_dir] [tmux_session]
agent_id="${1:-}"
count="${2:-0}"
project_dir="${3:-.}"
session="${4:-$agent_id}"
[ -n "$agent_id" ] || exit 0
build_text() {
  text="ACTION REQUIRED: You have $count unread message(s). Run \`thrum inbox --unread\` now to read and respond to them. Then mark them read: \`thrum message read <id> [<id>...]\` for the ids shown, or \`thrum message read --all\` (dry run) followed by \`thrum message read --all --force\` to clear everything — so this hook doesn't fire again on old messages."
}
send_nudge() {
  local rc=0 wait_rc=0 inbox fresh
  (cd "$project_dir" 2>/dev/null; THRUM_AGENT_ID="$agent_id" thrum tmux wait-pane-ready "$session" --ceiling "${THRUM_STOP_NUDGE_CEILING:-60}" >/dev/null 2>&1) || wait_rc=$?
  if [ "$wait_rc" -ne 0 ]; then
    echo "thrum stop-nudge-pane.sh: wait-pane-ready rc=${wait_rc} for ${session}; nudge skipped" >&2
    return 0
  fi
  command -v jq >/dev/null 2>&1 || return 0
  inbox=$(cd "$project_dir" 2>/dev/null && THRUM_AGENT_ID="$agent_id" thrum inbox --unread --json 2>/dev/null) || return 0
  fresh=$(printf '%s' "$inbox" | jq -r '.unread // 0' 2>/dev/null) || return 0
  case "$fresh" in ''|*[!0-9]*) return 0 ;; esac
  [ "$fresh" -gt 0 ] || return 0
  count="$fresh"
  build_text
  (cd "$project_dir" 2>/dev/null; THRUM_AGENT_ID="$agent_id" thrum tmux send "$agent_id" "$text" >/dev/null 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "thrum stop-nudge-pane.sh: tmux send rc=${rc} for ${agent_id}; nudge not delivered" >&2
  fi
}
# The daemon's queued send waits for the pane to go idle, which cannot happen
# while this Stop hook is still running, so detach it and return at once.
# THRUM_STOP_NUDGE_SYNC=1 runs it inline (tests).
if [ "${THRUM_STOP_NUDGE_SYNC:-0}" = 1 ]; then
  send_nudge
else
  send_nudge >/dev/null 2>&1 </dev/null &
  disown 2>/dev/null || true
fi
exit 0
