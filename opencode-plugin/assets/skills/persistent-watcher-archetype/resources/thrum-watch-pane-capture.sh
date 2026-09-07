#!/usr/bin/env bash
#
# thrum-watch-pane-capture.sh
#
# The generic, roster-driven pane-watch capture-loop script that ships with
# the persistent-watcher-archetype plugin skill (thrum-3mhrt). Works for
# BOTH a persistent-watcher-archetype watcher and the brainstorm-steward
# (one parameterized script serves both — the only differences, roster
# contents and cadence, are already `watch_params.json` fields, not script
# forks).
#
# WHAT THIS SCRIPT DOES (single, non-resident pass, driven by `thrum
# monitor`'s own schedule — never a loop; the next wake is the monitor's
# job, not this script's):
#   Read roster from watch_params.json -> resolve each roster member's
#   cross-daemon SSH-fallback target ONCE per run (thrum state
#   agent_pool/topology; fail CLOSED on any gap, never guess a path) ->
#   capture each member's pane (local `thrum tmux capture` first, ALWAYS —
#   `thrum tmux capture <agent>` already reaches remote agents by name via
#   the normal rpcrouter proxy; the SSH hop below is a resilience FALLBACK
#   for when that path is broken on the caller's side, e.g. thrum-7vwgy/
#   thrum-zkqut-class bugs, never a fleet-wide-watching enabler in its own
#   right, and never SSH-first) -> run each capture through `thrum detect
#   --category permission` -> for a STABLE (unchanged across two captures,
#   two seconds apart) detected permission prompt, flag it in the report ->
#   write ONE report file with a section per agent (pane tail + status) ->
#   emit ONE matchable summary line on stdout for `thrum monitor` to catch
#   and deliver as a wake message.
#
# DELIBERATE SCOPE LIMIT: this script is MECHANICAL ONLY — capture, detect,
# emit. It never auto-escalates and never auto-approves/denies a modal
# (never sends keys or text — never calls `thrum tmux send`). The persistent-watcher-
# archetype skill is explicit that judgment (approve/cancel/escalate/nudge)
# happens in the watcher's OWN turn when it reads the wake message this
# script's summary line triggers, not in a script. A bash script cannot
# safely reproduce that judgment.
#
# SETUP (per watcher/steward instance — see the skill's SKILL.md for the
# full recipe): copy BOTH this script and thrum-capture-fallback.sh from
# the skill's resources/ into your own `.thrum/agents/<you>/`, then
# register `thrum monitor start` against that absolute copy path.
# `CLAUDE_PLUGIN_ROOT` is a Claude-Code-hook-only env var, NOT present in
# `thrum monitor`'s scheduled-process environment, so the script cannot
# locate itself inside the plugin tree at run time — it must be copied
# next to the watch_params.json it reads.
#
# This script relies on that copy location to find its own paths: it lives
# at `<repo>/.thrum/agents/<name>/thrum-watch-pane-capture.sh`, so its own
# directory IS `.thrum/agents/<name>` and `<name>` (its own dirname's
# basename) IS the watcher/steward's agent name — used to namespace log/
# report/lock files so multiple watchers in one repo never collide.
#
# USAGE:
#   thrum-watch-pane-capture.sh
#
# THRUM MONITOR EXAMPLE (see SKILL.md for the full, current recipe —
# --notify-on-success is MANDATORY: a --schedule'd job delivers NOTHING on
# --match alone, thrum-ruz1z/S5c):
#   thrum monitor start --name <you>-pane-watch \
#     --match "^watch-tick: (cycle done|RESOLUTION-FAIL)" \
#     --to @<you> \
#     --notify-on-success \
#     --schedule '*/15 * * * *' \
#     -- /path/to/.thrum/agents/<you>/thrum-watch-pane-capture.sh
#
set -uo pipefail

# --- locate paths ------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
AGENT_NAME="$(basename -- "${SCRIPT_DIR}")"
# SCRIPT_DIR is <repo>/.thrum/agents/<AGENT_NAME> per the setup recipe above
# -- never hardcode REPO_ROOT (the prior box-specific adaptation this
# script generalizes did, and that was exactly the thing to fix).
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." >/dev/null 2>&1 && pwd)"
PARAMS_FILE="${SCRIPT_DIR}/watch_params.json"
FALLBACK_SCRIPT="${SCRIPT_DIR}/thrum-capture-fallback.sh"

LOG_DIR="${REPO_ROOT}/.thrum/var/log"
LOCK_DIR="${REPO_ROOT}/.thrum/var/${AGENT_NAME}-pane-watch.lockdir"
LOG_FILE="${LOG_DIR}/${AGENT_NAME}-pane-watch.log"
REPORT_FILE="${LOG_DIR}/${AGENT_NAME}-pane-watch-report.txt"

mkdir -p "${LOG_DIR}"

# --- logging -------------------------------------------------------------
# ALWAYS write a line, even on a no-op run: a silent run is
# indistinguishable from a run that never happened.
log() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >>"${LOG_FILE}"
}

# --- single-instance lock -------------------------------------------------
# macOS ships no `flock`(1) by default, so use `mkdir` as the atomic lock
# primitive instead (mkdir on an existing dir fails atomically on every
# POSIX filesystem -- same guarantee flock gives, no dependency, and
# `thrum monitor` resolves `#!/usr/bin/env bash` to macOS system /bin/bash
# 3.2 which also lacks flock's usual companion, `exec N>file`+flock -n N
# patterns some other watchers use).
# Stale-lock guard: if the lock dir is older than 10 min, a prior run
# almost certainly crashed without cleaning up -- reclaim it rather than
# wedging every future cycle forever.
if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  if [ -d "${LOCK_DIR}" ]; then
    LOCK_AGE=$(( $(date +%s) - $(stat -f %m "${LOCK_DIR}" 2>/dev/null || echo 0) ))
    if [ "${LOCK_AGE}" -gt 600 ]; then
      log "WARN: stale lock dir (${LOCK_AGE}s old) -- reclaiming"
      rm -r -- "${LOCK_DIR}"
      mkdir "${LOCK_DIR}" || { log "SKIP: could not reclaim stale lock, exiting"; exit 0; }
    else
      log "SKIP: another instance holds the lock (${LOCK_AGE}s old), exiting"
      exit 0
    fi
  else
    log "SKIP: mkdir lock failed for an unexpected reason, exiting"
    exit 0
  fi
fi

log "START"

# --- scratch dir for pane captures ----------------------------------------
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/${AGENT_NAME}-pane-watch.XXXXXX")"
# Single combined trap: both the lock dir AND the scratch dir must be
# cleaned up on exit, regardless of which path (success/error/SKIP) got
# here -- a second `trap ... EXIT` would silently REPLACE this one, not
# add to it, so both cleanups live in the same trap.
trap 'rm -r -- "${LOCK_DIR}" "${WORKDIR}"' EXIT

# --- load roster from watch_params.json -----------------------------------
if [ ! -f "${PARAMS_FILE}" ]; then
  log "ERROR: watch_params.json not found at ${PARAMS_FILE}, exiting"
  exit 1
fi

# `mapfile`/`readarray` are bash-4+ only; `thrum monitor`'s scheduled-run
# process resolves `bash` to macOS's system /bin/bash (3.2), not whatever
# Homebrew bash an interactive shell's PATH might pick up -- so array
# population must stick to bash-3.2-portable constructs throughout this
# script (no mapfile/readarray, no `local -n`, no bash-4 associative
# arrays -- parallel indexed arrays instead). Test with `/bin/bash
# thrum-watch-pane-capture.sh`, not just `bash ...` or `./...`, or this
# class of bug only surfaces on the live scheduled run (thrum-dnatz).
ROSTER=()
while IFS= read -r line; do
  [ -n "${line}" ] && ROSTER+=("${line}")
done < <(jq -r '.roster[]?' "${PARAMS_FILE}")

if [ "${#ROSTER[@]}" -eq 0 ]; then
  log "NOOP: roster is empty in watch_params.json"
  exit 0
fi
log "roster: ${ROSTER[*]}"

# NOTE: this script does NOT define its own is_proxy_failure() -- the
# local-vs-SSH decision happens ENTIRELY inside thrum-capture-fallback.sh
# (see capture_agent below, which always routes through that wrapper), so
# duplicating the signature here would be genuinely dead code, not a
# sync-source. If that division of responsibility ever changes, add the
# check back here too and see the "MUST STAY IN SYNC" note in
# thrum-capture-fallback.sh's own is_proxy_failure().

# --- per-agent SSH-fallback target resolution -----------------------------
# Resolved ONCE per roster agent, for the whole run (never guess a path;
# fail CLOSED on any gap -- an agent with an unresolved target simply gets
# no SSH fallback, it is NOT skipped from capture entirely: local capture
# is always attempted regardless of resolution outcome).
#
#   thrum state get agent_pool:<agent>   -> .entry.value.box (a hostname)
#   thrum state list --kind topology     -> enumerate topology SCOPES only
#   thrum state show topology:<scope>    -> per-scope .entry.value, matched
#                                            by .value.hostname == the box
#                                            hostname above
#
# NOTE ON THE TWO-STEP TOPOLOGY LOOKUP: `thrum state list --kind topology
# --json`'s CLI output does NOT include each entry's `.value` (verified
# against cmd/thrum/state.go's stateListEntry struct, which has no Value
# field, and confirmed live -- `state list --json` returns only
# kind/scope/method/as_of/established_by). Only `state get`/`state show`
# emit the full entry including `.value`. So topology resolution is
# necessarily two calls: `list` to enumerate scopes, `show` per scope for
# the value -- a single-call `.value.hostname` scan is not achievable
# against the current CLI, regardless of how the field/scope names read.
is_placeholder() {
  case "$1" in
    ""|PENDING-LEON|PENDING|TODO|TBD) return 0 ;;
    *) return 1 ;;
  esac
}

TOPO_HOSTNAME=()
TOPO_SSH_TARGET=()
TOPO_SSH_USER=()
TOPO_REPO_PATH=()

build_topology_table() {
  local scopes_json scope show_json hostname ssh_target ssh_user repo_path
  if ! scopes_json="$(thrum state list --kind topology --json 2>>"${LOG_FILE}")"; then
    log "WARN: thrum state list --kind topology failed -- ALL per-agent ssh-fallback resolution will fail closed this run"
    return 0
  fi
  while IFS= read -r scope; do
    [ -n "${scope}" ] || continue
    if ! show_json="$(thrum state show "topology:${scope}" --json 2>>"${LOG_FILE}")"; then
      log "WARN: thrum state show topology:${scope} failed, skipping this topology row"
      continue
    fi
    hostname="$(printf '%s' "${show_json}" | jq -r '.entry.value.hostname // empty')"
    [ -n "${hostname}" ] || continue
    ssh_target="$(printf '%s' "${show_json}" | jq -r '.entry.value.ssh.target // empty')"
    ssh_user="$(printf '%s' "${show_json}" | jq -r '.entry.value.ssh.user // empty')"
    repo_path="$(printf '%s' "${show_json}" | jq -r '.entry.value.repo_path // empty')"
    TOPO_HOSTNAME+=("${hostname}")
    TOPO_SSH_TARGET+=("${ssh_target}")
    TOPO_SSH_USER+=("${ssh_user}")
    TOPO_REPO_PATH+=("${repo_path}")
  done < <(printf '%s' "${scopes_json}" | jq -r '.entries[]?.scope')
}

# Parallel arrays, indexed 1:1 with ROSTER -- bash 3.2 has no associative
# arrays, so "agent -> resolved target" is a lookup-by-matching-ROSTER-
# index, not a map.
RESOLVED_SSH_TARGET=()
RESOLVED_SSH_USER=()
RESOLVED_SSH_REPO=()
RESOLVED_COUNT=0

resolve_roster_targets() {
  local agent pool_json box i matched row_found
  for agent in "${ROSTER[@]}"; do
    matched=0
    row_found=0
    if pool_json="$(thrum state get "agent_pool:${agent}" --json 2>>"${LOG_FILE}")"; then
      box="$(printf '%s' "${pool_json}" | jq -r '.entry.value.box // empty')"
      if [ -n "${box}" ]; then
        for i in "${!TOPO_HOSTNAME[@]}"; do
          if [ "${TOPO_HOSTNAME[$i]}" = "${box}" ]; then
            row_found=1
            if is_placeholder "${TOPO_REPO_PATH[$i]}" || is_placeholder "${TOPO_SSH_TARGET[$i]}"; then
              log "agent=${agent} WARN topology row for host=${box} has a placeholder/missing ssh.target or repo_path -- fail-closed, no ssh fallback for this agent"
            else
              RESOLVED_SSH_TARGET+=("${TOPO_SSH_TARGET[$i]}")
              RESOLVED_SSH_USER+=("${TOPO_SSH_USER[$i]}")
              RESOLVED_SSH_REPO+=("${TOPO_REPO_PATH[$i]}")
              RESOLVED_COUNT=$((RESOLVED_COUNT + 1))
              matched=1
            fi
            break
          fi
        done
        if [ "${row_found}" -eq 0 ]; then
          log "agent=${agent} WARN no topology row matches host=${box} -- fail-closed, no ssh fallback for this agent"
        fi
      else
        log "agent=${agent} WARN agent_pool entry has no .value.box -- fail-closed, no ssh fallback for this agent"
      fi
    else
      log "agent=${agent} WARN thrum state get agent_pool:${agent} failed -- fail-closed, no ssh fallback for this agent"
    fi
    if [ "${matched}" -eq 0 ]; then
      RESOLVED_SSH_TARGET+=("NONE")
      RESOLVED_SSH_USER+=("")
      RESOLVED_SSH_REPO+=("")
    fi
  done
}

build_topology_table
resolve_roster_targets

# Fork default (coordinator-resolved, thrum-3mhrt plan): if EVERY roster
# agent failed resolution, that is itself worth surfacing as a real
# problem (likely a fleet-wide topology/agent_pool data gap), not a clean
# tick -- flip the summary line's marker so `--match` treats it as a
# monitor-level FAIL rather than routine per-agent degradation. This is
# ORTHOGONAL to whether local capture actually needs the fallback this
# run -- it fires on a total resolution outage regardless.
RESOLUTION_ALL_FAILED=0
if [ "${RESOLVED_COUNT}" -eq 0 ]; then
  RESOLUTION_ALL_FAILED=1
  log "WARN: ALL ${#ROSTER[@]} roster agent(s) failed ssh-fallback target resolution this run"
fi

# --- capture helper: local first, ALWAYS; SSH fallback only inside the ---
# --- wrapper, only on the known proxy-failure signature -------------------
# Always routes through thrum-capture-fallback.sh (never calls `thrum tmux
# capture` directly itself) so the local/SSH/ssh-add retry logic lives in
# exactly one place. "Local or cross-daemon" is decided EMPIRICALLY by the
# wrapper's own local attempt succeeding/failing -- never by an up-front
# hostname-equality heuristic here.
capture_agent() {
  local agent="$1" out_file="$2" idx="$3"
  bash "${FALLBACK_SCRIPT}" capture "${agent}" \
    "${RESOLVED_SSH_TARGET[$idx]}" "${RESOLVED_SSH_USER[$idx]}" "${RESOLVED_SSH_REPO[$idx]}" \
    >"${out_file}" 2>&1
}

FLAGGED=0
{
  echo "# ${AGENT_NAME} pane-watch report"
  echo "# generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# roster: ${ROSTER[*]}"
  echo "# ssh-fallback resolved: ${RESOLVED_COUNT}/${#ROSTER[@]} roster agent(s)"
  echo
} >"${REPORT_FILE}"

ROSTER_IDX=0
for agent in "${ROSTER[@]}"; do
  CAP1="${WORKDIR}/${agent}.cap1"
  CAP2="${WORKDIR}/${agent}.cap2"

  if ! capture_agent "${agent}" "${CAP1}" "${ROSTER_IDX}"; then
    log "agent=${agent} WARN capture failed (exit code), recording report entry anyway"
  fi

  if [ ! -s "${CAP1}" ]; then
    log "agent=${agent} WARN empty capture, skipping detect"
    {
      echo "===== @${agent} ====="
      echo "status: CAPTURE FAILED (empty output -- check local + ssh-fallback paths; ssh-fallback target: ${RESOLVED_SSH_TARGET[$ROSTER_IDX]})"
      echo
    } >>"${REPORT_FILE}"
    ROSTER_IDX=$((ROSTER_IDX + 1))
    continue
  fi

  STATUS="clean"
  MATCH_NAME=""

  # thrum detect exit-code contract (cmd/thrum/detect.go):
  #   exit 0 + matched entry name on stdout  -> match
  #   exit 1, silent                         -> no match
  # `if VAR=$(...); then` is exempt from `set -e` semantics for this
  # purpose (we run under set -u only, not -e), so a "no match" does not
  # abort the loop -- this IS the intended branch.
  if MATCH_NAME=$(thrum detect --category permission --pane-file "${CAP1}" --runtime claude 2>>"${LOG_FILE}"); then
    # Stability check: a pane holding unsubmitted text or a live human/
    # agent mid-composition is not idle. Require the pane to be unchanged
    # across two captures, two seconds apart, before flagging.
    sleep 2
    if capture_agent "${agent}" "${CAP2}" "${ROSTER_IDX}" && [ -s "${CAP2}" ]; then
      if diff -q "${CAP1}" "${CAP2}" >/dev/null; then
        FLAGGED=$((FLAGGED + 1))
        STATUS="FLAGGED: stable permission prompt (pattern=${MATCH_NAME})"
        log "agent=${agent} pattern=${MATCH_NAME} STABLE permission prompt detected"
      else
        STATUS="pattern=${MATCH_NAME} detected but UNSTABLE across two captures -- pane is live, not flagging"
        log "agent=${agent} pattern=${MATCH_NAME} UNSTABLE across two captures -- leaving alone"
      fi
    else
      STATUS="pattern=${MATCH_NAME} detected, re-capture failed -- not flagging without stability confirmation"
      log "agent=${agent} WARN re-capture failed during stability check, not flagging"
    fi
  else
    log "agent=${agent} no permission prompt detected"
  fi

  {
    echo "===== @${agent} ====="
    echo "status: ${STATUS}"
    echo "--- pane tail (last 40 lines) ---"
    tail -n 40 "${CAP1}"
    echo "--- end pane ---"
    echo
  } >>"${REPORT_FILE}"

  ROSTER_IDX=$((ROSTER_IDX + 1))
done

log "DONE flagged=${FLAGGED} resolved=${RESOLVED_COUNT}/${#ROSTER[@]} report=${REPORT_FILE}"

# One matchable line for `thrum monitor --match` to catch and deliver.
# Two shapes: the routine tick, and the resolution-outage marker from the
# fork default above -- SKILL.md's registration example's --match regex
# must cover BOTH ("^watch-tick: (cycle done|RESOLUTION-FAIL)").
if [ "${RESOLUTION_ALL_FAILED}" -eq 1 ]; then
  echo "watch-tick: RESOLUTION-FAIL $(date -u +%Y-%m-%dT%H:%M:%SZ) -- ${#ROSTER[@]} agent(s), 0 ssh-fallback targets resolved -- report: ${REPORT_FILE}"
else
  echo "watch-tick: cycle done $(date -u +%Y-%m-%dT%H:%M:%SZ) -- ${#ROSTER[@]} agent(s), ${FLAGGED} flagged, ${RESOLVED_COUNT} ssh-fallback-ready -- report: ${REPORT_FILE}"
fi
