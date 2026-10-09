#!/bin/bash
# PreToolUse hook: protect the per-daemon CA private keys.
#
# .thrum/var/tls/ holds the daemon's self-sovereign CA: ca.key (root, ~10y) and
# leaf.key (~90d). These are SECRETS — peers pin the root, and possession of
# ca.key lets an attacker impersonate this daemon to every paired peer. They
# must never enter git (the event JSONL bundle must stay secret-free so the
# v0.12 push-bundle deploy stays possible) and must never leave the machine.
#
# A guard that keys on the mere PRESENCE of a path string blocks legitimate
# commands (docs, memory writes, grep) that just mention the path — this guard
# instead matches the ACTUAL DANGEROUS OPERATION SHAPE, never bare path-string
# presence:
#   1. git add/commit STAGING a path under .thrum/var/tls/  (not a -m message
#      that merely mentions it — the quote boundary is excluded).
#   2. a READ of a CA *.key PIPED into a network/transmit command, AND the
#      command actually references the CA material (tls path or ca/leaf.key) —
#      so `cat myapp.key | curl` (an unrelated key) is NOT blocked.
#
# Repair exception: the agent NEVER auto-handles the private key. For a CA
# restore it emits the file-copy (never-git) commands for the user to run.
#
# Allowed: reading/grepping/mentioning the path for docs or memory; `git add`
# of unrelated source paths; transmitting unrelated *.key files.
#
# Missing dependency or unusable input: if jq is not on PATH, or the hook input
# cannot be read or parsed, is not exactly one JSON document, or has no tool_name,
# this hook ALLOWS the command (exit 0) and prints one line naming the problem on
# stderr. It does not block: a box without jq must still be able to run
# commands, and a guard that cannot read its input cannot judge it. Inside the
# guard (pattern matching) the opposite holds: if it cannot evaluate, it blocks.
set -euo pipefail

# allow_unchecked <reason>: allow the command, loudly and exactly once (exit 0 ends
# the hook, so the line cannot repeat). printf, not a heredoc: no temp file.
allow_unchecked() {
  printf '%s\n' "${0##*/}: $1; this guard is NOT checking the command (allowing it)" >&2
  exit 0
}
if ! command -v jq >/dev/null 2>&1; then
  cat >/dev/null 2>&1 || true   # drain stdin so the writer does not get EPIPE
  allow_unchecked "jq not found on PATH (install it: apt install jq / dnf install jq / apk add jq / brew install jq)"
fi

# With fd 0 closed, bash reuses it for the $(...) pipe and `cat` would hang: point it
# at /dev/null first so a closed stdin reads as empty input.
if { exec 3<&0; } 2>/dev/null; then exec 3<&-; else exec 0</dev/null; fi
input=$(cat) || allow_unchecked "cannot read the hook input"
case "$input" in
  *[![:space:]]*) : ;;
  *) allow_unchecked "the hook input is empty" ;;
esac

tool_name=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null) || allow_unchecked "jq could not parse the hook input"
# Exactly one JSON value with a tool_name, else allow loudly: a missing tool_name or a
# first non-Bash document would otherwise be a silent allow.
ndocs=$(echo "$input" | jq -s 'length' 2>/dev/null) || allow_unchecked "jq could not parse the hook input"
[ "$ndocs" = 1 ] || allow_unchecked "the hook input is not exactly one JSON document"
[ -n "$tool_name" ] || allow_unchecked "the hook input has no tool_name"
# Case-insensitive: Muse reports its shell tool as lowercase `bash`.
case "$tool_name" in [Bb]ash) ;; *) exit 0 ;; esac

command=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || allow_unchecked "jq could not parse the hook input"
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
  # printf, not a heredoc: a heredoc needs a temp file on bash < 5.1, and if it cannot be
  # created `set -e` exits 1, which is NOT a block (only 2 blocks), so the guard would
  # allow exactly when it should deny.
  printf '%s\n' "{
  \"hookSpecificOutput\": {
    \"permissionDecision\": \"deny\"
  },
  \"systemMessage\": \"BLOCKED: $1 The per-daemon CA private keys under .thrum/var/tls/ are secrets — possession of ca.key lets an attacker impersonate this daemon to every paired peer. They must never enter git or leave the machine. For a CA restore, emit the file-copy (NEVER git) commands for the user to run manually — keep your hands off the key.\"
}" >&2
  exit 2
}

# guard_matches <ERE>: exit 0 = $command matches on some line, 1 = no match.
# Feeds grep through process substitution, NOT `echo | grep -q` (grep -q exits
# at the first match; on a large command echo died on SIGPIPE and, under
# pipefail, the guard silently ALLOWED it) and NOT a here-string
# (that needs a temp file on bash < 5.1, so an uncreatable temp file made the
# redirection fail and the guard allow). Process substitution uses /dev/fd, no
# temp file, and keeps grep's per-line ERE semantics. It uses `grep -c` (reads
# all input, prints a count either way) so "grep did not run at all" -- a failed
# redirection or fork also exits 1, exactly like "no match" -- is told apart
# from "no match" by the missing count. If the guard cannot evaluate the command
# it BLOCKS with a clear message; it never silently allows.
guard_matches() {
  local cnt="" rc=0
  exec 3< <(printf '%s\n' "$command") \
    || deny "The guard could not read the command to check it (internal error), so it is blocked."
  cnt=$(grep -cE "$1" <&3) && rc=0 || rc=$?
  exec 3<&-
  case "$cnt" in
    '' | *[!0-9]*) deny "The guard could not evaluate the command (grep produced no result), so it is blocked." ;;
  esac
  [ "$rc" -le 1 ] \
    || deny "The guard could not evaluate the command (grep error $rc), so it is blocked."
  [ "$cnt" -gt 0 ]
}

# 1. Staging CA material into git: `git [flags] add|stage|commit ... <path under
#    .thrum/var/tls/>`. The [^;&|"'] bridge stops at a quote, so a commit whose
#    -m MESSAGE merely mentions the path is NOT matched (op-shape, not presence).
# Match via guard_matches (above), not `echo "$command" | grep -q`.
if guard_matches "${CMDPOS}git[[:space:]]+([^;&|\"']*[[:space:]]+)?(add|stage|commit)[^;&|\"']*${TLS_PATH}"; then
  deny "Staging CA key material under .thrum/var/tls/ into git is forbidden."
fi

# 2. Exfiltration: a read of a CA *.key piped into a network/transmit command.
#    Require BOTH (a) the read->pipe->transmit shape AND (b) the command actually
#    references CA material, so an unrelated `cat app.key | curl` is allowed.
READ_PIPE_TRANSMIT='(cat|head|tail|dd|xxd|base64|od|strings|less|more)[^|]*\.key[^|]*\|[[:space:]]*(thrum[[:space:]]+send|curl|wget|nc|ncat|netcat|ssh|scp|sftp|mail|mailx|sendmail|telnet)'
REFERENCES_CA="${TLS_PATH}|(^|[[:space:]/])(ca|leaf)\.key"
if guard_matches "$READ_PIPE_TRANSMIT" && guard_matches "$REFERENCES_CA"; then
  deny "Piping a CA private key into a network/transmit command is forbidden (exfiltration guard)."
fi

exit 0
