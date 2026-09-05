#!/usr/bin/env bash
#
# ensure-permission-profile.sh — ship the thrum-workspace codex permission
# profile out-of-box.
#
# Codex's default `:workspace` sandbox profile doesn't cover two things thrum
# commands need:
#
#   1. Filesystem write to Thrum's redirected audit-log dir. Every thrum
#      command (prime/inbox/send) appends a command-log entry to
#      `<main-repo>/.thrum/var/log/` — resolved via `.thrum/redirect` from a
#      worktree, so it's OUTSIDE the worktree the `:workspace` profile scopes
#      to. This makes codex's auto-review DENY the write, blocking thrum
#      commands entirely on codex seats.
#   2. Network access to the thrum daemon's UNIX socket
#      (`<main-repo>/.thrum/var/thrum.sock`). Codex's sandbox also blocks
#      outbound UNIX-socket connections by default, so even with the
#      filesystem grant above, every RPC the thrum CLI makes to the daemon
#      over that socket is denied. Established by-effect (codex 0.146.0 and
#      0.149.1, no CLI flag needed): the grant requires BOTH
#      `[permissions.thrum-workspace.network] enabled = true` AND a
#      `[permissions.thrum-workspace.network.unix_sockets]` entry for the
#      socket path — `unix_sockets` alone, without `network.enabled = true`,
#      loads as valid TOML but is INERT (daemon calls still fail).
#
#   3. Filesystem READ to the redirect-resolved `.thrum` directory itself
#      (Codex leg). A codex agent's own sandboxed Read-tool
#      calls need this to load ordinary thrum monitor/support material —
#      `.thrum/role_templates/*.md`, `.thrum/hotpath-gate.json`,
#      `.thrum/philosophy.md`, `.thrum/config.json`, etc. In a worktree with
#      a redirect, this directory lives OUTSIDE the current
#      worktree/workspace root, exactly like the audit-log dir and daemon
#      socket above, so it isn't covered by the profile's
#      `extends = ":workspace"` baseline either. `.codex/skills` deliberately
#      gets NO equivalent entry: only `.thrum` and `.beads` are ever
#      redirected, so `.codex/skills` always lives inside the current
#      worktree/workspace root and is already covered by
#      `extends = ":workspace"` — an explicit entry for it would be a
#      redundant duplicate of a grant that already applies.
#
# This script resolves the redirect-aware audit-log dir, daemon-socket path,
# and `.thrum` dir for the repo it's run from and appends all of them
# (append-if-absent, matching install-plugin.sh's `[features]` insertion
# idiom) to a `[permissions.thrum-workspace]` profile in ~/.codex/config.toml.
# It also ensures the three root-level scalars (`approval_policy`,
# `approvals_reviewer`, `default_permissions`) exist, without clobbering any
# pre-existing user value.
#
# Idempotent: safe to run multiple times, and safe to run from multiple
# different thrum repos over time (each repo's resolved path is appended once;
# re-running for a path already present is a no-op).
#
# Environment overrides (primarily for tests):
#   CODEX_CONFIG      path to config.toml (default: ${CODEX_HOME:-$HOME/.codex}/config.toml)
#   THRUM_REPO_DIR    directory to resolve the .thrum dir from (default: $(pwd))
#
# Exit code 0 on success OR benign skip (no .thrum found under THRUM_REPO_DIR).
# Non-zero on a genuine I/O failure, OR on a malformed .thrum/redirect (empty,
# relative, missing/non-directory target, or chained — only a single-hop,
# absolute, existing, non-chained redirect target is resolved; anything else
# is a hard failure, mirroring internal/paths.ResolveThrumDir's semantics
# rather than silently mis-resolving to the wrong audit-log dir).

set -uo pipefail

CODEX_HOME_DIR="${CODEX_HOME:-${HOME}/.codex}"
CODEX_CONFIG="${CODEX_CONFIG:-${CODEX_HOME_DIR}/config.toml}"
THRUM_REPO_DIR="${THRUM_REPO_DIR:-$(pwd)}"

say() { printf '→ %s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; }

# 1. Walk up from THRUM_REPO_DIR looking for a .thrum subdirectory.
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
  say "No .thrum/ found under ${THRUM_REPO_DIR}; skipping thrum-workspace permission profile (re-run install-plugin.sh from inside a thrum worktree/repo to enable it)."
  exit 0
fi

# 2. Resolve the redirect (single-hop), falling back to the local .thrum on
#    any invalid/missing target.
local_thrum_dir="${found_dir}/.thrum"
redirect_file="${local_thrum_dir}/redirect"
resolved_thrum_dir="${local_thrum_dir}"

if [[ -f "${redirect_file}" ]]; then
  redirect_target="$(head -n1 "${redirect_file}" | tr -d '\r\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  if [[ -z "${redirect_target}" ]]; then
    err "redirect file ${redirect_file} is empty"
    exit 1
  fi
  if [[ "${redirect_target}" != /* ]]; then
    err "redirect target must be an absolute path, got: ${redirect_target}"
    exit 1
  fi
  if [[ ! -d "${redirect_target}" ]]; then
    err "redirect target does not exist or is not a directory: ${redirect_target}"
    exit 1
  fi
  if [[ -f "${redirect_target}/redirect" ]]; then
    err "redirect chain detected: ${redirect_file} points to ${redirect_target} which also has a redirect file; only single-hop redirects are supported"
    exit 1
  fi
  resolved_thrum_dir="${redirect_target}"
fi

audit_dir="${resolved_thrum_dir}/var/log"
# The thrum daemon's UNIX socket — same redirect-resolved thrum dir, so a
# worktree's socket permission grant follows the redirect to the MAIN repo's
# socket, exactly like the audit-log dir above (the daemon listens on the
# MAIN repo's .thrum/var/, not a per-worktree one).
socket_path="${resolved_thrum_dir}/var/thrum.sock"

# Global plugin-skill cache roots (the allowlist effort round-4). These are the two
# codex entries under global_read_paths in the canonical allowlist,
# internal/permissions/thrum_allowlist.json (FROZEN — read only, never
# edited by this script): "~/.codex/skills" (Codex's flattened global skill
# install dir) and "~/.codex/plugins/cache/thrum-marketplace/thrum" (the
# versioned plugin-cache mirror). Both are HOME-relative in the canonical
# JSON, but Codex's config.toml has NO ~/env-var expansion — confirmed by
# investigation: the live config only ever contains literal absolute paths
# as table keys. So, exactly like CODEX_HOME_DIR above, interpolate the
# literal ${HOME} value here at generation time rather than writing the
# tilde form, which would load as valid TOML but grant nothing.
codex_skills_dir="${HOME}/.codex/skills"
codex_plugin_cache_dir="${HOME}/.codex/plugins/cache/thrum-marketplace/thrum"

# Thrum-binary install-location read grant (consolidated round,
# Part B). Owner correction (owner ruling): agents need read/access to
# the thrum binary's install location so PATH-resolved `thrum` can execute
# under the sandbox — this mirrors the canonical allowlist's
# global_read_paths.codex entry (internal/permissions/thrum_allowlist.json),
# which now lists "~/.local/bin" for all three runtimes. Same $HOME
# interpolation rationale as codex_skills_dir/codex_plugin_cache_dir above:
# config.toml has no ~/env-var expansion, so the literal absolute path is
# rendered at generation time, never the tilde form. This is a filesystem
# READ grant — a separate axis from command_patterns matching — and does not
# touch the alt-exec carve-out in the permissions engine.
local_bin_dir="${HOME}/.local/bin"

# Owner-authorized /private/tmp exception (the allowlist effort round-4). Quoting the
# canonical allowlist's own comment verbatim so nobody removes this later
# thinking it's an accidental broad grant: "OWNER-AUTHORIZED EXCEPTION —
# /private/tmp (owner ruling, watcher-recovery P0; scope CONFIRMED
# all-runtimes by the fleet coordinator the same day — owner's wording was
# 'global configs for all agents', the operational-artifact class is
# runtime-independent): owner_authorized_exceptions grants EVERY supported
# runtime broad READ access to /private/tmp/* DESPITE it being a
# world-writable directory — explicitly ruled acceptable by the owner for
# coordinator/watcher operational artifacts. This is a DELIBERATE exception,
# not a template for widening elsewhere: it grants READ/ACCESS ONLY — never
# execute, never shell-interpolation, never a sibling root like /private or
# /private/tmpfoo, never write/delete." This path is already absolute, so no
# interpolation is needed. Codex renders this via its NATIVE
# filesystem-read profile mechanism (the same
# [permissions.thrum-workspace.filesystem] table as every other grant in
# this script) — NEVER as an invented Bash-pattern entry; per the project's
# hard constraint, Codex has no Bash-pattern command allowlist and this
# script must not add one.
tmp_exception_dir="/private/tmp"

# 3. Ensure root scalars + the permissions block/path line via python3
#    (append-if-absent, single read+write pass — matches install-plugin.sh's
#    existing `[features]` insertion idiom).
if ! command -v python3 >/dev/null 2>&1; then
  err "python3 not found on PATH; cannot update ${CODEX_CONFIG}"
  exit 1
fi

mkdir -p "$(dirname "${CODEX_CONFIG}")" || { err "could not create $(dirname "${CODEX_CONFIG}")"; exit 1; }
[[ -f "${CODEX_CONFIG}" ]] || : > "${CODEX_CONFIG}"

PY_OUT=$(python3 - "${CODEX_CONFIG}" "${audit_dir}" "${socket_path}" "${resolved_thrum_dir}" "${codex_skills_dir}" "${codex_plugin_cache_dir}" "${tmp_exception_dir}" "${local_bin_dir}" <<'PY'
import os
import re
import sys
import tempfile

(config_path, audit_dir, socket_path, thrum_dir,
 codex_skills_dir, codex_plugin_cache_dir, tmp_exception_dir,
 local_bin_dir) = sys.argv[1:9]

with open(config_path, "r") as f:
    content = f.read()

lines = content.split("\n")
messages = []

# 1) Insertion point for root scalars = index of first '[' line in the
#    ORIGINAL content, computed before any insertion.
insert_at = len(lines)
for idx, line in enumerate(lines):
    if line.startswith("["):
        insert_at = idx
        break

scalars = [
    ("approval_policy", 'approval_policy = "on-request"'),
    ("approvals_reviewer", 'approvals_reviewer = "auto_review"'),
    ("default_permissions", 'default_permissions = "thrum-workspace"'),
]

# Root-scalar "already set" check must be scoped to ONLY the lines strictly
# BEFORE the first '[' header in the ORIGINAL (pre-insertion) content — a
# same-named key nested under some unrelated table does not count.
root_lines = lines[:insert_at]

to_insert = []
for key, full_line in scalars:
    pattern = re.compile(r'^\s*' + re.escape(key) + r'\s*=')
    already_set = any(pattern.match(l) for l in root_lines)
    if already_set:
        messages.append("already_set:" + key)
    else:
        to_insert.append(full_line)

if to_insert:
    lines = lines[:insert_at] + to_insert + lines[insert_at:]

# 2) Permissions block / path lines, append-if-absent.
#
# Two lines go in the SAME [permissions.thrum-workspace.filesystem] table:
#   - path_line:      write access to the redirect-resolved audit-log dir
#                      (pre-existing grant, unchanged).
#   - thrum_read_line: READ access to the redirect-resolved `.thrum` dir
#                       itself (Codex leg). This is what lets a
#                       codex agent's own sandboxed Read-tool calls load
#                       ordinary thrum monitor/support material
#                       (.thrum/role_templates, .thrum/hotpath-gate.json,
#                       .thrum/philosophy.md, .thrum/config.json, etc.)
#                       without a permission denial — needed because, in the
#                       worktree-redirect case, that directory lives OUTSIDE
#                       the current worktree/workspace root the same way the
#                       audit-log dir and daemon socket do, so it isn't
#                       covered by the profile's `extends = ":workspace"`
#                       baseline. (`.codex/skills` deliberately gets NO such
#                       entry here: it is never redirected — only `.thrum`
#                       and `.beads` are — so it always lives inside the
#                       current worktree/workspace root and is therefore
#                       already covered by `extends = ":workspace"`; adding
#                       an explicit entry for it would be a redundant
#                       duplicate of a grant that already applies.)
path_line = '"%s" = "write"' % audit_dir
thrum_read_line = '"%s" = "read"' % thrum_dir
# Global plugin-skill cache read grants (the allowlist effort round-4) — literal,
# $HOME-resolved absolute paths (see the shell-side comment above for why no
# tilde form is used). Owner-authorized /private/tmp exception — literal
# absolute path, no interpolation needed. All three use "read" only, never
# "write"/"exec"/"allow" — same as the pre-existing .thrum-dir grant.
codex_skills_read_line = '"%s" = "read"' % codex_skills_dir
codex_plugin_cache_read_line = '"%s" = "read"' % codex_plugin_cache_dir
tmp_exception_read_line = '"%s" = "read"' % tmp_exception_dir
# Thrum-binary install-location read grant (Part B) — see the
# shell-side comment above local_bin_dir for rationale.
local_bin_read_line = '"%s" = "read"' % local_bin_dir
fs_lines_to_ensure = [
    (path_line, "already_present", "added_path"),
    (thrum_read_line, "already_present_thrum_read", "added_thrum_read"),
    (codex_skills_read_line, "already_present_codex_skills_read", "added_codex_skills_read"),
    (codex_plugin_cache_read_line, "already_present_codex_plugin_cache_read", "added_codex_plugin_cache_read"),
    (tmp_exception_read_line, "already_present_tmp_exception_read", "added_tmp_exception_read"),
    (local_bin_read_line, "already_present_local_bin_read", "added_local_bin_read"),
]

MAIN_HEADER_RE = re.compile(r'^\[\s*permissions\.thrum-workspace\s*\]$')
FS_HEADER_RE = re.compile(r'^\[\s*permissions\.thrum-workspace\.filesystem\s*\]$')

# Tables don't need to be contiguous in TOML, so first search the ENTIRE
# file for an existing filesystem sub-table header, regardless of where the
# main [permissions.thrum-workspace] header (if any) sits.
fs_header_idx = None
for idx, line in enumerate(lines):
    if FS_HEADER_RE.match(line.strip()):
        fs_header_idx = idx
        break

if fs_header_idx is not None:
    # The filesystem sub-table already exists somewhere in the file (main
    # header may or may not be contiguous with it — doesn't matter here).
    # Its own section runs from just after its header to the next '['
    # line anywhere in the file, or EOF. Check each managed line
    # independently (append-if-absent per-line, not per-table) and insert
    # whichever ones are missing, all at once, right after the header.
    fs_section_end = len(lines)
    for idx in range(fs_header_idx + 1, len(lines)):
        if lines[idx].strip().startswith("["):
            fs_section_end = idx
            break

    existing_fs_lines = {l.strip() for l in lines[fs_header_idx + 1:fs_section_end]}
    to_insert_fs = []
    for line, present_msg, added_msg in fs_lines_to_ensure:
        if line in existing_fs_lines:
            messages.append(present_msg)
        else:
            to_insert_fs.append(line)
            messages.append(added_msg)

    if to_insert_fs:
        lines = lines[:fs_header_idx + 1] + to_insert_fs + lines[fs_header_idx + 1:]
else:
    # No filesystem sub-table anywhere yet. Look for the main header.
    header_idx = None
    for idx, line in enumerate(lines):
        if MAIN_HEADER_RE.match(line.strip()):
            header_idx = idx
            break

    if header_idx is None:
        # No header at all: append the full block at the end.
        while lines and lines[-1].strip() == "":
            lines.pop()
        if lines:
            lines.append("")
        lines.append("[permissions.thrum-workspace]")
        lines.append('extends = ":workspace"')
        lines.append("")
        lines.append("[permissions.thrum-workspace.filesystem]")
        lines.extend(line for line, _, _ in fs_lines_to_ensure)
        messages.append("added_block")
    else:
        # Main header exists but no fs sub-table anywhere in the file, so
        # this section-end scan (next header that isn't a thrum-workspace
        # sub-table) can't miss an existing fs sub-table — there isn't one.
        section_end = len(lines)
        for idx in range(header_idx + 1, len(lines)):
            stripped_line = lines[idx].strip()
            if stripped_line.startswith("[") and not stripped_line.startswith("[permissions.thrum-workspace."):
                section_end = idx
                break

        lines = lines[:section_end] + ["[permissions.thrum-workspace.filesystem]"] + [
            line for line, _, _ in fs_lines_to_ensure
        ] + lines[section_end:]
        for _, _, added_msg in fs_lines_to_ensure:
            messages.append(added_msg)

# 3) Network table (`network.enabled` + `network.unix_sockets` sub-table),
#    append-if-absent. Runs as a third+fourth step AFTER the filesystem-grant
#    step above, on the CURRENT (possibly already-mutated) `lines` — so if
#    the filesystem-grant step just added the main [permissions.thrum-
#    workspace] header, this step sees it already present.
sock_line = '"%s" = "allow"' % socket_path

NET_HEADER_RE = re.compile(r'^\[\s*permissions\.thrum-workspace\.network\s*\]$')
SOCK_HEADER_RE = re.compile(r'^\[\s*permissions\.thrum-workspace\.network\.unix_sockets\s*\]$')
ENABLED_RE = re.compile(r'^\s*enabled\s*=')


def find_header(pattern):
    for idx, line in enumerate(lines):
        if pattern.match(line.strip()):
            return idx
    return None


# Tables don't need to be contiguous in TOML, so search the ENTIRE file for
# both headers first, regardless of where the main header sits.
sock_header_idx = find_header(SOCK_HEADER_RE)
net_header_idx = find_header(NET_HEADER_RE)

if sock_header_idx is not None:
    # The unix_sockets sub-table already exists somewhere in the file. Its
    # own section runs from just after its header to the next '[' line
    # anywhere in the file, or EOF.
    sock_section_end = len(lines)
    for idx in range(sock_header_idx + 1, len(lines)):
        if lines[idx].strip().startswith("["):
            sock_section_end = idx
            break

    already_present_socket = any(
        l.strip() == sock_line for l in lines[sock_header_idx + 1:sock_section_end]
    )
    if already_present_socket:
        messages.append("already_present_socket")
    else:
        lines = lines[:sock_header_idx + 1] + [sock_line] + lines[sock_header_idx + 1:]
        messages.append("added_socket")

    # unix_sockets is nested under network, so the network header must
    # exist too. Re-find it (insertion above may have shifted indices) and
    # ensure `enabled` is set within ITS OWN direct section — never force
    # an existing explicit value, only fill in if the key is absent
    # entirely (same never-clobber principle as the 3 root scalars).
    net_header_idx = find_header(NET_HEADER_RE)
    if net_header_idx is not None:
        net_section_end = len(lines)
        for idx in range(net_header_idx + 1, len(lines)):
            if lines[idx].strip().startswith("["):
                net_section_end = idx
                break
        has_enabled = any(
            ENABLED_RE.match(l) for l in lines[net_header_idx + 1:net_section_end]
        )
        if has_enabled:
            messages.append("network_already_set")
        else:
            lines = lines[:net_header_idx + 1] + ["enabled = true"] + lines[net_header_idx + 1:]
            messages.append("network_added")
    else:
        # No explicit [permissions.thrum-workspace.network] header exists
        # anywhere — TOML-legal via an implicit parent table (a hand-edited
        # config could produce this; the script's own branches B/C below
        # never do, since they always create the network header alongside
        # unix_sockets). Without this, `enabled` would never get added on
        # ANY run against such a file — a reliability gap, not a security
        # one (the RPC just stays denied), but untested and worth closing.
        # Insert the header + enabled=true right before the existing
        # unix_sockets header, making it the (now explicit) parent — re-find
        # the sock header since the sock_line insertion above may have
        # shifted indices.
        sock_header_idx_now = find_header(SOCK_HEADER_RE)
        lines = (
            lines[:sock_header_idx_now]
            + ["[permissions.thrum-workspace.network]", "enabled = true", ""]
            + lines[sock_header_idx_now:]
        )
        messages.append("network_added")
elif net_header_idx is not None:
    # The network table exists but its unix_sockets sub-table doesn't
    # (confirmed above — sock_header_idx is None). Ensure `enabled` is set
    # in the network table's own direct section (never clobber an existing
    # explicit value), then append the unix_sockets sub-table + entry at
    # the end of the network table's own "group" section (next header
    # anywhere after it that is NOT itself a network.* sub-table header —
    # mirrors the main-header group-section scan below).
    net_direct_end = len(lines)
    for idx in range(net_header_idx + 1, len(lines)):
        if lines[idx].strip().startswith("["):
            net_direct_end = idx
            break
    has_enabled = any(
        ENABLED_RE.match(l) for l in lines[net_header_idx + 1:net_direct_end]
    )
    if has_enabled:
        messages.append("network_already_set")
    else:
        lines = lines[:net_header_idx + 1] + ["enabled = true"] + lines[net_header_idx + 1:]
        messages.append("network_added")

    net_group_end = len(lines)
    for idx in range(net_header_idx + 1, len(lines)):
        stripped_line = lines[idx].strip()
        if stripped_line.startswith("[") and not stripped_line.startswith("[permissions.thrum-workspace.network."):
            net_group_end = idx
            break

    lines = lines[:net_group_end] + ["[permissions.thrum-workspace.network.unix_sockets]", sock_line] + lines[net_group_end:]
    messages.append("added_socket")
else:
    # Neither the network table nor the unix_sockets sub-table exists
    # anywhere in the file. Append a fresh block at the end of the MAIN
    # table's own "group" section (mirrors the filesystem-grant "header
    # exists, sub-table doesn't" branch above). By this point in the same
    # python3 pass, the filesystem-grant step (run first, above) has
    # already ensured the main header exists on every path that reaches
    # here — if it somehow still doesn't, that's a bug in the ordering
    # between the two steps, not something to paper over by silently
    # inventing a second main-header block here (which risks a duplicate
    # header the filesystem step doesn't know about); fail loudly instead.
    header_idx = find_header(MAIN_HEADER_RE)
    if header_idx is None:
        print(
            "ERROR: [permissions.thrum-workspace] header missing after "
            "filesystem-grant step; this indicates a bug in "
            "ensure-permission-profile.sh, not a valid config state.",
            file=sys.stderr,
        )
        sys.exit(1)

    section_end = len(lines)
    for idx in range(header_idx + 1, len(lines)):
        stripped_line = lines[idx].strip()
        if stripped_line.startswith("[") and not stripped_line.startswith("[permissions.thrum-workspace."):
            section_end = idx
            break

    lines = lines[:section_end] + [
        "[permissions.thrum-workspace.network]",
        "enabled = true",
        "",
        "[permissions.thrum-workspace.network.unix_sockets]",
        sock_line,
    ] + lines[section_end:]
    messages.append("network_added")
    messages.append("added_socket")

new_content = "\n".join(lines)
if not new_content.endswith("\n"):
    new_content += "\n"

# Write atomically: create a temp file in the SAME directory as the target
# (guarantees the same filesystem, so the rename below is atomic), then
# os.replace() over the target. Preserves the original file's permissions
# when it already existed.
config_dir = os.path.dirname(config_path) or "."
orig_mode = None
if os.path.exists(config_path):
    orig_mode = os.stat(config_path).st_mode

tmp_fd, tmp_path = tempfile.mkstemp(dir=config_dir, suffix=".tmp")
try:
    with os.fdopen(tmp_fd, "w") as f:
        f.write(new_content)
    if orig_mode is not None:
        os.chmod(tmp_path, orig_mode)
    os.replace(tmp_path, config_path)
except BaseException:
    try:
        os.remove(tmp_path)
    except OSError:
        pass
    raise

for m in messages:
    print(m)
PY
)
py_status=$?
if [[ ${py_status} -ne 0 ]]; then
  err "failed to update ${CODEX_CONFIG}"
  exit 1
fi

if [[ -n "${PY_OUT}" ]]; then
  while IFS= read -r msg; do
    [[ -z "${msg}" ]] && continue
    case "${msg}" in
      already_set:*)
        key="${msg#already_set:}"
        say "${key} already set in ${CODEX_CONFIG}; leaving as-is."
        ;;
      already_present)
        say "thrum-workspace permission already present for ${audit_dir}; leaving as-is."
        ;;
      added_block)
        say "added [permissions.thrum-workspace] block for ${audit_dir} to ${CODEX_CONFIG}."
        ;;
      added_path)
        say "added ${audit_dir} to existing [permissions.thrum-workspace] profile in ${CODEX_CONFIG}."
        ;;
      already_present_thrum_read)
        say "thrum-workspace read grant already present for ${resolved_thrum_dir}; leaving as-is."
        ;;
      added_thrum_read)
        say "added ${resolved_thrum_dir} read grant to [permissions.thrum-workspace.filesystem] in ${CODEX_CONFIG}."
        ;;
      already_present_codex_skills_read)
        say "thrum-workspace read grant already present for ${codex_skills_dir}; leaving as-is."
        ;;
      added_codex_skills_read)
        say "added ${codex_skills_dir} read grant to [permissions.thrum-workspace.filesystem] in ${CODEX_CONFIG}."
        ;;
      already_present_codex_plugin_cache_read)
        say "thrum-workspace read grant already present for ${codex_plugin_cache_dir}; leaving as-is."
        ;;
      added_codex_plugin_cache_read)
        say "added ${codex_plugin_cache_dir} read grant to [permissions.thrum-workspace.filesystem] in ${CODEX_CONFIG}."
        ;;
      already_present_tmp_exception_read)
        say "thrum-workspace read grant already present for ${tmp_exception_dir}; leaving as-is."
        ;;
      added_tmp_exception_read)
        say "added owner-authorized ${tmp_exception_dir} read grant to [permissions.thrum-workspace.filesystem] in ${CODEX_CONFIG}."
        ;;
      already_present_local_bin_read)
        say "thrum-workspace read grant already present for ${local_bin_dir}; leaving as-is."
        ;;
      added_local_bin_read)
        say "added ${local_bin_dir} read grant to [permissions.thrum-workspace.filesystem] in ${CODEX_CONFIG}."
        ;;
      already_present_socket)
        say "thrum-workspace network.unix_sockets grant already present for ${socket_path}; leaving as-is."
        ;;
      added_socket)
        say "added ${socket_path} to [permissions.thrum-workspace.network.unix_sockets] in ${CODEX_CONFIG}."
        ;;
      network_already_set)
        say "network.enabled already set in ${CODEX_CONFIG}; leaving as-is."
        ;;
      network_added)
        say "added network.enabled = true to [permissions.thrum-workspace.network] in ${CODEX_CONFIG}."
        ;;
    esac
  done <<< "${PY_OUT}"
fi

say "✓ thrum-workspace permission profile ensured for: ${audit_dir}"
say "✓ thrum-workspace network.unix_sockets grant ensured for: ${socket_path}"
say "✓ thrum-workspace read grant ensured for: ${resolved_thrum_dir}"
say "✓ thrum-workspace read grant ensured for: ${codex_skills_dir}"
say "✓ thrum-workspace read grant ensured for: ${codex_plugin_cache_dir}"
say "✓ thrum-workspace read grant (owner-authorized exception) ensured for: ${tmp_exception_dir}"
say "✓ thrum-workspace read grant ensured for: ${local_bin_dir}"
exit 0
