---
name: coordinator-assessing-agent-completion
description: "Use when deciding which live agents are FINISHED and can be stood down - finding obsolete agents, idle agents, agents nobody is waiting on, agents still running after their work landed, reaping candidates, tidying up the fleet, 'who can I shut down', 'which agents are done', auditing a box before a deploy or restart - AND when reducing the worktree count or reaping/freeing worktrees to relieve load (too many worktrees, the identity or collision scan timing out, tmux create or launches failing, 'reduce the worktree count', 'reap dead worktrees'), because a worktree is an agent's home and reaping one is an agent-lifecycle decision, never disk cleanup. Produces a candidate list from the transcript plus a DIRECT-OBSERVATION liveness check (live tmux pane / ppid, not a snapshot-presence proxy), never a kill list."
---

# Assessing Whether an Agent Is Finished — and Whether a Worktree Is Safe to Reap

`thrum tmux connect` tells you which agents are **alive**. Nothing tells you which
are **alive but done**. This is that second question.

**This produces INFORMATION. You make the judgment call.**

The scan ranks and quotes; it does not conclude. It has no flag that reaps,
kills, or changes a phase, and it must not grow one — a script that recommends
standing an agent down is read as having decided, and its phrasing then carries
weight its evidence does not.

Apply the gate and containment checks below and reach your own
conclusion. Destructive steps still follow the standing reap preconditions and
pacing rules; nothing here shortcuts them.

## Standing reap preconditions — ALL must hold

Reaping an agent (removing its worktree) is safe only when every one of these is
true. It is a gate, not a checklist to rationalize past:

1. **Idle > 48h** — no activity in its transcript for more than two days (rank by
   message CONTENT, not mtime; your own broadcasts reset mtime).
2. **No messages exchanged in the last 24h** — nothing sent to it or from it.
3. **Task complete AND nobody is waiting on it** — it finished and its
   dispatcher/manager moved on, so a reply it waits for will never come. (A pushed
   branch held on a still-queued merge is the one nuance — see the
   held-pending-merge rule.)
4. **Salvage done first** — its only-copy state is copied to a durable location and
   verified (see Containment and the reap steps).

**When a needed decision or merge is delayed, ESCALATE — never silently wait.** If an
agent is parked past the 24h window on something its manager/owner has not acted on,
raise it explicitly to whoever owns that decision, and re-raise on every subsequent
run. If the human owner is unresponsive, escalate through your designated escalation
contact (the human's proxy) rather than leaving the agent parked. A silent park is
the failure this whole procedure exists to prevent: each run must drive a parked
agent toward a terminal state — decision made / merge lands (reap-able) or deemed
orphaned (reap).

## The instruments, in order of trust

| Question | Instrument |
|---|---|
| Is it alive? | `thrum tmux connect < /dev/null` · `tmux list-sessions` |
| What did it last say? | its transcript JSONL — **the primary signal** |
| How long has it been quiet? | transcript mtime — **weak, see below** |
| What is it waiting for? | its own last message, read as prose |

**Do NOT use `thrum team`, `thrum agent list`, `phase`, or `last_seen_at` for any
of this.** They are stale, and they fail toward
reporting a live agent as absent.

## Locating an agent's transcript

The project directory is the agent's worktree path with `/` and `.` replaced by `-`:

```
/Users/<you>/.thrum/worktrees/thrum/<session>
  -> ~/.claude/projects/-Users-<you>--thrum-worktrees-thrum-<session>/*.jsonl
```

Newest `.jsonl` by mtime is the live session. Records carry `timestamp`, `type`,
and `message.content`.

## The scan

```bash
thrum tmux connect < /dev/null | awk 'NR>1 && $1 ~ /^[0-9]+$/ {print $2"|"$3}'
```
gives `session|@agent` for every alive agent. For each, open the newest transcript
and take the last record of `type == "assistant"` with a non-empty text block.
That text is the signal.

## Reading the signal

**Terminal-state language** — the agent declaring it holds nothing:

> *standing by* · *standing down* · *task done* · *idle* · *no further action* ·
> *completion report sent* · *held pending X* · *inbox clear, nothing to act on*

**Not terminal**: a question to another agent, a partial result, a stated next
step, an error it has not resolved.

## ⚠️ Two false positives the phrase match produces, both measured

The scan is a **pre-filter**. It matches anywhere in the last message, which
catches two agents that are not finished:

1. **A long active report that happens to contain a terminal phrase mid-text.**
   The agent is mid-work; the phrase is describing something else.
2. **A freshly-primed agent.** *"Inbox empty; standing by"* is part of its prime,
   not a completion. Check its session start — minutes old means it just woke.

⇒ **Read the END of the message, not a keyword hit.** A finished agent's last
sentence IS the terminal statement; a working agent's merely contains one.

## 🔴 THE GATE — an agent saying it is finished is not evidence that it is

**Name what it is waiting for, then prove that thing is dead or landed.**

*"Held pending the coordinator merge"* is finished only if the merge landed or was
abandoned. If the merge is still queued, whether the agent is *correctly* waiting
depends on its branch and its idle time — see the held-pending-merge rule below.

**If you cannot name the blocker, it is not a candidate.** (This governs the
*no-transcript* case — absence of evidence — not a named-but-stale merge wait.)

## 🔴 The held-pending-merge case — a PUSHED branch changes the gate

An agent parked "pending the merge" is judged by ONE thing first — **is its branch
pushed?** — because a merge wait only makes sense if the merge king can reach the
branch.

- **Branch NOT pushed — broken at ANY idle age.** The merge king cannot access an
  unpushed branch, so the wait can never resolve, and the agent's commits are also
  the only copy (unsafe to reap). This is not a legitimate wait — it is a stuck one.
  → Get the branch PUSHED (nudge the agent / its orchestrator to push it, or escalate
  that it needs pushing). Never reap an unpushed held-pending-merge agent — pushing
  first is both what unblocks the merge and what makes any later reap safe.
- **Branch pushed, idle < 24h.** Legitimately waiting its turn in the merge queue.
  Leave it (the pushed branch means the merge king can reach it and nothing is lost).
- **Branch pushed, idle ≥ 24h.** The wait is no longer legitimate — a pushed branch
  is not the only copy of anything, so any agent could carry the merge. Resolve it to
  one of two clear states:
  - **Merge HAPPENED** (branch is an ancestor of trunk, or was abandoned/superseded)
    → the agent is **ORPHANED**, waiting for a response that will never come → **reap**
    (salvage-first, and still subject to the standing reap preconditions).
  - **Merge still PENDING** (branch not on trunk, not abandoned) → the merge king
    forgot it or the queue is stuck → **ESCALATE** to the merge king (name the branch
    tip + how long it has waited), and **re-escalate on every subsequent skill run**
    until it resolves. Never leave it silently parked.

**The escalation is the load-bearing half.** Because each skill run re-checks and
re-escalates a still-pending merge, the condition is self-correcting: it drives toward
one of two terminal states — the merge completes (agent then reap-able) or the agent
is deemed orphaned (reap) — instead of a pushed-branch agent parked forever on a merge
nobody is tracking. A silent park is exactly the failure this rule prevents.

## Containment, before anything is stood down

- branch pushed, or no commits to lose
- no only-copy untracked state: `git -C <wt> status --porcelain --untracked-files=all --ignored -- .thrum` — **both flags**; the narrow form returns a false zero
- no restart snapshot under `<worktree>/.thrum/restart/` — a snapshot means a
  sleeping agent that expects to wake with its context

## Reaping many worktrees at once — the batch path

The single-agent gate above still governs EACH worktree; batching changes only how you
GATHER the evidence and EXECUTE, never the judgment.

**Gather with read-only examiner sub-agents.** For dozens of candidates, partition them
across background sub-agents that examine each worktree read-only and RETURN a verdict —
they never reap. Per worktree each reports: sleeping-agent marker present?; branch
containment (ancestor of trunk / pushed / UNMERGED-with-commit-list); only-copy authored
content (docs/plans/specs, undelivered reports, restart snapshots), ignoring regenerable
dirt (`scripts/thrum-*.sh`, `.thrum/redirect`, `runtime_config.json`). Fence them READ-ONLY
(no checkout/reset/stash/clean/rebase/commit/push, no `worktree remove`, no `agent delete`,
no `rm`). You consolidate and decide.

**Cross-check the reap set against the live + sleeping roster before ANY deletion** — one
protected agent in the set aborts the batch. Build the exclusion from the live-pid set +
sleeping set + locked worktrees, not from names.

**Salvage only-copy state FIRST, and diff by NAME.** Copy with `cp -a`, then compare source
vs salvage with `find -type f | sort` (set-diff by NAME) BEFORE trusting per-file `cmp` — a
flat copy of two same-basename files (e.g. `.thrum/restart/<a>.md` and
`.thrum/context/<a>.md`) silently clobbers one, and `cmp` on what copied passes clean. Give
salvaged files distinct names and land the salvage somewhere durable (the main repo, not
`/private/tmp`).

## 🔴 The reap is worktree-removal-only — and TEST every step on ONE item first

**`thrum agent delete --force` is REFUSED by the CAS guard on a stale agent with an empty
`agent_pid_start_time`** (*"expected-state premise is required … refusing rather than treating
an empty/never-read premise as a match"*). `--force` does NOT bypass it; the guard is
correct. So the reap that actually frees load is worktree removal — but salvage BEFORE you remove,
then remove PLAIN (no `--force`):

1. Enumerate untracked+ignored `.thrum` content — BOTH flags, one flag alone misses a class:
   `git status --untracked-files=all --ignored -- .thrum`
2. Salvage BOTH kinds to their canonical redirect paths, and `cmp`-verify each copy is
   byte-identical to its source:
   - `?? .thrum/agents/<agent>/sessions/*-restart.md` — the restart snapshot.
   - `!! .thrum/context/<agent>.md` — gitignored, NOT daemon-held, the **only copy**;
     losing it is permanent. (`_preamble.md` is regenerable — skip it.)
3. THEN `git worktree remove <path>` — **plain, no `--force`.** ⚠️ This refusal is a REAL
   backstop only for untracked/modified content (git's own rc=128 refusal) — it is NOT a
   backstop for the gitignored `.thrum/context/<agent>.md` file: `git worktree remove`
   silently deletes ignored-only content with exit 0, no refusal, no warning (verified by
   direct reproduction). **Step 2's salvage is the ONLY protection for that file — there is
   no git-level safety net behind it.** The rc=128 refusal still matters (it catches a stray
   untracked restart-snapshot salvage missed, or any other unexpected untracked file), so
   still read the BARE rc and still treat a refusal as a signal to investigate — just don't
   mistake it for protecting the ignored-file class. (Not a pipe — a pipe returns the last
   command's rc, not `git`'s.)

The delete (`thrum agent delete`) best-effort-fails and leaves a **benign orphan DB row**,
which you LEAVE (filtered at query per the fleet ruling; never `agent cleanup --force` to
tidy them).

⚠️ **After a large reap you may see a `DeadAgentSweeper` skip alert + elevated write-RPC
latency — do NOT assume the reap caused it.** This box carries a standing single-writer
contention condition (one serialized write conn, `SetMaxOpenConns(1)`) that spikes write-RPC
latency recurrently and **reap-independently**. A large reap is at most ONE coincident spike: stranding dozens of stale
agents (worktreeless, empty `pid_start_time` → always "due") stretches the sweep's
evidence-gathering run-length (that is what `held=` measures — a run duration, mostly off-lock
syscalls, not a lock hold or a deadlock; the skip is correct, the guard releases via `defer`),
but it drives almost no writes of its own. The
discriminator that it is contention and not poison: `write_pool in_use=0`,
`selfheal_write_poison_detected=0`. **So do not chase the reap as the lever** — pacing/batching
large reaps is mild hygiene at best (it trims run-length and a little pressure), a restart is
transient relief only, and the durable fix is **writer-decontention**, owned by the
daemon-perf agent. Symptom to recognize (reads and `daemon status` stay ~0.5s while
`status --self` climbs — writes slow, not reads): hand it to the daemon-perf owner, don't
re-diagnose the internals yourself.

**Before running any batched destructive loop, run it on ONE item and verify the EFFECT**
(agent gone from the registry / worktree gone from `git worktree list` and disk), not just
the exit code. A batch can fail wholesale for a reason a single test surfaces instantly — a
minimal-`PATH` loop/background context where `git`/`thrum`/`sleep` are `command not found`
(set `PATH` explicitly or use absolute paths); a `read` that collapses a leading empty field.
Batched worktree removal is also SLOW on a loaded box (seconds each) — run it in the
background or in chunks, never one 2-minute foreground loop.

## ⚠️ Idle time is corrupted by your own traffic

A coordinator broadcast resets every recipient's transcript mtime. After any
fleet-wide message, **every agent reads as freshly active** and the idle column
is meaningless for hours.

⇒ **Rank by the last message's CONTENT, not by elapsed time.** A nudged-then-idle
agent re-states that it is standing by, so the content signal survives what the
timing signal does not.

## ⚠️ Two absences that are not evidence

- **No transcript** does not mean no agent. Alive agents exist with no transcript
  directory.
- **Absent from `connect`** means only "no tmux session on THIS box". `connect` is
  box-local; remote agents can never appear in it.

## Idle-gopls RAM reclaim

Once you've classified an agent as idle, its `gopls` process (if any) is a
second, independent reclaim candidate — an idle agent's gopls is dead weight
sitting in RAM.

`scripts/reap-idle-gopls.sh` matches each running `gopls` process to its
owning agent (ppid chain → tmux pane_pid → `thrum team --json` session) and
uses `tmux_state` as a cheap first-pass filter — anything not idle by that
signal is skipped outright. That filter is bounded, not authoritative: it
does not replace this skill's own idle/finished judgment, which still comes
from the transcript per the rules above. Run the script alongside the scan
above, apply the same transcript-based gate to whatever it surfaces, and
fold the result into a single combined table: idle agent · gopls PID ·
RSS-MB.

- Killing an idle agent's gopls is a no-op — it respawns on the agent's next
  LSP request. Never destructive to the agent itself.
- **NEVER kill a pool or active-worker gopls.** The script excludes by ROLE
  (orchestrator, gate, coordinator, brainstormer, researcher — the roles
  that are never reap targets) plus the non-idle-state skip above, plus one
  named exception for a role-uncovered pool agent. It also runs a canary
  self-check before printing anything: if it can't prove the exclusion still
  resolves correctly, it aborts loudly instead of printing a kill-list.
  Do not override or bypass any of this.
- Same framing as the rest of this skill: the script **produces information,
  you decide**. It is read-only and dry-run — it prints a kill-list, it never
  kills anything.

## 🔴 Footguns — never do these (each measured, each cost real time or state)

- **Never glob/`cp` `.thrum/context/*.md` when salvaging** — the glob matches the
  shared `project_state.md` and overwrites the canonical copy with a stale worktree
  copy. Salvage the agent-specific `<agent>.md` by exact name only.
- **A worktree's `.thrum/` holds a redirect file to the main repo AND a physical
  stale local copy of shared files** (e.g. `project_state.md`) — the physical
  worktree copy is NOT canonical; never treat it as the source of truth or copy it
  upward.
- **Never use shell-specific builtins in a reap loop without checking the shell** —
  `mapfile`/`readarray` are bash-only and silently fail in zsh (`command not
  found`), so the salvage you thought ran did not. Use portable `while read` and
  verify each salvaged file actually landed.
- **`rm -rf` raises a confirmation modal that blocks the PARENT pane invisibly** —
  use `rm -r` for scratch cleanup (identical deletion, no modal). Never `rm -rf`.
- **`git worktree remove` (plain) silently deletes gitignored-only content (rc=0)**
  and refuses (rc=128) only on untracked/modified files — salvage is the ONLY
  protection for gitignored only-copy state.
- **`git worktree remove` refuses while a just-salvaged untracked snapshot still
  sits in the worktree** — remove that salvaged copy from the worktree first, then
  plain-remove.
- **Never `checkout`/`reset`/`restore`/`stash`/`clean` in a shared tree, even to
  undo** — to restore a file to its committed version, write it with a plain
  redirect from `git show <ref>:<path>`, not a checkout.
- **Test the reap on ONE agent first and verify the EFFECT** (gone from the worktree
  list AND disk), not just the exit code.
- **Rank candidates by last-message CONTENT, not elapsed time** — your own
  broadcasts reset every recipient's idle clock.
- **`--force` on agent-delete does NOT bypass the CAS guard** on a stale agent — the
  reap that frees load is worktree removal, not the delete.
- **Reap order is `thrum tmux kill <session>` FIRST, THEN `git worktree remove`** —
  removing the worktree alone leaves the agent's tmux session alive with a
  now-deleted cwd, which the fleet flags as recurring "cwd drift" and whose runtime
  process keeps consuming RAM/CPU. Kill the session, verify it's gone, then remove
  the worktree.

## Why this fails dangerously if you skip the gate

The failure direction is **false-GONE**: concluding a live agent is finished. It
authorises abandonment, and **nobody audits an agent nobody believes exists**, so
the error has no natural discovery path. A false-ALIVE costs one wasted check.
Prefer it.
