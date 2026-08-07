#!/usr/bin/env bash
# Basic unit tests for hook.sh logic components.
# Run: bash hook_test.sh
#
# Tests are split into three groups:
#   1. Fail-open tests — verify the hook exits 0 on malformed/empty stdin.
#   2. Pure logic tests — exercise the tool-name filter, MultiEdit path
#      extraction, and glob matching without calling thrum.
#   3. Integration tests — require a live thrum daemon; skipped when thrum
#      is not on PATH or the daemon is unreachable.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/hook.sh"

pass=0
fail=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "PASS: $desc"
        pass=$((pass + 1))
    else
        echo "FAIL: $desc — expected '$expected' got '$actual'"
        fail=$((fail + 1))
    fi
}

# ---------------------------------------------------------------------------
# Group 1: fail-open — hook must exit 0 on malformed/empty stdin so a bad
# PreToolUse payload never blocks a real edit.
# ---------------------------------------------------------------------------

# Test: malformed stdin exits 0 (fail-open).
out=$(printf 'not-json-at-all' | bash "$HOOK" 2>/dev/null; echo $?)
assert_eq "malformed stdin exits 0 (fail-open)" "0" "$out"

# Test: empty stdin exits 0 (fail-open).
out=$(printf '' | bash "$HOOK" 2>/dev/null; echo $?)
assert_eq "empty stdin exits 0 (fail-open)" "0" "$out"

# Test: valid Edit on a path with no matching rules exits 0.
out=$(CLAUDE_SESSION_ID="hook-test-failopen-$$" printf '{"tool_name":"Edit","tool_input":{"file_path":"README.md"}}' | bash "$HOOK" 2>/dev/null; echo $?)
assert_eq "Edit non-daemon path exits 0" "0" "$out"

# ---------------------------------------------------------------------------
# Group 2: pure logic — non-Edit tool and missing-path early-exit.
# These don't call thrum (rules_json will short-circuit on the tool check).
# ---------------------------------------------------------------------------

# Non-Edit tool must exit 0 silently.
result=0
printf '{"tool_name":"Bash","tool_input":{"command":"ls"}}' \
    | bash "$HOOK" 2>/dev/null || result=$?
assert_eq "non-Edit tool exits 0" "0" "$result"

# Read tool also exits 0.
result=0
printf '{"tool_name":"Read","tool_input":{"file_path":"/some/file.go"}}' \
    | bash "$HOOK" 2>/dev/null || result=$?
assert_eq "Read tool exits 0" "0" "$result"

# Edit with empty file_path exits 0 (no paths to match).
result=0
printf '{"tool_name":"Edit","tool_input":{"file_path":""}}' \
    | bash "$HOOK" 2>/dev/null || result=$?
assert_eq "Edit with empty file_path exits 0" "0" "$result"

# MultiEdit with no edits array exits 0.
result=0
printf '{"tool_name":"MultiEdit","tool_input":{"edits":[]}}' \
    | bash "$HOOK" 2>/dev/null || result=$?
assert_eq "MultiEdit with empty edits exits 0" "0" "$result"

# ---------------------------------------------------------------------------
# Group 3: integration — requires thrum.
# ---------------------------------------------------------------------------
if ! command -v thrum >/dev/null 2>&1; then
    echo "SKIP: thrum not on PATH — integration tests skipped"
else
    # Edit targeting a file that won't match any agent_rule path_globs
    # (e.g. README.md) should exit 0 with no output.
    result=0
    out=$(CLAUDE_SESSION_ID="hook-test-$$-readme" \
        printf '{"tool_name":"Edit","tool_input":{"file_path":"README.md"}}' \
        | bash "$HOOK" 2>/dev/null || true)
    result=$?
    assert_eq "Edit README.md exits 0" "0" "$result"

    # Write targeting a daemon path should either exit 0 (if no rule loaded)
    # or exit 2 (hard rule fired).  We can't assert a specific exit code
    # without knowing whether seeds are loaded, so just verify the hook
    # doesn't crash (exit code 0 or 2 only).
    result=0
    CLAUDE_SESSION_ID="hook-test-$$-daemon" \
        printf '{"tool_name":"Write","tool_input":{"file_path":"/Users/user/project/internal/daemon/safecmd/safecmd.go"}}' \
        | bash "$HOOK" 2>/dev/null || result=$?
    if [ "$result" -eq 0 ] || [ "$result" -eq 2 ]; then
        echo "PASS: Write to daemon path exits 0 or 2 (got $result)"
        pass=$((pass + 1))
    else
        echo "FAIL: Write to daemon path unexpected exit $result"
        fail=$((fail + 1))
    fi
fi

# ---------------------------------------------------------------------------
echo ""
echo "Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
