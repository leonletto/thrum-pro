#!/usr/bin/env bash
# SessionStart hook: inject `thrum prime` output into the agent's context.
#
# Emits the assembled banner+directive+briefing as plain stdout. Claude
# Code routes hook stdout through a size-gated path: small outputs
# (<~2KB) become inline `<system-reminder>` blocks delivered straight to
# the model; larger outputs get persisted to a `tool-results/<id>.txt`
# file with only the first ~2KB previewed inline (and a
# `<persisted-output>` wrapper showing the full file path).
#
#   - Uses plain stdout, not hookSpecificOutput.additionalContext —
#     Claude Code silently ignores that field for SessionStart hooks
#     (it lands in attachment.stdout, never attachment.additionalContext).
#   - A size-aware MUST-READ directive in hook stdout is not reliable —
#     system-reminder framing is treated as advisory, not imperative,
#     so agents rationalize deferring the Read.
#   - The MUST-READ directive moved to the daemon-emitted pane-typed
#     identity banner — that channel routes through the same input
#     path as user prompts, which the model treats more imperatively.
#
# Hook-level timeout is enforced by plugin.json; this script does not
# need a portable `timeout` wrapper.
#
# Output ordering for a registered agent (top → bottom):
#   1. Identity banner — agent / role / worktree / branch / module.
#      Always first; renders inside the 2KB preview.
#   2. Directive — single "auto-loaded, do not re-prime" message.
#      Always second so it lands inside the 2KB preview.
#   3. First-turn ack instruction — tells the agent to
#      emit a one-line ack as the first action of its turn. Produces
#      visible scrollback so humans can distinguish a healthy launch
#      from a stuck or failed one without probing. Pre-fills agent /
#      role / module from the captured whoami so only <intent> is
#      left to the agent.
#   4. Restart-snapshot preamble (existing). Hoisted only when the
#      briefing carries a `# Previous Session Context` block.
#   5. Briefing envelope + full prime output.

set -uo pipefail

# Project doesn't use thrum — silent no-op.
if ! command -v thrum >/dev/null 2>&1; then
  exit 0
fi

# Capture whoami JSON ONCE, extract identity fields downstream.
# Keeping the RPC count at one preserves session-start latency.
WHOAMI_JSON=""
AGENT_ID=""
if command -v jq >/dev/null 2>&1; then
  WHOAMI_JSON=$(thrum whoami --json 2>/dev/null || true)
  AGENT_ID=$(printf '%s' "$WHOAMI_JSON" \
    | jq -r 'select(.agent_id != null) | .agent_id // empty' 2>/dev/null \
    || true)
fi

if [ -z "$AGENT_ID" ]; then
  # No agent registered — preserve historical nudge so the user/agent
  # knows to prime manually after registration.
  echo "Run /thrum:prime to load your session context, identity, and any restart snapshots."
  exit 0
fi

# Extract additional banner fields. Each is best-effort: a missing
# field just renders as "unknown" in the banner, never aborts the hook.
AGENT_ROLE=$(printf '%s' "$WHOAMI_JSON" | jq -r '.role // empty' 2>/dev/null || true)
AGENT_WORKTREE=$(printf '%s' "$WHOAMI_JSON" | jq -r '.worktree // empty' 2>/dev/null || true)
AGENT_BRANCH=$(printf '%s' "$WHOAMI_JSON" | jq -r '.branch // empty' 2>/dev/null || true)
AGENT_MODULE=$(printf '%s' "$WHOAMI_JSON" | jq -r '.module // empty' 2>/dev/null || true)

# Strip any backticks from identity fields before interpolating into
# the markdown inline-code span in ACK_INSTRUCTION below — the
# identity validator blocks backticks upstream, so this is pure
# defensive hardening.
AGENT_ID="${AGENT_ID//\`/}"
AGENT_ROLE="${AGENT_ROLE//\`/}"
AGENT_MODULE="${AGENT_MODULE//\`/}"

PRIME_OUTPUT=$(thrum prime 2>/dev/null || true)

if [ -z "$PRIME_OUTPUT" ]; then
  # Prime failed (daemon down, slow, etc.) — fall back to the manual
  # nudge so session start never blocks on a broken thrum.
  echo "Run /thrum:prime to load your session context, identity, and any restart snapshots."
  echo "(Auto-injection failed — daemon may be unreachable. Run \`thrum daemon status\` to check.)"
  exit 0
fi

# Two-phase build: assemble BANNER, RESTART_PREAMBLE, and BRIEFING into
# separate variables, total their byte count, then choose the
# size-appropriate directive and emit in the canonical order.
append_to() { local _name="$1"; shift; printf -v "$_name" '%s%s' "${!_name}" "$1"; }

# 1. Identity banner — always first; lands in the 2KB preview.
BANNER=""
append_to BANNER "# 🎯 You are: @${AGENT_ID}"$'\n'
append_to BANNER $'\n'
append_to BANNER "- **Role:** ${AGENT_ROLE:-unknown}"$'\n'
append_to BANNER "- **Worktree:** ${AGENT_WORKTREE:-unknown}"$'\n'
append_to BANNER "- **Branch:** ${AGENT_BRANCH:-unknown}"$'\n'
if [ -n "$AGENT_MODULE" ] && [ "$AGENT_MODULE" != "$AGENT_ROLE" ]; then
  append_to BANNER "- **Module:** ${AGENT_MODULE}"$'\n'
fi
append_to BANNER $'\n---\n\n'

# 4. Restart-snapshot preamble (if `thrum prime` carries a Previous
# Session Context block).
#
# This is a SHORT top-of-context POINTER only — it hoists the alert so the
# agent sees it first. The substantive banner lives once, in-body, in the
# "# Previous Session Context" section emitted by `thrum prime` — keeping
# the full prose in both places duplicates lines into every restart briefing.
RESTART_PREAMBLE=""
if printf '%s' "$PRIME_OUTPUT" | grep -q '^# Previous Session Context'; then
  append_to RESTART_PREAMBLE '# 🛑 ACTION REQUIRED — you left yourself a Resume Plan'$'\n'
  append_to RESTART_PREAMBLE $'\n'
  append_to RESTART_PREAMBLE 'Before anything else, go to the **`# Previous Session Context`** section below, read its **`## Resume Plan`** in full, and execute the numbered steps in order — the full instructions are in that section.'$'\n'
  append_to RESTART_PREAMBLE $'\n'
  append_to RESTART_PREAMBLE '> ⚠️ **If this briefing was persisted to a `tool-results/*.txt` file instead of delivered inline, read it with the `Read` tool (use `offset`/`limit` to page through it) — NOT with `sed`, `grep`, `head`, `tail`, or `cat` via Bash.**'$'\n'
  append_to RESTART_PREAMBLE '>'$'\n'
  append_to RESTART_PREAMBLE '> Those paths live under `~/.claude/projects/**`, which the runtime treats as SENSITIVE. A Bash read of them raises a human permission prompt — misdescribed as a request to *edit* a sensitive file, even for a read-only `sed -n ...p` — and **the restart stalls there until a human answers.** Permission `allow` rules do NOT clear it: `Bash`, `Read`, `Edit` and path-scoped `Read(//Users/.../projects/**)` rules can all be present and the prompt still fires, because the gate is the sensitive-path check, not the permission-rule system. The `Read` tool is not subject to it. **Use `Read`.**'$'\n'
  append_to RESTART_PREAMBLE $'\n---\n\n'
fi

# 4. Briefing envelope + full prime output.
BRIEFING=""
append_to BRIEFING '# Thrum Session Briefing (auto-loaded)'$'\n'
append_to BRIEFING $'\n'
append_to BRIEFING 'The complete `thrum prime` output is included below. You do NOT need to run `/thrum:prime` or `thrum prime` again this session — the briefing is already in your context. Read it in full; the session context section at the end is the most important.'$'\n'
append_to BRIEFING $'\n'
append_to BRIEFING 'Only spawn additional commands if the inbox section shows unread messages that need processing.'$'\n'
append_to BRIEFING $'\n---\n\n'
append_to BRIEFING "$PRIME_OUTPUT"$'\n'

# Single directive: agents read this BEFORE the briefing body and act
# on it. The MUST-READ-the-persisted-file directive that previously
# lived here for the large-body case has moved to the daemon-emitted
# pane-typed banner, which is treated more imperatively by the model
# than hook-output system reminders.
DIRECTIVE=""
append_to DIRECTIVE '> ✅ **Context auto-loaded by SessionStart hook.**'$'\n'
append_to DIRECTIVE '>'$'\n'
append_to DIRECTIVE '> **Do NOT run `/thrum:prime` or `thrum prime` — the full briefing is already in your context below.**'$'\n'
append_to DIRECTIVE '> Only invoke them manually if this hook fell through to a degraded "auto-injection failed" notice.'$'\n'
append_to DIRECTIVE $'\n'

# First-turn ack. Tells the agent to emit one visible
# plain-text line before any tool calls so tmux pane scrollback shows
# a clear launch signal. Identity fields are pre-filled from whoami;
# the agent only fills <intent> from inbox or restart snapshot.
ACK_INSTRUCTION=""
if [ -n "$AGENT_MODULE" ] && [ "$AGENT_MODULE" != "$AGENT_ROLE" ]; then
  _ACK_LINE="@${AGENT_ID} primed (${AGENT_ROLE:-unknown}/${AGENT_MODULE}). <intent>. Standing by."
else
  _ACK_LINE="@${AGENT_ID} primed (${AGENT_ROLE:-unknown}). <intent>. Standing by."
fi
append_to ACK_INSTRUCTION '> 📣 **First turn: print a one-line ack to the user.**'$'\n'
append_to ACK_INSTRUCTION '>'$'\n'
append_to ACK_INSTRUCTION '> Before reading the briefing or running any tools, print this single plain-text line — substitute `<intent>` with a brief sentence drawn from your inbox or restart snapshot:'$'\n'
append_to ACK_INSTRUCTION '>'$'\n'
append_to ACK_INSTRUCTION "> \`${_ACK_LINE}\`"$'\n'
append_to ACK_INSTRUCTION '>'$'\n'
append_to ACK_INSTRUCTION '> This produces visible scrollback so humans can distinguish a healthy launch from a stuck or failed one without probing.'$'\n'
append_to ACK_INSTRUCTION $'\n'

# Emit in canonical order: banner → directive → ack → restart preamble →
# briefing. Banner + directive + ack always land inside the 2KB preview.
printf '%s' "$BANNER"
printf '%s' "$DIRECTIVE"
printf '%s' "$ACK_INSTRUCTION"
printf '%s' "$RESTART_PREAMBLE"
printf '%s' "$BRIEFING"
