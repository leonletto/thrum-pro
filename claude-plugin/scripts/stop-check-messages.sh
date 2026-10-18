#!/bin/bash
# Stop hook: check for unread thrum messages before allowing the agent to stop.
# If a check needs attention, provide Stop-hook feedback directing the agent.
# If no unread messages, exit 0 to let Claude stop normally.
#
# Dependencies: jq 1.6+ (for now/fromdate), thrum CLI
# This is an instant check (no blocking wait) — runs in <1s per turn.

# Start the runtime's 15-second Stop budget before input or preflight.
SECONDS=0

# Read hook input JSON — we need stop_hook_active to prevent infinite loops
INPUT=$(cat)

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

# Claude Code 2.1.163+ displays Stop-hook additionalContext as feedback and
# continues the turn. Older or unrecognized versions need the legacy exit-2
# behavior so the message is not silently dropped.
claude_supports_stop_feedback() {
  local version major minor patch
  command -v claude >/dev/null 2>&1 || return 1
  version=$(claude --version 2>/dev/null) || return 1
  [[ "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)([[:space:]]|$) ]] || return 1
  major=$((10#${BASH_REMATCH[1]}))
  minor=$((10#${BASH_REMATCH[2]}))
  patch=$((10#${BASH_REMATCH[3]}))
  (( major > 2 || (major == 2 && minor > 1) || (major == 2 && minor == 1 && patch >= 163) ))
}

stop_with_feedback() {
  local message="$1" payload
  if claude_supports_stop_feedback && command -v jq >/dev/null 2>&1; then
    if payload=$(jq -cn --arg text "$message" '{hookSpecificOutput:{hookEventName:"Stop",additionalContext:$text}}' 2>/dev/null); then
      printf '%s\n' "$payload"
      exit 0
    fi
  fi
  printf '%s\n' "$message" >&2
  exit 2
}
# BEGIN resolve-thrum-dir
# Same rule as internal/paths.ResolveThrumDir (the CLI's resolver), so this hook
# reads the same config.json and listener PID as the CLI. A worktree holds
# .thrum/redirect (the absolute path of the main repo's .thrum) and no
# config.json, so checking only the local .thrum made the hook exit silently in
# every worktree. Single hop only. Every case the CLI rejects (missing or
# non-directory target, a chained target, empty, relative, or multi-line
# content) falls back to the local .thrum, which the hook treats as "no config":
# fail quiet. Prints the .thrum directory itself.
resolve_thrum_dir() {
  local local_dir="$1/.thrum" target
  if [ ! -f "$local_dir/redirect" ]; then
    printf '%s' "$local_dir"; return 0
  fi
  target=$(cat -- "$local_dir/redirect" 2>/dev/null) || target=""
  target=${target//$'\r'/}
  target="${target#"${target%%[![:space:]]*}"}"
  target="${target%"${target##*[![:space:]]}"}"
  case "$target" in /*) ;; *) printf '%s' "$local_dir"; return 0 ;; esac
  case "$target" in *$'\n'*) printf '%s' "$local_dir"; return 0 ;; esac
  if [ ! -d "$target" ]; then printf '%s' "$local_dir"; return 0; fi
  if [ "$(cd -P -- "$target" && pwd)" = "$(cd -P -- "$local_dir" && pwd)" ]; then
    printf '%s' "$local_dir"; return 0
  fi
  if [ -e "$target/redirect" ]; then printf '%s' "$local_dir"; return 0; fi
  printf '%s' "$target"
}
# END resolve-thrum-dir

THRUM_DIR_RESOLVED=$(resolve_thrum_dir "$PROJECT_DIR")

# Check if we're already in a stop-hook continuation cycle
STOP_HOOK_ACTIVE=$(echo "$INPUT" | grep -o '"stop_hook_active":\s*true' || true)
if [ -n "$STOP_HOOK_ACTIVE" ]; then
  AGENT_ID="${THRUM_AGENT_ID:-${THRUM_NAME:-}}"
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  bash "${SCRIPT_DIR}/stop-set-idle.sh" "$PROJECT_DIR" "$AGENT_ID" "$((15 - SECONDS - 1))"
  exit 0
fi

# Bail out if thrum isn't available or daemon isn't running
if ! command -v thrum &>/dev/null; then
  exit 0
fi
if ! thrum daemon status &>/dev/null; then
  exit 0
fi

THRUM_CONFIG="${THRUM_DIR_RESOLVED}/config.json"

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
    exit 0
  fi
fi

# Phase 1: Resolve agent identity — must happen before inbox check so the
# query is scoped to this agent only. A worktree agent's Claude process has no
# THRUM_AGENT_ID or THRUM_NAME in its env, so fall back to `thrum whoami` as the
# codex and cursor hooks do. Empty or failed whoami fails open.
AGENT_ID="${THRUM_AGENT_ID:-${THRUM_NAME:-}}"
WHOAMI_JSON=""
if [ -z "$AGENT_ID" ]; then
  WHOAMI_JSON=$(cd "$PROJECT_DIR" && thrum whoami --json 2>/dev/null || true)
  AGENT_ID=$(echo "$WHOAMI_JSON" | jq -r '.agent_id // empty' 2>/dev/null || true)
fi
if [ -z "$AGENT_ID" ]; then
  exit 0
fi

# Phase 2: Check unread messages scoped to this agent
INBOX_JSON=$(cd "$PROJECT_DIR" && THRUM_AGENT_ID="$AGENT_ID" thrum inbox --unread --json 2>/dev/null) || exit 0
MSG_COUNT=$(echo "$INBOX_JSON" | jq -r '.unread // 0' 2>/dev/null || true)
MSG_COUNT="${MSG_COUNT:-0}"
if [ "$MSG_COUNT" -gt 0 ]; then
  stop_with_feedback "ACTION REQUIRED: You have $MSG_COUNT unread message(s). Run \`thrum inbox --unread\` now to read and respond to them. Then mark them read: \`thrum message read <id> [<id>...]\` for the ids shown, or \`thrum message read --all\` (dry run) followed by \`thrum message read --all --force\` to clear everything — so this hook doesn't fire again on old messages."
fi

# Skip listener check for tmux-managed agents (daemon nudges directly).
# If tmux_session is set in the identity file, the agent was launched via tmux.
# The session may have died, but if so the agent wouldn't be running this hook
# either (it runs inside the tmux pane). So field presence is sufficient here.
# When the id came from whoami above, its JSON already carries tmux_session, so no
# second whoami runs (each one is a daemon round trip plus a client refresh).
if [ -n "$WHOAMI_JSON" ]; then
  TMUX_SESSION=$(echo "$WHOAMI_JSON" | jq -r '.tmux_session // empty' 2>/dev/null || true)
else
  TMUX_SESSION=$(cd "$PROJECT_DIR" && THRUM_AGENT_ID="$AGENT_ID" \
    thrum whoami --field tmux_session 2>/dev/null)
fi
if [ -n "$TMUX_SESSION" ]; then
	SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	bash "${SCRIPT_DIR}/stop-set-idle.sh" "$PROJECT_DIR" "$AGENT_ID" "$((15 - SECONDS - 1))"
  exit 0
fi

# Phase 3: Check if listener process is alive via PID file. `thrum listen` writes
# the PID into the resolved .thrum/var. This hook resolves from THRUM_HOME when it
# is set, else from the project dir: THRUM_HOME-first. The CLI's EffectiveRepoPath
# gives the cwd authority and uses THRUM_HOME only when no .thrum exists above the
# cwd. So the two agree for a redirected worktree; they differ only when a stale
# THRUM_HOME points at another project than the cwd (a named residual).
PID_VAR="$(resolve_thrum_dir "${THRUM_HOME:-$PROJECT_DIR}")/var"
PID_FILE="$PID_VAR/${AGENT_ID}-listener.pid"

if [ ! -f "$PID_FILE" ]; then
  stop_with_feedback "Your background message listener is not running. Start it now."
fi

# PID file exists but cannot be parsed without jq: skip validation (note above).
command -v jq >/dev/null 2>&1 || exit 0
LISTENER_PID=$(jq -r '.pid // empty' "$PID_FILE" 2>/dev/null || true)
if [ -z "$LISTENER_PID" ]; then
  stop_with_feedback "Your background message listener is not running (invalid PID file). Start it now."
fi

if ! kill -0 "$LISTENER_PID" 2>/dev/null; then
  rm -f "$PID_FILE"
  stop_with_feedback "Your background message listener has stopped (stale PID file). Restart it."
fi

# All stop gates passed: clear only a still-working status. Keep the RPC
# bounded because Stop hooks run synchronously in the agent's turn lifecycle.
# The client deadline bounds our wait; the daemon may already have accepted
# the write when that deadline expires.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPT_DIR}/stop-set-idle.sh" "$PROJECT_DIR" "$AGENT_ID" "$((15 - SECONDS - 1))"

# No unread messages and listener is healthy — let Claude proceed normally
exit 0
