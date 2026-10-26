// tool.execute.after hook: point the agent at the memory-to-thrum-pointer skill
// when a tool wrote a memory file (AGENTS.md, a memory dir, .cursor/rules) or
// saved one through a memory tool.
//
// The decision lives in the shared memory-pointer.sh, which every runtime runs.
// This shim only passes the tool call in and appends the line it prints.
import { execFile } from "node:child_process"
import { fileURLToPath } from "node:url"

const SCRIPT = fileURLToPath(new URL("../../assets/hooks/memory-pointer.sh", import.meta.url))

export function memoryPointerHook() {
  return async (
    input: { tool: string; args?: unknown },
    output: { output: string },
  ) => {
    const payload = JSON.stringify({ tool_name: input.tool, tool_input: input.args ?? {} })
    const line = await runHook(payload)
    if (line) output.output += `\n${line}`
  }
}

function runHook(payload: string): Promise<string> {
  return new Promise((resolve) => {
    const child = execFile(
      "bash",
      [SCRIPT, "--out", "text"],
      { timeout: 5000 },
      (err, stdout) => resolve(err ? "" : stdout.trim()),
    )
    child.stdin?.end(payload)
  })
}
