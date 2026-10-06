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

# jq is optional for this hook (every use below is guarded), but without it the
# hook cwd and identity self-message are skipped, so say so once instead of
# skipping silently.
if ! command -v jq >/dev/null 2>&1; then
  echo "thrum post-compact-recover.sh: jq was not found on PATH; hook cwd and identity self-message are SKIPPED. Install jq (apt install jq / brew install jq)." >&2
fi

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
# thrum-xyz: the SessionStart prime MOVES that file into the MAIN repo's
# .thrum/agents/<id>/sessions/<ts>-restart.md, so by the time this hook runs
# the restart/ copy is normally gone. Resolve what exists AT NUDGE TIME and
# name that exact path. A still-present restart/ file is the freshest (an
# archived copy is always older), so it wins; otherwise the newest archived
# copy. Best-effort: every command is guarded so set -e can never abort.
COMPACT_SNAPSHOT=""
_restart_file="$THRUM_DIR/.thrum/restart/${IDENTITY_AGENT_ID}.md"
if [ -s "$_restart_file" ]; then
  COMPACT_SNAPSHOT="$_restart_file"
else
  # A worktree's .thrum/redirect names the main repo's .thrum directory.
  _main_thrum="$THRUM_DIR/.thrum"
  if [ -f "$THRUM_DIR/.thrum/redirect" ]; then
    _redir=$(head -n 1 "$THRUM_DIR/.thrum/redirect" 2>/dev/null | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' || true)
    # A relative redirect resolves against the worktree root, not the hook's cwd.
    case "$_redir" in ""|/*) ;; *) _redir="$THRUM_DIR/$_redir" ;; esac
    if [ -n "$_redir" ] && [ -d "$_redir" ]; then _main_thrum="$_redir"; fi
  fi
  _sessions_dir="$_main_thrum/agents/${IDENTITY_AGENT_ID}/sessions"
  if [ -d "$_sessions_dir" ]; then
    _newest=$(ls -1t "$_sessions_dir"/*-restart.md 2>/dev/null | head -n 1 || true)
    if [ -n "$_newest" ] && [ -s "$_newest" ]; then COMPACT_SNAPSHOT="$_newest"; fi
  fi
fi

if [ -n "$COMPACT_SNAPSHOT" ]; then
  # Quoted heredoc ('MSGEOF') — no command substitution ever runs on this
  # body. The dynamic snapshot path is spliced in afterward via plain
  # parameter-expansion string replacement, never by re-opening the heredoc
  # to shell expansion.
  COMPACT_MSG=$(cat <<'MSGEOF'
You've been compacted. Please read your snapshot at __SNAPSHOT_PATH__ (use the Read tool).
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

# Pane nudge: the daemon nudges a pane only when an ordinary message arrives
# for it; a compaction event produces no message, so without this the pane
# can sit idle after compacting even though the self-message above may have
# been sent. This script has no single-agent-mode / AGENT_ID / tmux-managed
# early exits of its own (see the NOT-CURRENTLY-WIRED note at the top), so
# there is nothing else here to place it before — it simply runs after the
# self-message step, unconditionally, mirroring the equivalent point in
# claude-plugin/scripts/post-compact-recover.sh (before that script's
# single-agent/AGENT_ID/tmux-managed-skip exits). Resolved independently of
# THRUM_AGENT_ID / THRUM_NAME (a hook may run without either set) via a
# plain `thrum whoami` call, which resolves identity from THRUM_HOME/cwd on
# its own since this hook runs inside the agent's own worktree.
#
# Best-effort and fully guarded: if `thrum` is missing or the tmux session
# can't be resolved, the whole block is skipped silently. De-duplication
# uses an atomic `mkdir` lock rather than a time-window check (simpler, no
# arithmetic, portable): a near-simultaneous second hook firing for the same
# session finds the lock dir already there and skips; the backgrounded
# subshell removes the lock once its nudge attempt finishes, so a later,
# genuinely separate compaction can still nudge again.
NUDGE_TMUX_SESSION=$(thrum whoami --field tmux_session 2>/dev/null) || NUDGE_TMUX_SESSION=""
NUDGE_TMUX_SESSION="${NUDGE_TMUX_SESSION%%:*}"

if [ -n "$NUDGE_TMUX_SESSION" ] && command -v thrum >/dev/null 2>&1; then
  NUDGE_VAR_DIR="$THRUM_DIR/.thrum/var"
  mkdir -p "$NUDGE_VAR_DIR" 2>/dev/null || true
  NUDGE_LOCK_DIR="$NUDGE_VAR_DIR/${NUDGE_TMUX_SESSION}-postcompact-nudge.lock"
  if [ -d "$NUDGE_LOCK_DIR" ]; then
    # A lock older than ~1 minute means the backgrounded job that created it
    # died before it could clean up (OOM-kill, tmux kill-server, reboot) --
    # without this reap, every future nudge for this session name would
    # silently no-op forever since mkdir keeps failing.
    if [ -n "$(find "$NUDGE_LOCK_DIR" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
      rm -r "${NUDGE_LOCK_DIR:?}" 2>/dev/null || true
    fi
  fi
  if mkdir "$NUDGE_LOCK_DIR" 2>/dev/null; then
    ( sleep "${THRUM_POSTCOMPACT_NUDGE_DELAY:-10}"
      thrum tmux send "$NUDGE_TMUX_SESSION" "Compaction complete - please continue with your resume plan" >/dev/null 2>&1 || true
      rm -r "${NUDGE_LOCK_DIR:?}" 2>/dev/null || true
    ) >/dev/null 2>&1 &
    disown 2>/dev/null || true
  fi
fi

exit 0
