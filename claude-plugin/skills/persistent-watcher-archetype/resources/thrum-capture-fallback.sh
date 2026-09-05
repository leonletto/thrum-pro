#!/usr/bin/env bash
# thrum-capture-fallback.sh — capture/key an agent, falling back to an SSH
# hop when the local `thrum tmux capture|key` proxy path fails with a known
# cross-daemon proxy-routing error signature (thrum-7vwgy / thrum-zkqut
# class bugs: same-host dual-daemon caller-identity collision, and a
# phantom-routing regression on daemon builds predating EnsureProxies).
#
# `thrum tmux capture <agent>` ALREADY reaches remote agents by name via the
# rpcrouter proxy — this script is a resilience FALLBACK for when that path
# is broken on the CALLER's side, not a replacement for it and not a
# fleet-wide-watching enabler in its own right. Local-first, always.
#
# This papers over those bugs rather than fixing them — it does not touch
# thrum's daemon/peer/proxy config. It retries the identical command via
# SSH, cd'd into the TARGET AGENT's own repo checkout on its box, using a
# caller-resolved ssh target/user/repo. There is no hardcoded host or repo
# in this script — resolution is the CALLER's job (see the companion
# thrum-watch-pane-capture.sh's resolve_agent_ssh, which reads thrum state
# agent_pool/topology to find the right box + repo per agent).
#
# Usage:
#   thrum-capture-fallback.sh capture <agent_name> <ssh_target> <ssh_user> <repo_path>
#   thrum-capture-fallback.sh key <agent_name> <ssh_target> <ssh_user> <repo_path> <key1> [key2 ...]
#
# <ssh_target> may be the literal string "NONE" to mean "no SSH fallback is
# available for this agent" (e.g. the caller's target resolution failed
# closed on a missing/placeholder topology.repo_path) — in that case a
# local failure is returned as-is, with no SSH attempt at all.
#
# <ssh_user> may be empty ("") to let ssh/its own config resolve the user
# (e.g. when <ssh_target> is itself a configured Host alias) — in that case
# the ssh destination is just <ssh_target>, not user@target.
#
# Exit status: propagates the underlying thrum command's exit status from
# whichever path (local or SSH) actually produced the returned output.
set -uo pipefail

MODE="${1:?usage: $0 <capture|key> <agent_name> <ssh_target> <ssh_user> <repo_path> [keys...]}"
AGENT="${2:?usage: $0 <capture|key> <agent_name> <ssh_target> <ssh_user> <repo_path> [keys...]}"
SSH_TARGET="${3:?usage: $0 <capture|key> <agent_name> <ssh_target> <ssh_user> <repo_path> [keys...]}"
SSH_USER="${4-}"
REPO_PATH="${5-}"
shift 5 || true
EXTRA_ARGS=("$@")

# Known local-proxy failure signatures that mean "try the SSH fallback."
# MUST STAY IN SYNC BY HAND with thrum-watch-pane-capture.sh's identical
# is_proxy_failure() -- no shared-sourcing across the two files. This
# script is also directly callable standalone (e.g. `key` to approve/deny
# a modal on a cross-daemon agent), so it re-derives the signature
# independently rather than trusting a caller's prior classification.
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
    # "${EXTRA_ARGS[@]:-}" not "${EXTRA_ARGS[@]}": a DECLARED-EMPTY array
    # subscripted with [@] is a fatal unbound-variable under `set -u` on
    # bash <4.4 (a real bug, not a style choice -- `key` mode with zero
    # key args crashes on this fleet's /bin/bash 3.2.57 without the ":-").
    capture) thrum tmux capture "$AGENT" 2>&1 ;;
    key)     thrum tmux key "$AGENT" "${EXTRA_ARGS[@]:-}" 2>&1 ;;
  esac
}

run_ssh() {
  local dest cmd
  dest="$(ssh_destination)"
  case "$MODE" in
    capture) cmd="thrum tmux capture '$AGENT'" ;;
    key)     cmd="thrum tmux key '$AGENT' ${EXTRA_ARGS[*]:-}" ;;
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
# thrum-level error), the caller's identities may need re-adding to the
# keychain-backed ssh-agent. No default keys ship here -- this is a
# generic plugin script, and baking in one operator's specific key
# filenames would be wrong for every other fleet/operator that copies it.
# Set THRUM_CAPTURE_FALLBACK_SSH_KEYS (space-separated paths) per-operator
# if this retry needs to add specific identities; with it unset, `ssh-add
# --apple-use-keychain` still runs with no extra args, which adds ssh's
# own default identities.
retry_with_ssh_add() {
  local keys="${THRUM_CAPTURE_FALLBACK_SSH_KEYS:-}"
  # Intentional word-splitting of a space-separated key-path list below.
  # shellcheck disable=SC2086
  ssh-add --apple-use-keychain ${keys} >/dev/null 2>&1
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
