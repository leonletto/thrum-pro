#!/usr/bin/env bash
# Memory pointer hook: point the agent at the memory-to-thrum-pointer skill when
# a memory file is written or a memory tool saves a memory.
#
# One script serves every runtime. It reads the tool payload on stdin and finds
# target paths by shape: a path field, an apply_patch header (Add File / Update
# File), or a shell command that writes a memory file. The tool name only says
# whether the payload can be a write at all. Nothing here branches on runtime.
#
# Usage: memory-pointer.sh [--out hook|additional|cursor|text|mark|emit]
#   hook        stdout {"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":...}}
#   additional  stdout {"additionalContext":...}
#   cursor      stdout {"additional_context":...}
#   text        stdout the reminder line only (a plugin shim appends it)
#   mark        append the reminder to the pending file, no stdout (a PostToolUse
#               hook whose output does not reach the model)
#   emit        stdout the pending reminders as an injectSteps systemMessage, then
#               clear them (a PreInvocation hook that runs before the next turn)
#
# Memory files: a *.md directly inside a directory named "memory" (MEMORY.md
# included), any AGENTS.md or GEMINI.md, and any .mdc under .cursor/rules/.
#
# Fail-open: any error exits 0 with no output, so this hook never blocks an edit.
set -u
trap 'exit 0' ERR

command -v jq >/dev/null 2>&1 || exit 0

out=hook
while [ $# -gt 0 ]; do
    case "$1" in
        --out) out=${2:-hook}; shift 2 ;;
        *) shift ;;
    esac
done

pending="${THRUM_MEMORY_POINTER_PENDING:-${HOME}/.thrum/var/memory-pointer/pending}"

if [ "$out" = emit ]; then
    [ -s "$pending" ] || exit 0
    reminders=$(cat "$pending")
    rm -f "$pending"
    printf '%s' "$reminders" | jq -Rs '{injectSteps:[{systemMessage:{systemMessage:.}}]}'
    exit 0
fi

input=$(cat)

tool=$(printf '%s' "$input" | jq -r '.tool_name // .toolName // .toolCall.name // empty' 2>/dev/null) || exit 0

# Only what the tool was asked to do counts as a write. A tool_response or
# toolResult can echo a memory path or a write operator (a read of SKILL.md
# shows AGENTS.md text), so the response never enters the scan.
scope=$(printf '%s' "$input" | jq -c '[.tool_input, .toolArgs, .toolCall.args, .args] | map(select(. != null))' 2>/dev/null) || exit 0

# Tool kinds: a file-write tool counts for its path fields and patch text; a
# memory tool counts on its own; a shell tool counts only for a write operator
# aimed at a memory file.
is_write=0
is_memory_tool=0
case "$tool" in
    Write|Edit|MultiEdit|StrReplace|write_file|edit_file|write|edit|apply_patch) is_write=1 ;;
    add_memory|edit_memory|store_memory) is_memory_tool=1 ;;
    Bash|bash|run_command|Shell|shell) is_write=2 ;;
esac

is_memory_path() {
    local p=$1 base dir
    base=$(basename "$p")
    dir=$(dirname "$p")
    case "$base" in
        AGENTS.md|GEMINI.md) return 0 ;;
        *.md) [ "$(basename "$dir")" = memory ] && return 0 ;;
        *.mdc) [ "$(basename "$dir")" = rules ] && [ "$(basename "$(dirname "$dir")")" = .cursor ] && return 0 ;;
    esac
    return 1
}

reminder=""
if [ "$is_write" -eq 1 ] || [ "$is_memory_tool" -eq 1 ]; then
    strs=$(printf '%s' "$scope" | jq -r '.. | strings' 2>/dev/null) || exit 0
    paths=$(printf '%s' "$scope" | jq -r '.. | objects | to_entries[] | select(.key | IN("file_path","filePath","Path","path")) | .value | strings' 2>/dev/null) || exit 0
    # -E: BSD sed (macOS) has no \| alternation in basic regexps.
    patch_paths=$(printf '%s\n' "$strs" | sed -E -n 's/^\*\*\* (Add|Update) File: //p')
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        if is_memory_path "$p"; then
            reminder="Memory entry written: ${p}. Run the memory-to-thrum-pointer skill for this entry."
            break
        fi
    done <<EOF
$paths
$patch_paths
EOF
fi

if [ -z "$reminder" ] && [ "$is_memory_tool" -eq 1 ]; then
    reminder="Memory saved with ${tool}. Run the memory-to-thrum-pointer skill for this entry."
fi

if [ -z "$reminder" ] && [ "$is_write" -eq 2 ]; then
    strs=$(printf '%s' "$scope" | jq -r '.. | strings' 2>/dev/null) || exit 0
    if printf '%s\n' "$strs" | grep -qE '(>>?|tee |sed -i|cp |mv |install )[^;&|]*(AGENTS\.md|GEMINI\.md|MEMORY\.md|/memory/[^ ]*\.md|\.cursor/rules/[^ ]*\.mdc)'; then
        reminder="Memory file written by a shell command. Run the memory-to-thrum-pointer skill for the entry it changed."
    fi
fi

[ -n "$reminder" ] || exit 0

case "$out" in
    hook)       jq -n --arg c "$reminder" '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$c}}' ;;
    additional) jq -n --arg c "$reminder" '{additionalContext:$c}' ;;
    cursor)     jq -n --arg c "$reminder" '{additional_context:$c}' ;;
    text)       printf '%s\n' "$reminder" ;;
    mark)       mkdir -p "$(dirname "$pending")" && printf '%s\n' "$reminder" >> "$pending" ;;
esac
exit 0
