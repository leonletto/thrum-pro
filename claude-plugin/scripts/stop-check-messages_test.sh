#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/stop-check-messages.sh"
TMP="$(mktemp -d)"
export THRUM_STOP_NUDGE_SYNC=1
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
  'inbox --unread --json')
    # First call is the hook's count; later calls are the helper's recheck.
    n=0; [ ! -f "${MOCK_INBOX_N:-/nonexistent}" ] || n=$(cat "$MOCK_INBOX_N")
    n=$((n + 1)); [ -z "${MOCK_INBOX_N:-}" ] || printf '%s' "$n" > "$MOCK_INBOX_N"
    if [ "$n" -gt 1 ] && [ -n "${MOCK_RECHECK_UNREAD:-}" ]; then
      printf '{"unread":%s}\n' "$MOCK_RECHECK_UNREAD"
    else
      printf '{"unread":%s}\n' "${MOCK_UNREAD:-1}"
    fi ;;
  tmux\ wait-pane-ready\ *) exit "${MOCK_WAIT_RC:-0}" ;;
  'whoami --field tmux_session') [ -z "${MOCK_TMUX:-}" ] || printf '%s\n' "$MOCK_TMUX"; exit 0 ;;
  tmux\ send\ *) printf '%s\n' "$*" >> "${MOCK_SEND_LOG:-/dev/null}"; exit "${MOCK_SEND_RC:-0}" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$BIN/claude" "$BIN/thrum"

run_hook() {
  local version="$1" unread="$2" stdout="$3" stderr="$4" status=0
  printf '{"stop_hook_active":false}\n' |
    env PATH="$BIN:$PATH" CLAUDE_PROJECT_DIR="$PROJECT" THRUM_HOME="$PROJECT" THRUM_AGENT_ID=stop-hook-test \
      MOCK_TMUX="${MOCK_TMUX:-}" MOCK_SEND_LOG="${MOCK_SEND_LOG:-}" MOCK_SEND_RC="${MOCK_SEND_RC:-0}" \
      MOCK_INBOX_N="${MOCK_INBOX_N:-}" MOCK_RECHECK_UNREAD="${MOCK_RECHECK_UNREAD:-}" MOCK_WAIT_RC="${MOCK_WAIT_RC:-0}" \
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

# tmux agent with unread mail: nudge the pane once, never block the stop.
for send_rc in 0 1; do
  OUT="${TMP}/tmux.stdout"; ERR="${TMP}/tmux.stderr"; SENDLOG="${TMP}/tmux.send"
  : > "$SENDLOG"
  status=0
  MOCK_TMUX=managed-session MOCK_SEND_LOG="$SENDLOG" MOCK_SEND_RC="$send_rc" \
    run_hook '2.1.302 (Claude Code)' 2 "$OUT" "$ERR" || status=$?
  [[ "$status" -eq 0 ]] || { echo "FAIL: tmux agent stop exited $status (send rc $send_rc)"; exit 1; }
  [[ ! -s "$OUT" ]] || { echo "FAIL: tmux agent stop emitted stdout feedback"; cat "$OUT"; exit 1; }
  grep -q 'ACTION REQUIRED' "$ERR" && { echo "FAIL: tmux agent stop emitted block text on stderr"; exit 1; }
  n=$(grep -c '^tmux send stop-hook-test ' "$SENDLOG" || true)
  [[ "$n" -eq 1 ]] || { echo "FAIL: expected exactly 1 tmux send, got $n (send rc $send_rc)"; exit 1; }
  grep -Fq 'You have 2 unread message(s)' "$SENDLOG" || { echo "FAIL: nudge text missing"; exit 1; }
done

# Delivery-time recheck: (a) read before delivery -> no send; (b) still unread
# -> exactly one send with the fresh count; (c) pane never ready -> no send.
for scenario in a b c; do
  OUT="${TMP}/rc-$scenario.stdout"; ERR="${TMP}/rc-$scenario.stderr"; SENDLOG="${TMP}/rc-$scenario.send"
  : > "$SENDLOG"; rm -f "${TMP}/rc-$scenario.n"
  recheck=2; wait_rc=0; want=1
  [[ "$scenario" != a ]] || { recheck=0; want=0; }
  [[ "$scenario" != c ]] || { wait_rc=1; want=0; }
  status=0
  MOCK_TMUX=managed-session MOCK_SEND_LOG="$SENDLOG" MOCK_INBOX_N="${TMP}/rc-$scenario.n" \
    MOCK_RECHECK_UNREAD="$recheck" MOCK_WAIT_RC="$wait_rc" \
    run_hook '2.1.302 (Claude Code)' 3 "$OUT" "$ERR" || status=$?
  [[ "$status" -eq 0 && ! -s "$OUT" ]] || { echo "FAIL: recheck scenario $scenario blocked or exited $status"; exit 1; }
  n=$(grep -c '^tmux send ' "$SENDLOG" || true)
  [[ "$n" -eq "$want" ]] || { echo "FAIL: recheck scenario $scenario expected $want sends, got $n"; exit 1; }
  if [[ "$want" -eq 1 ]]; then
    grep -Fq 'You have 2 unread message(s)' "$SENDLOG" || { echo "FAIL: fresh count missing from nudge"; exit 1; }
  fi
done

# tmux agent with no unread mail: no nudge.
OUT="${TMP}/tmux0.stdout"; ERR="${TMP}/tmux0.stderr"; SENDLOG="${TMP}/tmux0.send"; : > "$SENDLOG"
MOCK_TMUX=managed-session MOCK_SEND_LOG="$SENDLOG" run_hook '2.1.302 (Claude Code)' 0 "$OUT" "$ERR" || { echo "FAIL: tmux no-unread exit"; exit 1; }
[[ ! -s "$SENDLOG" && ! -s "$OUT" ]] || { echo "FAIL: tmux agent with no unread nudged or blocked"; exit 1; }

echo "PASS: Stop feedback JSON shape and legacy-version fallback"
