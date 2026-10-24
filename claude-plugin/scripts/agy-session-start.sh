#!/usr/bin/env bash
# agy SessionStart adapter: runs the Claude prime hook and wraps its plain
# stdout in agy's injectSteps shape, so agy injects the same briefing Claude
# gets from inject-prime-context.sh.
#
#   stdin  agy hook input (camelCase JSON); passed through to the prime hook
#   stdout {"injectSteps":[{"systemMessage":{"systemMessage":"<briefing>"}}]}
#          or nothing when the prime hook produced no output
#
# agy runs hooks with cwd set to the plugin directory, not the workspace, so
# the prime hook (and thrum's daemon lookup) would miss the agent's worktree.
# The adapter cds to stdin.workspacePaths[0] first. ./scripts paths resolve
# from the plugin dir, so SCRIPT_DIR is taken before the cd.
#
# Only agy loads this file (claude-plugin/hooks.json, agy schema). Claude keeps
# its own SessionStart hook inline in .claude-plugin/plugin.json.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INPUT="$(cat)"

# Without jq the briefing cannot be wrapped as JSON. Stay silent rather than
# emit plain text agy would not inject.
command -v jq >/dev/null 2>&1 || exit 0

WORKSPACE="$(printf '%s' "$INPUT" | jq -r '.workspacePaths[0] // empty' 2>/dev/null || true)"
if [ -n "$WORKSPACE" ] && [ -d "$WORKSPACE" ]; then
  cd "$WORKSPACE" || exit 0
fi

BRIEFING="$(printf '%s' "$INPUT" | bash "${SCRIPT_DIR}/inject-prime-context.sh" 2>/dev/null || true)"
[ -n "$BRIEFING" ] || exit 0

printf '%s' "$BRIEFING" | jq -Rs '{injectSteps: [{systemMessage: {systemMessage: .}}]}'
