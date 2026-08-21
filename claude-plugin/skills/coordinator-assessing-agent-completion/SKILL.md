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
abandoned. If the merge is still queued, the agent is **correctly** waiting and
reaping it destroys live context that nobody else holds.

**If you cannot name the blocker, it is not a candidate.**

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
correct. So the reap that actually frees load is **`git worktree remove --force <path>`** —
the delete best-effort-fails and leaves a **benign orphan DB row**, which you LEAVE (filtered
at query per the fleet ruling; never `agent cleanup --force` to tidy them).

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

## Why this fails dangerously if you skip the gate

The failure direction is **false-GONE**: concluding a live agent is finished. It
authorises abandonment, and **nobody audits an agent nobody believes exists**, so
the error has no natural discovery path. A false-ALIVE costs one wasted check.
Prefer it.
