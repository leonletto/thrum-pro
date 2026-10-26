// Tests for the memory pointer shim (memory-pointer.ts). The decision lives in
// assets/hooks/memory-pointer.sh, which claude-plugin/hooks/memory-pointer
// owns; these check the OpenCode side: the tool-call shape handed in and the
// line appended to output.output.
//
// Run: npm test  (builds, then `node --test dist`)

import { test } from "node:test"
import assert from "node:assert/strict"
import { memoryPointerHook } from "./memory-pointer.js"

const hook = memoryPointerHook()

test("a write to AGENTS.md appends the skill reminder", async () => {
  const output = { output: "wrote file" }
  await hook({ tool: "write", args: { filePath: "/repo/AGENTS.md", content: "x" } }, output)
  assert.match(output.output, /Memory entry written: \/repo\/AGENTS\.md\. Run the memory-to-thrum-pointer skill/)
})

test("an edit to a memory topic file appends the reminder", async () => {
  const output = { output: "edited" }
  await hook({ tool: "edit", args: { filePath: "/h/.claude/projects/-x/memory/feedback.md" } }, output)
  assert.match(output.output, /memory-to-thrum-pointer/)
})

test("a read of AGENTS.md leaves the output unchanged", async () => {
  const output = { output: "contents" }
  await hook({ tool: "read", args: { filePath: "/repo/AGENTS.md" } }, output)
  assert.equal(output.output, "contents")
})

test("a write to a source file leaves the output unchanged", async () => {
  const output = { output: "ok" }
  await hook({ tool: "write", args: { filePath: "/repo/main.go", content: "x" } }, output)
  assert.equal(output.output, "ok")
})

test("positive control: the same write to a memory path does append", async () => {
  const output = { output: "ok" }
  await hook({ tool: "write", args: { filePath: "/repo/GEMINI.md", content: "x" } }, output)
  assert.notEqual(output.output, "ok")
})
