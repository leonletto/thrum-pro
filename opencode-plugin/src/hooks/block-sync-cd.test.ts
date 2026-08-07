// Regression tests for the a-sync worktree guard (block-sync-cd.ts).
// Mirrors claude-plugin/scripts/block-sync-worktree-cd_test.sh so the OpenCode
// port stays behavior-faithful to the reference bash hook.
//
// Run: npm test  (builds, then `node --test dist`)

import { test } from "node:test"
import assert from "node:assert/strict"
import { isBlockedCommand, blockSyncCdHook } from "./block-sync-cd.js"

const ASYNC = ".git/thrum-sync/a-sync"

// DENY: branch-changing ops on / cd into the a-sync worktree.
const DENY: Array<[string, string]> = [
  ["cd into a-sync", `cd ${ASYNC}`],
  ["pushd into a-sync", `pushd ${ASYNC}`],
  ["cd after &&", `git status && cd ${ASYNC}`],
  ["cd after ;", `echo hi; cd ${ASYNC}`],
  ["git -C a-sync checkout", `git -C ${ASYNC} checkout main`],
  ["git -C a-sync switch", `git -C ${ASYNC} switch main`],
  ["git -C a-sync reset --hard", `git -C ${ASYNC} reset --hard`],
  ["git -C a-sync merge", `git -C ${ASYNC} merge main`],
  ["git -C a-sync rebase", `git -C ${ASYNC} rebase main`],
  ["git -C a-sync pull", `git -C ${ASYNC} pull`],
  ["git --work-tree= checkout", `git --work-tree=${ASYNC} checkout main`],
  ["git --git-dir= checkout", `git --git-dir=${ASYNC} checkout main`],
]

// ALLOW: safe ops on a-sync, non-command-position mentions, unrelated commands.
const ALLOW: Array<[string, string]> = [
  ["bare git status", "git status"],
  ["git -C a-sync add", `git -C ${ASYNC} add .`],
  ["git -C a-sync status", `git -C ${ASYNC} status`],
  ["git -C a-sync commit", `git -C ${ASYNC} commit -m x`],
  ["git -C a-sync push", `git -C ${ASYNC} push`],
  ["git -C a-sync log (not branch-changing)", `git -C ${ASYNC} log --oneline`],
  ["ls the path", `ls ${ASYNC}/`],
  // D5 false-positive guard: cd inside a quoted argument (bare space before it),
  // not at command position -> must be ALLOWED.
  ["quoted cd inside bd remember", `bd remember "note: do not cd ${ASYNC} directly"`],
]

for (const [name, cmd] of DENY) {
  test(`DENY: ${name}`, () => {
    assert.equal(isBlockedCommand(cmd), true, `expected blocked: ${cmd}`)
  })
}

for (const [name, cmd] of ALLOW) {
  test(`ALLOW: ${name}`, () => {
    assert.equal(isBlockedCommand(cmd), false, `expected allowed: ${cmd}`)
  })
}

// Contract: the hook THROWS on a blocked bash command (OpenCode aborts the
// tool call on throw) and resolves for allowed / non-bash tools.
test("hook throws on blocked bash command", async () => {
  const hook = blockSyncCdHook()
  await assert.rejects(
    () => hook(
      { tool: "bash", sessionID: "s", callID: "c" },
      { args: { command: `git -C ${ASYNC} checkout main` } },
    ),
  )
})

test("hook resolves on allowed bash command", async () => {
  const hook = blockSyncCdHook()
  await assert.doesNotReject(
    () => hook(
      { tool: "bash", sessionID: "s", callID: "c" },
      { args: { command: `git -C ${ASYNC} add .` } },
    ),
  )
})

test("hook ignores non-bash tools", async () => {
  const hook = blockSyncCdHook()
  await assert.doesNotReject(
    () => hook(
      { tool: "read", sessionID: "s", callID: "c" },
      { args: { command: `cd ${ASYNC}` } },
    ),
  )
})
