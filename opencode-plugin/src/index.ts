import type { Plugin, PluginModule } from "@opencode-ai/plugin"
import { installAssets, installPermissions } from "./installer.js"
import { shellEnvHook } from "./hooks/shell-env.js"
import { blockSyncCdHook } from "./hooks/block-sync-cd.js"

const TOOL_MAPPING = `
## Thrum Plugin — Tool Mapping for OpenCode

When Thrum skills reference Claude Code tool names, use these OpenCode equivalents:
- TodoWrite → todowrite
- Task (subagents) → @mention syntax (e.g., @explore, @general)
- Skill tool → OpenCode's native skill tool
- Agent tool → @mention syntax for subagents
- Read, Write, Edit, Bash → your native tools (same names, lowercase)
`.trim()

const server: Plugin = async (ctx) => {
  await installAssets(ctx)
  // Runs unconditionally (not version-gated like installAssets above): it's
  // cheap and idempotent, and gating it on the skills-version marker would
  // skip re-merging the allowlist for users who already had the plugin
  // installed before this permission block existed (allowlist).
  //
  // installPermissions() throws when the user's existing global
  // opencode.json is present but malformed (unreadable or invalid JSON) —
  // deliberately, so we never silently overwrite it (allowlist landing-
  // blocker). Catch and log here rather than letting it become an unhandled
  // rejection that would abort plugin bootstrap entirely; every other hook
  // this plugin provides should still register.
  try {
    await installPermissions()
  } catch (err) {
    await ctx.client.app.log({
      body: {
        service: "opencode-thrum",
        level: "error",
        message: `failed to install thrum permission allowlist (leaving your opencode.json untouched): ${(err as Error).message}`,
      },
    })
  }

  return {
    "shell.env": shellEnvHook(ctx),
    "tool.execute.before": blockSyncCdHook(),
    "experimental.chat.system.transform": async (
      _input: { sessionID?: string; model?: unknown },
      output: { system: string[] },
    ) => {
      ;(output.system ||= []).push(TOOL_MAPPING)
    },
  }
}

export default { id: "opencode-thrum", server } satisfies PluginModule
