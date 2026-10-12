#!/usr/bin/env bash
# Best-effort turn-end status clear. The daemon applies it only if the
# agent is still working; busy and changed-state results are quiet skips.
set -u
SECONDS=0

project_dir=${1:-.}
agent_id=${2:-}
remaining=${3:-15}
if ! command -v thrum >/dev/null 2>&1; then
  exit 0
fi

cd "$project_dir" >/dev/null 2>&1 || exit 0
# Use the same parent budget for identity resolution and the status write.
# Reserve a second for helper setup and scheduling as well as the parent's
# separate clock-granularity allowance.
bounded_cli() {
  local available term_timeout status_pid watchdog_pid cli_rc
  available=$((remaining - SECONDS - 1))
  ((available >= 2)) || return 1
  term_timeout=$((available - 3))
  ((term_timeout > 10)) && term_timeout=10
  ((term_timeout < 0)) && term_timeout=0
  "$@" 2>/dev/null &
  status_pid=$!

  # Watch the actual CLI PID, including identity refresh and client setup.
  # TERM allows a cooperative exit; KILL reaps a stuck CLI within the budget.
  (
    sleeper_pid=
    trap '[[ -z "$sleeper_pid" ]] || kill "$sleeper_pid" 2>/dev/null || true; exit 0' TERM INT
    sleep "$term_timeout" &
    sleeper_pid=$!
    wait "$sleeper_pid" || exit 0
    kill -TERM "$status_pid" 2>/dev/null || true
    sleep 2 &
    sleeper_pid=$!
    wait "$sleeper_pid" || exit 0
    kill -KILL "$status_pid" 2>/dev/null || true
  ) &
  watchdog_pid=$!
  cli_rc=0
  wait "$status_pid" 2>/dev/null || cli_rc=$?
  kill -TERM "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true
  return "$cli_rc"
}

if [[ -z "$agent_id" ]]; then
  command -v jq >/dev/null 2>&1 || exit 0
  identity_output=$(mktemp "${TMPDIR:-/tmp}/turnend-status.XXXXXX") || exit 0
  if ! bounded_cli thrum whoami --json >"$identity_output"; then
    rm -r "$identity_output"
    exit 0
  fi
  identity_json=$(cat "$identity_output")
  rm -r "$identity_output"
  agent_id=$(printf '%s\n' "$identity_json" | jq -r '.agent_id // empty' 2>/dev/null) || exit 0
  [[ -n "$agent_id" ]] || exit 0
fi
THRUM_AGENT_ID="$agent_id" THRUM_STATUS_WRITE_TIMEOUT=3s \
  bounded_cli thrum agent set-status idle --if-current working >/dev/null || true
exit 0
