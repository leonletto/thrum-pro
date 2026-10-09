#!/bin/bash
# PreToolUse hook: protect the a-sync JSONL worktree from destruction.
#
# .git/thrum-sync/a-sync/ is a detached git worktree living INSIDE .git/.
# It holds the append-only JSONL event log for thrum message sync.
#
# DANGER: If you check out a different branch in that worktree, git replaces
# its contents — but since it lives inside .git/, this DESTROYS the git object
# store, refs, and config. The entire repo and ALL worktrees are wiped.
#
# Blocked:
#   1. cd/pushd into the a-sync worktree (prevents arbitrary commands there)
#   2. git -C <a-sync-path> with branch-changing commands (checkout, switch,
#      reset, merge, rebase, pull) — these change HEAD without cd
#   3. git --work-tree=<a-sync-path> with branch-changing commands
#
# Allowed:
#   git -C <a-sync-path> add/commit/push/status/rm/log/diff — safe operations
#   ls/cat/grep/rm on absolute paths — no CWD change
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

SYNC_PATTERN='\.git/thrum-sync/a-sync'

# Command-position anchor: line start or immediately after a shell separator
# (;, &&, ||), then optional whitespace. Matches `cd`/`git` only when they are
# the actual command — not when those words appear inside a quoted argument.
# Match op-shape, not mere presence of the path string.
CMDPOS='(^|;|&&|\|\|)\s*'

deny() {
  # printf, not a heredoc: a heredoc needs a temp file on bash < 5.1, and if it cannot be
  # created `set -e` exits 1, which is NOT a block (only 2 blocks), so the guard would
  # allow exactly when it should deny.
  printf '%s\n' "{
  \"hookSpecificOutput\": {
    \"permissionDecision\": \"deny\"
  },
  \"systemMessage\": \"BLOCKED: $1 The .git/thrum-sync/a-sync/ worktree lives INSIDE .git/ — checking out a different branch there DESTROYS the entire git object store, wiping the repo and all worktrees. Use absolute paths with safe operations (ls, grep, rm, git -C ... add/commit/push) instead.\"
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

# 1. Block cd/pushd/chdir into the a-sync worktree (command-position only)
# Match via guard_matches (above), not `echo "$command" | grep -q`.
if guard_matches "${CMDPOS}(cd|pushd|chdir)\s+['\"]?[^[:space:]]*${SYNC_PATTERN}"; then
  deny "Changing directory into .git/thrum-sync/a-sync/ is forbidden."
fi

# 2. Block git -C <a-sync-path> with branch-changing commands
if guard_matches "${CMDPOS}git\s+(-C\s+['\"]?[^[:space:]]*${SYNC_PATTERN}['\"]?\s+)(checkout|switch|reset|merge|rebase|pull)\b"; then
  deny "Branch-changing git operations on the a-sync worktree are forbidden."
fi

# 3. Block git --work-tree=<a-sync-path> with branch-changing commands
if guard_matches "${CMDPOS}git\s+(--work-tree[= ]['\"]?[^[:space:]]*${SYNC_PATTERN}['\"]?\s+).*(checkout|switch|reset|merge|rebase|pull)\b"; then
  deny "Branch-changing git operations on the a-sync worktree are forbidden."
fi

# 4. Block git --git-dir=<a-sync-path> with branch-changing commands
if guard_matches "${CMDPOS}git\s+(--git-dir[= ]['\"]?[^[:space:]]*${SYNC_PATTERN}['\"]?\s+).*(checkout|switch|reset|merge|rebase|pull)\b"; then
  deny "Branch-changing git operations on the a-sync worktree are forbidden."
fi
