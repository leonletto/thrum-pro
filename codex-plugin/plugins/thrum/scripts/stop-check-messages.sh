#!/bin/bash
# Stop hook: check for unread thrum messages before allowing the agent to stop.
# If unread messages exist, block the stop and direct the agent to check inbox.
# If no unread messages, exit 0 to let Codex stop normally.
#
# Block mechanism: JSON {"decision":"block","reason":"..."} on stdout.
# The reason field becomes the continuation prompt re-injected to the agent.
#
# Dependencies: jq 1.6+ (for now/fromdate), thrum CLI
# This is an instant check (no blocking wait) — runs in <1s per turn.

# -e intentionally omitted: external commands use || true / || exit 0 guards.
set -uo pipefail

# Start the runtime's 15-second Stop budget before input or preflight.
SECONDS=0

# Read hook input JSON — we need stop_hook_active to prevent infinite loops
INPUT=$(cat)

# Phase 0 (per spec §3.3.1 step 1): Parse cwd from stdin
# (codex always provides it in Stop hook input).
# Without jq the hook cannot read cwd or the inbox; the previous effective
# behaviour was a silent allow, so keep exit 0 and just say why.
if ! command -v jq >/dev/null 2>&1; then
  echo "thrum stop-check-messages.sh: jq is required to check unread messages but was not found on PATH; unread-message check NOT active. Install jq (apt install jq / brew install jq)." >&2
  exit 0
fi
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')
# Codex runs the hook in the session's cwd, which can be a subdirectory of the
# worktree. Walk up to the nearest directory holding a .thrum, as the CLI's repo
# lookup does, so a subdirectory session finds the same .thrum. With none above,
# keep the cwd: the hook then fails quiet, as before.
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
CWD=$(thrum_project_root "$CWD")
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

THRUM_DIR_RESOLVED=$(resolve_thrum_dir "$CWD")

# Check if we're already in a stop-hook continuation cycle
STOP_HOOK_ACTIVE=$(echo "$INPUT" | grep -o '"stop_hook_active":\s*true' || true)
if [ -n "$STOP_HOOK_ACTIVE" ]; then
  AGENT_ID="${THRUM_AGENT_ID:-${THRUM_NAME:-}}"
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  bash "${SCRIPT_DIR}/stop-set-idle.sh" "$CWD" "$AGENT_ID" "$((15 - SECONDS - 1))"
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

# Early exit: single-agent mode
if command -v jq >/dev/null 2>&1; then
  SAM=$(jq -r '.daemon.single_agent_mode // false' "$THRUM_CONFIG" 2>/dev/null)
  if [ "$SAM" = "true" ]; then
    exit 0
  fi
fi

# Phase 1: Resolve agent identity — must happen before inbox check so the
# query is scoped to this agent only.
#
# 4-step resolution algorithm (spec §3.3.1):
# Step 2: Honor explicit env override if user set it (back-compat with manual exports).
AGENT_ID="${THRUM_AGENT_ID:-${THRUM_NAME:-}}"
WHOAMI_JSON=""

# Step 3: If still unset, ask the daemon. `thrum whoami --json` walks the
# canonical identity-resolution chain (env → .thrum/identities/<name>.json by
# worktree-path match → daemon's session registry). Run from cwd so the daemon
# scopes its lookup correctly.
if [ -z "$AGENT_ID" ]; then
  WHOAMI_JSON=$(cd "$CWD" && thrum whoami --json 2>/dev/null || true)
  AGENT_ID=$(echo "$WHOAMI_JSON" | jq -r '.agent_id // empty' 2>/dev/null || true)
fi

# Step 4: Still unset → no agent registered for this cwd. Silent exit (never
# block on missing identity).
if [ -z "$AGENT_ID" ]; then
  exit 0
fi

# Phase 2: Check unread messages scoped to this agent
INBOX_JSON=$(cd "$CWD" && THRUM_AGENT_ID="$AGENT_ID" thrum inbox --unread --json 2>/dev/null) || exit 0
MSG_COUNT=$(echo "$INBOX_JSON" | jq -r '.unread // 0')
if [ "$MSG_COUNT" -gt 0 ]; then
  printf '{"decision":"block","reason":"ACTION REQUIRED: You have %s unread message(s). Run `thrum inbox --unread` now to read and respond to them. Then mark them read: `thrum message read <id> [<id>...]` for the ids shown, or `thrum message read --all` (dry run) followed by `thrum message read --all --force` to clear everything — so this hook does not fire again on old messages."}\n' "$MSG_COUNT"
  exit 0
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
  TMUX_SESSION=$(cd "$CWD" && THRUM_AGENT_ID="$AGENT_ID" \
    thrum whoami --field tmux_session 2>/dev/null)
fi
if [ -n "$TMUX_SESSION" ]; then
	SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	bash "${SCRIPT_DIR}/stop-set-idle.sh" "$CWD" "$AGENT_ID" "$((15 - SECONDS - 1))"
  exit 0
fi

# Phase 3: Check if listener process is alive via PID file. `thrum listen` writes
# the PID into the resolved .thrum/var. This hook resolves from THRUM_HOME when it
# is set, else from the project dir: THRUM_HOME-first. The CLI's EffectiveRepoPath
# gives the cwd authority and uses THRUM_HOME only when no .thrum exists above the
# cwd. So the two agree for a redirected worktree; they differ only when a stale
# THRUM_HOME points at another project than the cwd (a named residual).
PID_VAR="$(resolve_thrum_dir "${THRUM_HOME:-$CWD}")/var"
PID_FILE="$PID_VAR/${AGENT_ID}-listener.pid"

if [ ! -f "$PID_FILE" ]; then
  printf '{"decision":"block","reason":"Your background message listener is not running. Start it now."}\n'
  exit 0
fi

LISTENER_PID=$(jq -r '.pid // empty' "$PID_FILE" 2>/dev/null)
if [ -z "$LISTENER_PID" ]; then
  printf '{"decision":"block","reason":"Your background message listener is not running (invalid PID file). Start it now."}\n'
  exit 0
fi

if ! kill -0 "$LISTENER_PID" 2>/dev/null; then
  rm -f "$PID_FILE"
  printf '{"decision":"block","reason":"Your background message listener has stopped (stale PID file). Restart it."}\n'
  exit 0
fi

# All stop gates passed: clear only a still-working status. Keep the RPC
# bounded because Stop hooks run synchronously in the agent's turn lifecycle.
# The client deadline bounds our wait; the daemon may already have accepted
# the write when that deadline expires.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPT_DIR}/stop-set-idle.sh" "$CWD" "$AGENT_ID" "$((15 - SECONDS - 1))"

# No unread messages and listener is healthy — let Codex proceed normally
exit 0
