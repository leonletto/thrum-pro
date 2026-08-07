// tool.execute.before hook: protect the a-sync JSONL worktree from destruction.
//
// .git/thrum-sync/a-sync/ is a detached git worktree living INSIDE .git/.
// It holds the append-only JSONL event log for thrum message sync.
//
// DANGER: If you check out a different branch in that worktree, git replaces
// its contents — but since it lives inside .git/, this DESTROYS the git object
// store, refs, and config. The entire repo and ALL worktrees are wiped.
//
// This happened once and required significant effort to recover.
//
// Faithful port of claude-plugin/scripts/block-sync-worktree-cd.sh (4 patterns
// + command-position anchor). OpenCode contract: throwing inside
// tool.execute.before ABORTS the tool call (the bash command never runs) —
// verified against sst/opencode plugin dispatch (raw `yield*`, no catch).
//
// Blocked:
//   1. cd/pushd/chdir into the a-sync worktree (prevents arbitrary commands there)
//   2. git -C <a-sync-path> with branch-changing commands (checkout, switch,
//      reset, merge, rebase, pull) — these change HEAD without cd
//   3. git --work-tree=<a-sync-path> with branch-changing commands
//   4. git --git-dir=<a-sync-path> with branch-changing commands
//
// Allowed:
//   git -C <a-sync-path> add/commit/push/status/rm/log/diff — safe operations
//   ls/cat/grep/rm on absolute paths — no CWD change

// Matches the literal sync-worktree path. Mirrors SYNC_PATTERN in the bash hook.
const SYNC = String.raw`\.git/thrum-sync/a-sync`

// Command-position anchor: line start or immediately after a shell separator
// (;, &&, ||), then optional whitespace. This matches `cd`/`git` only when they
// are the actual command — NOT when those words appear inside a quoted argument
// preceded by a bare space (the D5 false-positive: `bd remember "... cd
// .git/thrum-sync/a-sync ..."` must NOT be denied). Match op-shape, not the mere
// presence of the path string.
const CMDPOS = String.raw`(^|;|&&|\|\|)\s*`

// Branch-changing git subcommands that mutate HEAD / working tree.
const BRANCH_CHANGING = String.raw`(checkout|switch|reset|merge|rebase|pull)\b`

// The `m` flag makes `^` in CMDPOS match the start of each line, mirroring the
// line-by-line behavior of `echo "$command" | grep -E` in the bash hook.
const PATTERNS: RegExp[] = [
  // 1. cd/pushd/chdir into the a-sync worktree (command-position only)
  new RegExp(String.raw`${CMDPOS}(cd|pushd|chdir)\s+['"]?[^\s]*${SYNC}`, "m"),
  // 2. git -C <a-sync-path> with a branch-changing command
  new RegExp(String.raw`${CMDPOS}git\s+-C\s+['"]?[^\s]*${SYNC}['"]?\s+${BRANCH_CHANGING}`, "m"),
  // 3. git --work-tree=<a-sync-path> ... branch-changing command
  new RegExp(String.raw`${CMDPOS}git\s+--work-tree[= ]['"]?[^\s]*${SYNC}['"]?\s+.*${BRANCH_CHANGING}`, "m"),
  // 4. git --git-dir=<a-sync-path> ... branch-changing command
  new RegExp(String.raw`${CMDPOS}git\s+--git-dir[= ]['"]?[^\s]*${SYNC}['"]?\s+.*${BRANCH_CHANGING}`, "m"),
]

const DENY_MESSAGE =
  "BLOCKED: branch-changing git operations on (or cd into) the " +
  ".git/thrum-sync/a-sync/ worktree are forbidden. That worktree lives INSIDE " +
  ".git/ — checking out a different branch there DESTROYS the entire git object " +
  "store, wiping the repo and all worktrees. Use absolute paths with safe " +
  "operations (ls, grep, rm, git -C ... add/commit/push) instead."

/** Returns true if the command must be blocked. Exported for testing. */
export function isBlockedCommand(command: string): boolean {
  if (!command) return false
  return PATTERNS.some((re) => re.test(command))
}

export function blockSyncCdHook() {
  return async (
    input: { tool: string; sessionID: string; callID: string },
    output: { args: Record<string, any> },
  ) => {
    if (input.tool !== "bash") return
    const cmd = String(output.args?.command ?? "")
    if (isBlockedCommand(cmd)) {
      // Throwing aborts the tool call in OpenCode (tool.execute.before contract).
      throw new Error(DENY_MESSAGE)
    }
  }
}
