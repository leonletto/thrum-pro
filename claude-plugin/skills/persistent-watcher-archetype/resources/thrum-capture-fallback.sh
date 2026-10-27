#!/usr/bin/env bash
# thrum-capture-fallback.sh — capture or key an agent, falling back to an
# SSH hop when the local `thrum tmux capture|send` proxy path fails with
# a known cross-daemon proxy-routing error signature (known bug classes:
# same-host dual-daemon caller-identity collision, and a
# phantom-routing regression on daemon builds predating EnsureProxies).
#
# `thrum tmux capture <agent>` ALREADY reaches remote agents by name via the
# rpcrouter proxy — this script is a resilience FALLBACK for when that path
# is broken on the CALLER's side, not a replacement for it and not a
# fleet-wide-watching enabler in its own right. Local-first, always.
#
# `key` is the LAST rung of the watcher's modal ladder: use it only after the
# daemon grant and that machine's coordinator have failed and an agent stays
# blocked. The key safety rules of the persistent-watcher-archetype skill
# apply unchanged (judge the command, never "don't ask again").
#
# This papers over those bugs rather than fixing them — it does not touch
# thrum's daemon/peer/proxy config. There is no hardcoded host or repo in
# this script — resolution is the CALLER's job (see the companion
# thrum-watch-pane-capture.sh, which takes a roster entry's hostname and
# tmux_session, or reads thrum state agent_pool/topology to find the box and
# repo per agent).
#
# Usage:
#   thrum-capture-fallback.sh capture <agent_name> <ssh_target> <ssh_user> <repo_path> [tmux_session]
#   thrum-capture-fallback.sh key <agent_name> <ssh_target> <ssh_user> <repo_path> <key1> [key2 ...]
#
# <ssh_target> may be the literal string "NONE" to mean "no SSH fallback is
# available for this agent" — a local failure is then returned as-is, with
# no SSH attempt at all.
#
# <ssh_user> may be empty ("") to let ssh/its own config resolve the user
# (e.g. when <ssh_target> is itself a configured Host alias).
#
# SSH fallback shape: with a <repo_path>, the identical `thrum tmux capture`
# runs in the target agent's own checkout on its box. With an empty
# <repo_path> and a <tmux_session>, a raw read-only `tmux capture-pane` of
# that session runs instead.
#
# Exit status: propagates the underlying command's exit status from
# whichever path (local or SSH) actually produced the returned output.
set -uo pipefail

USAGE="usage: $0 <capture|key> <agent_name> <ssh_target> <ssh_user> <repo_path> [tmux_session | keys...]"
MODE="${1:?${USAGE}}"
AGENT="${2:?${USAGE}}"
SSH_TARGET="${3:?${USAGE}}"
SSH_USER="${4-}"
REPO_PATH="${5-}"
shift 5 || true
EXTRA_ARGS=("$@")
TMUX_SESSION=""
case "${MODE}" in
  capture) TMUX_SESSION="${EXTRA_ARGS[0]-}" ;;
  key) ;;
  *)
    echo "thrum-capture-fallback.sh: unknown mode '${MODE}'; ${USAGE}" >&2
    exit 2
    ;;
esac

# Known local-proxy failure signatures that mean "try the SSH fallback."
# MUST STAY IN SYNC BY HAND with thrum-watch-pane-capture.sh's identical
# is_proxy_failure() -- no shared-sourcing across the two files. This
# script is also directly callable standalone, so it re-derives the
# signature independently rather than trusting a caller's classification.
is_proxy_failure() {
  grep -qE 'rpcrouter: caller-peer lacks required capability|peer unreachable|circuit open, dial skipped' <<<"$1"
}

ssh_destination() {
  if [ -n "${SSH_USER}" ]; then
    printf '%s@%s' "${SSH_USER}" "${SSH_TARGET}"
  else
    printf '%s' "${SSH_TARGET}"
  fi
}

run_local() {
  case "$MODE" in
    capture) thrum tmux capture "$AGENT" 2>&1 ;;
    # "${EXTRA_ARGS[*]:-}" not "${EXTRA_ARGS[*]}": a DECLARED-EMPTY array
    # subscripted with [*] is a fatal unbound-variable under `set -u` on
    # bash <4.4 (a real bug, not a style choice -- `key` mode with zero
    # key args crashes on /bin/bash 3.2.57 without the ":-").
    # key mode delivers named tmux keys via `thrum tmux send --keys` (the
    # peer-routed primitive); EXTRA_ARGS (one key per element) is comma-joined
    # into a single --keys value inside a subshell so IFS="," never leaks.
    key) thrum tmux send "$AGENT" --keys "$(IFS=,; printf '%s' "${EXTRA_ARGS[*]:-}")" 2>&1 ;;
  esac
}

run_ssh() {
  local dest cmd
  dest="$(ssh_destination)"
  if [ "${MODE}" = "capture" ] && [ -z "${REPO_PATH}" ] && printf '%s' "${TMUX_SESSION}" | grep -Eq '^[A-Za-z0-9_.:-]+$'; then
    # Read-only raw capture of the named tmux session: no thrum, no keys.
    cmd="tmux has-session -t '=${TMUX_SESSION%%:*}' 2>/dev/null || exit 1; tmux capture-pane -p -J -t '=${TMUX_SESSION%%:*}:' -S -30"
    # shellcheck disable=SC2029
    ssh -n -o BatchMode=yes -o ConnectTimeout=5 "${dest}" "${cmd}" 2>&1
    return
  fi
  case "$MODE" in
    capture) cmd="thrum tmux capture '$AGENT'" ;;
    key)     cmd="thrum tmux send '$AGENT' --keys $(IFS=,; printf '%s' "${EXTRA_ARGS[*]:-}")" ;;
  esac
  # Client-side expansion of REPO_PATH/cmd into the remote command string is
  # intentional -- that's how the resolved repo path and thrum invocation
  # reach the remote shell at all. REPO_PATH and AGENT are quoted here so a
  # space in either (e.g. a topology repo_path with a space) doesn't break
  # the remote `cd` -- consistent with fail-closed-on-bad-topology-data
  # everywhere else in this pair of scripts.
  # shellcheck disable=SC2029
  ssh "${dest}" "cd '${REPO_PATH}' && ${cmd}" 2>&1
}

# ssh-add retry: if the SSH hop itself fails at the connection layer (not a
# CLI-level error), the caller's identities may need re-adding to the
# ssh-agent. No default keys ship here -- this is a generic plugin script,
# and baking in one operator's specific key filenames would be wrong for
# every other operator that copies it. Set THRUM_CAPTURE_FALLBACK_SSH_KEYS
# (space-separated paths) per-operator if this retry needs to add specific
# identities; with it unset, ssh-add adds ssh's own default identities.
# The keychain flag exists only on macOS.
retry_with_ssh_add() {
  local keys="${THRUM_CAPTURE_FALLBACK_SSH_KEYS:-}"
  if [ "$(uname -s)" = "Darwin" ]; then
    # Intentional word-splitting of a space-separated key-path list below.
    # shellcheck disable=SC2086
    ssh-add --apple-use-keychain ${keys} >/dev/null 2>&1
  else
    # shellcheck disable=SC2086
    ssh-add ${keys} >/dev/null 2>&1
  fi
  run_ssh
}

OUT="$(run_local)"
STATUS=$?

if [ "${STATUS}" -ne 0 ] && is_proxy_failure "${OUT}" && [ "${SSH_TARGET}" != "NONE" ]; then
  OUT="$(run_ssh)"
  STATUS=$?
  # SSH connection-layer failure (not a thrum proxy error) -> try ssh-add once.
  if [ "${STATUS}" -ne 0 ] && grep -qE 'Permission denied|Could not resolve hostname|Connection refused|Connection timed out|Too many authentication failures' <<<"${OUT}"; then
    OUT="$(retry_with_ssh_add)"
    STATUS=$?
  fi
fi

echo "${OUT}"
exit "${STATUS}"
