#!/usr/bin/env bash
# PreToolUse hook: JIT agent-rule injection.
#
# Reads PreToolUse JSON from stdin. For Edit/Write/MultiEdit tools:
#   1. Extracts the file path(s) from tool_input.
#   2. Fetches agent_rule records (zoom=full) from thrum memory list.
#   3. Matches rules whose triggers.path_globs match the path AND
#      triggers.tools include the current tool.
#   4. Consults per-session dedup file; skips already-injected rule IDs.
#   5. Hard rules (enforcement=hard): emits permissionDecision=ask to stderr,
#      exits 2.
#   6. Soft rules (enforcement=soft): emits rule body to stdout as additional
#      context, exits 0.
#
# Dedup file: ~/.thrum/var/hook-state/$CLAUDE_SESSION_ID/injected-rules
# One rule ID per line. Created on first injection.
#
# Output contract:
#   - Soft rules: plain text to stdout → CC routes hook stdout as
#     additionalContext injected before the next model turn. No JSON envelope
#     needed; hookEventName field is not required.
#   - Hard rules: JSON to stderr with hookSpecificOutput.permissionDecision=ask
#     + permissionDecisionReason. Exit 2 triggers the ask dialog. hookEventName
#     is optional (omitted here).
#
# Plugin sync: this hook is wired in claude-plugin only. sync-skills.sh does
# not propagate hooks to opencode/codex/cursor plugins (they use different hook
# registration mechanisms). Manual step required per plugin when adopting.
#
# Smoke test: edit internal/daemon/x.go → hard rule (safedb) fires ask.
#             Edit again → dedup prevents re-fire (exits 0 for already-injected).

set -u
# Fail-open trap: any unexpected error defaults to allow so this hook
# never blocks the agent's ability to edit files. Guideline injection
# is a nicety; it must never wedge real work.
trap 'exit 0' ERR

# Require jq and thrum — bail silently if either is absent so the hook
# never blocks the agent on a misconfigured machine.
if ! command -v jq >/dev/null 2>&1 || ! command -v thrum >/dev/null 2>&1; then
    exit 0
fi

# Detect timeout command (macOS ships gtimeout via coreutils, not timeout).
_timeout_cmd=""
if command -v timeout >/dev/null 2>&1; then
    _timeout_cmd="timeout 7"
elif command -v gtimeout >/dev/null 2>&1; then
    _timeout_cmd="gtimeout 7"
fi

input=$(cat)

tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
case "$tool_name" in
    Edit|Write|MultiEdit) ;;
    *) exit 0 ;;
esac

# Extract file path(s).
file_paths=()
if [ "$tool_name" = "MultiEdit" ]; then
    while IFS= read -r p; do
        [ -n "$p" ] && file_paths+=("$p")
    done < <(printf '%s' "$input" | jq -r '.tool_input.edits[]?.file_path // empty' 2>/dev/null)
else
    fp=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
    [ -n "$fp" ] && file_paths+=("$fp")
fi

if [ ${#file_paths[@]} -eq 0 ]; then
    exit 0
fi

# Fetch agent_rule records (zoom=full).
rules_json=$(${_timeout_cmd} thrum memory list --kind agent_rule --zoom full --format json 2>/dev/null) || rules_json='{"items":[]}'

# Per-session dedup file.
session_id="${CLAUDE_SESSION_ID:-default}"
dedup_dir="${HOME}/.thrum/var/hook-state/${session_id}"
dedup_file="${dedup_dir}/injected-rules"
mkdir -p "$dedup_dir" 2>/dev/null || { dedup_file=/dev/null; }
touch "$dedup_file" 2>/dev/null || { dedup_file=/dev/null; }

# Match rules against file paths and tool.
matched_hard=()
matched_soft=()

rule_count=$(printf '%s' "$rules_json" | jq '.items | length' 2>/dev/null) || exit 0
[ -z "$rule_count" ] && exit 0

for i in $(seq 0 $((rule_count - 1))); do
    rule=$(printf '%s' "$rules_json" | jq ".items[$i]" 2>/dev/null) || continue
    rule_id=$(printf '%s' "$rule" | jq -r '.id // empty' 2>/dev/null) || continue
    metadata_raw=$(printf '%s' "$rule" | jq -r '.metadata // empty' 2>/dev/null) || continue

    # Parse triggers from metadata — metadata may be a JSON string or
    # already an object; try both before giving up.
    triggers=$(printf '%s' "$metadata_raw" | jq -r '.triggers // empty' 2>/dev/null || echo '')
    [ -z "$triggers" ] && continue
    # jq returns 'null' when the key exists but is null.
    [ "$triggers" = "null" ] && continue

    enforcement=$(printf '%s' "$triggers" | jq -r '.enforcement // "soft"' 2>/dev/null) || enforcement="soft"
    tools_json=$(printf '%s' "$triggers" | jq -c '.tools // []' 2>/dev/null) || tools_json='[]'
    globs_json=$(printf '%s' "$triggers" | jq -c '.path_globs // []' 2>/dev/null) || globs_json='[]'

    # Check tool match.
    tool_match=$(printf '%s' "$tools_json" | jq --arg t "$tool_name" 'map(select(. == $t)) | length > 0' 2>/dev/null) || continue
    [ "$tool_match" = "true" ] || continue

    # Check path glob match against any file path.
    glob_count=$(printf '%s' "$globs_json" | jq 'length' 2>/dev/null) || continue
    path_matched=false
    for fp in "${file_paths[@]}"; do
        for gi in $(seq 0 $((glob_count - 1))); do
            glob=$(printf '%s' "$globs_json" | jq -r ".[$gi]" 2>/dev/null) || continue
            # Use bash extglob-style [[ == ]] pattern matching.
            # shellcheck disable=SC2053
            if [[ "$fp" == $glob ]]; then
                path_matched=true
                break 2
            fi
        done
    done
    "$path_matched" || continue

    # Check dedup — skip rules already injected this session.
    if grep -qxF "$rule_id" "$dedup_file" 2>/dev/null; then
        continue
    fi

    body=$(printf '%s' "$rule" | jq -r '.body_full // .body_oneline // empty' 2>/dev/null) || continue
    title=$(printf '%s' "$rule" | jq -r '.title // empty' 2>/dev/null) || continue

    case "$enforcement" in
        hard) matched_hard+=("${rule_id}"$'\x01'"${title}"$'\x01'"${body}") ;;
        *)    matched_soft+=("${rule_id}"$'\x01'"${title}"$'\x01'"${body}") ;;
    esac
done

# Emit soft rules as additional context (stdout, exit 0).
for entry in "${matched_soft[@]}"; do
    IFS=$'\x01' read -r rule_id title body <<< "$entry"
    printf '%s\n' "$rule_id" >> "$dedup_file"
    printf 'Agent Rule: %s\n\n%s\n\n' "$title" "$body"
done

# Emit first hard rule as ask (stderr, exit 2).
# Only one hard rule per invocation — Claude Code routes the first
# permissionDecision=ask to the user and retries; subsequent rules
# fire on the retry.
if [ ${#matched_hard[@]} -gt 0 ]; then
    IFS=$'\x01' read -r rule_id title body <<< "${matched_hard[0]}"
    printf '%s\n' "$rule_id" >> "$dedup_file"
    reason="Agent rule (enforcement=hard): ${title} -- ${body}"
    if output=$(jq -n --arg reason "$reason" \
        '{"hookSpecificOutput":{"permissionDecision":"ask","permissionDecisionReason":$reason}}' \
        2>/dev/null); then
        printf '%s\n' "$output" >&2
        exit 2
    fi
    # jq failed — emit anyway with best-effort string (tr-sanitized).
    safe_reason=$(printf '%s' "$reason" | tr '\n' ' ' | tr '"' "'" | tr '\\' '/')
    printf '{"hookSpecificOutput":{"permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' \
        "$safe_reason" >&2
    exit 2
fi

exit 0
