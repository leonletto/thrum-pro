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

# One absolute Unix-seconds deadline for ALL Thrum work this hook starts.
# Computed here, at the first executable step (before stdin is read and before
# any thrum invocation), exported once, and inherited unchanged by every
# thrum child (whoami, prime --light, prime). It is never recomputed or
# renewed, and any value the caller pre-set is overwritten on purpose.
THRUM_SESSIONSTART_DEADLINE=$(( $(date +%s) + 10 ))
export THRUM_SESSIONSTART_DEADLINE

# Project doesn't use thrum — silent no-op.
if ! command -v thrum >/dev/null 2>&1; then
  exit 0
fi

# Capture hook stdin ONCE, immediately — stdin can only be read once and
# nothing downstream reads it directly. Used below to detect
# SessionStart's `source: "compact"` case.
HOOK_INPUT=$(cat 2>/dev/null || true)

# Capture whoami JSON ONCE, extract identity fields downstream.
# Keeping the RPC count at one preserves session-start latency.
WHOAMI_JSON=""
AGENT_ID=""
# A licence refusal (not accepted, no TTY) prints one stable line on stderr,
# "Error: thrum: EULA not accepted: ...", and exits non-zero. Keep stderr so the
# hook can pass that line into the briefing instead of failing silently.
EULA_ERR=$(mktemp 2>/dev/null) || EULA_ERR=/dev/null
WHOAMI_JSON=$(thrum whoami --json 2>"$EULA_ERR" || true)
EULA_LINE=$(grep -m 1 'thrum: EULA not accepted' "$EULA_ERR" 2>/dev/null || true)
if [ "$EULA_ERR" != /dev/null ]; then rm -f "$EULA_ERR"; fi
if [ -n "$EULA_LINE" ]; then
  echo "$EULA_LINE"
  exit 0
fi
if command -v jq >/dev/null 2>&1; then
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

# Post-/thrum:compact zero-turn light path: if this SessionStart fired
# because of a compaction (source == "compact") AND a fresh restart
# snapshot exists for this agent, run `thrum prime --light` and feed its
# output through the SAME banner/directive/ack/briefing assembly used by
# the full startup path below (LIGHT_MODE=1 just swaps a line of prose in
# the BRIEFING envelope). This used to short-circuit with a one-line nudge
# telling the agent to spend a turn reading a file + running a skill —
# that cost a turn for something the hook can now inject directly. Any
# other case (startup/resume/clear, or compact without a fresh snapshot)
# falls through unchanged into the full-prime path.
HOOK_SOURCE=""
if command -v jq >/dev/null 2>&1; then
  HOOK_SOURCE=$(printf '%s' "$HOOK_INPUT" | jq -r '.source // empty' 2>/dev/null || true)
fi

LIGHT_MODE=0
SNAPSHOT_SHOWN=""
PRIME_DONE=0
if [ "$HOOK_SOURCE" = "compact" ] && [ -n "$AGENT_WORKTREE" ]; then
  SNAPSHOT="${AGENT_WORKTREE}/.thrum/restart/${AGENT_ID}.md"
  # An earlier prime may already have ARCHIVED (moved) the
  # restart file; accept the newest archived copy in the main repo's
  # sessions/ for the freshness check. Best-effort, fully guarded.
  if [ ! -s "$SNAPSHOT" ]; then
    _main_thrum="${AGENT_WORKTREE}/.thrum"
    if [ -f "${AGENT_WORKTREE}/.thrum/redirect" ]; then
      _redir=$(head -n 1 "${AGENT_WORKTREE}/.thrum/redirect" 2>/dev/null | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' || true)
      # A relative redirect resolves against the worktree root, not the hook's cwd.
      case "$_redir" in ""|/*) ;; *) _redir="${AGENT_WORKTREE}/$_redir" ;; esac
      if [ -n "$_redir" ] && [ -d "$_redir" ]; then _main_thrum="$_redir"; fi
    fi
    _newest=$(ls -1t "${_main_thrum}/agents/${AGENT_ID}/sessions/"*-restart.md 2>/dev/null | head -n 1 || true)
    if [ -n "$_newest" ]; then SNAPSHOT="$_newest"; fi
  fi
  if [ -s "$SNAPSHOT" ] && [ -r "$SNAPSHOT" ]; then
    # mtime: choose the stat dialect explicitly (matches the dialect-detection
    # approach used in claude-plugin/commands/compact.md's snapshot-verify step).
    if stat -f %m . >/dev/null 2>&1; then
      MTIME=$(stat -f %m "$SNAPSHOT" 2>/dev/null)
    else
      MTIME=$(stat -c %Y "$SNAPSHOT" 2>/dev/null) # portable-ok: else-branch of the stat -f dialect probe; GNU only
    fi
    NOW=$(date +%s)
    AGE=$(( NOW - ${MTIME:-0} ))

    # Known limitation: mtime is a PROXY for "this snapshot was written for
    # THIS compaction", not proof of it — a bare /compact fired within 300s
    # of an unrelated /thrum:restart or /thrum:compact write on the same
    # agent will also take the lean path and point at that older snapshot.
    # Same proxy compact.md itself relies on; documented, not fixed here.
    if [ "$AGE" -ge 0 ] && [ "$AGE" -le 300 ]; then
      LIGHT_OUTPUT=$(thrum prime --light 2>/dev/null || true)
      if [ -z "$LIGHT_OUTPUT" ]; then
        # Light prime failed (daemon down, slow, etc.) — degrade to the
        # nudge, never to silence.
        # The failed render may already have archived (moved) the restart
        # file into sessions/. Name the path that exists NOW: the file hooked
        # at start if still there, else the newest archived copy in the main
        # repo (redirect-aware, same lookup as the freshness check above).
        NUDGE_SNAP="${SNAPSHOT}"
        if [ ! -s "$NUDGE_SNAP" ]; then
          _nd_thrum="${AGENT_WORKTREE}/.thrum"
          if [ -f "${AGENT_WORKTREE}/.thrum/redirect" ]; then
            _nd_redir=$(head -n 1 "${AGENT_WORKTREE}/.thrum/redirect" 2>/dev/null | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' || true)
            case "$_nd_redir" in ""|/*) ;; *) _nd_redir="${AGENT_WORKTREE}/$_nd_redir" ;; esac
            if [ -n "$_nd_redir" ] && [ -d "$_nd_redir" ]; then _nd_thrum="$_nd_redir"; fi
          fi
          _nd_newest=$(ls -1t "${_nd_thrum}/agents/${AGENT_ID}/sessions/"*-restart.md 2>/dev/null | head -n 1 || true)
          if [ -n "$_nd_newest" ]; then NUDGE_SNAP="$_nd_newest"; fi
        fi
        echo "You were just compacted. Your snapshot is at \`${NUDGE_SNAP}\`. Read it first (Read tool), then run \`thrum:prime-agent\` — auto-injection failed (daemon may be unreachable; check \`thrum daemon status\`)."
        exit 0
      fi
      # `thrum prime --light` degrades to a FULL render for a
      # light-ineligible role (e.g. coordinator). LIGHT_MODE=1 only when the
      # first line is the marker; that line is stripped. Without it the output
      # is a full render and gets the full wording. ONE prime call either way.
      PRIME_OUTPUT="$LIGHT_OUTPUT"
      PRIME_DONE=1
      _first_line=$(printf '%s\n' "$LIGHT_OUTPUT" | head -n 1 | tr -d '\r')
      if [ "$_first_line" = "<!-- thrum-prime: light -->" ]; then
        LIGHT_MODE=1
        # The render's session.archive step may have MOVED
        # the restart file into sessions/. Name the path that exists NOW.
        SNAPSHOT_SHOWN="${SNAPSHOT}"
        if [ ! -s "$SNAPSHOT_SHOWN" ]; then
          _sm_thrum="${AGENT_WORKTREE}/.thrum"
          if [ -f "${AGENT_WORKTREE}/.thrum/redirect" ]; then
            _sm_redir=$(head -n 1 "${AGENT_WORKTREE}/.thrum/redirect" 2>/dev/null | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' || true)
            case "$_sm_redir" in ""|/*) ;; *) _sm_redir="${AGENT_WORKTREE}/$_sm_redir" ;; esac
            if [ -n "$_sm_redir" ] && [ -d "$_sm_redir" ]; then _sm_thrum="$_sm_redir"; fi
          fi
          _sm_newest=$(ls -1t "${_sm_thrum}/agents/${AGENT_ID}/sessions/"*-restart.md 2>/dev/null | head -n 1 || true)
          if [ -n "$_sm_newest" ]; then SNAPSHOT_SHOWN="$_sm_newest"; fi
        fi
        PRIME_OUTPUT=$(printf '%s\n' "$LIGHT_OUTPUT" | tail -n +2)
      fi
    fi
  fi
fi

if [ "$PRIME_DONE" -ne 1 ]; then
  PRIME_OUTPUT=$(thrum prime 2>/dev/null || true)

  if [ -z "$PRIME_OUTPUT" ]; then
    # Prime failed (daemon down, slow, etc.) — fall back to the manual
    # nudge so session start never blocks on a broken thrum.
    echo "Run /thrum:prime to load your session context, identity, and any restart snapshots."
    echo "(Auto-injection failed — daemon may be unreachable. Run \`thrum daemon status\` to check.)"
    exit 0
  fi
fi

# Briefing split. `thrum prime` emits an exact marker line between the inline
# part and the reference part. The line right after it carries the absolute
# paths of the role preamble and Project State that the agent reads from disk:
#   <!-- thrum:briefing-paths preamble="<abs>" project_state="<abs or empty>" -->
# An empty project_state means there is no Project State file to name. Split
# only when the output is over BRIEFING_INLINE_MAX bytes AND the marker line AND
# a well-formed paths line (absolute preamble; project_state empty or absolute)
# are all present. Otherwise the output is used unchanged. The hook never builds
# these paths itself.
BRIEFING_SPLIT_MARKER='<!-- thrum:briefing-split -->'
BRIEFING_INLINE_MAX=9000
SPLIT_FIRST_LINE=""
if [ "$(printf '%s' "$PRIME_OUTPUT" | LC_ALL=C wc -c | tr -d ' ')" -gt "$BRIEFING_INLINE_MAX" ]; then
  _split_wrapped=$'\n'"$PRIME_OUTPUT"$'\n'
  _split_marker_line=$'\n'"$BRIEFING_SPLIT_MARKER"$'\n'
  case "$_split_wrapped" in
    *"$_split_marker_line"*)
      _split_after=${_split_wrapped#*"$_split_marker_line"}
      _split_paths_line=${_split_after%%$'\n'*}
      _split_ok=0
      case "$_split_paths_line" in
        '<!-- thrum:briefing-paths preamble="/'*'" project_state="'*'" -->')
          _split_pair=${_split_paths_line#'<!-- thrum:briefing-paths preamble="'}
          _split_preamble=${_split_pair%%'" project_state="'*}
          _split_project=${_split_pair#*'" project_state="'}
          _split_project=${_split_project%'" -->'}
          case "$_split_project" in
            ''|/*) _split_ok=1 ;;
          esac
          ;;
      esac
      if [ "$_split_ok" -eq 1 ]; then
        _split_inline=${_split_wrapped%%"$_split_marker_line"*}
        PRIME_OUTPUT=${_split_inline#$'\n'}
        if [ -n "$_split_project" ]; then
          SPLIT_FIRST_LINE="The briefing was SPLIT: only its inline part is below. Your first action is to read your role preamble ${_split_preamble} and the Project State file ${_split_project}. Other reference sections (State.md, knowledge-tree domains, Past Sessions, messaging protocol) are omitted from this output."
        else
          SPLIT_FIRST_LINE="The briefing was SPLIT: only its inline part is below. Your first action is to read your role preamble ${_split_preamble}. Other reference sections (State.md, knowledge-tree domains, Past Sessions, messaging protocol) are omitted from this output."
        fi
      fi
      ;;
  esac
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
if [ -z "$SPLIT_FIRST_LINE" ] && grep -q '^# Previous Session Context' <<<"$PRIME_OUTPUT"; then  # here-string: a pipe + grep -q SIGPIPEs printf under pipefail on big output
  append_to RESTART_PREAMBLE '# 🛑 ACTION REQUIRED — you left yourself a Resume Plan'$'\n'
  append_to RESTART_PREAMBLE $'\n'
  append_to RESTART_PREAMBLE 'Before anything else, go to the **`# Previous Session Context`** section below, read its **`## Resume Plan`** (or its final next-actions section) in full, and execute the numbered steps in order. If the briefing was truncated or persisted to a file, first read the whole file with your file-reading tool, every page in order (if there is no file, run `thrum prime --to-file` (if --to-file is an unknown flag, run plain `thrum prime` once and read its output fully) ONCE and read that file; never repeat the prime command), do not jump to the Resume Plan, and name one fact from it before acting.'
  if [ "$LIGHT_MODE" -eq 1 ]; then
    append_to RESTART_PREAMBLE " In light mode your snapshot is also at \`${SNAPSHOT_SHOWN:-.thrum/restart/${AGENT_ID}.md}\` (archived under \`.thrum/agents/${AGENT_ID}/sessions/\` once a prime has run); Read it first if the section is truncated or missing."
  fi
  append_to RESTART_PREAMBLE $'\n'
  append_to RESTART_PREAMBLE $'\n'
  append_to RESTART_PREAMBLE '> ⚠️ **If this briefing was persisted to a `tool-results/*.txt` file instead of delivered inline, read it with the `Read` tool (use `offset`/`limit` to page through it) — NOT with `sed`, `grep`, `head`, `tail`, or `cat` via Bash.**'$'\n'
  append_to RESTART_PREAMBLE $'\n---\n\n'
fi

# 4. Briefing envelope + full/light prime output.
BRIEFING=""
append_to BRIEFING '# Thrum Session Briefing (auto-loaded)'$'\n'
append_to BRIEFING $'\n'
if [ "$LIGHT_MODE" -eq 1 ]; then
  # LIGHT_MODE is 1 only when the light marker was present, so
  # this label is true; an ineligible role's full render takes the else branch.
  append_to BRIEFING "The **light** \`thrum prime --light\` output is included below (auto-injected after compaction; it trims the other briefing sections, and your Resume Plan is in its **\`# Previous Session Context\`** section, with your snapshot also at \`${SNAPSHOT_SHOWN:-.thrum/restart/${AGENT_ID}.md}\`). You do not need to run \`thrum:prime-agent\` again this session. Read it in full."$'\n'
elif [ -n "$SPLIT_FIRST_LINE" ]; then
  append_to BRIEFING 'The inline part of the `thrum prime` output is included below. Read it in full.'$'\n'
else
  append_to BRIEFING 'The complete `thrum prime` output is included below. Read it in full.'$'\n'
fi
append_to BRIEFING $'\n'
append_to BRIEFING 'During this priming turn, beyond the queue/state reconcile and inbox check, run extra commands only for unread messages that need processing. This does not limit work you are already authorized to do; resume it after priming.'$'\n'
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
if [ -n "$SPLIT_FIRST_LINE" ]; then
  append_to DIRECTIVE '> **The briefing was SPLIT — only its inline part is below.** Do not treat it as the full briefing; your first action is the SPLIT line at the top of this output.'$'\n'
else
  append_to DIRECTIVE '> **Do NOT run `/thrum:prime` or `thrum prime` — the full briefing is already in your context below.**'$'\n'
fi
append_to DIRECTIVE '> Only invoke them manually if this hook fell through to a degraded "auto-injection failed" notice.'$'\n'
if [ "$LIGHT_MODE" -eq 1 ]; then
  append_to DIRECTIVE "> In light mode, read your snapshot at \`${SNAPSHOT_SHOWN:-.thrum/restart/${AGENT_ID}.md}\` for the Resume Plan if the section below is truncated or missing."$'\n'
fi
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
append_to ACK_INSTRUCTION $'\n'

# Emit in canonical order: banner → directive → ack → restart preamble →
# briefing. Banner + directive + ack always land inside the 2KB preview.
if [ -n "$SPLIT_FIRST_LINE" ]; then
  printf '%s\n\n' "$SPLIT_FIRST_LINE"
fi
printf '%s' "$BANNER"
printf '%s' "$DIRECTIVE"
printf '%s' "$ACK_INSTRUCTION"
printf '%s' "$RESTART_PREAMBLE"
printf '%s' "$BRIEFING"
