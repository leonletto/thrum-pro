#!/bin/bash
# beforeShellExecution hook: protect the per-daemon CA private keys (D5 exfil guard).
#
# .thrum/var/tls/ holds the daemon's self-sovereign CA: ca.key (root, ~10y) and
# leaf.key (~90d). These are SECRETS — peers pin the root, and possession of
# ca.key lets an attacker impersonate this daemon to every paired peer. They
# must never enter git (the event JSONL bundle must stay secret-free so the
# v0.12 push-bundle deploy stays possible) and must never leave the machine.
#
# DESIGN LESSON (observed live 2026-06-04, brainstorm D5 L86): the sibling
# block-sync-worktree-cd.sh hook false-positived on a benign `bd remember` whose
# TEXT merely contained a protected path next to "cd". A guard that keys on the
# mere PRESENCE of a path string blocks legitimate commands (docs, memory
# writes, grep) that just mention the path. So this guard matches the ACTUAL
# DANGEROUS OPERATION SHAPE, never bare path-string presence:
#   1. git add/commit STAGING a path under .thrum/var/tls/  (not a -m message
#      that merely mentions it — the quote boundary is excluded).
#   2. a READ of a CA *.key PIPED into a network/transmit command, AND the
#      command actually references the CA material (tls path or ca/leaf.key) —
#      so `cat myapp.key | curl` (an unrelated key) is NOT blocked.
#
# Repair exception (D5): the agent NEVER auto-handles the private key. For a CA
# restore it emits the file-copy (never-git) commands for the user to run.
set -euo pipefail

input=$(cat)

# Cursor Agent beforeShellExecution: try both Cursor's format and Claude's format
# Cursor may provide the command as .command or .tool_input.command
command=$(echo "$input" | jq -r '.tool_input.command // .command // empty')
[ -n "$command" ] || exit 0

TLS_PATH='\.thrum/var/tls/'
# Command-position anchor: line start or immediately after a shell separator —
# so "git"/"add" appearing as a word inside a quoted argument is not matched.
# Accepted trade-off: a wrapper prefix (`sudo git ...`, `env X=Y git ...`,
# `xargs git ...`) is NOT matched, so those bypass this check. That is fine —
# this guard is defense-in-depth against the COMMON accidental shape; the
# primary defenses are the scoped .gitignore (keeps the keys untracked) and the
# 0600 file perms. Loosening the anchor to chase wrapper prefixes would
# re-introduce the bare-space false-positive this anchor exists to kill.
CMDPOS='(^|[;&|])[[:space:]]*'

deny() {
  cat >&2 <<EOF
{
  "hookSpecificOutput": {
    "permissionDecision": "deny"
  },
  "systemMessage": "BLOCKED: $1 The per-daemon CA private keys under .thrum/var/tls/ are secrets — possession of ca.key lets an attacker impersonate this daemon to every paired peer. They must never enter git or leave the machine. For a CA restore, emit the file-copy (NEVER git) commands from daemontls.RestoreCommands for the user to run manually — keep your hands off the key."
}
EOF
  exit 2
}

# 1. Staging CA material into git: `git [flags] add|stage|commit ... <path under
#    .thrum/var/tls/>`. The [^;&|"'] bridge stops at a quote, so a commit whose
#    -m MESSAGE merely mentions the path is NOT matched (op-shape, not presence).
if echo "$command" | grep -qE "${CMDPOS}git[[:space:]]+([^;&|\"']*[[:space:]]+)?(add|stage|commit)[^;&|\"']*${TLS_PATH}"; then
  deny "Staging CA key material under .thrum/var/tls/ into git is forbidden."
fi

# 2. Exfiltration: a read of a CA *.key piped into a network/transmit command.
#    Require BOTH (a) the read->pipe->transmit shape AND (b) the command actually
#    references CA material, so an unrelated `cat app.key | curl` is allowed.
READ_PIPE_TRANSMIT='(cat|head|tail|dd|xxd|base64|od|strings|less|more)[^|]*\.key[^|]*\|[[:space:]]*(thrum[[:space:]]+send|curl|wget|nc|ncat|netcat|ssh|scp|sftp|mail|mailx|sendmail|telnet)'
REFERENCES_CA="${TLS_PATH}|(^|[[:space:]/])(ca|leaf)\.key"
if echo "$command" | grep -qE "$READ_PIPE_TRANSMIT" && echo "$command" | grep -qE "$REFERENCES_CA"; then
  deny "Piping a CA private key into a network/transmit command is forbidden (exfiltration guard)."
fi

exit 0
