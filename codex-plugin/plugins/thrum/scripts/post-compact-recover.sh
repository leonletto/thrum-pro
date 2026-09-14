#!/usr/bin/env bash
# Post-compaction self-message: read the agent's own identity file to find
# its ID and send it a `thrum` message naming its restart snapshot.
#
# Owner requirement: "the
# post-compact hook should read the identity file to find the agent's ID and
# send the agent a thrum message saying: You've been compacted. Please read
# your snapshot. It runs within the agent's worktree so this can work
# reliably." — i.e. resolve the ID from the LOCAL identity file, not a live
# `thrum whoami` RPC round-trip, since a compaction-time hook may fire when a
# round-trip is less reliable than a local file read.
#
# NOT CURRENTLY WIRED into hooks.json: Codex's plugin manifest
# (codex-plugin/plugins/thrum/hooks/hooks.json) has no `PostCompact` event —
# it only wires SessionStart (matcher "startup|resume|clear|compact"),
# PreToolUse, and Stop. Codex's own compaction signal already flows through
# SessionStart's "compact" source into inject-prime-context.sh (see that
# script's LIGHT_MODE branch), which is a SEPARATE concern (re-priming
# context) from this self-message step. This script is the direct logic
# mirror of claude-plugin/scripts/post-compact-recover.sh's new self-message
# step, kept here for parity and direct-invocation testing so the two
# runtimes' behavior doesn't drift; it becomes wireable the moment Codex
# adds an equivalent lifecycle hook. Confirm this gap still holds before
# assuming it is dead code.
#
# -e intentionally omitted: external commands use || true guards, matching
# the rest of this plugin's scripts.
set -uo pipefail

# Codex hook payloads carry `cwd` on stdin (see stop-check-messages.sh for
# the same pattern); THRUM_HOME overrides it when set. Falls back to "." so
# direct invocation (tests) without stdin JSON still works.
INPUT=$(cat 2>/dev/null || true)
HOOK_CWD="."
if command -v jq >/dev/null 2>&1; then
  HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // "."' 2>/dev/null || echo ".")
fi
THRUM_DIR="${THRUM_HOME:-$HOOK_CWD}"

IDENTITIES_DIR="$THRUM_DIR/.thrum/identities"
IDENTITY_AGENT_ID=""
if command -v jq >/dev/null 2>&1 && [ -d "$IDENTITIES_DIR" ]; then
  for _id_file in "$IDENTITIES_DIR"/*.json; do
    [ -f "$_id_file" ] || continue
    _name=$(jq -r '.agent.Name // empty' "$_id_file" 2>/dev/null || true)
    if [ -n "$_name" ]; then
      IDENTITY_AGENT_ID="$_name"
      break
    fi
  done
fi

if [ -z "$IDENTITY_AGENT_ID" ]; then
  echo "post-compact-recover: no identity file found under $IDENTITIES_DIR — skipping self-message." >&2
  exit 0
fi

# Defensive backtick strip, matching inject-prime-context.sh's AGENT_ID
# hardening (the identity validator already blocks backticks upstream).
IDENTITY_AGENT_ID="${IDENTITY_AGENT_ID//\`/}"

# Mirror inject-prime-context.sh's snapshot-path convention:
# <worktree>/.thrum/restart/<agent_id>.md
COMPACT_SNAPSHOT="$THRUM_DIR/.thrum/restart/${IDENTITY_AGENT_ID}.md"

if [ -s "$COMPACT_SNAPSHOT" ]; then
  # Quoted heredoc ('MSGEOF') — no command substitution ever runs on this
  # body. The dynamic snapshot path is spliced in afterward via plain
  # parameter-expansion string replacement, never by re-opening the heredoc
  # to shell expansion.
  COMPACT_MSG=$(cat <<'MSGEOF'
You've been compacted. Please read your snapshot at __SNAPSHOT_PATH__.
MSGEOF
)
  COMPACT_MSG="${COMPACT_MSG//__SNAPSHOT_PATH__/$COMPACT_SNAPSHOT}"
else
  COMPACT_MSG=$(cat <<'MSGEOF'
You've been compacted. No snapshot found — please re-prime normally.
MSGEOF
)
fi

if command -v thrum >/dev/null 2>&1; then
  if ! printf '%s\n' "$COMPACT_MSG" \
      | thrum send --to "@${IDENTITY_AGENT_ID}" --stdin >/dev/null 2>&1; then
    echo "post-compact-recover: thrum send failed (daemon down?) — continuing." >&2
  fi
else
  echo "post-compact-recover: thrum not on PATH — skipping self-message." >&2
fi

exit 0
