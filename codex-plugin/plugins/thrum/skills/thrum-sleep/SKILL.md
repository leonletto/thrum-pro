---
name: thrum-sleep
description: Park this agent for operator-initiated wake. Saves a standard 11-section snapshot (does NOT signal coordinator) then thrum-tmux-kills own session. Use when the operator is shutting down (e.g. computer restart) and the agent should resume from snapshot on next boot.
# source: claude-plugin/commands/sleep.md
# generated-by: scripts/sync-skills.sh
---

# Thrum Sleep

Use this skill when the user explicitly wants the `sleep` Thrum
workflow. Prefer the umbrella `thrum` skill when the request spans multiple
commands or needs broader coordination judgment.


## Sleep — Park Until Operator Wake

Compose a standard 11-section prose continuation, write it directly to your
restart file, then end session cleanly and kill own tmux session. The agent goes
to sleep until the operator wakes it later via
`thrum tmux create <session-name>`. Unlike `$thrum-restart`, sleep does NOT
signal the coordinator and does NOT wait for an external mover — it terminates
its own tmux session.

### When to Use

- The operator is shutting down the machine (e.g. computer restart) and wants
  this agent's work durably parked.
- The operator wants to free a tmux session slot but resume this agent's work
  later.
- You (the agent) decide independently that further progress requires the
  operator's attention later, not the coordinator's now.

For routine context-exhaustion / rate-limit restarts where the coordinator
should bring you back in-place, use `$thrum-restart` instead.

### Steps

#### 1. Resolve identity + verify tmux session (Tier 1 pre-check; run BEFORE anything else)

```bash
# Resolve identity + your worktree (needed before reading the partial).
# $REPO must be YOUR worktree — the directory `thrum prime` reads the restart
# snapshot back from. Resolve it from the daemon's authoritative identity, NOT
# `git rev-parse` (which keys off the current shell CWD and would write to the
# wrong .thrum/restart/ if a bash step left your worktree). Fall back to git
# only if whoami can't answer.
REPO=$(thrum whoami --field worktree 2>/dev/null)
[ -n "$REPO" ] || REPO=$(git rev-parse --show-toplevel) || { echo "ERROR: cannot resolve your worktree"; exit 1; }
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

#### 2. Read the shared snapshot-composition partial

Read the partial at the absolute path:

```text
${REPO}/claude-plugin/commands/_snapshot-protocol.md
```

Apply its Step 2 (compose your continuation) per the structure guidance.

**Use the STANDARD 11-section structure.** For comprehensive
designer/architect-grade snapshots, use `$thrum-sleep-extended` instead.

**Note on §1 framing:** For sleep snapshots, the Big Picture section frames as
"where work stands at park time" rather than "what shipped" — the agent is
parking, not completing. Composition discipline (1–3 sentences, specific,
load-bearing-first) is identical to restart.

#### 3. Write the continuation

Per Step 3 of the partial, use the Write tool to save your composed continuation
to `${REPO}/.thrum/restart/${AGENT}.md`. On next boot, `thrum prime`
auto-injects this file — same mechanism as restart wake.

#### 4. Back up important files to your durable agents folder (survives worktree teardown)

**Your worktree may be torn down while you sleep — and if it is, YOUR SNAPSHOT
GOES WITH IT unless you do this step.**

🔴 **READ THIS CAREFULLY.** A worktree's `.thrum/` is a REAL LOCAL DIRECTORY. The
`redirect` inside it is just a plain text FILE containing a path — a pointer
thrum's code consults. The filesystem redirects nothing. Your worktree keeps its
own local `agents/`, `context/`, `identities/`, and `restart/`.

**THE ACTUAL MECHANISM:** your snapshot at `<worktree>/.thrum/restart/<agent-id>.md`
is **worktree-local**. It is copied into the main repo **only when you WAKE** —
`thrum prime` reads it from the worktree and archives it to
`<main-repo>/.thrum/agents/<agent-id>/sessions/`. **Then and only then.** So a
teardown that happens BEFORE your wake destroys the snapshot, permanently, and
nothing warns you.

**Leave the snapshot where it is** — `thrum prime` reads it from the worktree on
wake, so that path is correct and required. **Additionally**, copy anything you
need to survive teardown to the MAIN REPO PATH, resolved explicitly:

```bash
# Resolve the main repo's .thrum from the redirect FILE (do not assume a path).
MAIN_THRUM=$(cat "${REPO}/.thrum/redirect" 2>/dev/null) || MAIN_THRUM="${REPO}/.thrum"
mkdir -p "${MAIN_THRUM}/agents/${AGENT}"
cp "${REPO}/.thrum/restart/${AGENT}.md" "${MAIN_THRUM}/agents/${AGENT}/last-sleep-snapshot.md"
# ...and any other artifact you need on wake.
ls -la "${MAIN_THRUM}/agents/${AGENT}/last-sleep-snapshot.md"   # VERIFY IT LANDED
```

Copy there: reports / findings you authored, important uncommitted artifacts, and
anything your resume plan references.

**VERIFY THE COPY EXISTS AT THE MAIN PATH before ending your session.** Do not
trust `cp`'s exit code — list the destination file. This step is your ONLY
recoverability guarantee against teardown-while-asleep; the redirect is not one.

#### 5. Mark agent operational status idle

```bash
thrum agent set-status idle
```

`idle` is the signal that this agent has parked. NO new "sleeping" state was
added — `idle` covers both "no active work" and "parked for operator wake."

If `thrum agent set-status` returns an error (e.g. rate-limited), continue to
Step 6 — the snapshot on disk is the load-bearing artifact, not the status
field. The operator can set status post-wake.

#### 6. End session cleanly

```bash
thrum session end
```

This emits an `agent.session.end` event cleanly so the dead-agent sweeper does
NOT later treat the disconnect as a crash. If `thrum session end` fails,
continue to Step 7.

#### 7. Kill own tmux session

```bash
thrum tmux kill "$SESSION"
```

Tmux pane terminates → runtime process exits → no further activity until
operator wakes the agent via `thrum tmux create <session-name>`.

**If Step 7 fails with "anonymous caller cannot invoke":** `thrum session end`
(Step 6) severs the daemon binding, so `thrum tmux kill` may be rejected if the
daemon hasn't yet processed the CallerWorktree self-kill path. Use the raw tmux
fallback — the lifecycle safeguards (snapshot, status idle, session end) were
already discharged by Steps 1-6, so nothing is lost:

```bash
tmux kill-session -t "$SESSION"
```

### How wake works

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

### Programmatic use (operator shutdown scripts)

The underlying mechanic — write snapshot + set status idle + session end + tmux
kill — can be invoked from an operator's shutdown script directly via the bash
commands above (without going through the skill).
