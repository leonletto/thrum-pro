#!/usr/bin/env bash
# SessionStart hook: inject `thrum prime` output into the agent's context.
#
# Emits the assembled banner+directive+briefing as plain stdout. Codex
# routes SessionStart hook stdout into the agent's initial context.
# Plain stdout is simpler than JSON hookSpecificOutput.additionalContext
# and matches the tested claude pattern. (claude tested additionalContext
# → silently ignored there; codex docs say it works but stdout is simpler.)
#
# Output ordering for a registered agent (top → bottom):
#   1. Identity banner — agent / role / worktree / branch / module
#   2. Directive — single "auto-loaded, do not re-prime" message.
#      Always second so it lands inside the preview.
#   3. First-turn ack instruction — tells the agent to
#      emit a one-line ack as the first action of its turn. Produces
#      visible scrollback so humans can distinguish a healthy launch
#      from a stuck or failed one without probing. Pre-fills agent /
#      role / module from the captured whoami so only <intent> is
#      left to the agent.
#   4. Restart-snapshot preamble (existing). Hoisted only when the
#      briefing carries a `# Previous Session Context` block.
#   5. Briefing envelope + full prime output.

# -e intentionally omitted: external commands use || true guards.
set -uo pipefail

# Capture hook stdin ONCE, before anything else might consume it. Codex
# SessionStart hooks receive a JSON payload on stdin including a
# `source` field (startup|resume|clear|compact) identifying why the
# session started.
HOOK_INPUT=$(cat 2>/dev/null || true)
HOOK_SOURCE=""
if command -v jq >/dev/null 2>&1; then
  HOOK_SOURCE=$(printf '%s' "$HOOK_INPUT" | jq -r '.source // empty' 2>/dev/null || true)
fi

# Project doesn't use thrum — silent no-op.
if ! command -v thrum >/dev/null 2>&1; then
  exit 0
fi

# Capture whoami JSON ONCE, extract identity fields downstream. The
# script ran a single `thrum whoami --json` previously; keeping the
# RPC count at one preserves session-start latency.
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
  echo "Run \$thrum-prime to load your session context, identity, and any restart snapshots."
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

# Compact-triggered session start with a fresh restart snapshot on disk:
# run `thrum prime --light` and feed it through the SAME banner/directive/
# ack/briefing assembly used by the full startup path below (LIGHT_MODE=1
# just swaps a line of prose in the BRIEFING envelope). This used to
# short-circuit with a one-line nudge telling the agent to spend a turn
# reading a file + running a skill — that cost a turn for something the
# hook can now inject directly. Every other case (startup/resume/clear, or
# compact with a stale/missing snapshot) falls through unchanged into the
# full-prime path below.
LIGHT_MODE=0
if [ "$HOOK_SOURCE" = "compact" ] && [ -n "$AGENT_WORKTREE" ]; then
  SNAPSHOT_FILE="${AGENT_WORKTREE}/.thrum/restart/${AGENT_ID}.md"
  if [ -s "$SNAPSHOT_FILE" ] && [ -r "$SNAPSHOT_FILE" ]; then
    SNAPSHOT_MTIME=""
    if command -v stat >/dev/null 2>&1; then
      SNAPSHOT_MTIME=$(stat -c %Y "$SNAPSHOT_FILE" 2>/dev/null || stat -f %m "$SNAPSHOT_FILE" 2>/dev/null || true)
    fi
    if [ -n "$SNAPSHOT_MTIME" ]; then
      NOW=$(date +%s)
      SNAPSHOT_AGE=$((NOW - SNAPSHOT_MTIME))
      # Known limitation: mtime is a PROXY for "this snapshot was written for
      # THIS compaction", not proof of it — a bare /compact fired within 300s
      # of an unrelated /thrum:restart or /thrum:compact write on the same
      # agent will also take the lean path and point at that older snapshot.
      # Same proxy compact.md itself relies on; documented, not fixed here.
      if [ "$SNAPSHOT_AGE" -ge 0 ] && [ "$SNAPSHOT_AGE" -le 300 ]; then
        LIGHT_OUTPUT=$(thrum prime --light 2>/dev/null || true)
        if [ -z "$LIGHT_OUTPUT" ]; then
          # Light prime failed (daemon down, slow, etc.) — degrade to the
          # nudge, never to silence.
          echo "Session resumed after compaction. Read your restart snapshot, then run \$thrum-prime-agent to catch up (inbox + newly-shipped skills) instead of a full \$thrum-prime — auto-injection failed (daemon may be unreachable; check \`thrum daemon status\`)."
          exit 0
        fi
        PRIME_OUTPUT="$LIGHT_OUTPUT"
        LIGHT_MODE=1
      fi
    fi
  fi
fi

if [ "$LIGHT_MODE" -ne 1 ]; then
  PRIME_OUTPUT=$(thrum prime 2>/dev/null || true)

  if [ -z "$PRIME_OUTPUT" ]; then
    # Prime failed (daemon down, slow, etc.) — fall back to the manual
    # nudge so session start never blocks on a broken thrum.
    echo "Run \$thrum-prime to load your session context, identity, and any restart snapshots."
    echo "(Auto-injection failed — daemon may be unreachable. Run \`thrum daemon status\` to check.)"
    exit 0
  fi
fi

# Two-phase build: assemble BANNER, RESTART_PREAMBLE, and BRIEFING into
# separate variables, total their byte count, then choose the
# size-appropriate directive and emit in the canonical order.
append_to() { local _name="$1"; shift; printf -v "$_name" '%s%s' "${!_name}" "$1"; }

# 1. Identity banner — always first; lands in the preview.
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
  append_to RESTART_PREAMBLE '> ⚠️ **If this briefing was persisted to a file instead of delivered inline, read it with your file-reading tool (paging with offset/limit) — NOT with `sed`, `grep`, `head`, `tail`, or `cat` via a shell command.**'$'\n'
  append_to RESTART_PREAMBLE '>'$'\n'
  append_to RESTART_PREAMBLE '> Persisted hook output lives under a runtime-managed state directory that is treated as SENSITIVE. A shell read of it raises a human approval prompt — often misdescribed as a request to *edit* a sensitive file, even for a read-only `sed -n ...p` — and **the restart stalls there until a human answers.** This is the single most common way a coordinator restart dies before it starts. Permission allow-rules do NOT clear it: broad tool allows and path-scoped read rules can all be present and the prompt still fires, because the gate is a sensitive-path check rather than the permission-rule system. The native file-reading tool is not subject to it.'$'\n'
  append_to RESTART_PREAMBLE $'\n---\n\n'
fi

# 4. Briefing envelope + full/light prime output.
# build_directive sets DIRECTIVE for the current TRUNCATED mode.
build_directive() {
  DIRECTIVE=""
  if [ "$TRUNCATED" -eq 1 ]; then
    append_to DIRECTIVE '> ⚠️ **Context partially auto-loaded by SessionStart hook (truncated to fit this runtime'"'"'s hook output cap).**'$'\n'
    append_to DIRECTIVE '>'$'\n'
    append_to DIRECTIVE '> **Run `thrum prime` now to load the rest of your briefing** — the hook output below was cut.'$'\n'
    append_to DIRECTIVE $'\n'
  else
    append_to DIRECTIVE '> ✅ **Context auto-loaded by SessionStart hook.**'$'\n'
    append_to DIRECTIVE '>'$'\n'
    append_to DIRECTIVE '> **Do NOT run `$thrum-prime` or `thrum prime` — the full briefing is already in your context below.**'$'\n'
    append_to DIRECTIVE '> Only invoke them manually if this hook fell through to a degraded "auto-injection failed" notice.'$'\n'
    append_to DIRECTIVE $'\n'
  fi
}

build_briefing_head() {
  BRIEFING=""
  append_to BRIEFING '# Thrum Session Briefing (auto-loaded)'$'\n'
  append_to BRIEFING $'\n'
  if [ "$LIGHT_MODE" -eq 1 ]; then
    append_to BRIEFING 'The **light** `thrum prime --light` output is included below (auto-injected after compaction — the light render omits the full Resume Plan body, replacing it with a pointer to re-run full `thrum prime` if you need it). You do NOT need to run `$thrum-prime`, `thrum prime`, or `$thrum-prime-agent` again this session — the briefing is already in your context. Read it in full.'$'\n'
  elif [ "$TRUNCATED" -eq 1 ]; then
    append_to BRIEFING 'A **truncated** `thrum prime` output is included below — this runtime caps SessionStart hook output, so the tail was cut. Run `thrum prime` yourself for the full briefing (it is NOT already in your context in full).'$'\n'
  else
    append_to BRIEFING 'The complete `thrum prime` output is included below. You do NOT need to run `$thrum-prime` or `thrum prime` again this session — the briefing is already in your context. Read it in full; the session context section at the end is the most important.'$'\n'
  fi
  append_to BRIEFING $'\n'
  append_to BRIEFING 'Only spawn additional commands if the inbox section shows unread messages that need processing.'$'\n'
  append_to BRIEFING $'\n---\n\n'
}

# Single directive: agents read this BEFORE the briefing body and act
# on it.

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

# Runtime hook-output cap. Some runtimes reject the WHOLE hook output when
# stdout exceeds a byte cap (muse: "output_too_large"), which loses the
# banner and identity too. The cap is declared in the runtime preset
# (hook_stdout_cap_bytes) and read here via `thrum runtime hook-cap`; 0 or an
# unresolvable runtime means unlimited. Never hard-code the number here.
HOOK_CAP=$(thrum runtime hook-cap 2>/dev/null || true)
case "$HOOK_CAP" in
  ''|*[!0-9]*) HOOK_CAP=0 ;;
esac

byte_len() { printf '%s' "$1" | wc -c | tr -d '[:space:]'; }

TRUNCATED=0
build_directive
build_briefing_head
FULL_LEN=$(( $(byte_len "$BANNER") + $(byte_len "$DIRECTIVE") + $(byte_len "$ACK_INSTRUCTION") + $(byte_len "$RESTART_PREAMBLE") + $(byte_len "$BRIEFING") + $(byte_len "$PRIME_OUTPUT") + 1 ))
if [ "$HOOK_CAP" -gt 0 ] && [ "$FULL_LEN" -gt "$HOOK_CAP" ]; then
  TRUNCATED=1
  build_directive
  build_briefing_head
  TRUNC_NOTICE=$'\n\n[thrum: hook output truncated to fit this runtime'"'"'s '"${HOOK_CAP}"'-byte cap. Run `thrum prime` for the full briefing.]\n'
  FIXED_LEN=$(( $(byte_len "$BANNER") + $(byte_len "$DIRECTIVE") + $(byte_len "$ACK_INSTRUCTION") + $(byte_len "$RESTART_PREAMBLE") + $(byte_len "$BRIEFING") + $(byte_len "$TRUNC_NOTICE") ))
  BUDGET=$(( HOOK_CAP - FIXED_LEN - 16 ))
  if [ "$BUDGET" -gt 0 ]; then
    # Cut on a line boundary so a multi-byte character is never split: take
    # BUDGET bytes, drop the trailing (possibly partial) line, then drop any
    # stray invalid bytes if iconv is available.
    CUT=$(printf '%s' "$PRIME_OUTPUT" | head -c "$BUDGET")
    if [ "$(byte_len "$CUT")" -lt "$(byte_len "$PRIME_OUTPUT")" ]; then
      CUT_LINES=$(printf '%s\n' "$CUT" | sed '$d')
      [ -n "$CUT_LINES" ] && CUT="$CUT_LINES"
    fi
    if command -v iconv >/dev/null 2>&1; then
      # iconv -c legitimately exits nonzero whenever it drops an incomplete
      # trailing multi-byte sequence -- that is its intended success path
      # here, not a failure. Capture its stdout unconditionally (never gated
      # on `|| fallback`, which would re-run the fallback's own stdout and
      # get it concatenated onto iconv's already-emitted output inside this
      # command substitution, doubling/corrupting the result). Only fall
      # back to the untouched CUT if iconv produced no output at all.
      ICONV_CUT=$(printf '%s' "$CUT" | iconv -c -f UTF-8 -t UTF-8 2>/dev/null)
      [ -n "$ICONV_CUT" ] && CUT="$ICONV_CUT"
    fi
    PRIME_OUTPUT="$CUT"
  else
    PRIME_OUTPUT=""
  fi
  append_to BRIEFING "$PRIME_OUTPUT"
  append_to BRIEFING "$TRUNC_NOTICE"
else
  append_to BRIEFING "$PRIME_OUTPUT"$'\n'
fi

# Emit in canonical order: banner → directive → ack → restart preamble →
# briefing. Banner + directive + ack always land inside the preview.
printf '%s' "$BANNER"
printf '%s' "$DIRECTIVE"
printf '%s' "$ACK_INSTRUCTION"
printf '%s' "$RESTART_PREAMBLE"
printf '%s' "$BRIEFING"
