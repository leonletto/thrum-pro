#!/usr/bin/env bash
# roster-watch_test.sh — unit tests for roster-watch.sh's
# resolve_watch_params() (thrum-y5nto: the ".thrum/redirect" fix), plus a
# coverage bonus for thrum-watch-pane-capture.sh's PARAMS_FILE resolution
# logic (inline harness — that script isn't structured as sourceable
# functions the way roster-watch.sh is; see Scenario 3 below).
#
# Run: bash claude-plugin/skills/persistent-watcher-archetype/resources/roster-watch_test.sh
# (or: SCRIPT_UNDER_TEST=/path/to/alt-roster-watch.sh bash roster-watch_test.sh
#  to run Scenario 1 against a different implementation, e.g. for a manual
#  RED-before/GREEN-after check against a deliberately-reverted copy.)
#
# All tests are hermetic: every fixture is a throwaway tree under mktemp -d,
# cleaned up via a trap; nothing here touches the real repo's .thrum, a live
# daemon, or the network.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_UNDER_TEST="${SCRIPT_UNDER_TEST:-$SCRIPT_DIR/roster-watch.sh}"

# shellcheck source=/dev/null
source "$SCRIPT_UNDER_TEST" || {
  echo "roster-watch.sh not found/sourceable at $SCRIPT_UNDER_TEST -- thrum-y5nto resolve_watch_params is missing" >&2
  exit 1
}

pass=0
fail=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then echo "PASS: $desc"; pass=$((pass + 1));
  else echo "FAIL: $desc -- expected '$expected' got '$actual'"; fail=$((fail + 1)); fi
}
assert_ne() {
  local desc="$1" unexpected="$2" actual="$3"
  if [ "$unexpected" != "$actual" ]; then echo "PASS: $desc"; pass=$((pass + 1));
  else echo "FAIL: $desc -- '$actual' unexpectedly equals '$unexpected'"; fail=$((fail + 1)); fi
}

# roster_count <file> -- number of entries in the "roster" array of a
# watch_params.json fixture. Uses python3 (already a hard dependency of
# roster-watch.sh itself, e.g. load_roster()).
roster_count() {
  python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print(len(d.get("roster", [])))
except Exception:
    print(-1)
' "$1" 2>/dev/null
}

# mk_watch_params <file> <n> -- write a watch_params.json fixture with a
# roster array of n plain-string entries.
mk_watch_params() {
  local file="$1" n="$2"
  mkdir -p "$(dirname "$file")"
  python3 -c '
import json, sys
n = int(sys.argv[1])
json.dump({"roster": [f"agent{i}" for i in range(n)]}, open(sys.argv[2], "w"))
' "$n" "$file"
}

AGENT="watcher_primary"

# =============================================================================
# Scenario 1 (MANDATORY, cmain-required regression guard): a worktree that
# redirects to a main-repo tree. The "roster-editing agent's Edit-tool write"
# lands in the REDIRECT TARGET (main-repo) copy -- that's the physically
# correct, shared, redirect-resolved location per internal/paths/paths.go
# AgentDir ("the agents/ tree is shared, not per-worktree"), and it's what
# resolve_watch_params must read. A worktree-LOCAL copy at the naive,
# unresolved path is a decoy: it's what a broken script (SCRIPT_DIR-relative,
# no redirect-follow) would read instead, and it must be ignored.
#
# Bead framing: main-repo (correct) copy has 25 entries ("not 25" in the
# bug's own words -- i.e. the FIXED behavior must see 25); the worktree-local
# decoy has 24 (the stale/wrong count an unfixed script would see instead).
# =============================================================================
echo "--- Scenario 1: regression guard (redirect-resolved read wins over worktree-local decoy) ---"

worktree_root="$(mktemp -d)"
mainrepo_root="$(mktemp -d)"
trap 'rm -r -- "$worktree_root" "$mainrepo_root" 2>/dev/null || true' EXIT

mkdir -p "$worktree_root/.thrum"
printf '%s/.thrum' "$mainrepo_root" > "$worktree_root/.thrum/redirect"

mainrepo_params="$mainrepo_root/.thrum/agents/$AGENT/watch_params.json"
worktree_decoy_params="$worktree_root/.thrum/agents/$AGENT/watch_params.json"

mk_watch_params "$mainrepo_params" 25       # the real edit, correctly-wired fixture
mk_watch_params "$worktree_decoy_params" 24 # the stale worktree-local decoy

resolved="$(resolve_watch_params "$worktree_root" "$AGENT")"
assert_eq "resolves to the redirect-target (main-repo) path" "$mainrepo_params" "$resolved"
assert_ne "does NOT resolve to the worktree-local decoy path" "$worktree_decoy_params" "$resolved"
assert_eq "resolved file has the EDITED count (25, not 24)" "25" "$(roster_count "$resolved")"

# --- Negative control: prove the resolver is really reading the redirect
# target's CONTENT, not something incidental (e.g. a hardcoded/dead-end
# path, or a test bug where both fixtures happen to satisfy the assertion
# regardless of which tree holds what). Swap which tree holds the "right"
# (25) vs "wrong" (24) count, WITHOUT changing which path resolve_watch_params
# points at. If the resolver is doing real redirect-following, the resolved
# PATH stays the main-repo path (structural, content-independent), but the
# roster COUNT read from it must now be 24 (the swapped-in wrong count) --
# i.e. the same "expect 25" assertion used above must now correctly FAIL,
# proving the earlier PASS wasn't vacuous.
echo "--- Scenario 1 (mis-wired control): swapped fixture must make the same assertion fail ---"
mk_watch_params "$mainrepo_params" 24        # now the main-repo copy is "stale"
mk_watch_params "$worktree_decoy_params" 25  # decoy now happens to hold the "right" count

resolved_mis="$(resolve_watch_params "$worktree_root" "$AGENT")"
assert_eq "mis-wired: resolved path is unchanged (still the main-repo path)" "$mainrepo_params" "$resolved_mis"
got_count="$(roster_count "$resolved_mis")"
if [ "$got_count" = "25" ]; then
  echo "FAIL: mis-wired control -- expected count MISMATCH (resolver should read the swapped-in 24, not the decoy's 25) but got 25; this would mean the test passes regardless of fixture wiring"
  fail=$((fail + 1))
else
  echo "PASS: mis-wired control -- resolver reads 24 (the main-repo tree's current content), confirming it is not incidentally reading the decoy"
  pass=$((pass + 1))
fi

# restore correct wiring for anything downstream that might reuse these dirs
mk_watch_params "$mainrepo_params" 25
mk_watch_params "$worktree_decoy_params" 24

rm -r -- "$worktree_root" "$mainrepo_root"
trap - EXIT

# =============================================================================
# Scenario 2: existing (non-worktree) behavior unchanged -- no .thrum/redirect
# file at all means this IS the main repo; resolve_watch_params must fall
# through to the LOCAL .thrum/agents/<agent>/watch_params.json.
# =============================================================================
echo "--- Scenario 2: no redirect file -> resolves to local .thrum path (no regression) ---"

mainrepo_only="$(mktemp -d)"
trap 'rm -r -- "$mainrepo_only" 2>/dev/null || true' EXIT

local_params="$mainrepo_only/.thrum/agents/$AGENT/watch_params.json"
mk_watch_params "$local_params" 7
# deliberately no redirect file created

resolved_local="$(resolve_watch_params "$mainrepo_only" "$AGENT")"
assert_eq "no-redirect case resolves to the local path" "$local_params" "$resolved_local"
assert_eq "no-redirect case reads the local file's real content" "7" "$(roster_count "$resolved_local")"

rm -r -- "$mainrepo_only"
trap - EXIT

# =============================================================================
# Scenario 3 (bonus): thrum-watch-pane-capture.sh's PARAMS_FILE resolution.
# That script is NOT structured as sourceable functions (its redirect logic
# is a flat sequence of top-level assignments between REPO_ROOT and
# FALLBACK_SCRIPT, guarded by no function boundary) -- sourcing the whole
# file would run its lock-dir/roster-load/capture logic as a side effect.
# So this reproduces JUST that resolution snippet as a tiny inline harness,
# verified byte-for-byte against the live file below (so the harness can't
# silently drift from the real script) before asserting on it.
# =============================================================================
echo "--- Scenario 3 (bonus): thrum-watch-pane-capture.sh PARAMS_FILE resolution (inline harness) ---"

pane_capture_script="$SCRIPT_DIR/thrum-watch-pane-capture.sh"
if [ ! -f "$pane_capture_script" ]; then
  echo "SKIP: $pane_capture_script not found -- skipping Scenario 3"
else
  expected_snippet='THRUM_DIR="${REPO_ROOT}/.thrum"
if [ -f "${THRUM_DIR}/redirect" ]; then
  THRUM_DIR="$(tr -d '"'"'[:space:]'"'"' < "${THRUM_DIR}/redirect")"
fi
PARAMS_FILE="${THRUM_DIR}/agents/${AGENT_NAME}/watch_params.json"'
  live_snippet="$(sed -n '/^THRUM_DIR="\${REPO_ROOT}\/\.thrum"$/,/^PARAMS_FILE=/p' "$pane_capture_script")"
  if [ "$live_snippet" != "$expected_snippet" ]; then
    echo "FAIL: Scenario 3 harness has drifted from the live PARAMS_FILE resolution snippet in $pane_capture_script -- update the harness (this is a test-maintenance guard, not a product assertion)"
    echo "  live snippet was:"
    echo "$live_snippet" | sed 's/^/    /'
    fail=$((fail + 1))
  else
    echo "PASS: inline harness matches the live PARAMS_FILE resolution snippet verbatim"
    pass=$((pass + 1))

    resolve_pane_capture_params() {
      # Args: repo_root, agent_name. Mirrors the verbatim snippet above.
      local REPO_ROOT="$1" AGENT_NAME="$2" THRUM_DIR
      THRUM_DIR="${REPO_ROOT}/.thrum"
      if [ -f "${THRUM_DIR}/redirect" ]; then
        THRUM_DIR="$(tr -d '[:space:]' < "${THRUM_DIR}/redirect")"
      fi
      printf '%s/agents/%s/watch_params.json\n' "${THRUM_DIR}" "${AGENT_NAME}"
    }

    pc_worktree="$(mktemp -d)"
    pc_mainrepo="$(mktemp -d)"
    trap 'rm -r -- "$pc_worktree" "$pc_mainrepo" 2>/dev/null || true' EXIT

    mkdir -p "$pc_worktree/.thrum"
    printf '%s/.thrum' "$pc_mainrepo" > "$pc_worktree/.thrum/redirect"
    pc_mainrepo_params="$pc_mainrepo/.thrum/agents/$AGENT/watch_params.json"
    pc_decoy_params="$pc_worktree/.thrum/agents/$AGENT/watch_params.json"
    mk_watch_params "$pc_mainrepo_params" 25
    mk_watch_params "$pc_decoy_params" 24

    pc_resolved="$(resolve_pane_capture_params "$pc_worktree" "$AGENT")"
    assert_eq "pane-capture: redirect present -> resolves to main-repo path" "$pc_mainrepo_params" "$pc_resolved"
    assert_ne "pane-capture: does NOT resolve to worktree-local decoy" "$pc_decoy_params" "$pc_resolved"
    assert_eq "pane-capture: resolved file has the edited count (25)" "25" "$(roster_count "$pc_resolved")"

    rm -r -- "$pc_worktree" "$pc_mainrepo"
    trap - EXIT

    pc_mainrepo_only="$(mktemp -d)"
    trap 'rm -r -- "$pc_mainrepo_only" 2>/dev/null || true' EXIT
    pc_local_params="$pc_mainrepo_only/.thrum/agents/$AGENT/watch_params.json"
    mk_watch_params "$pc_local_params" 3
    pc_resolved_local="$(resolve_pane_capture_params "$pc_mainrepo_only" "$AGENT")"
    assert_eq "pane-capture: no redirect -> resolves to local path" "$pc_local_params" "$pc_resolved_local"
    rm -r -- "$pc_mainrepo_only"
    trap - EXIT
  fi
fi

# ---------------------------------------------------------------------------
echo "----------------------------------------"
echo "roster-watch: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
