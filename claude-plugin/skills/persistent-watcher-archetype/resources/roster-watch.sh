#!/usr/bin/env bash
# roster-watch.sh — reconciled persistent-watcher/steward roster capture
# script (thrum-y5nto).
#
# PROVENANCE: this file reconciles two live, independently-evolved,
# never-merged personal-branch scripts (`origin/agent/watcher-primary` and
# `origin/agent/brainstorm-steward`, see /tmp/y5nto-reconcile.md for the
# full byte-level diff account) into one canonical, git-tracked script.
# Neither branch is an ancestor of thrum-agents; this is the first time
# either design lands in the shared tree.
#
# EXECUTION MODEL: single-pass / cron-driven by default (ported from
# brainstorm-steward, the LATER of the two designs, Sep 10 vs Sep 6). Its
# own header explained why it moved off a resident loop: "the earlier
# persistent-loop version had its sleep reset every time the monitor
# supervisor restarted the script during docker-bridge-flap capture
# failures, so the 2h overnight cadence never held." Cron + single-pass is
# immune to that class of bug because the NEXT wake is `thrum monitor`'s
# cron schedule, not an internal `sleep` that a supervisor restart can
# reset. This is now the RECOMMENDED mode for any deployment.
#
# LEGACY LOOP MODE: set ROSTER_WATCH_MODE=loop to opt into the OLDER
# watcher-primary persistent-loop model (a resident `while true; do
# ...; sleep "${INTERVAL_SECS:-600}"; done`, plus its self-submit-Enter
# block — see run_self_submit_enter below). This mode is kept, not
# dropped, because some live deployments may still depend on it until
# they are migrated to a `thrum monitor --schedule` cron registration;
# migrating any such deployment is an operational follow-up, NOT done by
# this script. Do not add new loop-mode deployments — use cron/single-pass
# (the unset/default mode) instead.
#
# GHOST-TIP DETECTION: Claude Code's TUI renders an unaccepted inline
# autocomplete suggestion in the input box using the literal SGR
# "dim/faint" escape code (ESC[2m ... ESC[0m) — confirmed by direct byte
# inspection (2026-08-17, brainstormer_reconciler's "Stop the sweep loop
# for now" tip). Real typed/submitted text never carries that code. `thrum
# tmux capture` returns plain text with all styling stripped, so a script
# parsing ONLY that output cannot tell a live ghost-tip apart from real
# unsubmitted input sitting in the box — both render as identical plain
# text. This script does a SECOND, raw pass per agent (tmux capture-pane
# -e, escape codes intact) purely to check for that one signature and
# annotate it, so the agent reading the capture file knows NOT to treat a
# flagged line as real pending input (never nudge/escalate on it) or as an
# agent's own submitted text. watcher-primary's committed copy had this;
# brainstorm-steward's did not (dropped, not deliberately removed per any
# commit message found) — kept here because the underlying TUI behavior it
# guards against is not mode-specific, and dropping it silently would
# regress a real, previously-fixed false-escalation risk for every
# steward-mode deployment.
#
# REDIRECT FIX (thrum-y5nto, the actual bug this reconciliation targets):
# `watch_params.json` lives under the SHARED, redirect-resolved `agents/`
# tree (`internal/paths/paths.go` AgentDir: "the agents/ tree is shared,
# not per-worktree"), not under this script's own worktree. Both source
# scripts read it as if it were always reachable via a hardcoded/relative
# main-repo path (`cd /Users/leon/dev/falcondev/thrum` +
# `.thrum/agents/<agent>/watch_params.json`) — correct only by accident of
# always invoking from the main repo, and silently wrong (reads a stale,
# worktree-local copy) the moment this script or its cwd ever moves to a
# feature worktree. `resolve_watch_params()` below replaces that implicit
# assumption with the same explicit `.thrum/redirect`-following idiom
# already used by `scripts/heartbeat-lib.sh:225-232` and
# `scripts/thrum-check-inbox.sh:25-41`.
#
# PORTABILITY FIX: both source scripts also hardcoded a single macOS
# user's absolute paths (`cd /Users/leon/dev/falcondev/thrum`,
# `OUTDIR=/Users/leon/.thrum/worktrees/thrum/<agent>/.thrum-watch`). This
# script derives every path from its own location instead, so the exact
# same file works when copied into ANY worktree for ANY agent.
#
# DEPLOYMENT: per operational precedent (dev-docs/2026-09-16-thrum-y5nto-
# roster-watch-redirect-research.md §1), this script is hand-copied to
# `<worktree>/.thrum-watch/roster-watch.sh` — a directory SIBLING to
# `.thrum/`, NOT inside `.thrum/agents/<you>/` (unlike this skill's other
# resource, thrum-watch-pane-capture.sh, which IS deployed under
# `.thrum/agents/<you>/`). Because of that different deployment shape,
# SCRIPT_DIR here is `<worktree>/.thrum-watch`, so WORKTREE_ROOT is
# `dirname(SCRIPT_DIR)` — one level up, not three. Register with:
#   thrum monitor start --name roster-watch-<you> \
#     --match "^roster capture ready:" --to @<you> --notify-on-success \
#     --schedule '*/10 * * * *' -- <worktree>/.thrum-watch/roster-watch.sh
# (loop mode does not need --schedule; it stays resident under Monitor.)
#
# AGENT IDENTITY: neither source script derived its own agent name — both
# hardcoded it (watcher_primary, brainstorm_steward) throughout. This
# script defaults AGENT_NAME to the worktree directory's basename with
# hyphens folded to underscores (matches both known deployments:
# worktree `watcher-primary` -> agent `watcher_primary`; worktree
# `brainstorm_steward` -> agent `brainstorm_steward`, a no-op fold). Set
# the AGENT_NAME env var explicitly if a deployment's worktree/agent-name
# pair doesn't follow that convention.
#
# TESTABILITY: every function below is safe to `source` on its own (no
# top-level side effects, no network calls, no loop) — only `main` (run
# at the bottom, guarded so `source`-ing this file does not execute it)
# performs I/O. This lets `resolve_watch_params` and friends be unit
# tested by sourcing this file and calling them directly.
set -uo pipefail

# ---------------------------------------------------------------------------
# resolve_watch_params — follow .thrum/redirect (thrum-y5nto fix)
# ---------------------------------------------------------------------------
# Args: worktree_root, agent. Prints the redirect-resolved absolute path
# to that agent's watch_params.json. Matches the idiom already used by
# scripts/heartbeat-lib.sh's hb_sessions_dir() and
# scripts/thrum-check-inbox.sh's SPOOL_THRUM resolution: no redirect file
# present (main repo) -> use the local .thrum/ as-is; redirect file
# present (feature worktree) -> follow it to the main repo's .thrum/.
resolve_watch_params() {
  local worktree_root="$1" agent="$2" thrum
  thrum="${worktree_root}/.thrum"
  [[ -f "${thrum}/redirect" ]] && thrum="$(tr -d '[:space:]' < "${thrum}/redirect")"
  printf '%s/agents/%s/watch_params.json\n' "${thrum}" "${agent}"
}

# ---------------------------------------------------------------------------
# prune_roster_captures — keep only the 5 newest roster-capture-*.txt
# files under $outdir (brainstorm-steward fix; watcher-primary had none
# and let captures accumulate indefinitely).
# ---------------------------------------------------------------------------
prune_roster_captures() {
  local outdir="$1" path
  find "$outdir" -maxdepth 1 -type f -name 'roster-capture-*.txt' -print 2>/dev/null | \
    LC_ALL=C sort -r | awk 'NR > 5' | while IFS= read -r path; do
      rm -f "$path"
    done
}

# ---------------------------------------------------------------------------
# resolve_session — resolve an agent name to its tmux session name via
# `thrum tmux status --json` (ported from watcher-primary; needed only for
# the ghost-tip raw-capture pass below, which reads the tmux pane
# directly rather than through `thrum tmux capture`). Falls back to the
# agent name itself if resolution fails (session name sometimes equals
# agent name).
# ---------------------------------------------------------------------------
resolve_session() {
  local agent="$1"
  local session
  session=$(thrum tmux status --json 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
for s in d.get('sessions', []):
    if s.get('agent') == '$agent':
        print(s.get('name', ''))
        break
" 2>/dev/null)
  if [ -z "$session" ]; then
    session="$agent"
  fi
  printf '%s' "$session"
}

# ---------------------------------------------------------------------------
# check_ghost_tip — see the GHOST-TIP DETECTION header comment above.
# Skips cleanly (no-op) if the sibling detect_ghost_tip.py hasn't been
# deployed alongside this script (it ships separately, per the
# persistent-watcher-archetype skill's "copy BOTH ..." setup recipe).
# ---------------------------------------------------------------------------
check_ghost_tip() {
  local session="$1"
  [ -n "${DETECTOR:-}" ] && [ -f "${DETECTOR}" ] || return 0
  local raw
  raw=$(tmux -L default capture-pane -e -p -t "$session" -S -6 2>/dev/null)
  if [ -z "$raw" ]; then
    local sock
    for sock in $(ls /private/tmp/tmux-501/ 2>/dev/null | grep -v '^te-leon-' | head -20); do
      raw=$(tmux -L "$sock" capture-pane -e -p -t "$session" -S -6 2>/dev/null)
      [ -n "$raw" ] && break
    done
  fi
  [ -z "$raw" ] && return 0

  local tip
  tip=$(printf '%s' "$raw" | python3 "$DETECTOR" 2>/dev/null | head -1)
  if [ -n "$tip" ]; then
    echo "--- GHOST-TIP (dim/unaccepted autocomplete on the input line — NOT real typed input; do NOT nudge/escalate on it): ${tip#GHOST-TIP: } ---"
  fi
}

# ---------------------------------------------------------------------------
# quote_shell / resolve_capture_target / ssh_capture_pane — SSH fallback,
# ported verbatim from brainstorm-steward (watcher-primary had none).
# ---------------------------------------------------------------------------
quote_shell() {
  python3 -c 'import shlex,sys; print(shlex.quote(sys.argv[1]))' "$1"
}

resolve_capture_target() {
  local agent="$1" team_json host worktree
  # Scoped member read: this fallback runs per failed pane, so `team
  # --all` would repeatedly pull the entire fleet and fan out under an
  # outage. The scoped form carries the same member fields we need below.
  if ! team_json="$(thrum team "@$agent" --offline --json 2>/dev/null)"; then
    return 1
  fi
  host="$(printf '%s' "$team_json" | python3 -c '
import json,sys
agent=sys.argv[1]
data=json.load(sys.stdin)
for member in data.get("team", {}).get("members", []):
    if member.get("agent_id") == agent:
        print(member.get("hostname") or "")
        break
' "$agent")"
  worktree="$(printf '%s' "$team_json" | python3 -c '
import json,sys
agent=sys.argv[1]
data=json.load(sys.stdin)
for member in data.get("team", {}).get("members", []):
    if member.get("agent_id") == agent:
        print(member.get("worktree") or "")
        break
' "$agent")"
  # Thrum session IDs (ses_...) are not tmux targets. Persistent panes use
  # both conventions in the fleet: some use the agent ID, while others use
  # the worktree basename. Return both and let the remote tmux server
  # choose the first existing session; this remains useful while daemon
  # routing is circuit-open and `thrum tmux status` cannot resolve a
  # canonical name.
  [ -n "$host" ] && [ -n "$agent" ] || return 1
  printf '%s|%s|%s\n' "$host" "$agent" "${worktree##*/}"
}

ssh_capture_pane() {
  local agent="$1" declared_host="${2-}" declared_session="${3-}"
  local host agent_session worktree_session worktree_normalized
  local agent_quoted worktree_quoted normalized_quoted remote_cmd
  local target
  if [ -n "$declared_host" ] || [ -n "$declared_session" ]; then
    [ -n "$declared_host" ] && [ -n "$declared_session" ] || return 1
    host="$declared_host"
    agent_quoted="$(quote_shell "$declared_session")"
    remote_cmd="tmux has-session -t ${agent_quoted} 2>/dev/null || exit 1; tmux capture-pane -p -J -t ${agent_quoted} -S -30"
    ssh -n -o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=5 -o ServerAliveCountMax=1 "$host" "$remote_cmd" 2>&1
    return $?
  fi
  if ! target="$(resolve_capture_target "$agent")"; then
    return 1
  fi
  host="${target%%|*}"
  target="${target#*|}"
  agent_session="${target%%|*}"
  worktree_session="${target#*|}"
  [ -n "$host" ] && [ -n "$agent_session" ] || return 1
  # Worktree basenames can contain dots while tmux launch normalizes them
  # to hyphens (for example my.thrum.team -> my-thrum-team). Try both
  # forms.
  worktree_normalized="${worktree_session//./-}"
  agent_quoted="$(quote_shell "$agent_session")"
  worktree_quoted="$(quote_shell "$worktree_session")"
  normalized_quoted="$(quote_shell "$worktree_normalized")"
  remote_cmd="for session in ${agent_quoted} ${worktree_quoted} ${normalized_quoted}; do if tmux has-session -t \"\$session\" 2>/dev/null; then tmux capture-pane -p -J -t \"\$session\" -S -30; exit \$?; fi; done; exit 1"
  ssh -n -o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=5 -o ServerAliveCountMax=1 "$host" "$remote_cmd" 2>&1
}

# ---------------------------------------------------------------------------
# probe_agent — SHARED DEGRADED-KNOWN / hard-FAIL PID-liveness
# classification. Both source scripts had this exact logic (same
# thrum-955bl/x2bao-sibling two-proof design: independently-verified-live-
# PID OR fresh direct-message/session-artifact) — watcher-primary as an
# extracted function, brainstorm-steward inlined a second, drifted copy.
# Factored into ONE function here so there is exactly one place to fix it.
#
# Args: agent, first-line-of-the-failed-primary-capture-output (for the
# message only). Prints the classification line to stdout. Side effect:
# appends the agent id to the global DEGRADED or FAILED array (both must
# be declared by the caller before use).
# ---------------------------------------------------------------------------
probe_agent() {
  local a="$1" firstline="$2"
  local pid="" hostname="" last_seen="" is_local="" session_id="" inbox_total="0" state=""
  # --offline: the online-only read omits offline agents entirely (empty
  # members[]), which false-fails the proof; the offline record carries
  # the same fields plus last-known state.
  eval "$(thrum team "@$a" --offline --json 2>/dev/null | python3 -c "
import json,sys
agent=sys.argv[1]
try:
    d=json.load(sys.stdin)
except: sys.exit(0)
for m in d.get('team',{}).get('members',[]):
    if m.get('agent_id')==agent:
        print(f\"pid={m.get('agent_pid') or 0}\")
        print(f\"hostname={m.get('hostname') or ''}\")
        print(f\"last_seen={m.get('last_seen') or ''}\")
        print(f\"is_local={str(m.get('is_local')).lower()}\")
        print(f\"state={m.get('state') or ''}\")
        print(f\"session_id={m.get('session_id') or ''}\")
        print(f\"inbox_total={m.get('inbox_total') or 0}\")
        break
" "$a" 2>/dev/null)"
  local live_pid_verified=0 fresh_msg_verified=0
  # Case 1: independently verified live PID (ps on the owning host, not
  # just team pid != 0).
  if [ -n "$pid" ] && [ "$pid" != "0" ] && [ -n "$hostname" ] && { [ -z "$state" ] || [ "$state" = "alive" ]; }; then
    if [ "$is_local" = "true" ] || [ "$hostname" = "leonsmacm1pro" ] || [ "$hostname" = "leonsmacm1pro.local" ]; then
      if ps -p "$pid" >/dev/null 2>&1; then live_pid_verified=1; fi
    else
      if ssh -n -o ConnectTimeout=5 -o BatchMode=yes "$hostname" "ps -p $pid >/dev/null 2>&1" 2>/dev/null; then live_pid_verified=1; fi
      if [ $live_pid_verified -eq 0 ]; then
        sess=$(thrum tmux status --json 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); [print(s.get('name','')) for s in d.get('sessions',[]) if s.get('agent')==sys.argv[1]]" "$a" 2>/dev/null | head -1)
        if [ -n "$sess" ]; then
          sess_quoted="$(quote_shell "$sess")"
          if ssh -n -o ConnectTimeout=5 -o BatchMode=yes "$hostname" "tmux has-session -t ${sess_quoted} 2>/dev/null" 2>/dev/null; then live_pid_verified=1; fi
        fi
      fi
    fi
  fi
  # Case 2: fresh direct-message/session-artifact (last_seen within 15m,
  # single snapshot carries session_id/inbox_total). The monitor runs
  # every 10m, so a 5m window falsely fails healthy agents between
  # captures.
  if [ -n "$last_seen" ] && { [ -z "$state" ] || [ "$state" = "alive" ]; }; then
    fresh_msg_verified=$(python3 -c "
import sys, datetime
s=sys.argv[1]
try:
    if s.endswith('Z'): s=s[:-1]+'+00:00'
    dt=datetime.datetime.fromisoformat(s)
    now=datetime.datetime.now(datetime.timezone.utc)
    delta=(now-dt).total_seconds()
    has_artifact=bool(sys.argv[2]) or int(sys.argv[3]) > 0
    print(1 if 0 <= delta < 900 and has_artifact else 0)
except: print(0)
" "$last_seen" "$session_id" "$inbox_total" 2>/dev/null)
  fi
  # Negative controls: stale last_seen (>15m) and dead/reused PID (ps
  # fails) remain hard FAIL unless other proof.
  if [ "${live_pid_verified:-0}" -eq 1 ] || [ "${fresh_msg_verified:-0}" -eq 1 ]; then
    proof=""
    [ "${live_pid_verified:-0}" -eq 1 ] && proof="independently verified live PID ${pid:-unknown} on ${hostname}"
    [ "${fresh_msg_verified:-0}" -eq 1 ] && proof="${proof:+$proof + }fresh direct-message/session-artifact (last_seen ${last_seen})"
    echo "--- DEGRADED-KNOWN for $a: thrum tmux capture failed (capability-denied/empty binding: ${firstline}) but LIVE by fallback proof ($proof) — visible warning; use direct-message/session-artifact fallback, not repeated hard FAIL (thrum-955bl/x2bao-sibling) ---"
    DEGRADED+=("$a")
  else
    echo "--- CAPTURE FAILED for $a (capability-denied/empty binding — no independent live proof: true pid0/dead PID or stale last_seen) — hard FAIL ---"
    FAILED+=("$a")
  fi
}

# ---------------------------------------------------------------------------
# roster_self_check — ported from watcher-primary: verify every ROSTER
# entry resolves to a real agent_id via `thrum team --offline --json`, and
# log ROSTER-CHECK OK/FAIL. Cheap and valuable regardless of execution
# model (catches the exact "bare `<box>`-as-hostname" class of stale-
# roster-entry bug watcher-primary hit 2026-07-24..2026-09-06). Runs AFTER
# the dynamic roster is loaded from watch_params.json, not against a
# hardcoded array.
# ---------------------------------------------------------------------------
roster_self_check() {
  local outdir="$1"; shift
  local roster=("$@")
  local bad="" r
  for r in "${roster[@]}"; do
    if ! thrum team "@$r" --offline --json 2>/dev/null | python3 -c "
import json,sys
agent=sys.argv[1]
try: ms=json.load(sys.stdin)['team']['members']
except: sys.exit(1)
sys.exit(0 if any(m.get('agent_id')==agent for m in ms) else 1)
" "$r" 2>/dev/null; then
      bad="$bad $r"
    fi
  done
  if [ -n "$bad" ]; then
    echo "ROSTER-CHECK FAIL: no such agent(s):$bad — remove or fix before trusting this run's coverage" | tee "$outdir/roster-check.log"
  else
    echo "ROSTER-CHECK OK: ${#roster[@]} entries resolve" > "$outdir/roster-check.log"
  fi
}

# ---------------------------------------------------------------------------
# run_self_submit_enter — LOOP MODE ONLY (watcher-primary): 10s after the
# ready-line notice, submit the watcher's OWN pane with Enter so a message
# queued while the loop was mid-capture gets processed. GUARDED: never
# send Enter while a permission modal is open in the watcher's own pane
# (Enter would approve the default option unseen); only submit when a
# message-waiting notice is visible.
# ---------------------------------------------------------------------------
run_self_submit_enter() {
  local self_agent="$1"
  sleep 10
  local me_out
  me_out=$(thrum tmux capture "$self_agent" --lines 15 2>&1)
  if echo "$me_out" | grep -q "run 'thrum inbox --unread' to read"; then
    if echo "$me_out" | grep -qiE "Do you want to proceed\?|requires confirmation|Permission rule"; then
      echo "self-submit skipped: modal open in ${self_agent} pane" >&2
    else
      thrum tmux send "$self_agent" --keys "Enter" >/dev/null 2>&1 || true
    fi
  fi
}

# ---------------------------------------------------------------------------
# load_roster — populate the global ROSTER / ROSTER_HOSTNAME /
# ROSTER_TMUX_SESSION parallel arrays from watch_params.json (bash 3.2
# portable — no mapfile). Entries may remain legacy plain strings, or may
# declare the exact remote capture target as
# {"agent_id","hostname","tmux_session"}; the declared form is
# authoritative for SSH fallback (never rediscover its host or guess a
# pane). This dynamic read is brainstorm-steward's design and already
# fixes the OTHER bug (hardcoded ROSTER array, drifted from
# watch_params.json in both directions) that watcher-primary's copy still
# has in full — do not reintroduce a hardcoded array here.
# ---------------------------------------------------------------------------
load_roster() {
  local params_file="$1"
  ROSTER=()
  ROSTER_HOSTNAME=()
  ROSTER_TMUX_SESSION=()
  while IFS=$'\t' read -r _a _host _tmux; do
    [ -n "$_a" ] || continue
    ROSTER+=("$_a")
    ROSTER_HOSTNAME+=("$_host")
    ROSTER_TMUX_SESSION+=("$_tmux")
  done < <(python3 -c '
import json, sys
for entry in json.load(open(sys.argv[1])).get("roster", []):
    if isinstance(entry, str):
        print(f"{entry}\t\t")
        continue
    agent = entry.get("agent_id") or entry.get("agent") or entry.get("name") or ""
    print(f"{agent}\t{entry.get('"'"'hostname'"'"') or '"'"''"'"'}\t{entry.get('"'"'tmux_session'"'"') or '"'"''"'"'}")
' "$params_file" 2>/dev/null)
}

# ---------------------------------------------------------------------------
# run_capture_cycle — one full roster pass: local capture first (always;
# `thrum tmux capture <agent>` already reaches remote agents by name via
# the normal proxy), SSH fallback only on a known capability-denied/proxy-
# failure signature, DEGRADED-KNOWN/hard-FAIL classification via the
# shared probe_agent, and a GHOST-TIP annotation pass per agent. Writes
# the whole roster to $FILE. Populates the global FAILED/DEGRADED/CAPTURED
# arrays (caller must reset them to empty before calling).
# ---------------------------------------------------------------------------
run_capture_cycle() {
  local file="$1"
  local roster_idx=0
  local a session
  {
    for a in "${ROSTER[@]}"; do
      echo "=== $a ==="
      local primary_out="" primary_rc=0
      if [ "$a" = "brainstormer_reference" ]; then
        primary_out=$(thrum tmux capture "$a" --daemon-id d_01KPVXQCZS298W3C5ACVW767ZE --format=annotated --lines 30 2>&1)
      else
        primary_out=$(thrum tmux capture "$a" --format=annotated --lines 30 2>&1)
      fi
      primary_rc=$?
      local cap_out="$primary_out" cap_rc="$primary_rc"
      if [ "$cap_rc" -eq 0 ] && [ -n "$cap_out" ]; then
        echo "$cap_out"
        CAPTURED+=("$a")
      else
        local ssh_out="" ssh_rc=0
        if ssh_out=$(ssh_capture_pane "$a" "${ROSTER_HOSTNAME[$roster_idx]}" "${ROSTER_TMUX_SESSION[$roster_idx]}") && [ -n "$ssh_out" ]; then
          cap_out="$ssh_out"; cap_rc=0
          echo "$cap_out"
          CAPTURED+=("$a")
        else
          ssh_rc=$?
          cap_out="${primary_out}
--- SSH fallback failed for $a (exit $ssh_rc) ---
${ssh_out}"
          cap_rc=$ssh_rc
          echo "$cap_out"
        fi
        # A successful SSH capture is a real pane capture, not a degraded
        # liveness proof. Only classify when both capture routes failed.
        if [ "$cap_rc" -ne 0 ]; then
          if echo "$primary_out" | grep -qiE "local agent not found|lacks required capability|empty.*binding|proxy.*capability|capability.*denied|peer.*unreachable|circuit open|dial skipped"; then
            probe_agent "$a" "$(echo "$primary_out" | head -1 | tr -d '\n' | cut -c1-120)"
          else
            echo "--- CAPTURE FAILED for $a (nonzero exit — NOT an empty pane) ---"
            FAILED+=("$a")
          fi
        fi
      fi
      session=$(resolve_session "$a")
      check_ghost_tip "$session"
      echo
      roster_idx=$((roster_idx + 1))
    done
  } >"$file" 2>&1
}

# ---------------------------------------------------------------------------
# emit_wake_line — overnight wake-gating (brainstorm-steward; TZ fix:
# the monitor process runs in UTC, so a bare `date +%H` gives the UTC
# hour and the overnight gate never matches — Leon means LOCAL time).
# Daytime (local 08:00-23:59) every run emits the matchable wake line.
# Overnight (local 00:00-07:59) it still captures every run, but only
# EMITS the wake line once ~2h has passed (tracked via $stamp), printing a
# non-matching line otherwise. Reverts automatically at 08:00.
# ---------------------------------------------------------------------------
emit_wake_line() {
  local file="$1" ts="$2" stamp="$3"
  local hour now last emit=1
  hour=$(TZ=America/Los_Angeles date +%H); hour=$((10#$hour)) # 10# avoids octal parse of 08/09
  now=$(date +%s)
  if [ "$hour" -ge 0 ] && [ "$hour" -lt 8 ]; then
    last=$(cat "$stamp" 2>/dev/null || echo 0)
    [ $((now - last)) -lt 7000 ] && emit=0 # 7000s ~ 2h with cron fudge
  fi
  if [ "$emit" -eq 1 ]; then
    echo "$now" > "$stamp"
    echo "roster capture ready: $file ($ts) — reconcile roster state and linked queue waits"
  else
    echo "roster capture taken, wake suppressed (overnight 2h cadence): $file ($ts)"
  fi
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  # --- locate paths --------------------------------------------------------
  local script_dir worktree_root agent_name
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
  # Deployment shape: <worktree>/.thrum-watch/roster-watch.sh -- SCRIPT_DIR
  # is .thrum-watch, so WORKTREE_ROOT is one level up, NOT the
  # .thrum/agents/<you>/-relative three-levels-up thrum-watch-pane-
  # capture.sh uses (that script deploys under .thrum/agents/<you>/, this
  # one deploys under a worktree-root-sibling .thrum-watch/).
  worktree_root="$(cd -- "${script_dir}/.." >/dev/null 2>&1 && pwd)"
  agent_name="${AGENT_NAME:-$(basename -- "${worktree_root}" | tr '-' '_')}"

  local outdir="${script_dir}"
  mkdir -p "${outdir}"

  local watch_params
  watch_params="$(resolve_watch_params "${worktree_root}" "${agent_name}")"

  local detector="${script_dir}/detect_ghost_tip.py"
  DETECTOR="${detector}"

  local interval_secs="${INTERVAL_SECS:-600}"
  local stamp="${outdir}/.last-emit"
  local fail_state="${outdir}/.last-failed-roster"

  # --prune-roster-captures passthrough: usable standalone (e.g. from a
  # cron/monitor cleanup step) without touching the network.
  if [ "${1-}" = "--prune-roster-captures" ]; then
    [ "$#" -eq 2 ] || exit 2
    prune_roster_captures "$2"
    exit 0
  fi

  load_roster "${watch_params}"
  local ts file
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  file="${outdir}/roster-capture-$(date -u +%Y%m%d-%H%M%S).txt"
  if [ "${#ROSTER[@]}" -eq 0 ]; then
    echo "roster capture ready: $file ($ts) — WARNING empty/unreadable roster in $watch_params" | tee "$file"
    exit 0
  fi

  # Startup self-check runs once, against the dynamically-loaded roster,
  # regardless of execution mode.
  roster_self_check "${outdir}" "${ROSTER[@]}"

  run_one_cycle() {
    FAILED=(); DEGRADED=(); CAPTURED=()
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    file="${outdir}/roster-capture-$(date -u +%Y%m%d-%H%M%S).txt"

    run_capture_cycle "${file}"
    prune_roster_captures "${outdir}"

    if [ "${#DEGRADED[@]}" -gt 0 ]; then
      echo "DEGRADED-KNOWN: tmux capture capability-denied/empty binding for ${DEGRADED[*]} but LIVE by independent fallback proof; inspect $file (direct-message/session-artifact fallback)"
    fi
    if [ "${#FAILED[@]}" -gt 0 ]; then
      local current_failures="${FAILED[*]}" previous_failures
      previous_failures=$(cat "$fail_state" 2>/dev/null || true)
      printf '%s\n' "$current_failures" > "$fail_state"
      if [ "$current_failures" != "$previous_failures" ]; then
        echo "ROSTER INCIDENT: tmux capture failed for $current_failures; inspect $file"
      else
        echo "roster incident persists unchanged for $current_failures; inspect $file"
      fi
    elif [ -f "$fail_state" ]; then
      local previous_failures
      previous_failures=$(cat "$fail_state" 2>/dev/null || true)
      rm -f "$fail_state"
      echo "roster incident cleared for $previous_failures; inspect $file"
    fi

    emit_wake_line "${file}" "${ts}" "${stamp}"
  }

  if [ "${ROSTER_WATCH_MODE:-}" = "loop" ]; then
    # LEGACY LOOP MODE — see header comment for why this exists and why
    # cron/single-pass (the default) is preferred.
    while true; do
      run_one_cycle
      run_self_submit_enter "${agent_name}"
      sleep "${interval_secs}"
    done
  else
    run_one_cycle
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
