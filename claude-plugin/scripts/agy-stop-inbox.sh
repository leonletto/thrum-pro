#!/usr/bin/env bash
# agy Stop adapter: runs the Claude unread-inbox check and maps its result to
# agy's Stop contract. agy continues a stopped turn when the hook answers
# {"decision":"continue","reason":...}; the reason is injected as a system
# message. Any other answer lets the stop proceed.
#
#   stdin  agy hook input (camelCase JSON, conversationId among its fields)
#   stdout {"decision":"continue","reason":"ACTION REQUIRED: ..."} when the
#          agent has unread messages and this stop is not a repeat; nothing
#          otherwise
#
# agy runs hooks with cwd set to the plugin directory. The adapter cds to
# stdin.workspacePaths[0] so the stop check resolves the agent's project.
#
#
# agy sends no stop_hook_active flag, so this adapter keeps a marker per
# conversation. The first stop with unread messages continues the turn and
# writes the marker. The next stop removes the marker and lets the stop
# proceed, so one continuation at most per turn end, as Claude's
# stop_hook_active guard gives.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# agy has no background listener: its preset sets no listener_spawn_template.
# Declare that to the stop check so it never asks for a listener, which on agy
# becomes a polling loop (`while true; do thrum wait ...`).
export THRUM_BACKGROUND_LISTENER=0

INPUT="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

WORKSPACE="$(printf '%s' "$INPUT" | jq -r '.workspacePaths[0] // empty' 2>/dev/null || true)"
if [ -n "$WORKSPACE" ] && [ -d "$WORKSPACE" ]; then
  cd "$WORKSPACE" || exit 0
  export CLAUDE_PROJECT_DIR="$WORKSPACE"
fi

KEY="$(printf '%s' "$INPUT" | jq -r '.conversationId // "default"' 2>/dev/null || true)"
[ -n "$KEY" ] || KEY="default"
KEY="${KEY//[^A-Za-z0-9_.-]/_}"
MARK="${TMPDIR:-/tmp}/thrum_agy_stop_${KEY}"

# Repeat stop in the same cycle: allow it and clear the marker.
if [ -e "$MARK" ]; then
  rm -f "$MARK"
  exit 0
fi

OUT="$(printf '%s' "$INPUT" | bash "${SCRIPT_DIR}/stop-check-messages.sh" 2>/dev/null || true)"
REASON="$(printf '%s' "$OUT" | jq -r '.reason // .hookSpecificOutput.additionalContext // empty' 2>/dev/null || true)"
[ -n "$REASON" ] || exit 0

: > "$MARK"
jq -cn --arg reason "$REASON" '{decision: "continue", reason: $reason}'
