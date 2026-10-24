#!/usr/bin/env bash
# Focused checks for to-thrum.sh with a fake thrum on PATH. No real daemon.
# The entitlement is the daemon's answer to a memory.edit probe, so the fake
# answers that probe from FAKE_PROBE (granted: "not found" for the probe ID;
# not granted: the license error). Tier names are not consulted.
# Covers: refusal before any change when not entitled, refusal when THRUM_REPO
# is unset, a granted create that verifies byte for byte, and that a granted
# entitlement proceeds whatever the license tier.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/to-thrum-test.XXXXXX")"
trap 'rm -r "${TMP:?}"' EXIT

BIN="$TMP/bin"; LOG="$TMP/calls.log"; STORE="$TMP/store"
mkdir -p "$BIN" "$STORE" "$TMP/repo" "$TMP/memory"
export FAKE_LOG="$LOG" FAKE_STORE="$STORE"

# Fake thrum. memory edit (the probe) prints FAKE_PROBE_OUT. memory create
# stores the --full body and returns an ID. memory show prints the stored body.
cat > "$BIN/thrum" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_LOG"
case "$1 ${2:-}" in
  "memory edit")
    cat "$FAKE_PROBE_OUT" ;;
  "memory create")
    full=""; while [ $# -gt 0 ]; do [ "$1" = "--full" ] && { full="${2#@}"; break; }; shift; done
    cp "$full" "$FAKE_STORE/mem-1.body"; echo '{"id":"mem-1"}' ;;
  "memory show")
    cat "$FAKE_STORE/mem-1.body" ;;
  *) echo "unexpected: $*" >&2; exit 9 ;;
esac
FAKE
chmod +x "$BIN/thrum"

# Probe answers. "not found" means the gate passed; the license line means it did not.
printf 'Error: memory.edit: RPC error -32000: memory.edit: memory: not found: thrum-mem-entitlement-probe-000\n' > "$TMP/probe-granted"
printf 'Error: memory.substrate requires a license — run `thrum license` to activate\n' > "$TMP/probe-not-granted"

topic="$TMP/memory/topic.md"
printf -- '---\nname: topic\nmetadata:\n  type: feedback\n---\n\nRule body line one.\nRule body line two.\n' > "$topic"
before="$(cat "$topic")"
index="$TMP/memory/MEMORY.md"; printf -- '- index line\n' > "$index"; index_before="$(cat "$index")"

fail() { echo "FAIL: $*" >&2; exit 1; }
run() { PATH="$BIN:$PATH" FAKE_PROBE_OUT="$1" THRUM_REPO="$TMP/repo" \
  bash "$SCRIPT_DIR/to-thrum.sh" "$2" "$3" 2>&1; }

# 1. Not entitled: exit 7, plain message, nothing changed, no create called.
: > "$LOG"
set +e
out="$(run "$TMP/probe-not-granted" "$topic" "before any change")"; rc=$?
set -e
[ "$rc" -eq 7 ] || fail "not-entitled exit was $rc, want 7"
printf '%s' "$out" | grep -q 'needs Thrum Pro (free for eligible public repositories)' || fail "missing Pro message"
[ "$(cat "$topic")" = "$before" ] || fail "topic file changed while not entitled"
[ "$(cat "$index")" = "$index_before" ] || fail "index changed while not entitled"
grep -q 'memory create' "$LOG" && fail "memory create ran while not entitled"

# 2. THRUM_REPO unset: refuse with exit 2 and change nothing.
set +e
PATH="$BIN:$PATH" FAKE_PROBE_OUT="$TMP/probe-granted" env -u THRUM_REPO \
  bash "$SCRIPT_DIR/to-thrum.sh" "$topic" "x" >/dev/null 2>&1; rc=$?
set -e
[ "$rc" -eq 2 ] || fail "unset THRUM_REPO exit was $rc, want 2"

# 3. Entitled: create, verify byte for byte, and add thrum_memory to frontmatter.
id="$(run "$TMP/probe-granted" "$topic" "when the rule applies")"
[ "$id" = "mem-1" ] || fail "id was [$id], want mem-1"
grep -q '^  thrum_memory: mem-1$' "$topic" || fail "thrum_memory not written to frontmatter"
[ "$(cat "$index")" = "$index_before" ] || fail "index changed by the helper"

# 4. The tier does not matter: an entitled probe proceeds for any license tier.
#    The fake ignores the tier, so this checks that the helper does not read it.
topic2="$TMP/memory/topic2.md"
printf -- '---\nname: topic2\nmetadata:\n  type: feedback\n---\n\nSecond rule body.\n' > "$topic2"
id2="$(run "$TMP/probe-granted" "$topic2" "granted under any tier")"
[ -n "$id2" ] || fail "granted entitlement did not create a record"

echo "PASS: to-thrum.sh refuses when memory.substrate is not granted (no change), and proceeds when it is"
