#!/usr/bin/env bash
# Regression tests for the a-sync worktree guard (block-sync-worktree-cd.sh).
#
# This anchors cd/git at COMMAND POSITION so the hook stops false-positiving on
# benign commands (docs, memory writes) that merely MENTION the a-sync path
# next to the word "cd". Executable assertions:
#   real destructive ops  -> DENY (exit 2)
#   path mentioned in text -> ALLOW (exit 0)
#   safe git ops on a-sync -> ALLOW (exit 0)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/block-sync-worktree-cd.sh"
ASYNC='.git/thrum-sync/a-sync'

if [[ ! -f "$HOOK" ]]; then
  echo "FAIL: hook not found at $HOOK"
  exit 1
fi

fails=0

run_case() {
  local want="$1" desc="$2" cmd="$3"
  local json got
  json=$(jq -nc --arg c "$cmd" '{tool_name:"Bash", tool_input:{command:$c}}')
  set +e
  echo "$json" | bash "$HOOK" >/dev/null 2>&1
  got=$?
  set -e
  if [[ "$got" -ne "$want" ]]; then
    echo "FAIL [$desc]: expected exit $want, got $got — cmd: $cmd"
    fails=$((fails + 1))
  else
    echo "ok   [$desc]"
  fi
}

# Real destructive ops -> DENY
run_case 2 "cd into a-sync"            "cd $ASYNC"
run_case 2 "cd into a-sync after &&"   "git status && cd $ASYNC"
run_case 2 "git -C a-sync checkout"    "git -C $ASYNC checkout main"
run_case 2 "git -C a-sync reset"       "git -C $ASYNC reset --hard"

# The path appears as TEXT inside a quoted argument, preceded by a bare
# space — not an actual cd/git command.
run_case 0 "bd remember mentions cd+path" "bd remember \"to inspect, cd $ASYNC and look\""
run_case 0 "echo mentions the path"        "echo \"never cd $ASYNC\""

# Safe git ops on a-sync remain allowed (no branch change).
run_case 0 "git -C a-sync add"         "git -C $ASYNC add ."
run_case 0 "git -C a-sync status"      "git -C $ASYNC status"

# Regression: `[^\s]` inside a bracket expression is NOT "non-whitespace" in
# ERE — it excludes backslash and the letter 's', so any path with an 's'
# before .git slipped through. Every real worktree path contains one.
WT='/tmp/example/.thrum/worktrees/thrum/foo'
SB='/tmp/sandbox'
run_case 2 "cd abs path w/ 's' (worktrees)"  "cd $WT/$ASYNC"
run_case 2 "cd abs path w/ 's' (sandbox)"    "cd $SB/$ASYNC"
run_case 2 "cd relative ../.git a-sync"      "cd ../$ASYNC"
run_case 2 "cd sandbox && ls"                "cd $SB/$ASYNC && ls"
run_case 2 "pushd sandbox"                   "pushd $SB/$ASYNC"
run_case 2 "cd double-quoted sandbox"        "cd \"$SB/$ASYNC\""
run_case 2 "cd single-quoted worktrees"      "cd '$WT/$ASYNC'"
run_case 2 "git -C sandbox checkout"         "git -C $SB/$ASYNC checkout main"
run_case 2 "git -C quoted worktrees reset"   "git -C \"$WT/$ASYNC\" reset --hard"
run_case 2 "git --work-tree sandbox checkout" "git --work-tree=$SB/$ASYNC checkout main"
run_case 2 "git --git-dir sandbox checkout"  "git --git-dir=$SB/$ASYNC checkout main"
run_case 0 "benign cd sandbox/src"           "cd $SB/src"
run_case 0 "benign cd worktrees .git"        "cd $WT/.git"
run_case 0 "git -C sandbox a-sync status"    "git -C $SB/$ASYNC status"

if [[ "$fails" -ne 0 ]]; then
  echo "FAILED: $fails case(s)"
  exit 1
fi
echo "PASS: all a-sync guard regression cases"
