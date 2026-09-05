#!/usr/bin/env bash
#
# ensure-permission-activation.sh — SessionStart runtime activation for the
# thrum-workspace permission profile (Part A).
#
# Problem this closes: a customer who installs the plugin via Codex's OWN raw
# native marketplace flow (`codex plugin marketplace add` run directly,
# bypassing install-plugin.sh entirely) never gets the thrum-workspace
# permission profile applied — nothing in that raw flow calls
# ensure-permission-profile.sh. install-plugin.sh's own fail-closed fix
# (step 7) only protects customers who go through THAT installer.
#
# This script is wired as the FIRST entry in hooks.json's SessionStart array,
# ahead of inject-prime-context.sh, so it runs before any protected `thrum`
# call is made this turn.
#
# Ground truth (established empirically by a fleet coordinator against an
# isolated native Codex 0.151.0 install + openai/codex source
# codex-rs/hooks/src/events/session_start.rs + schema.rs — treated as
# settled, not re-derived here):
#   1. SessionStart hooks run HOST/PRE-SANDBOX — they CAN write
#      CODEX_HOME/config.toml even before any thrum-workspace profile grant
#      exists (a sandboxed tool call could not).
#   2. Config activation is NEXT-PROCESS-ONLY — writing the profile now does
#      not retroactively apply to the currently-running session; the
#      customer's codex process must be restarted.
#   3. The fail-closed halt signal is the EXACT JSON control message on
#      stdout: {"continue":false,"stopReason":"..."}. A nonzero exit code
#      does NOT halt the turn on its own. A Stop-hook-style `decision:block`
#      field is INVALID for SessionStart.
#
# This script never calls `thrum` itself — it only shells out to
# ensure-permission-profile.sh (the pre-sandbox-safe profile writer) — so
# "zero protected thrum calls this turn" is structural: whichever of the 3
# outcomes below fires, no `thrum whoami`/`thrum prime` invocation happens
# in this script, and this script is ordered before inject-prime-context.sh
# (the one that DOES call `thrum`) in hooks.json's SessionStart array.
#
# Three outcomes (idempotent — safe on every session start):
#   1. EXACT   — the consolidated profile is already fully present and
#                correct. Fast-path: a plain grep of config.toml against the
#                expected grant lines, no subprocess beyond that. No JSON is
#                emitted; exit 0 and the rest of the SessionStart chain
#                (inject-prime-context.sh) proceeds exactly as today.
#   2. CHANGED — the profile is absent or stale. ensure-permission-profile.sh
#                is invoked to write the corrected consolidated profile (it
#                is pre-sandbox-safe per fact #1 above), then the exact
#                control JSON below is emitted on stdout and the script exits
#                0 (a successful — if incomplete-until-restart — activation,
#                not an error):
#                  {"continue":false,"stopReason":"THRUM_PERMISSION_ACTIVATION_REQUIRES_RESTART"}
#   3. FAILS   — ensure-permission-profile.sh itself errors (malformed
#                redirect, I/O failure, etc.). A distinct control JSON is
#                emitted with an actionable reason, and the script exits
#                non-zero (a genuine failure):
#                  {"continue":false,"stopReason":"<actionable message>"}
#                Never a silent degraded success.
#
# A project that doesn't use thrum (no .thrum/ found) is treated the same as
# ensure-permission-profile.sh's own benign skip: outcome EXACT, no-op, rest
# of the chain proceeds.
#
# Environment overrides (mirrors ensure-permission-profile.sh):
#   CODEX_HOME        base dir for config.toml (default: $HOME/.codex)
#   CODEX_CONFIG      path to config.toml (default: ${CODEX_HOME}/config.toml)
#   THRUM_REPO_DIR    directory to resolve the .thrum dir from (default: $(pwd))

set -uo pipefail

CODEX_HOME_DIR="${CODEX_HOME:-${HOME}/.codex}"
CODEX_CONFIG="${CODEX_CONFIG:-${CODEX_HOME_DIR}/config.toml}"
THRUM_REPO_DIR="${THRUM_REPO_DIR:-$(pwd)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_SCRIPT="${SCRIPT_DIR}/ensure-permission-profile.sh"

# Emit the exact control JSON on stdout. No jq dependency — the two dynamic
# stopReason values (the restart sentinel, and a stderr-derived failure
# message) both need JSON-string escaping since stderr text can contain
# quotes/newlines/backslashes; do it with a small inline sed pipeline rather
# than pulling in python3 for the fast path (this must stay cheap).
emit_control_json() {
  local reason="$1"
  local escaped
  escaped=$(printf '%s' "$reason" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n' ' ')
  printf '{"continue":false,"stopReason":"%s"}\n' "$escaped"
}

# 1. If there's no python3, ensure-permission-profile.sh can't run at all —
#    that's a genuine failure, not a benign skip (the benign skip is scoped
#    to "no .thrum/ found", never to a missing prerequisite).
if [[ ! -x "${PROFILE_SCRIPT}" && ! -f "${PROFILE_SCRIPT}" ]]; then
  emit_control_json "THRUM_PERMISSION_ACTIVATION_FAILED: ensure-permission-profile.sh not found at ${PROFILE_SCRIPT}. Reinstall the thrum plugin, or run it manually from INSTALL.md's \"Sandbox permission profile\" section."
  exit 1
fi

# 2. Cheap fast-path check: walk up from THRUM_REPO_DIR for a .thrum dir and
#    resolve its (single-hop) redirect, mirroring
#    ensure-permission-profile.sh's own steps 1-2 exactly (same env vars,
#    same walk bound, same redirect-validation rules) so the expected grant
#    lines below are computed against the SAME resolved paths the profile
#    script itself would use. This mirrors, rather than sources, that logic:
#    ensure-permission-profile.sh runs as a flat top-level script (no
#    functions to source), and the walk is ~15 lines with no external
#    dependency, so duplicating it here is lower-risk than restructuring the
#    tested, shipped profile script to expose it. If this ever drifts from
#    ensure-permission-profile.sh's own resolution, the worst case is a
#    spurious CHANGED verdict (which just re-runs the always-correct writer
#    below) — never a false EXACT that skips a real gap, because a
#    resolution mismatch here means the expected lines won't match what's on
#    disk either.
found_dir=""
walk_dir="${THRUM_REPO_DIR}"
i=0
while [[ ${i} -lt 20 ]]; do
  if [[ -d "${walk_dir}/.thrum" ]]; then
    found_dir="${walk_dir}"
    break
  fi
  if [[ "${walk_dir}" == "/" ]]; then
    break
  fi
  walk_dir="$(dirname "${walk_dir}")"
  i=$((i + 1))
done

if [[ -z "${found_dir}" ]]; then
  # Not a thrum project — nothing to activate. Same benign-skip semantics as
  # ensure-permission-profile.sh itself.
  exit 0
fi

local_thrum_dir="${found_dir}/.thrum"
redirect_file="${local_thrum_dir}/redirect"
resolved_thrum_dir="${local_thrum_dir}"
redirect_malformed=0

if [[ -f "${redirect_file}" ]]; then
  redirect_target="$(head -n1 "${redirect_file}" | tr -d '\r\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  if [[ -z "${redirect_target}" ]]; then
    redirect_malformed=1
  elif [[ "${redirect_target}" != /* ]]; then
    redirect_malformed=1
  elif [[ ! -d "${redirect_target}" ]]; then
    redirect_malformed=1
  elif [[ -f "${redirect_target}/redirect" ]]; then
    redirect_malformed=1
  else
    resolved_thrum_dir="${redirect_target}"
  fi
fi

if [[ ${redirect_malformed} -eq 1 ]]; then
  # Don't try to reproduce ensure-permission-profile.sh's exact validation
  # error here — invoke it for real below and surface ITS error, which is
  # the authoritative message. Skip straight to the write/verify path.
  run_write=1
else
  run_write=0
  audit_dir="${resolved_thrum_dir}/var/log"
  socket_path="${resolved_thrum_dir}/var/thrum.sock"
  codex_skills_dir="${HOME}/.codex/skills"
  codex_plugin_cache_dir="${HOME}/.codex/plugins/cache/thrum-marketplace/thrum"
  tmp_exception_dir="/private/tmp"
  local_bin_dir="${HOME}/.local/bin"

# grant_present validates ONE expected profile line STRUCTURALLY (Pass-3 B1):
# it reports success iff config.toml contains, inside table `tbl` ("" = the
# root, before any table header), an ACTIVE line of the exact form
#   <key> = <value>
# with optional surrounding whitespace and nothing else — never merely a
# substring somewhere in the file. Three properties the previous
# `grep -qF` loop could not provide:
#   1. COMMENT-PROOF: lines whose first non-whitespace char is "#" are
#      skipped entirely, so a grant commented out by a previous profile
#      version or a hand-edit reads as ABSENT (triggering a rewrite), never
#      as evidence the grant is active.
#   2. TABLE-ANCHORED: TOML table headers are tracked, and a match only
#      counts inside the expected table. The lookalike that motivated this:
#      `[plugins."thrum@thrum-marketplace"]` carries its own
#      `enabled = true` — the plugin's enable flag — which the substring
#      check happily counted as the network-enabled evidence, silently
#      skipping a missing [permissions.thrum-workspace.network] block.
#   3. EXACT-LINE: the key must START the line and only whitespace may
#      follow the value — a hit in the middle of another key, value, or
#      string never counts. Bias is deliberately toward CHANGED (rewrite):
#      a legitimate variant the writer never emits (e.g. a trailing inline
#      comment) costs one harmless rewrite, while a false EXACT silently
#      skips activation — the one outcome this gate must never produce.
# No new dependencies: awk is POSIX-standard (the writer's python3
# requirement is untouched; the fast path must stay cheap and dependency-
# free).
grant_present() {
  local tbl="$1" key="$2" val="$3"
  awk -v tbl="${tbl}" -v key="${key}" -v val="${val}" '
    {
      line = $0
      sub(/\r$/, "", line)
      stripped = line
      sub(/^[[:space:]]+/, "", stripped)
      if (stripped == "") next
      first = substr(stripped, 1, 1)
      if (first == "#") next
      if (first == "[") {
        cur = stripped
        sub(/[[:space:]]*#.*$/, "", cur)
        sub(/[[:space:]]+$/, "", cur)
        sub(/^\[[[:space:]]*/, "", cur)
        sub(/[[:space:]]*\]$/, "", cur)
        next
      }
      if (cur != tbl) next
      if (index(stripped, key) != 1) next
      rest = substr(stripped, length(key) + 1)
      sub(/^[[:space:]]+/, "", rest)
      if (substr(rest, 1, 1) != "=") next
      rest = substr(rest, 2)
      sub(/^[[:space:]]+/, "", rest)
      if (index(rest, val) != 1) next
      tail = substr(rest, length(val) + 1)
      if (tail ~ /^[[:space:]]*$/) { found = 1; exit }
    }
    END { exit found ? 0 : 1 }
  ' "${CODEX_CONFIG}"
}

FS_TABLE="permissions.thrum-workspace.filesystem"

  if [[ ! -f "${CODEX_CONFIG}" ]]; then
    run_write=1
  else
    run_write=0
    # Each triple is <table>|<key>|<value>; root-level scalars use an empty
    # table. Order mirrors the writer's own layout (see
    # ensure-permission-profile.sh and the e2e test's post-write assertion).
    while IFS='|' read -r tbl key val; do
      [[ -n "${tbl}${key}${val}" ]] || continue
      if ! grant_present "${tbl}" "${key}" "${val}"; then
        run_write=1
        break
      fi
    done <<GRANTS
${FS_TABLE}|"${audit_dir}"|"write"
${FS_TABLE}|"${resolved_thrum_dir}"|"read"
${FS_TABLE}|"${codex_skills_dir}"|"read"
${FS_TABLE}|"${codex_plugin_cache_dir}"|"read"
${FS_TABLE}|"${tmp_exception_dir}"|"read"
${FS_TABLE}|"${local_bin_dir}"|"read"
permissions.thrum-workspace.network.unix_sockets|"${socket_path}"|"allow"
permissions.thrum-workspace.network|enabled|true
|approval_policy|"on-request"
|approvals_reviewer|"auto_review"
|default_permissions|"thrum-workspace"
GRANTS
  fi
fi

if [[ ${run_write} -eq 0 ]]; then
  # 3a. EXACT — nothing missing. Fast-path exit, rest of the SessionStart
  #     chain proceeds exactly as today.
  exit 0
fi

# 3b/3c. CHANGED/MISSING or a genuine resolution failure — invoke the real
# writer. It's pre-sandbox-safe (fact #1) and idempotent, so this is safe to
# call even if our own cheap check above misjudged something.
write_output=$(bash "${PROFILE_SCRIPT}" 2>&1)
write_status=$?

if [[ ${write_status} -ne 0 ]]; then
  emit_control_json "THRUM_PERMISSION_ACTIVATION_FAILED: ensure-permission-profile.sh failed while applying the thrum-workspace permission profile: ${write_output}"
  exit 1
fi

emit_control_json "THRUM_PERMISSION_ACTIVATION_REQUIRES_RESTART"
exit 0
