#!/bin/bash
# Stop hook: check for unread thrum messages before allowing the agent to stop.
# ONE source for every runtime (claude-plugin/scripts is authoritative; the
# codex and cursor copies are generated from it). Only what a runtime's hook
# contract requires differs, and it is selected by STOP_RUNTIME below:
#   claude: project dir from CLAUDE_PROJECT_DIR; block = Stop feedback JSON on
#           stdout (Claude Code >= 2.1.163) else stderr + exit 2
#   codex:  project dir from the hook input's "cwd" (walked up to .thrum);
#           block = {"decision":"block","reason":...} on stdout, exit 0
#   cursor: project dir from CURSOR_PROJECT_DIR; block = stderr + exit 2
# A tmux-managed agent is never blocked on unread mail: one nudge is queued to
# its own pane (stop-nudge-pane.sh) and the stop proceeds.
#
# Dependencies: jq 1.6+, thrum CLI. Instant check, no blocking wait.

# Start the runtime's 15-second Stop budget before input or preflight.
SECONDS=0

# Generated copies rewrite the default on this line; THRUM_STOP_RUNTIME
# overrides it (tests).
STOP_RUNTIME="${THRUM_STOP_RUNTIME:-claude}"

# Read hook input JSON; stop_hook_active prevents infinite loops.
INPUT=$(cat)

thrum_project_root() {
  local d
  d=$(cd -- "$1" 2>/dev/null && pwd -P) || { printf '%s' "$1"; return 0; }
  while [ "$d" != "/" ]; do
    if [ -d "$d/.thrum" ]; then printf '%s' "$d"; return 0; fi
    d=$(dirname "$d")
  done
  if [ -d "/.thrum" ]; then printf '%s' "/"; return 0; fi
  printf '%s' "$1"
}

case "$STOP_RUNTIME" in
  codex)
    # Codex always supplies cwd on stdin; without jq it cannot be read.
    if ! command -v jq >/dev/null 2>&1; then
      echo "thrum stop-check-messages.sh: jq is required to check unread messages but was not found on PATH; unread-message check NOT active. Install jq (apt install jq / brew install jq)." >&2
      exit 0
    fi
    PROJECT_DIR=$(echo "$INPUT" | jq -r '.cwd // "."')
    PROJECT_DIR=$(thrum_project_root "$PROJECT_DIR")
    ;;
  cursor) PROJECT_DIR="${CURSOR_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}" ;;
  *) PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}" ;;
esac

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
# Block the stop with MESSAGE in this runtime's contract.
emit_block() {
  local message="$1" payload
  case "$STOP_RUNTIME" in
    codex)
      payload=$(jq -cn --arg reason "$message" '{decision:"block",reason:$reason}')
      printf '%s\n' "$payload"
      exit 0
      ;;
    cursor)
      printf '%s\n' "$message" >&2
      exit 2
      ;;
    *) stop_with_feedback "$message" ;;
  esac
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
    AGENT_ID="${THRUM_AGENT_ID:-${THRUM_NAME:-}}"
    write_idle
    exit 0
  fi
fi

# Phase 1: Resolve agent identity — must happen before inbox check so the
# query is scoped to this agent only (resolveLocalAgentID checks THRUM_AGENT_ID).
AGENT_ID="${THRUM_AGENT_ID:-${THRUM_NAME:-}}"
IDENTITY_FROM_WHOAMI=0
IDENTITY_TMUX_SESSION=""
if [ -z "$AGENT_ID" ]; then
  # Without jq there is no safe way to parse a resolved identity or unread
  # count. Keep Stop permissive, but do not write an unknown agent's status.
  command -v jq >/dev/null 2>&1 || exit 0
  PREFLIGHT_OUTPUT=$(mktemp "${TMPDIR:-/tmp}/thrum-stop.XXXXXX") || exit 0
  trap 'rm -f "$PREFLIGHT_OUTPUT"' EXIT
  bounded_preflight "$PROJECT_DIR" "$PREFLIGHT_OUTPUT" thrum whoami --json || exit 0
  AGENT_ID=$(jq -r '.agent_id // empty' "$PREFLIGHT_OUTPUT" 2>/dev/null) || exit 0
  [ -n "$AGENT_ID" ] || exit 0
  # The same JSON carries tmux_session, so the tmux check below reuses it instead
  # of a second whoami.
  IDENTITY_FROM_WHOAMI=1
  IDENTITY_TMUX_SESSION=$(jq -r '.tmux_session // empty' "$PREFLIGHT_OUTPUT" 2>/dev/null || true)
fi

# Phase 2: Check unread messages scoped to this agent
if command -v jq >/dev/null 2>&1; then
  if [ -z "${PREFLIGHT_OUTPUT:-}" ]; then
    PREFLIGHT_OUTPUT=$(mktemp "${TMPDIR:-/tmp}/thrum-stop.XXXXXX") || { write_idle; exit 0; }
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
    # A tmux-managed agent is never blocked from stopping: queue one nudge to
    # its own pane (the daemon waits for idle) and let the stop proceed.
    if [ "$IDENTITY_FROM_WHOAMI" = 1 ]; then
      TMUX_SESSION="$IDENTITY_TMUX_SESSION"
    else
      TMUX_SESSION=$(cd "$PROJECT_DIR" && THRUM_AGENT_ID="$AGENT_ID" \
        thrum whoami --field tmux_session 2>/dev/null || true)
    fi
    if [ -n "$TMUX_SESSION" ]; then
      bash "${SCRIPT_DIR}/stop-nudge-pane.sh" "$AGENT_ID" "$MSG_COUNT" "$PROJECT_DIR"
      write_idle
      exit 0
    fi
    emit_block "ACTION REQUIRED: You have $MSG_COUNT unread message(s). Run \`thrum inbox --unread\` now to read and respond to them. Then mark them read: \`thrum message read <id> [<id>...]\` for the ids shown, or \`thrum message read --all\` (dry run) followed by \`thrum message read --all --force\` to clear everything — so this hook doesn't fire again on old messages."
  fi
fi

# Skip listener check for tmux-managed agents (daemon nudges directly).
# If tmux_session is set in the identity file, the agent was launched via tmux.
# The session may have died, but if so the agent wouldn't be running this hook
# either (it runs inside the tmux pane). So field presence is sufficient here.
if [ "$IDENTITY_FROM_WHOAMI" = 1 ]; then
  TMUX_SESSION="$IDENTITY_TMUX_SESSION"
else
  if [ -z "${PREFLIGHT_OUTPUT:-}" ]; then
    PREFLIGHT_OUTPUT=$(mktemp "${TMPDIR:-/tmp}/thrum-stop.XXXXXX") || { write_idle; exit 0; }
    trap 'rm -f "$PREFLIGHT_OUTPUT"' EXIT
  fi
  if ! THRUM_AGENT_ID="$AGENT_ID" bounded_preflight "$PROJECT_DIR" "$PREFLIGHT_OUTPUT" thrum whoami --field tmux_session; then
    # Listener state is unknown after a failed identity lookup; allow Stop and
    # attempt only the conditional status write within the remaining budget.
    write_idle
    exit 0
  fi
  TMUX_SESSION=$(cat "$PREFLIGHT_OUTPUT")
fi
if [ -n "$TMUX_SESSION" ]; then
  write_idle
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
  emit_block "Your background message listener is not running. Start it now."
fi

# PID file exists but cannot be parsed without jq: allow Stop and clear status.
if ! command -v jq >/dev/null 2>&1; then
  write_idle
  exit 0
fi
LISTENER_PID=$(jq -r '.pid // empty' "$PID_FILE" 2>/dev/null || true)
if [ -z "$LISTENER_PID" ]; then
  emit_block "Your background message listener is not running (invalid PID file). Start it now."
fi

if ! kill -0 "$LISTENER_PID" 2>/dev/null; then
  rm -f "$PID_FILE"
  emit_block "Your background message listener has stopped (stale PID file). Restart it."
fi

# All stop gates passed: clear only a still-working status within the remaining
# Stop allowance. The helper treats daemon latency and failed writes as skips.
write_idle

# No unread messages and listener is healthy — let the agent proceed normally
exit 0
