#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/stop-check-messages.sh"
TMP="$(mktemp -d)"
trap 'rm -r "${TMP:?}"' EXIT
BIN="${TMP}/bin"
PROJECT="${TMP}/project"
mkdir -p "$BIN" "$PROJECT/.thrum"
printf '{"daemon":{"single_agent_mode":false}}\n' > "$PROJECT/.thrum/config.json"

cat > "$BIN/claude" <<'EOF'
#!/bin/sh
[ "${1:-}" = "--version" ] || exit 1
printf '%s\n' "${MOCK_CLAUDE_VERSION:-}"
EOF
cat > "$BIN/thrum" <<'EOF'
#!/bin/sh
case "$*" in
  'daemon status') exit 0 ;;
  'inbox --unread --json') printf '{"unread":%s}\n' "${MOCK_UNREAD:-1}" ;;
  'whoami --field tmux_session') exit 0 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$BIN/claude" "$BIN/thrum"

run_hook() {
  local version="$1" unread="$2" stdout="$3" stderr="$4" status=0
  printf '{"stop_hook_active":false}\n' |
    env PATH="$BIN:$PATH" CLAUDE_PROJECT_DIR="$PROJECT" THRUM_HOME="$PROJECT" THRUM_AGENT_ID=stop-hook-test \
      MOCK_CLAUDE_VERSION="$version" MOCK_UNREAD="$unread" bash "$HOOK" >"$stdout" 2>"$stderr" || status=$?
  return "$status"
}

assert_feedback_shape() {
  local json_file="$1" prefix="$2"
  jq -e --arg prefix "$prefix" '
    type == "object" and
    (keys == ["hookSpecificOutput"]) and
    (.hookSpecificOutput | type == "object") and
    (.hookSpecificOutput | keys == ["additionalContext", "hookEventName"]) and
    (.hookSpecificOutput.hookEventName == "Stop") and
    (.hookSpecificOutput.additionalContext | type == "string" and startswith($prefix))
  ' "$json_file" >/dev/null
}

OUT="${TMP}/supported.stdout"
ERR="${TMP}/supported.stderr"
if run_hook '2.1.163 (Claude Code)' 3 "$OUT" "$ERR"; then
  :
else
  echo "FAIL: supported Claude version did not continue with feedback"
  exit 1
fi
assert_feedback_shape "$OUT" 'ACTION REQUIRED: You have 3 unread message(s).'
[[ ! -s "$ERR" ]] || { echo "FAIL: supported version wrote to stderr"; exit 1; }

OUT="${TMP}/listener.stdout"
ERR="${TMP}/listener.stderr"
if run_hook '2.1.302 (Claude Code)' 0 "$OUT" "$ERR"; then
  :
else
  echo "FAIL: supported listener warning did not continue with feedback"
  exit 1
fi
assert_feedback_shape "$OUT" 'Your background message listener is not running.'
[[ ! -s "$ERR" ]] || { echo "FAIL: supported listener warning wrote to stderr"; exit 1; }

for version in '2.1.162 (Claude Code)' 'unknown version'; do
  OUT="${TMP}/legacy.stdout"
  ERR="${TMP}/legacy.stderr"
  if run_hook "$version" 1 "$OUT" "$ERR"; then
    echo "FAIL: unsupported Claude version '$version' did not retain exit 2"
    exit 1
  else
    status=$?
    [[ "$status" -eq 2 ]] || { echo "FAIL: expected exit 2 for '$version', got $status"; exit 1; }
  fi
  [[ ! -s "$OUT" ]] || { echo "FAIL: unsupported Claude version emitted stdout"; exit 1; }
  grep -Fq 'ACTION REQUIRED: You have 1 unread message(s).' "$ERR" || {
    echo "FAIL: unsupported Claude version omitted the legacy stderr message"
    exit 1
  }
done

echo "PASS: Stop feedback JSON shape and legacy-version fallback"
