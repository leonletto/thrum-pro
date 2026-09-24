---
description:
  Park this agent for operator-initiated wake. Saves a standard 11-section
  snapshot (does NOT signal coordinator) then thrum-tmux-kills own session. Use
  when the operator is shutting down (e.g. computer restart) and the agent
  should resume from snapshot on next boot.
---

# Sleep — Park Until Operator Wake

Compose a standard 11-section prose continuation, write it directly to your
restart file, then end session cleanly and kill own tmux session. The agent goes
to sleep until the operator wakes it later via
`thrum tmux create <session-name>`. Unlike `/thrum:restart`, sleep does NOT
signal the coordinator and does NOT wait for an external mover — it terminates
its own tmux session.

## When to Use

- The operator is shutting down the machine (e.g. computer restart) and wants
  this agent's work durably parked.
- The operator wants to free a tmux session slot but resume this agent's work
  later.
- You (the agent) decide independently that further progress requires the
  operator's attention later, not the coordinator's now.

For routine context-exhaustion / rate-limit restarts where the coordinator
should bring you back in-place, use `/thrum:restart` instead.

## Steps

### 1. Resolve identity + verify tmux session (Tier 1 pre-check; run BEFORE anything else)

```bash
# Resolve identity + your worktree (needed before reading the partial).
# $REPO must be YOUR worktree — the directory `thrum prime` reads the restart
# snapshot back from. Resolve it ONLY via the daemon's authoritative,
# peercred-resolved identity (`thrum agent worktree --authoritative`) — NEVER
# via `thrum whoami --field worktree` or `git rev-parse --show-toplevel`
# (both cwd-resolved). A cwd-derived pattern could silently
# resolve to a DIFFERENT agent's worktree, or the main repo. There is NO git
# fallback — if the daemon can't answer, refuse and stop rather than guess.
REPO=$(thrum agent worktree --authoritative 2>/dev/null) || { echo "ERROR: cannot authoritatively resolve your worktree via the daemon. Refusing to fall back to cwd/git-toplevel — that would risk silently saving this snapshot to the wrong repo. Check daemon connectivity and retry."; exit 1; }
[ -n "$REPO" ] || { echo "ERROR: thrum agent worktree --authoritative returned empty"; exit 1; }
AGENT=$(thrum whoami --field agent_id) || { echo "ERROR: agent not registered"; exit 1; }
[ -n "$AGENT" ] || { echo "ERROR: empty agent_id"; exit 1; }
mkdir -p "${REPO}/.thrum/restart"

# Tier 1 pre-check: tmux session must exist BEFORE writing snapshot:
SESSION=$(thrum whoami --field tmux_session)
if [ -z "$SESSION" ]; then
  echo "ERROR: the sleep command requires a tmux-managed agent session (tmux_session field is empty)."
  echo "Use the restart command for non-tmux sessions."
  exit 1
fi
```

If `tmux_session` is empty: ABORT before writing any snapshot. No status change,
no session end. Exit code 1. The skill is the wrong tool for non-tmux agents.

### 2. Read the shared snapshot-composition partial

Read the partial at the absolute path:

```text
${REPO}/claude-plugin/commands/_snapshot-protocol.md
```

Apply its Step 2 (compose your continuation) per the structure guidance.

**Use the STANDARD 11-section structure.** For comprehensive
designer/architect-grade snapshots, use `/thrum:sleep-extended` instead.

**Note on §1 framing:** For sleep snapshots, the Big Picture section frames as
"where work stands at park time" rather than "what shipped" — the agent is
parking, not completing. Composition discipline (1–3 sentences, specific,
load-bearing-first) is identical to restart.

### 3. Write the continuation

Per Step 3 of the partial, use the Write tool to save your composed continuation
to `${REPO}/.thrum/restart/${AGENT}.md`. On next boot, `thrum prime`
auto-injects this file — same mechanism as restart wake.

### 4. Back up OTHER important artifacts to your durable agents folder (survives worktree teardown)

**Your restart snapshot itself no longer needs this step.** Step 6
(`thrum agent sleep`) now relocates `<worktree>/.thrum/restart/<agent-id>.md`
to the canonical `<main-repo>/.thrum/agents/<agent-id>/sessions/<ts>-restart.md`
synchronously, BEFORE it kills your pane — that is the fix for the bug this
step used to exist to work around (the snapshot previously was archived only
at your NEXT WAKE, so a worktree reap between sleep and wake destroyed it
permanently with no warning).

🔴 **READ THIS CAREFULLY.** A worktree's `.thrum/` is a REAL LOCAL DIRECTORY. The
`redirect` inside it is just a plain text FILE containing a path — a pointer
thrum's code consults. The filesystem redirects nothing. Your worktree keeps its
own local `agents/`, `context/`, `identities/`, and `restart/`.

**What THIS step is still for:** anything OTHER than the restart snapshot that
you need to survive a worktree teardown while parked — reports / findings you
authored, important uncommitted artifacts, and anything your resume plan
references. Copy those to the MAIN REPO PATH, resolved explicitly:

```bash
# Resolve the main repo's .thrum from the redirect FILE (do not assume a path).
MAIN_THRUM=$(cat "${REPO}/.thrum/redirect" 2>/dev/null) || MAIN_THRUM="${REPO}/.thrum"
mkdir -p "${MAIN_THRUM}/agents/${AGENT}"
cp <artifact> "${MAIN_THRUM}/agents/${AGENT}/<name>"
ls -la "${MAIN_THRUM}/agents/${AGENT}/<name>"   # VERIFY IT LANDED
```

If you have nothing beyond the restart snapshot to preserve, this step is a
no-op — proceed to Step 5. Do not trust `cp`'s exit code for anything you do
copy — list the destination file to confirm it landed.

### 5. Mark agent operational status idle

```bash
thrum agent set-status idle
```

`idle` is the operational/presence-status signal, separate from the durable
`agents.phase` field. Step 6 (`thrum agent sleep`) is what transitions phase
to `sleeping` — a real, distinct phase, not folded into `idle`. This step
only covers the lighter-weight status field.

If `thrum agent set-status` returns an error (e.g. rate-limited), continue to
Step 6 — the snapshot on disk is the load-bearing artifact, not the status
field. The operator can set status post-wake.

### 6. Sleep the agent (relocate snapshot, teardown, phase transition)

```bash
thrum agent sleep --agent "$AGENT"
```

This calls the daemon's `agent.sleep` RPC (CLI alias `park`), which runs the
full park ceremony in the correct order: it relocates your snapshot from the
worktree-local `.thrum/restart/` into the canonical
`agents/<id>/sessions/` directory, *then* kills your own tmux session, *then*
writes the `agent.phase.transition {to: "sleeping"}` event. This is the fix
for the bug a raw `thrum session end` + `thrum tmux kill` sequence had: it
killed the pane before the snapshot was ever relocated (permanent data-loss
risk if the worktree was reaped first) and left the roster row reading
`active` after the pane was already gone — a "ghost-active" agent.

**Critical: the daemon kills YOUR OWN pane mid-call, as part of this same
RPC's teardown stage.** A successful self-park is therefore observed, from
inside this pane, as the CLI call's transport dying — connection reset, EOF,
or broken pipe — NOT a clean JSON response; the pane is gone before a
response can reach it. **Do not retry** `thrum agent sleep` on transport
loss after dispatch, and **do not treat transport loss as a failure.** It is
the expected signal that self-park succeeded. A real failure (a gate,
relocation, or teardown error) is signaled by the RPC returning an explicit
error message BEFORE the pane dies — that is the only failure signal
observable from inside this pane. If independent confirmation is needed, it
must come from a DIFFERENT caller (this pane will be gone) checking
`thrum agent list` / `thrum team list` afterward.

**Do not fall back to a raw `tmux kill-session`.** A raw kill bypasses
`agent.sleep`'s relocate-before-kill ordering and daemon bookkeeping
entirely — reintroducing the exact data-loss and ghost-active bug this
ceremony exists to close.

## How wake works

On runtime start, `thrum prime` auto-injects the snapshot at
`.thrum/restart/<your-agent-id>.md` — same mechanism used by restart. Resume
from §9 (Numbered resume plan).

**Two wake paths, and they are NOT interchangeable — pick by WHO is waking you.**

**A. THE OPERATOR (a human, at a terminal):** `thrum tmux start` from the agent's
own working directory. That is create + launch + prime + attach in one, and it is
the simplest path.

**B. ANOTHER AGENT (e.g. a coordinator waking a parked agent):** the operator path
will FAIL for you, by design. Running `thrum tmux start` from someone else's
worktree fires the `cross_worktree` identity guard (`pid_mismatch`) — that guard
exists to stop one agent assuming another's identity, and it is working correctly
when it blocks you. Use this instead, in order:

```bash
# 1. PROVE THE STALE PID IS DEAD — by DIRECT OBSERVATION, never from the DB.
ps -p <identity-pid> -o pid=,lstart=,comm=          # must return NOTHING
tmux list-panes -a -F '#{pane_pid}' | grep -w <identity-pid>   # must return NOTHING
# If either shows life, STOP. The agent is not parked; do not force anything.

# 2. SALVAGE FIRST if the snapshot is not already in the main repo — it is
#    worktree-local until wake (see Step 4 above). Forcing is safe; losing is not.

# 3. Create, replacing the stale identity. The quickstart flags are REQUIRED —
#    without --name/--role/--module this fails with "quickstart flags required".
thrum tmux create <name> --cwd <worktree> \
  --name <agent-id> --role <role> --module <module> \
  --model <model> --effort <effort> --force

# 4. Launch the runtime; it re-binds the identity on start.
thrum tmux launch <name>
```

`--force` replaces the STALE IDENTITY FILE (you will see
`tmux.create.identity-replaced`). It does **not** touch the snapshot — that is why
step 1 (prove dead) and step 2 (salvage) come first. Forcing against a LIVE agent
would evict a working agent from its own identity.

The snapshot file moves to `.thrum/agents/<your-agent-id>/sessions/` archive on
wake (same as restart). Worst-case fallback: previous Claude session may be
resumable via Claude Code's native session-continuation mechanism.

## Programmatic use (operator shutdown scripts)

The underlying mechanic — write snapshot + set status idle + `thrum agent sleep`
(relocate + teardown + phase transition) — can be invoked from an operator's
shutdown script directly via the bash commands above (without going through
the skill).
