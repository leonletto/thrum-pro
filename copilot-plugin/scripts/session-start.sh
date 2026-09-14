#!/usr/bin/env bash
# sessionStart hook: inject `thrum prime` output into the agent's context,
# for GitHub Copilot CLI's plugin-declared hooks.
#
# WIRE CONTRACT (measured against Copilot CLI 1.0.80, differs from Claude
# Code's hook contract — do NOT copy that shape here):
#   Final stdout MUST be exactly one line of JSON:
#     {"additionalContext": "<text>"}
#   The debug log line that proved this:
#     [rust:hooks] [hook stdout] {"additionalContext":"THRUM_PROBE_MARKER_7f3a9c"}
#   That JSON's `additionalContext` value reaches the model as a
#   role:"user" message. Config-file sessionStart hooks
#   (.github/hooks/*.json, ~/.copilot/config.json) are measured
#   NON-FUNCTIONAL — their output is silently discarded — this plugin-
#   declared path is the one that works.
#
# This hook must never fail hard or block session start: every external
# call degrades gracefully, and the script always exits 0.

set -uo pipefail

# Resolve our own directory, then the plugin root — belt-and-suspenders
# self-location for any future sibling-file reference. Copilot 1.0.82
# (measured) resolves hooks.json's `command` relative to --plugin-dir and
# runs the hook with CWD=plugin-dir, so bare-relative refs already work
# without any of this — but copilot ALSO exports the plugin root as an env
# var, so prefer that when present, then CLAUDE_PLUGIN_ROOT (compatible
# proxy path), then our own computed location as the last resort.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${COPILOT_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(dirname "$SCRIPT_DIR")}}"
export SCRIPT_DIR PLUGIN_ROOT

# Project doesn't use thrum — silent no-op. Emit NOTHING on stdout (not
# even an empty additionalContext object) to match the no-op contract of
# the sibling hooks in claude-plugin/ and codex-plugin/.
if ! command -v thrum >/dev/null 2>&1; then
  exit 0
fi

HAVE_JQ=0
if command -v jq >/dev/null 2>&1; then
  HAVE_JQ=1
fi

# emit_json TEXT — wraps TEXT as {"additionalContext": TEXT} and prints it
# as a single line. Prefers jq -Rs (raw input, slurp) so the text is
# safely escaped; never hand-rolls JSON string escaping unless jq is
# genuinely unavailable, in which case falls back to a minimal manual
# escape of a single safe line.
emit_json() {
  local text="$1"
  if [ "$HAVE_JQ" -eq 1 ]; then
    printf '%s' "$text" | jq -Rsc '{additionalContext: .}'
  else
    # Minimal fallback: escape backslash, double-quote, and ALL C0 control
    # characters (0x00-0x1F) generically — not just \n. Arbitrary `thrum
    # prime` output can contain \t, \r, or other control bytes; leaving any
    # of them unescaped produces invalid JSON on this safety-net path.
    local escaped="${text//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    local out="" i len ch ord
    len=${#escaped}
    for (( i = 0; i < len; i++ )); do
      ch="${escaped:i:1}"
      case "$ch" in
        $'\n') out+='\n' ;;
        $'\r') out+='\r' ;;
        $'\t') out+='\t' ;;
        *)
          # The `'c` ordinal idiom tests byte-wise even for multi-byte
          # UTF-8 sequences: each byte is checked independently, and only
          # true C0 control bytes are < 0x20, so UTF-8 continuation bytes
          # (always >= 0x80) are never misidentified here.
          printf -v ord '%d' "'$ch"
          if [ "$ord" -lt 32 ]; then
            printf -v ord '\\u%04x' "$ord"
            out+="$ord"
          else
            out+="$ch"
          fi
          ;;
      esac
    done
    printf '{"additionalContext": "%s"}\n' "$out"
  fi
}

NUDGE_TEXT="Run \`thrum prime\` to load your session context, identity, and any restart snapshots."

# Capture whoami JSON ONCE, extract identity fields downstream. Keeping
# the RPC count at one preserves session-start latency.
WHOAMI_JSON=""
AGENT_ID=""
if [ "$HAVE_JQ" -eq 1 ]; then
  WHOAMI_JSON=$(thrum whoami --json 2>/dev/null || true)
  AGENT_ID=$(printf '%s' "$WHOAMI_JSON" \
    | jq -r 'select(.agent_id != null) | .agent_id // empty' 2>/dev/null \
    || true)
fi

if [ -z "$AGENT_ID" ]; then
  # No agent registered — emit the JSON-wrapped nudge so the model knows
  # to prime manually after registration. There IS content to report
  # here, so unlike the no-thrum branch above this always emits.
  emit_json "$NUDGE_TEXT"
  exit 0
fi

# Extract additional banner fields. Each is best-effort: a missing field
# just renders as "unknown" in the banner, never aborts the hook.
AGENT_ROLE=$(printf '%s' "$WHOAMI_JSON" | jq -r '.role // empty' 2>/dev/null || true)
AGENT_WORKTREE=$(printf '%s' "$WHOAMI_JSON" | jq -r '.worktree // empty' 2>/dev/null || true)
AGENT_BRANCH=$(printf '%s' "$WHOAMI_JSON" | jq -r '.branch // empty' 2>/dev/null || true)
AGENT_MODULE=$(printf '%s' "$WHOAMI_JSON" | jq -r '.module // empty' 2>/dev/null || true)

# Strip any backticks from identity fields before interpolating into the
# banner — defensive hardening, mirrors inject-prime-context.sh.
AGENT_ID="${AGENT_ID//\`/}"
AGENT_ROLE="${AGENT_ROLE//\`/}"
AGENT_MODULE="${AGENT_MODULE//\`/}"

PRIME_OUTPUT=$(thrum prime 2>/dev/null || true)

if [ -z "$PRIME_OUTPUT" ]; then
  # Prime failed (daemon down, slow, etc.) — fall back to the manual
  # nudge so session start never blocks on a broken thrum.
  emit_json "${NUDGE_TEXT}
(Auto-injection failed — daemon may be unreachable. Run \`thrum daemon status\` to check.)"
  exit 0
fi

# Identity banner — mirrors the BANNER section of inject-prime-context.sh.
BANNER=""
BANNER+="# 🎯 You are: @${AGENT_ID}"$'\n'
BANNER+=$'\n'
BANNER+="- **Role:** ${AGENT_ROLE:-unknown}"$'\n'
BANNER+="- **Worktree:** ${AGENT_WORKTREE:-unknown}"$'\n'
BANNER+="- **Branch:** ${AGENT_BRANCH:-unknown}"$'\n'
if [ -n "$AGENT_MODULE" ] && [ "$AGENT_MODULE" != "$AGENT_ROLE" ]; then
  BANNER+="- **Module:** ${AGENT_MODULE}"$'\n'
fi
BANNER+=$'\n---\n\n'

FULL_TEXT="${BANNER}${PRIME_OUTPUT}"

emit_json "$FULL_TEXT"
exit 0
