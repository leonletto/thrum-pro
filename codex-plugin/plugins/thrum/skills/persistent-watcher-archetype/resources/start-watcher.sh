#!/usr/bin/env bash
# start-watcher.sh - the one supported way to start a watcher or steward.
#
# A coordinator runs this once per watcher/steward. It checks everything
# first and creates nothing when any check fails, then uses existing thrum
# commands in a fixed order: worktree create, write watch_params.json,
# tmux create, tmux launch, monitor start. The agent's first act is /loop, by
# which time its params file already exists.
#
# Usage:
#   start-watcher.sh <name> --role watcher|steward --parent <agent|user:NAME> \
#     --roster <a,b,...|@file> --model <model> --effort <effort> \
#     [--cadence-active 5m] [--cadence-idle 10m] [--runtime <runtime>] \
#     [--owner <user>] [--restart-ctx-pct 50]
#
#   --roster   comma-separated agent names, or @file holding one name per
#              line or a JSON array. An array entry may be a name or an
#              object {"agent_id","hostname","tmux_session"} for an agent on
#              another machine.
#   --cadence  durations such as 90s, 5m, 2h. Anything under one minute is
#              refused (the monitor schedule has a one-minute floor).
#   --owner    the human who receives escalations, as a thrum user name.
#              Without it the owner is the first @user: entry of
#              permission_supervisors in .thrum/config.json. No owner is a
#              refusal. Whether the owner has linked Telegram or email is not
#              consulted: the owner is sent a normal message to their inbox,
#              and the existing bridges forward it if they are linked.
#
# Environment (for tests): THRUM_BIN (default thrum), THRUM_DIR (the
# redirect-resolved .thrum directory).
#
# Exit status: 0 started and verified; 2 refused before creating anything;
# 1 a step failed after creation began (what exists is printed; nothing is
# cleaned up automatically).
set -uo pipefail

THRUM="${THRUM_BIN:-thrum}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
TEMPLATE="${SCRIPT_DIR}/watch_params.template.json"
MATCH_REGEX='^watch-tick: (cycle done|RESOLUTION-FAIL)'

die() {
  printf 'start-watcher: %s\n' "$1" >&2
  exit "${2:-2}"
}

NAME=""
ROLE=""
PARENT=""
ROSTER_ARG=""
CAD_ACTIVE="5m"
CAD_IDLE="10m"
RUNTIME=""
MODEL=""
EFFORT=""
OWNER_ARG=""
RESTART_PCT=50

while [ "$#" -gt 0 ]; do
  case "$1" in
    --role) ROLE="${2-}"; shift 2 ;;
    --parent) PARENT="${2-}"; shift 2 ;;
    --roster) ROSTER_ARG="${2-}"; shift 2 ;;
    --cadence-active) CAD_ACTIVE="${2-}"; shift 2 ;;
    --cadence-idle) CAD_IDLE="${2-}"; shift 2 ;;
    --runtime) RUNTIME="${2-}"; shift 2 ;;
    --model) MODEL="${2-}"; shift 2 ;;
    --effort) EFFORT="${2-}"; shift 2 ;;
    --owner) OWNER_ARG="${2-}"; shift 2 ;;
    --restart-ctx-pct) RESTART_PCT="${2-}"; shift 2 ;;
    -h | --help) sed -n '2,32p' "${BASH_SOURCE[0]}"; exit 0 ;;
    -*) die "unknown flag: $1" ;;
    *)
      [ -z "${NAME}" ] || die "unexpected argument: $1"
      NAME="$1"
      shift
      ;;
  esac
done

command -v jq >/dev/null 2>&1 || die "jq is required"
[ -f "${TEMPLATE}" ] || die "missing ${TEMPLATE}"

# --- validate everything before touching anything --------------------------
printf '%s' "${NAME}" | grep -Eq '^[A-Za-z][A-Za-z0-9_]*$' || die "name must be letters, digits and underscores, starting with a letter"
case "${ROLE}" in watcher | steward) ;; *) die "--role must be watcher or steward" ;; esac
[ -n "${PARENT}" ] || die "--parent is required"
[ -n "${MODEL}" ] || die "--model is required (every launch pins a model)"
[ -n "${EFFORT}" ] || die "--effort is required (every launch pins an effort)"
printf '%s' "${RESTART_PCT}" | grep -Eq '^[0-9]+$' || die "--restart-ctx-pct must be an integer"

# cadence_secs <duration>: print seconds, or return 1.
cadence_secs() {
  local n unit
  printf '%s' "$1" | grep -Eq '^[0-9]+[smh]$' || return 1
  n="${1%[smh]}"
  unit="${1#"${n}"}"
  case "${unit}" in
    s) printf '%s' "${n}" ;;
    m) printf '%s' "$((n * 60))" ;;
    h) printf '%s' "$((n * 3600))" ;;
  esac
}
ACTIVE_SECS="$(cadence_secs "${CAD_ACTIVE}")" || die "--cadence-active '${CAD_ACTIVE}' is not a duration like 5m"
IDLE_SECS="$(cadence_secs "${CAD_IDLE}")" || die "--cadence-idle '${CAD_IDLE}' is not a duration like 10m"
[ "${ACTIVE_SECS}" -ge 60 ] || die "--cadence-active '${CAD_ACTIVE}' is below one minute"
[ "${IDLE_SECS}" -ge 60 ] || die "--cadence-idle '${CAD_IDLE}' is below one minute"

# cron_for <seconds>: the 5-field schedule for the idle cadence.
cron_for() {
  local mins
  mins=$(($1 / 60))
  if [ "${mins}" -lt 60 ]; then
    printf '*/%s * * * *' "${mins}"
  elif [ $((mins % 60)) -eq 0 ] && [ $((mins / 60)) -le 23 ]; then
    printf '0 */%s * * *' "$((mins / 60))"
  else
    return 1
  fi
}
CRON="$(cron_for "${IDLE_SECS}")" || die "--cadence-idle '${CAD_IDLE}' must be under an hour or a whole number of hours up to 23"

# Roster: names or objects, never empty.
[ -n "${ROSTER_ARG}" ] || die "--roster is required and must not be empty"
case "${ROSTER_ARG}" in
  @*)
    [ -f "${ROSTER_ARG#@}" ] || die "roster file ${ROSTER_ARG#@} not found"
    RAW_ROSTER="$(cat "${ROSTER_ARG#@}")"
    ;;
  *) RAW_ROSTER="${ROSTER_ARG}" ;;
esac
if printf '%s' "${RAW_ROSTER}" | grep -Eq '^[[:space:]]*\['; then
  ROSTER_JSON="$(printf '%s' "${RAW_ROSTER}" | jq -c '.' 2>/dev/null)" || die "roster is not valid JSON"
else
  ROSTER_JSON="$(printf '%s\n' "${RAW_ROSTER}" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | { grep -v '^$' || true; } | jq -R . | jq -cs '.')" || die "roster could not be parsed"
fi
[ "$(printf '%s' "${ROSTER_JSON}" | jq 'length')" -gt 0 ] || die "roster is empty; a watcher with no roster has nothing to watch"
printf '%s' "${ROSTER_JSON}" | jq -e 'all(.[]; (type == "string" and length > 0) or (type == "object" and (.agent_id // "") != "" and (.hostname // "") != "" and (.tmux_session // "") != ""))' >/dev/null ||
  die "every roster entry must be an agent name or an object with agent_id, hostname and tmux_session"

# The team: the name must be free, the parent and every local member known.
TEAM_JSON="$("${THRUM}" team --json 2>/dev/null)" || die "could not read the team (thrum team --json failed)"
member_exists() {
  printf '%s' "${TEAM_JSON}" | jq -e --arg a "$1" '[.team.members[]?.agent_id] | index($a) != null' >/dev/null
}
member_exists "${NAME}" && die "${NAME} is already registered"
case "${PARENT}" in
  user:*) ;;
  *) member_exists "${PARENT}" || die "--parent ${PARENT} does not resolve in thrum team" ;;
esac
while IFS= read -r m; do
  [ -z "${m}" ] || member_exists "${m}" || die "roster member ${m} does not resolve in thrum team"
done <<<"$(printf '%s' "${ROSTER_JSON}" | jq -r '.[] | select(type == "string")')"
ROSTER_NAMES="$(printf '%s' "${ROSTER_JSON}" | jq -r '.[] | if type == "object" then .agent_id else . end')"

# --- owner -----------------------------------------------------------------
if [ -n "${THRUM_DIR:-}" ]; then
  T="${THRUM_DIR}"
else
  TOP="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository (set THRUM_DIR)"
  T="$(cat "${TOP}/.thrum/redirect" 2>/dev/null)"
  [ -n "${T}" ] || T="${TOP}/.thrum"
fi
[ -d "${T}" ] || die "no .thrum directory at ${T}"

norm_user() { printf '%s' "$1" | sed 's/^@//; s/^user://'; }

if [ -n "${OWNER_ARG}" ]; then
  OWNER="$(norm_user "${OWNER_ARG}")"
else
  OWNER="$(norm_user "$(jq -r '.permission_supervisors[]? | select(startswith("@user:"))' "${T}/config.json" 2>/dev/null | head -1)")"
fi
[ -n "${OWNER}" ] || die "no owner: pass --owner or set a @user: entry in permission_supervisors"

# --- start, in order -------------------------------------------------------
AGENT_DIR="${T}/agents/${NAME}"
PARAMS="${AGENT_DIR}/watch_params.json"

WT_JSON="$("${THRUM}" worktree create "${NAME}" --json)" || die "worktree create failed; nothing else was started" 1
WT_PATH="$(printf '%s' "${WT_JSON}" | jq -r '.worktree_path // empty')"
[ -n "${WT_PATH}" ] || die "worktree create printed no worktree_path; nothing else was started" 1

EXPECTED="$(jq --arg n "${NAME}" --arg p "${PARENT}" --arg m "${MODEL}" --argjson r "${ROSTER_JSON}" \
  --arg ca "${CAD_ACTIVE}" --arg ci "${CAD_IDLE}" --argjson pct "${RESTART_PCT}" \
  '.watcher = $n | .parent = $p | .model = $m | .roster = $r | .cadence_active = $ca | .cadence_idle = $ci | .restart_ctx_pct = $pct' "${TEMPLATE}")" ||
  die "could not fill the params template; worktree ${WT_PATH} exists" 1
mkdir -p "${AGENT_DIR}" || die "could not create ${AGENT_DIR}; worktree ${WT_PATH} exists" 1
if ! { printf '%s\n' "${EXPECTED}" >"${PARAMS}.tmp" && mv "${PARAMS}.tmp" "${PARAMS}"; }; then
  die "could not write ${PARAMS}; worktree ${WT_PATH} exists" 1
fi
[ "$(jq -S . "${PARAMS}")" = "$(printf '%s' "${EXPECTED}" | jq -S .)" ] || die "${PARAMS} did not re-read equal; worktree ${WT_PATH} exists" 1

RT_ARGS=()
[ -z "${RUNTIME}" ] || RT_ARGS=(--runtime "${RUNTIME}")
"${THRUM}" tmux create "${NAME}" --name "${NAME}" --role "${ROLE}" --cwd "${WT_PATH}" --model "${MODEL}" --effort "${EFFORT}" ${RT_ARGS[@]+"${RT_ARGS[@]}"} ||
  die "tmux create failed; worktree ${WT_PATH} and ${PARAMS} exist" 1
"${THRUM}" tmux launch "${NAME}" --model "${MODEL}" --effort "${EFFORT}" ${RT_ARGS[@]+"${RT_ARGS[@]}"} ||
  die "tmux launch failed; the session exists but the agent did not start" 1

for f in thrum-watch-pane-capture.sh thrum-capture-fallback.sh; do
  if ! { cp "${SCRIPT_DIR}/${f}" "${AGENT_DIR}/${f}" && chmod +x "${AGENT_DIR}/${f}"; }; then
    die "could not copy ${f} into ${AGENT_DIR}" 1
  fi
done
"${THRUM}" monitor start --name "${NAME}-pane-watch" --match "${MATCH_REGEX}" --to "@${NAME}" --notify-on-success \
  --schedule "${CRON}" -- "${AGENT_DIR}/thrum-watch-pane-capture.sh" ||
  die "monitor start failed; the agent is running without its pane-watch monitor" 1

if [ "${ROLE}" = "steward" ]; then
  while IFS= read -r m; do
    [ -n "${m}" ] || continue
    "${THRUM}" send --to "@${m}" --stdin <<EOF || printf 'start-watcher: warning: could not brief %s\n' "${m}" >&2
steward: @${NAME}
Send questions that need the owner to @${NAME} as "NEED [topic]: <what you need decided and why>". The steward routes them to the owner and replies with the owner's answer. See the brainstorm-queue-aware skill for the convention.
EOF
  done <<<"${ROSTER_NAMES}"
fi

# --- verify by effect ------------------------------------------------------
"${THRUM}" monitor list --json 2>/dev/null | jq -e --arg n "${NAME}-pane-watch" 'any(.[]?; .name == $n)' >/dev/null ||
  die "monitor ${NAME}-pane-watch is not listed after start" 1

printf 'started %s (%s)\n' "${NAME}" "${ROLE}"
printf '  roster:  %s\n' "$(printf '%s' "${ROSTER_NAMES}" | tr '\n' ' ')"
printf '  parent:  %s\n' "${PARENT}"
printf '  cadence: active %s, idle %s (schedule %s)\n' "${CAD_ACTIVE}" "${CAD_IDLE}" "${CRON}"
printf '  params:  %s\n' "${PARAMS}"
printf '  owner:   @user:%s\n' "${OWNER}"
exit 0
