---
name: brainstormer-staying-current
description: "Use when a long-lived brainstormer worktree may be behind its configured merge target, before review or handoff, or when asked to merge-forward and leave the worktree clean. Resolves the target and merge owner from Thrum config, preserves local work, and verifies freshness after the merge."
# source: claude-plugin/skills/brainstormer-staying-current/SKILL.md
# generated-by: scripts/sync-skills.sh
---


## Brainstormer: Stay Current with the Merge Target

Keep a long-lived brainstorm branch current without landing it into the merge
target. Every git write in this skill (commit, merge, revert, push) stays with
you — never delegate a git write to a subagent. Every `fetch` also stays with
you, the acting agent, per Preserve and Bind freshness below. If you delegate
the read-only merge-base/status analysis, load `choosing-subagent-models`
first and fence the subagent to `show`, `log`, `diff`, `grep`, `rev-parse`,
`merge-base`, `status` — the same read-only git surface CLAUDE.md requires for
every sub-agent — never `stash`, `reset`, `rebase`, `restore`, `clean`,
`commit`, `push`, or `checkout`.

### Resolve authority from config

Locate the canonical config from the current worktree:

```bash
CONFIG=.thrum/config.json
if [ ! -f "$CONFIG" ]; then
  COMMON_DIR=$(git rev-parse --path-format=absolute --git-common-dir)
  CONFIG="${COMMON_DIR%/.git}/.thrum/config.json"
fi
test -f "$CONFIG"
TARGET=$(jq -er '.orchestration.merge_target | select(type == "string" and length > 0)' "$CONFIG")
MERGE_KING=$(jq -r --arg target "$TARGET" '.orchestration.merge_kings[$target] // "unset"' "$CONFIG")
```

Treat an absent config or target as a blocker — merge-forward has nowhere to
target without them. A merge-forward only brings `origin/$TARGET` into the
brainstorm branch; it never grants permission to merge the brainstorm branch
into `$TARGET`, so it needs no landing authority to run and an `unset`
`MERGE_KING` never blocks it.

`orchestration.merge_kings` may not be populated for every target yet: `unset`
does NOT mean "nobody owns landing, proceed however" — it means the map
hasn't caught up (same gap `coordinator-merging-code/SKILL.md` documents for
branch-keyed lookups). `MERGE_KING` matters only when a conflict needs routing
or at final report. With it `unset` at either point, fall back to whichever
coordinator has actually been the merge authority for `$TARGET` in practice
(check with your team, or the project's operational convention) and
route/report to them the same as if the map had named them explicitly.

### Preserve before merging

Record the current branch, HEAD, status, and ahead/behind counts. Require an
attached non-target feature branch. Fetch the target branch explicitly:

```bash
git fetch origin "refs/heads/$TARGET:refs/remotes/origin/$TARGET"
git rev-list --left-right --count HEAD..."origin/$TARGET"
```

If the worktree is dirty, preserve tracked and untracked changes as a WIP
commit and record its SHA — never `git stash`. `stash` is a single shared
stack across every worktree on this box, not scoped to this worktree or to
you; a stash push or pop here can silently destroy or restore another agent's
uncommitted work, with no reflog entry and no recoverable blob for unstaged
content. A commit is yours alone and fully recoverable.

```bash
git add -A
git commit -m "wip: preserve <branch> before merge-forward <timestamp>"
git rev-parse HEAD
git status --short
```

Do not squash, drop, or revert the WIP commit when the requested outcome is a
clean worktree — it is real history now, not something to discard.

Stop if the worktree is still dirty after the WIP commit. Never use `stash`,
reset, rebase, force checkout, clean, or force push to obtain a clean state —
`stash` is banned here exactly like the others, with no worktree-scoped
exception.

### Merge-forward

Merge the remote-tracking target into the brainstorm branch:

```bash
git merge --no-edit "origin/$TARGET"
```

Resolve a conflict only when the correct result is supported by current source
and the branch's intended work. Otherwise stop with the conflict intact and
send the branch, worktree, target, and conflicted paths to the user or
`$MERGE_KING` for direction — falling back to the operational-convention
authority per above if `$MERGE_KING` is `unset`.

After a successful merge, run validation relevant to every resolved file and
always run `git diff --check origin/$TARGET..HEAD`.

### Bind freshness to handoff

Immediately before reporting success, fetch the target branch explicitly again
and verify the fetched target is an ancestor of HEAD:

```bash
git fetch origin "refs/heads/$TARGET:refs/remotes/origin/$TARGET"
git rev-list --left-right --count HEAD..."origin/$TARGET"
git merge-base --is-ancestor "origin/$TARGET" HEAD
git status --short
```

If the target advanced, repeat the merge-forward and verification, up to three
merge cycles in one run. After three moving-target results, stop and report the
new target SHA instead of claiming the branch is current.

Report the branch and target SHAs, ahead/behind counts, `$MERGE_KING` (or the
fallback authority if `unset`), validation, clean status, and the WIP commit
SHA if one was made. Do not push, squash, or drop the WIP commit unless the
user separately asks.
