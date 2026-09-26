#!/usr/bin/env bash
# roster-watch.sh — reconciled persistent-watcher/steward roster capture
# script.
#
# PROVENANCE: this file reconciles two live, independently-evolved,
# never-merged personal-branch scripts (`origin/agent/watcher-primary` and
# `origin/agent/brainstorm-steward`, reconciled against a full byte-level
# diff account of both) into one canonical, git-tracked script.
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
# inspection (2026-08-17, a reconciler agent's "Stop the sweep loop
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
# REDIRECT FIX (the actual bug this reconciliation targets):
# `watch_params.json` lives under the SHARED, redirect-resolved `agents/`
# tree (`internal/paths/paths.go` AgentDir: "the agents/ tree is shared,
# not per-worktree"), not under this script's own worktree. Both source
# scripts read it as if it were always reachable via a hardcoded/relative
# main-repo path (`cd /Users/you/dev/thrum` +
# `.thrum/agents/<agent>/watch_params.json`) — correct only by accident of
# always invoking from the main repo, and silently wrong (reads a stale,
# worktree-local copy) the moment this script or its cwd ever moves to a
# feature worktree. `resolve_watch_params()` below replaces that implicit
# assumption with the same explicit `.thrum/redirect`-following idiom
# already used by `scripts/heartbeat-lib.sh:225-232` and
# `scripts/thrum-check-inbox.sh:25-41`.
#
# PORTABILITY FIX: both source scripts also hardcoded a single operator's
# absolute paths (`cd /Users/you/dev/thrum`,
# `OUTDIR=/Users/you/.thrum/worktrees/thrum/<agent>/.thrum-watch`). This
# script derives every path from its own location instead, so the exact
# same file works when copied into ANY worktree for ANY agent.
#
# DEPLOYMENT: per prior operational research into this exact redirect-
# resolution issue, this script is hand-copied to
# `<worktree>/.thrum-watch/roster-watch.sh` — a directory SIBLING to
# `.thrum/`, NOT inside `.thrum/agents/<you>/` (unlike this skill's other
# resource, thrum-watch-pane-capture.sh, which IS deployed under
# `.thrum/agents/<you>/`). Because of that different deployment shape,
# SCRIPT_DIR here is `<worktree>/.thrum-watch`, so WORKTREE_ROOT is
# `dirname(SCRIPT_DIR)` — one level up, not three. Register with:
#   thrum monitor start --name roster-watch-<you> \
#     --match "^(roster capture ready:|ROSTER INCIDENT:)" --to @<you> --notify-on-success \
#     --schedule '*/10 * * * *' -- <worktree>/.thrum-watch/roster-watch.sh
# (loop mode does not need --schedule; it stays resident under Monitor.)
# Keep --notify-on-success; the daemon honors the terminal JEV quiet marker per run.
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
# resolve_thrum_dir — follow .thrum/redirect (factored out
# of resolve_watch_params/resolve_capture_outdir per dual-review,
# both of which were independently reimplementing this same body).
# ---------------------------------------------------------------------------
# Args: worktree_root. Prints the redirect-resolved absolute .thrum/ dir.
# Matches the idiom already used by scripts/heartbeat-lib.sh's
# hb_sessions_dir() and scripts/thrum-check-inbox.sh's SPOOL_THRUM
# resolution: no redirect file present (main repo) -> use the local .thrum/
# as-is; redirect file present (feature worktree) -> follow it to the main
# repo's .thrum/.
resolve_thrum_dir() {
  local worktree_root="$1" thrum
  thrum="${worktree_root}/.thrum"
  [[ -f "${thrum}/redirect" ]] && thrum="$(tr -d '[:space:]' < "${thrum}/redirect")"
  printf '%s\n' "${thrum}"
}

# ---------------------------------------------------------------------------
# resolve_watch_params
# ---------------------------------------------------------------------------
# Args: worktree_root, agent. Prints the redirect-resolved absolute path
# to that agent's watch_params.json.
resolve_watch_params() {
  local worktree_root="$1" agent="$2"
  printf '%s/agents/%s/watch_params.json\n' "$(resolve_thrum_dir "${worktree_root}")" "${agent}"
}

# ---------------------------------------------------------------------------
# resolve_capture_outdir — same redirect-following idiom as
# resolve_watch_params, but for roster-capture output.
# outdir must NEVER be derived from this script's own on-disk location
# (BASH_SOURCE/SCRIPT_DIR) — that resolves into plugin source whenever the
# script is invoked directly from its skill/resources directory instead of
# its deployed <worktree>/.thrum-watch copy. Anchor it instead to the
# shared, redirect-resolved .thrum/agents/<agent>/ tree, matching where
# watch_params.json itself already lives.
# ---------------------------------------------------------------------------
resolve_capture_outdir() {
  local worktree_root="$1" agent="$2"
  printf '%s/agents/%s/watch-captures\n' "$(resolve_thrum_dir "${worktree_root}")" "${agent}"
}

# ---------------------------------------------------------------------------
# prune_roster_captures — intentionally preserve roster-capture-*.txt
# history for watcher review and later training/export.
# ---------------------------------------------------------------------------
prune_roster_captures() {
  :
}

utc_now_iso() {
  python3 -c 'import datetime; print(datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="microseconds").replace("+00:00","Z"))'
}

utc_now_file_stamp() {
  python3 -c 'import datetime; print(datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H%M%S-%f"))'
}

safe_capture_name() {
  python3 -c 'import re,sys; print(re.sub(r"[^A-Za-z0-9_.-]+", "_", sys.argv[1])[:80] or "agent")' "$1"
}

measure_geometry_json() {
  local session="$1" raw
  [ -n "$session" ] || return 0
  raw=$(tmux display-message -p -t "$session" '#{pane_width}	#{pane_height}	#{cursor_x}	#{cursor_y}	#{pane_in_mode}' 2>/dev/null) || return 0
  python3 -c '
import json, sys
parts=sys.argv[1].split("\t")
if len(parts) != 5:
    sys.exit(0)
try:
    width=int(parts[0]); height=int(parts[1]); cursor_x=int(parts[2]); cursor_y=int(parts[3])
except Exception:
    sys.exit(0)
print(json.dumps({
    "pane_width": width,
    "pane_height": height,
    "cursor_x": cursor_x,
    "cursor_y": cursor_y,
    "pane_in_mode": parts[4],
    "source": "tmux display-message",
}, sort_keys=True))
' "$raw" 2>/dev/null
}

agent_is_local() {
  local agent="$1"
  thrum team "@$agent" --offline --json 2>/dev/null | python3 -c '
import json, sys
agent=sys.argv[1]
try:
    data=json.load(sys.stdin)
except Exception:
    sys.exit(1)
for member in data.get("team", {}).get("members", []):
    if member.get("agent_id") == agent:
        sys.exit(0 if member.get("is_local") is True else 1)
sys.exit(1)
' "$agent" 2>/dev/null
}

record_archive_degraded() {
  local outdir="$1" capture_id="$2" component="$3" agent="$4" message="$5"
  local archive_dir="${outdir}/archive" health_dir="${archive_dir}/health"
  mkdir -p "$health_dir" 2>/dev/null || true
  chmod 700 "$archive_dir" "$health_dir" 2>/dev/null || true
  ARCHIVE_DEGRADED=1
  ARCHIVE_DEGRADED_MESSAGES+=("${component}${agent:+:$agent}")
  python3 -c '
import json, os, sys, datetime
out=sys.argv[1]
payload={
  "schema_version": "roster-capture-archive-health-v1",
  "status": "archive_degraded",
  "capture_id": sys.argv[2],
  "component": sys.argv[3],
  "agent": sys.argv[4] or None,
  "message": sys.argv[5],
  "recorded_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="microseconds").replace("+00:00","Z"),
}
stamp = payload["recorded_at_utc"].replace(":","").replace("-","")
agent = payload["agent"] or "source"
component = payload["component"]
name = f"{stamp}_{component}_{agent}.json"
path=os.path.join(out, name)
tmp=path+f".{os.getpid()}.tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    fh.write(json.dumps(payload, sort_keys=True, separators=(",", ":"))+"\n")
    fh.flush(); os.fsync(fh.fileno())
os.chmod(tmp, 0o600)
os.replace(tmp, path)
' "$health_dir" "$capture_id" "$component" "$agent" "$message" 2>/dev/null || true
  printf '%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$capture_id" "$component${agent:+:$agent}" "$message" >>"${archive_dir}/archive-health.log" 2>/dev/null || true
  chmod 600 "${archive_dir}/archive-health.log" 2>/dev/null || true
}

archive_source_file() {
  local outdir="$1" file="$2" capture_id="$3" ts="$4"
  local archive_py="${SCRIPT_DIR}/capture_archive.py"
  local archive_dir="${outdir}/archive"
  if [ ! -f "$archive_py" ]; then
    echo "capture archive warning: missing helper $archive_py; source archive skipped" >&2
    record_archive_degraded "$outdir" "$capture_id" "archive_source_missing_helper" "" "missing helper $archive_py"
    return 0
  fi
  mkdir -p "$archive_dir" 2>/dev/null || true
  chmod 700 "$archive_dir" 2>/dev/null || true
  python3 "$archive_py" archive-source \
    --archive-dir "$archive_dir" \
    --source "$file" \
    --capture-id "$capture_id" \
    --capture-timestamp-utc "$ts" >/dev/null 2>>"${archive_dir}/archive-errors.log" || \
    { echo "capture archive warning: source archive failed for $file" >&2; record_archive_degraded "$outdir" "$capture_id" "archive_source_failed" "" "source archive failed for $file"; }
}

archive_agent_file() {
  local outdir="$1" agent="$2" raw_file="$3" source_file="$4" capture_id="$5" ts="$6" cap_rc="$7" requested_lines="$8" runtime="${9-}" geometry_json="${10-}" capture_route="${11-}" primary_rc="${12-}" ssh_rc="${13-}" final_rc="${14-}"
  local archive_py="${SCRIPT_DIR}/capture_archive.py"
  local archive_dir="${outdir}/archive"
  if [ ! -f "$archive_py" ]; then
    echo "capture archive warning: missing helper $archive_py; agent archive skipped for $agent" >&2
    record_archive_degraded "$outdir" "$capture_id" "archive_agent_missing_helper" "$agent" "missing helper $archive_py"
    return 0
  fi
  mkdir -p "$archive_dir" 2>/dev/null || true
  chmod 700 "$archive_dir" 2>/dev/null || true
  local cmd=(python3 "$archive_py" archive-agent
    --archive-dir "$archive_dir"
    --agent "$agent"
    --raw-file "$raw_file"
    --source-file "$source_file"
    --capture-id "$capture_id"
    --capture-timestamp-utc "$ts"
    --capture-rc "$cap_rc"
    --requested-lines "$requested_lines")
  [ -n "$runtime" ] && cmd+=(--runtime "$runtime")
  [ -n "$geometry_json" ] && cmd+=(--geometry-json "$geometry_json")
  [ -n "$capture_route" ] && cmd+=(--capture-route "$capture_route")
  [ -n "$primary_rc" ] && cmd+=(--primary-rc "$primary_rc")
  [ -n "$ssh_rc" ] && cmd+=(--ssh-rc "$ssh_rc")
  [ -n "$final_rc" ] && cmd+=(--final-rc "$final_rc")
  "${cmd[@]}" >/dev/null 2>>"${archive_dir}/archive-errors.log" || \
    { echo "capture archive warning: agent archive failed for $agent in $capture_id" >&2; record_archive_degraded "$outdir" "$capture_id" "archive_agent_failed" "$agent" "agent archive failed for $agent in $capture_id"; }
}

write_raw_from_capture_json() {
  local json_file="$1" raw_file="$2"
  python3 -c '
import json, pathlib, sys
doc=json.load(open(sys.argv[1], encoding="utf-8"))
if not doc.get("ok"):
    raise SystemExit(1)
lines=doc.get("lines")
if not isinstance(lines, list) or any(not isinstance(line, str) for line in lines):
    raise SystemExit(1)
ghost_lines=doc.get("ghost_lines") or []
if not isinstance(ghost_lines, list) or any(not isinstance(i, int) for i in ghost_lines):
    raise SystemExit(1)
out=[]
out.extend(lines)
if ghost_lines or doc.get("has_ghost") or doc.get("composer_text"):
    out.append("--- GHOST METADATA (structured; non-submitted suggestion text, not pane input) ---")
    if ghost_lines:
        out.append("ghost_lines: " + ",".join(str(i) for i in ghost_lines))
    if doc.get("composer_text"):
        out.append("ghost_text: " + str(doc.get("composer_text")))
text="\n".join(out)
if text:
    text += "\n"
path=pathlib.Path(sys.argv[2])
path.write_text(text, encoding="utf-8")
' "$json_file" "$raw_file"
}

write_filter_manifest_row() {
  local manifest="$1" agent="$2" raw_file="$3" source_file="$4" capture_id="$5" ts="$6" cap_rc="$7" route="$8" provider_input_file="${9-}" provider_input_source="${10-}" capture_json_file="${11-}"
  python3 -c '
import json, sys
row={
  "agent": sys.argv[1],
  "raw_file": sys.argv[2],
  "source_file": sys.argv[3],
  "capture_id": sys.argv[4],
  "capture_timestamp_utc": sys.argv[5],
  "capture_rc": int(sys.argv[6]),
  "capture_route": sys.argv[7],
}
if sys.argv[8]:
  row["provider_input_file"] = sys.argv[8]
if sys.argv[9]:
  row["provider_input_source"] = sys.argv[9]
if sys.argv[10]:
  row["capture_json_file"] = sys.argv[10]
print(json.dumps(row, sort_keys=True, separators=(",", ":")))
' "$agent" "$raw_file" "$source_file" "$capture_id" "$ts" "$cap_rc" "$route" "$provider_input_file" "$provider_input_source" "$capture_json_file" >>"$manifest"
}

# jev_key_present — true (rc 0) iff a JEV provider key is actually available:
# checks THRUM_TYPESAFE_KEY/OPENROUTER_API_KEY in the process environment
# first, then falls back to parsing the resolved env file ($1) as DATA
# (never sourced/eval'd) using the same key-matching + quote-stripping
# convention as jev_watcher_filter.py's read_env_keys().
jev_key_present() {
  local env_file="$1"
  if [ -n "${THRUM_TYPESAFE_KEY:-}" ] || [ -n "${OPENROUTER_API_KEY:-}" ]; then
    return 0
  fi
  [ -n "$env_file" ] && [ -f "$env_file" ] || return 1
  python3 -c '
import sys
env_file = sys.argv[1]
names = ("THRUM_TYPESAFE_KEY", "OPENROUTER_API_KEY")
try:
    with open(env_file, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
except OSError:
    sys.exit(1)
for line in text.splitlines():
    if "=" not in line:
        continue
    name, value = line.split("=", 1)
    if name not in names:
        continue
    value = value.strip().strip("\"").strip("'"'"'")
    if value:
        sys.exit(0)
sys.exit(1)
' "$env_file"
}

run_jev_filter() {
  local outdir="$1" manifest="$2" capture_id="$3"
  local filter_py="${SCRIPT_DIR}/jev_watcher_filter.py"
  local decisions_dir="${outdir}/archive/jev-decisions/${capture_id}"
  JEV_FILTER_MODE=fallback
  JEV_FILTER_ATTENTION=0
  if [ ! -f "$filter_py" ]; then
    echo "jev filter warning: missing helper; using watcher fallback" >&2
    return 0
  fi
  mkdir -p "$decisions_dir" 2>/dev/null || true
  chmod 700 "${outdir}/archive" "${outdir}/archive/jev-decisions" "$decisions_dir" 2>/dev/null || true
  local env_file="${ROSTER_JEV_ENV_FILE:-${REPO_ROOT}/.env}"
  local cmd=(python3 "$filter_py" --manifest "$manifest" --out-dir "$decisions_dir" --env-file "$env_file"
    --timeout "${ROSTER_JEV_TIMEOUT:-8}" --retries "${ROSTER_JEV_RETRIES:-1}" --concurrency "${ROSTER_JEV_CONCURRENCY:-4}")
  [ -n "${ROSTER_JEV_EGRESS_AUDIT_DIR:-}" ] && cmd+=(--egress-audit-dir "$ROSTER_JEV_EGRESS_AUDIT_DIR")
  if ! "${cmd[@]}" >"${decisions_dir}/filter-output.json" 2>>"${decisions_dir}/filter-errors.log"; then
    echo "jev filter warning: execution failed; using watcher fallback" >&2
    return 0
  fi
  local parsed
  if ! parsed=$(python3 - "${decisions_dir}/summary.json" "${ROSTER[@]}" <<'PY'
import json, sys
try:
    summary = json.load(open(sys.argv[1], encoding="utf-8"))
    expected = sys.argv[2:]
    rows = summary["results"]
    if not isinstance(rows, list) or len(rows) != len(expected):
        raise ValueError("incomplete results")
    if sorted(row["agent"] for row in rows) != sorted(expected):
        raise ValueError("roster mismatch")
    attention = fallback = 0
    for row in rows:
        status, route = row.get("filter_status"), row.get("route")
        if status == "ok" and route == "archive_only" and row.get("reason") == "confident_ordinary":
            continue
        if status == "ok" and route == "notify_watcher" and row.get("reason") in ("active_permission_prompt", "blocking_user_question_tui"):
            attention += 1
        else:
            fallback += 1
    print(f"{attention}|{fallback}")
except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError):
    raise SystemExit(1)
PY
  ); then
    echo "jev filter warning: malformed or incomplete summary; using watcher fallback" >&2
    return 0
  fi
  local fallback_count
  IFS='|' read -r JEV_FILTER_ATTENTION fallback_count <<<"$parsed"
  if [ "$fallback_count" -gt 0 ]; then
    echo "jev filter warning: uncertain classification; using watcher fallback" >&2
    return 0
  fi
  JEV_FILTER_MODE=ok
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
    for sock in $(ls "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/" 2>/dev/null | grep -v '^te-' | head -20); do
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
# classification. Both source scripts had this exact logic (the same
# two-proof design: independently-verified-live-
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
    if [ "$is_local" = "true" ] || [ "$hostname" = "$(hostname)" ] || [ "$hostname" = "$(hostname).local" ]; then
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
    echo "--- DEGRADED-KNOWN for $a: thrum tmux capture failed (capability-denied/empty binding: ${firstline}) but LIVE by fallback proof ($proof) — visible warning; use direct-message/session-artifact fallback, not repeated hard FAIL ---"
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
    ROSTER_SELF_CHECK_FAILED=1
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
# ROSTER_TMUX_SESSION / ROSTER_RUNTIME / ROSTER_DAEMON_OVERRIDE parallel
# arrays from watch_params.json (bash 3.2
# portable — no mapfile, no associative arrays). Entries may remain legacy
# plain strings, or may declare the exact remote capture target as
# {"agent_id","hostname","tmux_session"}; the declared form is
# authoritative for SSH fallback (never rediscover its host or guess a
# pane). This dynamic read is brainstorm-steward's design and already
# fixes the OTHER bug (hardcoded ROSTER array, drifted from
# watch_params.json in both directions) that watcher-primary's copy still
# has in full — do not reintroduce a hardcoded array here.
#
# ROSTER_DAEMON_OVERRIDE is sourced from the OPTIONAL top-level
# "capture_daemon_overrides" map: {"<agent>": "<daemon_id>"}. Default
# empty/absent -> every entry resolves to "" -> plain `thrum tmux capture`
# for everyone (inert). Set an entry only for an agent whose capture must
# route through a specific daemon (a real, currently rare, cross-daemon
# deployment need) — see run_capture_cycle below for where it's applied.
# ---------------------------------------------------------------------------
load_roster() {
  local params_file="$1"
  ROSTER=()
  ROSTER_HOSTNAME=()
  ROSTER_TMUX_SESSION=()
  ROSTER_RUNTIME=()
  ROSTER_DAEMON_OVERRIDE=()
  while IFS='|' read -r _a _host _tmux _runtime _daemon_override; do
    [ -n "$_a" ] || continue
    ROSTER+=("$_a")
    ROSTER_HOSTNAME+=("$_host")
    ROSTER_TMUX_SESSION+=("$_tmux")
    ROSTER_RUNTIME+=("$_runtime")
    ROSTER_DAEMON_OVERRIDE+=("$_daemon_override")
  done < <(python3 -c '
import json, sys
data = json.load(open(sys.argv[1]))
overrides = data.get("capture_daemon_overrides") or {}
for entry in data.get("roster", []):
    if isinstance(entry, str):
        agent = entry
        print(f"{agent}||||{overrides.get(agent) or '"'"''"'"'}")
        continue
    agent = entry.get("agent_id") or entry.get("agent") or entry.get("name") or ""
    print(f"{agent}|{entry.get('"'"'hostname'"'"') or '"'"''"'"'}|{entry.get('"'"'tmux_session'"'"') or '"'"''"'"'}|{entry.get('"'"'runtime'"'"') or '"'"''"'"'}|{overrides.get(agent) or '"'"''"'"'}")
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
  local file="$1" capture_id="$2" ts="$3" requested_lines="${4:-30}"
  local roster_idx=0
  local a session
  ARCHIVE_AGENTS=()
  ARCHIVE_RAW_FILES=()
  ARCHIVE_CAPTURE_RCS=()
  ARCHIVE_RUNTIMES=()
  ARCHIVE_GEOMETRIES=()
  ARCHIVE_ROUTES=()
  ARCHIVE_PRIMARY_RCS=()
  ARCHIVE_SSH_RCS=()
  ARCHIVE_FINAL_RCS=()
  local raw_root="${outdir}/archive/raw-ticks/${capture_id}"
  mkdir -p "$raw_root" 2>/dev/null || true
  chmod 700 "${outdir}/archive" "${outdir}/archive/raw-ticks" "$raw_root" 2>/dev/null || true
  if [ "${USE_JEV:-0}" = "1" ]; then
    JEV_FILTER_MANIFEST="${raw_root}/jev-filter-manifest.jsonl"
    : >"$JEV_FILTER_MANIFEST"
  fi
  : >"$file"
  for a in "${ROSTER[@]}"; do
      local safe raw_file primary_file primary_json_file provider_input_file ssh_file primary_rc=0 primary_json_rc="" ssh_rc="" cap_rc=0 runtime geometry_json capture_route provider_input_source capture_json_file daemon_override primary_capture_file capture_format
      safe="$(safe_capture_name "$a")"
      raw_file="${raw_root}/$(printf '%04d' "$roster_idx")-${safe}.txt"
      primary_file="${raw_root}/$(printf '%04d' "$roster_idx")-${safe}.primary.txt"
      primary_json_file="${raw_root}/$(printf '%04d' "$roster_idx")-${safe}.primary.json"
      provider_input_file="${raw_root}/$(printf '%04d' "$roster_idx")-${safe}.provider-input.txt"
      ssh_file="${raw_root}/$(printf '%04d' "$roster_idx")-${safe}.ssh.txt"
      runtime="${ROSTER_RUNTIME[$roster_idx]}"
      daemon_override="${ROSTER_DAEMON_OVERRIDE[$roster_idx]}"
      geometry_json=""
      capture_route="primary"
      provider_input_source=""
      capture_json_file=""
      session=$(resolve_session "$a")
      # capture_daemon_overrides (watch_params.json, optional, default empty
      # -> inert): routes this agent's capture through a specific daemon
      # instead of the normal proxy-by-name resolution, for the rare
      # cross-daemon deployment where that's required. See load_roster.
      if [ "${USE_JEV:-0}" = "1" ]; then
        primary_capture_file="$primary_json_file"
        capture_format=json
      else
        primary_capture_file="$primary_file"
        capture_format=annotated
      fi
      if [ -n "$daemon_override" ]; then
        thrum tmux capture "$a" --daemon-id "$daemon_override" --format="$capture_format" --lines "$requested_lines" >"$primary_capture_file" 2>&1
      else
        thrum tmux capture "$a" --format="$capture_format" --lines "$requested_lines" >"$primary_capture_file" 2>&1
      fi
      primary_rc=$?
      if [ "${USE_JEV:-0}" = "1" ] && [ "$primary_rc" -eq 0 ] && [ -s "$primary_json_file" ] && write_raw_from_capture_json "$primary_json_file" "$raw_file" 2>/dev/null; then
        cap_rc=0
        primary_json_rc=0
        capture_json_file="$primary_json_file"
        provider_input_source="thrum_tmux_capture_json_structured_state"
        if agent_is_local "$a"; then
          geometry_json=$(measure_geometry_json "$session" 2>/dev/null || true)
        fi
        CAPTURED+=("$a")
      elif [ "${USE_JEV:-0}" != "1" ] && [ "$primary_rc" -eq 0 ] && [ -s "$primary_file" ]; then
        cp "$primary_file" "$raw_file"
        cap_rc=0
        if agent_is_local "$a"; then
          geometry_json=$(measure_geometry_json "$session" 2>/dev/null || true)
        fi
        CAPTURED+=("$a")
      else
        ssh_capture_pane "$a" "${ROSTER_HOSTNAME[$roster_idx]}" "${ROSTER_TMUX_SESSION[$roster_idx]}" >"$ssh_file" 2>&1
        ssh_rc=$?
        if [ "$ssh_rc" -eq 0 ] && [ -s "$ssh_file" ]; then
          cp "$ssh_file" "$raw_file"
          if [ "${USE_JEV:-0}" = "1" ]; then
            cp "$ssh_file" "$provider_input_file"
            chmod 600 "$provider_input_file" 2>/dev/null || true
            provider_input_source="ssh_capture_pane_text"
          fi
          cap_rc=0
          capture_route="ssh_fallback"
          geometry_json=""
          CAPTURED+=("$a")
        else
          cat "$primary_capture_file" >"$raw_file"
          printf '\n--- SSH fallback failed for %s (exit %s) ---\n' "$a" "$ssh_rc" >>"$raw_file"
          cat "$ssh_file" >>"$raw_file"
          cap_rc=$ssh_rc
          capture_route="both_failed"
          geometry_json=""
        fi
        # A successful SSH capture is a real pane capture, not a degraded
        # liveness proof. Only classify when both capture routes failed.
        if [ "$cap_rc" -ne 0 ]; then
          if grep -qiE "local agent not found|lacks required capability|empty.*binding|proxy.*capability|capability.*denied|peer.*unreachable|circuit open|dial skipped" "$primary_capture_file"; then
            probe_agent "$a" "$(head -1 "$primary_capture_file" | tr -d '\n' | cut -c1-120)" >>"$raw_file"
          else
            echo "--- CAPTURE FAILED for $a (nonzero exit — NOT an empty pane) ---" >>"$raw_file"
            FAILED+=("$a")
          fi
        fi
      fi
      if [ "${USE_JEV:-0}" != "1" ] || [ "$capture_route" != "primary" ]; then
        check_ghost_tip "$session" >>"$raw_file"
      fi
      {
        echo "=== $a ==="
        cat "$raw_file"
        echo
      } >>"$file"
      ARCHIVE_AGENTS+=("$a")
      ARCHIVE_RAW_FILES+=("$raw_file")
      ARCHIVE_CAPTURE_RCS+=("$cap_rc")
      ARCHIVE_RUNTIMES+=("$runtime")
      ARCHIVE_GEOMETRIES+=("$geometry_json")
      ARCHIVE_ROUTES+=("$capture_route")
      ARCHIVE_PRIMARY_RCS+=("$primary_rc")
      ARCHIVE_SSH_RCS+=("$ssh_rc")
      ARCHIVE_FINAL_RCS+=("$cap_rc")
      if [ "${USE_JEV:-0}" = "1" ]; then
        write_filter_manifest_row "$JEV_FILTER_MANIFEST" "$a" "$raw_file" "$file" "$capture_id" "$ts" "$cap_rc" "$capture_route" "${provider_input_source:+$provider_input_file}" "$provider_input_source" "$capture_json_file"
      fi
      roster_idx=$((roster_idx + 1))
  done
  archive_source_file "$outdir" "$file" "$capture_id" "$ts"
  local archive_idx=0
  while [ "$archive_idx" -lt "${#ARCHIVE_AGENTS[@]}" ]; do
    archive_agent_file \
      "$outdir" \
      "${ARCHIVE_AGENTS[$archive_idx]}" \
      "${ARCHIVE_RAW_FILES[$archive_idx]}" \
      "$file" \
      "$capture_id" \
      "$ts" \
      "${ARCHIVE_CAPTURE_RCS[$archive_idx]}" \
      "$requested_lines" \
      "${ARCHIVE_RUNTIMES[$archive_idx]}" \
      "${ARCHIVE_GEOMETRIES[$archive_idx]}" \
      "${ARCHIVE_ROUTES[$archive_idx]}" \
      "${ARCHIVE_PRIMARY_RCS[$archive_idx]}" \
      "${ARCHIVE_SSH_RCS[$archive_idx]}" \
      "${ARCHIVE_FINAL_RCS[$archive_idx]}"
    archive_idx=$((archive_idx + 1))
  done
  if [ "${USE_JEV:-0}" = "1" ]; then
    run_jev_filter "$outdir" "$JEV_FILTER_MANIFEST" "$capture_id"
  fi
}

# ---------------------------------------------------------------------------
# emit_wake_line — overnight wake-gating (brainstorm-steward; TZ fix:
# the monitor process runs in UTC, so a bare `date +%H` gives the UTC
# hour and the overnight gate never matches; the gate is meant to compare
# against LOCAL time by design).
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
  SCRIPT_DIR="$script_dir"

  # --prune-roster-captures passthrough: usable standalone (e.g. from a
  # cron/monitor cleanup step) without touching the network. Checked FIRST,
  # before the source-tree refusal guard below -- this
  # mode never resolves worktree_root/outdir/watch_params and never writes
  # anywhere but the explicit $2 directory argument, so script_dir alone
  # (always the resources/ dir for this standalone invocation shape) must
  # not disqualify it the way it correctly disqualifies the main
  # capture-cycle path below.
  if [ "${1-}" = "--prune-roster-captures" ]; then
    [ "$#" -eq 2 ] || exit 2
    prune_roster_captures "$2"
    exit 0
  fi

  # Deployment shape: <worktree>/.thrum-watch/roster-watch.sh -- SCRIPT_DIR
  # is .thrum-watch, so WORKTREE_ROOT is one level up, NOT the
  # .thrum/agents/<you>/-relative three-levels-up thrum-watch-pane-
  # capture.sh uses (that script deploys under .thrum/agents/<you>/, this
  # one deploys under a worktree-root-sibling .thrum-watch/).
  # Refuse to run in place from a plugin skill source tree.
  # Any deployed copy lives at <worktree>/.thrum-watch/roster-watch.sh
  # (see SKILL.md); this exact suffix is only ever the plugin skill
  # resources dir itself. Failing loud here -- before worktree_root/outdir
  # are ever computed -- is what keeps a mis-invocation from writing
  # anything at all under claude-plugin/ or any mirror plugin tree, rather
  # than resolving worktree_root to a bogus plugin-adjacent path and
  # silently creating a new .thrum/ sibling there.
  #
  # NOTE (dual-review): this glob match is a fail-fast
  # nicety for the one known mis-invocation shape, not the real barrier --
  # it only ever catches THIS exact source layout. The actual fix is below:
  # outdir no longer derives from script_dir/BASH_SOURCE at all, so even an
  # invocation shape this glob fails to recognize still cannot write under
  # claude-plugin/ (or any mirror). Do not extend this case statement and
  # assume that alone closes a new variant -- verify outdir's derivation
  # instead.
  case "${script_dir}" in
    */skills/persistent-watcher-archetype/resources)
      echo "roster-watch.sh: refusing to run from a plugin skill source tree (${script_dir}); deploy to <worktree>/.thrum-watch/roster-watch.sh first (see SKILL.md)" >&2
      exit 1
      ;;
  esac

  worktree_root="$(cd -- "${script_dir}/.." >/dev/null 2>&1 && pwd)"
  agent_name="${AGENT_NAME:-$(basename -- "${worktree_root}" | tr '-' '_')}"

  # outdir must resolve via the shared, redirect-followed .thrum/agents/
  # tree -- NOT from script_dir/BASH_SOURCE, which
  # resolves into plugin source whenever this script runs from its
  # skill/resources location instead of its deployed .thrum-watch copy.
  local outdir
  outdir="$(resolve_capture_outdir "${worktree_root}" "${agent_name}")"
  mkdir -p "${outdir}"

  # One-time, idempotent capture-history migration (per dual-review).
  # Capture output moved from <worktree>/.thrum-watch/ (script_dir,
  # the pre-fix outdir) to the new outdir above. A live deployment's
  # existing .thrum-watch/archive/ history must not be silently orphaned on
  # redeploy. Runs on every invocation but is a no-op after the first pass:
  # only fires when the OLD archive exists and the NEW one does not, and
  # never overwrites an existing new archive (mv fails loudly instead, per
  # the project's never-clobber-with-a-move convention).
  local legacy_archive="${script_dir}/archive" new_archive="${outdir}/archive"
  if [ -d "${legacy_archive}" ] && [ ! -e "${new_archive}" ]; then
    if mv "${legacy_archive}" "${new_archive}"; then
      echo "roster-watch.sh: migrated capture archive history ${legacy_archive} -> ${new_archive}" >&2
    else
      echo "roster-watch.sh: capture archive migration failed (${legacy_archive} -> ${new_archive}); leaving legacy archive in place" >&2
    fi
  fi

  local watch_params
  watch_params="$(resolve_watch_params "${worktree_root}" "${agent_name}")"

  local detector="${script_dir}/detect_ghost_tip.py"
  DETECTOR="${detector}"

  local interval_secs="${INTERVAL_SECS:-600}"
  local stamp="${outdir}/.last-emit"
  local fail_state="${outdir}/.last-failed-roster"

  load_roster "${watch_params}"
  REPO_ROOT="$(git -C "$worktree_root" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$worktree_root")"
  USE_JEV_REQUESTED=$(python3 -c 'import json,sys; print(int(json.load(open(sys.argv[1])).get("use_jev") is True))' "$watch_params" 2>/dev/null || echo 0)
  USE_JEV=0
  if [ "$USE_JEV_REQUESTED" = "1" ]; then
    if jev_key_present "${ROSTER_JEV_ENV_FILE:-${REPO_ROOT}/.env}"; then
      USE_JEV=1
    else
      echo "JEV requested but no key found — skipped" >&2
    fi
  fi
  local ts file capture_stamp capture_id
  ts=$(utc_now_iso)
  capture_stamp=$(utc_now_file_stamp)
  file="${outdir}/roster-capture-${capture_stamp}.txt"
  if [ "${#ROSTER[@]}" -eq 0 ]; then
    echo "roster capture ready: $file ($ts) — WARNING empty/unreadable roster in $watch_params" | tee "$file"
    exit 0
  fi

  # Startup self-check runs once, against the dynamically-loaded roster,
  # regardless of execution mode.
  ROSTER_SELF_CHECK_FAILED=0
  roster_self_check "${outdir}" "${ROSTER[@]}"

  run_one_cycle() {
    FAILED=(); DEGRADED=(); CAPTURED=()
    ROSTER_INCIDENT_CLEARED=0
    ARCHIVE_DEGRADED=0; ARCHIVE_DEGRADED_MESSAGES=()
    ts=$(utc_now_iso)
    capture_stamp=$(utc_now_file_stamp)
    capture_id="roster-capture-${capture_stamp}-$$"
    file="${outdir}/roster-capture-${capture_stamp}.txt"

    run_capture_cycle "${file}" "${capture_id}" "${ts}" 30
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
      ROSTER_INCIDENT_CLEARED=1
      echo "roster incident cleared for $previous_failures; inspect $file"
    fi

    if [ "${ARCHIVE_DEGRADED:-0}" -ne 0 ]; then
      echo "roster capture ready: ${file} (${ts}) — ARCHIVE-DEGRADED: ${ARCHIVE_DEGRADED_MESSAGES[*]}; inspect archive/health and archive-errors.log"
    elif [ "${USE_JEV:-0}" = "1" ]; then
      if [ "${ROSTER_SELF_CHECK_FAILED:-0}" -ne 0 ]; then
        echo "roster capture ready: $file ($ts) - ROSTER-CHECK FAIL; inspect $outdir/roster-check.log"
      elif [ "${ROSTER_INCIDENT_CLEARED:-0}" -ne 0 ]; then
        echo "roster capture ready: $file ($ts) - roster incident cleared; inspect $file"
      elif [ "${JEV_FILTER_MODE:-fallback}" != "ok" ]; then
        emit_wake_line "${file}" "${ts}" "${stamp}"
      elif [ "${JEV_FILTER_ATTENTION:-0}" -gt 0 ]; then
        echo "roster capture ready: $file ($ts) — active permission prompt or blocking user choice (${JEV_FILTER_ATTENTION} agent(s)); decisions archived"
      elif [ "${#FAILED[@]}" -gt 0 ] || [ "${#DEGRADED[@]}" -gt 0 ]; then
        emit_wake_line "${file}" "${ts}" "${stamp}"
      else
        echo "roster capture archived, jev filter found no watcher-needed panes: $file ($ts)"
        if [ "${ROSTER_WATCH_MODE:-}" != "loop" ]; then
          echo "THRUM_ROSTER_JEV_ARCHIVE_ONLY_V1"
        fi
      fi
    else
      emit_wake_line "${file}" "${ts}" "${stamp}"
    fi
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
