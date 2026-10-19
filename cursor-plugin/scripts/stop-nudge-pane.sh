#!/bin/bash
# Stop-hook helper: queue ONE nudge to a tmux-managed agent's own pane instead
# of blocking the stop. `thrum tmux send` is the daemon's queued send: it waits
# for the pane to go idle, types the text and submits it. Always exits 0 and
# prints nothing on stdout, so the runtime never renders it as Stop feedback.
#
# Usage: stop-nudge-pane.sh <agent_id> <unread_count> [project_dir]
agent_id="${1:-}"
count="${2:-0}"
project_dir="${3:-.}"
[ -n "$agent_id" ] || exit 0
text="ACTION REQUIRED: You have $count unread message(s). Run \`thrum inbox --unread\` now to read and respond to them. Then mark them read: \`thrum message read <id> [<id>...]\` for the ids shown, or \`thrum message read --all\` (dry run) followed by \`thrum message read --all --force\` to clear everything — so this hook doesn't fire again on old messages."
send_nudge() {
  local rc=0
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
