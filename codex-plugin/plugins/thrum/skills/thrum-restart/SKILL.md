---
name: thrum-restart
description:
  Save a conversation snapshot and prepare for session restart. Use when you
  need a fresh session due to context exhaustion, rate limits, or stuck state.
# source: claude-plugin/commands/restart.md
# generated-by: scripts/sync-skills.sh
---

# Thrum Restart

Use this skill when the user explicitly wants the `restart` Thrum workflow.
Prefer the umbrella `thrum` skill when the request spans multiple commands or
needs broader coordination judgment.

## Session Restart

Compose a prose continuation, write it directly to your restart file, then
orchestrate the handoff.

### Steps

#### 1. Resolve your identity and your worktree

```bash
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
```

#### 2. Compose your continuation

Your context is high and we want to restart without losing the decisions we've
made. Write a rich continuation that future-you will read as the first action
after restart.

##### §1 Big picture — REQUIRED FIRST SECTION (write this BEFORE anything else)

Every restart snapshot MUST begin with a section using this exact heading:

```text
## 1. Big picture — what shipped this session
```

Followed by 1-3 sentences (a single paragraph or up to 3 short ones) summarizing
what the session accomplished. Be specific: name the artifacts, the decisions,
the cycles closed. Examples:

> Locked the session-archive spec v2 with §1 Big picture requirement, five
> Q-Spec approvals, and Q-Spec-5 deferred to impl-time. Hand-off pending
> coordinator final review.
>
> Investigated rc.9 inbox-race against impl_inbox_race's hypothesis: confirmed
> the lock-substrate fence is the right fix. Filed thrum-XXX with 4 BLOCKING
> evidence points.
>
> Closed B-B1 E6.0 brainstormer-third pass. 2 BLOCKING + 5 IMPORTANT + 10 MINOR.
> All three load-bearing traps PASSed. Standing by for E6.1 next batch.

This section becomes YOUR OWN log entry, visible in `thrum agent sessions list`
alongside the archives of every other session you've ever restarted from.
Future-you (and other agents inspecting your history) skim §1 to decide which
sessions are worth re-reading. Write it first — before the Resume Plan, before
file paths, before patterns — because composing the §1 summary forces you to
identify what was actually load-bearing about this session, and that priority
shapes everything else you write below it.

**Stamp your snapshot with the base it was authored against (thrum-m43mk).**
Derive and emit the **Authored-against** stamp per
`claude-plugin/commands/_stamp-protocol.md` and place it at the very top of your
§1 section (that protocol computes the SHA and merge_target for you — never
hand-type them). This is what lets `thrum prime` diff your snapshot at the next
wake and flag which cited files have MOVED; an unstamped snapshot reads as
"current", indistinguishable from one that never drifted.

After the §1 block:

CRITICAL DISCIPLINE — compose from your own working context only. To preserve
the remaining runway:

- Do NOT dispatch sub-agents (Agent, Explore, etc.)
- Do NOT re-read files you've already read this session
- Do NOT spawn web fetches or external lookups
- Do NOT run lengthy investigations (git log spelunking, codebase searches,
  multi-file grep walks)

Each of those costs context you don't have to spend, and the cost compounds — a
sub-agent that returns 6K tokens of summary doesn't just cost the dispatch, it
pollutes the dying session further. If a fact isn't already in your working
context, label it "unknown" or "verify post-restart" rather than fetching it
now. Trust your in-context state.

Write for a competent stranger in your role — someone who has the runtime
briefing (`thrum prime`, role preamble, project state) but none of this
session's conversation context. Refer to the previous session in third person.

Use these numbered sections (write each as prose or table — your call — but the
numbered structure itself should be present):

1. **Big picture** — what shipped this session (REQUIRED FIRST, written above
   per the §1 mandate).
2. **Where every artifact stands** — branches, specs, plans, in-flight PRs,
   partially-landed work. Concrete tips / paths / commit SHAs.
3. **Players + contributions** — who's working on what, who's standing down,
   what each agent's latest state is.
4. **Decisions made this session** — with the context that drove each. Just
   listing the decision loses the reasoning future-you needs to judge edge
   cases.
5. **Questions awaiting repo owner input** — anything queued for the project
   owner's call before work can proceed. Name the question concretely.
6. **Outstanding work you owe** — commitments still open on your side (pushes,
   merges, dispatches, doc-patches).
7. **Patterns that worked / burned us** — short reflective section: what to keep
   doing, what to stop. Two sub-sections is enough.
8. **File paths future-you will reopen** — concrete paths the next session will
   need. Group by purpose (in-flight / queued / reference).
9. **Numbered resume plan** — concrete first-N-steps the next session should
   take, in order. Step 1 must be actionable from a cold start.
10. **Honest unknowns — verify post-restart, do NOT fabricate** — list facts you
    suspect changed during the session OR were never confirmed in the first
    place. Future-you must NOT carry these forward as truth until they're
    verified (e.g., "whether @impl_X has progressed past Task N", "exact branch
    tip — listed as ~SHA but multiple FF merges may have happened during the
    snapshot write", "whether the keepalive cron survived restart").
11. **End-of-continuation note** — one short paragraph reflecting on the session
    itself. What was the dominant pattern this session, what pattern proved
    load-bearing, what's a known fragility going into the next one.

Skip a section only when it genuinely doesn't apply — an honest "N/A: no
decisions this session" beats fabrication. The numbered structure itself should
always be present so future-you can scan for what's covered and what isn't.

#### 3. Write the continuation directly to your restart file

Use your Write tool to save the composed continuation to:

```text
${REPO}/.thrum/restart/${AGENT}.md
```

`thrum prime` will auto-inject this file at next session start. No bash heredoc
or `cat <<EOF` redirection is needed — write the file directly.

#### 4. Check session type and your role

```bash
SESSION_RAW=$(thrum whoami --field tmux_session)
# thrum whoami --field tmux_session returns a PANE-QUALIFIED value
# (e.g. "i7xv1-lifecycle-cmds:0.0"), not a session name. `thrum tmux restart`
# takes a session NAME and the daemon sanitizes ":"/"." to "-", so passing the
# raw value produces a lookup key ("i7xv1-lifecycle-cmds-0-0") that does not
# exist and every self-restart would fail. Strip to the bare session name:
SESSION=${SESSION_RAW%%:*}
ROLE=$(thrum whoami --field role)
echo "tmux_session_raw=$SESSION_RAW tmux_session=$SESSION role=$ROLE"
```

#### 5. Verify your snapshot before any self-restart (the gate)

**Self-restart is authorised ONLY after you verify your OWN snapshot on disk.**
Restarting without a verified snapshot destroys the context the restart exists
to preserve — strictly worse than idling. Verify the EFFECT, not the action: a
vague "I wrote it" is not verification; check the FILE.

```bash
SNAPSHOT="${REPO}/.thrum/restart/${AGENT}.md"
NOW=$(date +%s)
MTIME=$(stat -f %m "$SNAPSHOT" 2>/dev/null || stat -c %Y "$SNAPSHOT" 2>/dev/null)
AGE=$(( NOW - ${MTIME:-0} ))
SNAPSHOT_OK=1

if [ ! -f "$SNAPSHOT" ]; then
  echo "VERIFY FAILED: no snapshot at $SNAPSHOT"; SNAPSHOT_OK=0
elif [ ! -s "$SNAPSHOT" ]; then
  echo "VERIFY FAILED: snapshot at $SNAPSHOT is empty"; SNAPSHOT_OK=0
elif [ ! -r "$SNAPSHOT" ]; then
  echo "VERIFY FAILED: snapshot at $SNAPSHOT is not readable"; SNAPSHOT_OK=0
elif [ "$AGE" -gt 300 ]; then
  echo "VERIFY FAILED: snapshot at $SNAPSHOT is ${AGE}s old — stale (from a prior restart), not this session's write"; SNAPSHOT_OK=0
else
  echo "VERIFY OK: snapshot exists, non-empty, readable, written ${AGE}s ago"
fi

# The snapshot gate alone is not enough — the RESTART TARGET must also
# resolve. Guard the stripped session name the same way: if it doesn't
# resolve to a real tmux session, that's a verification failure too, not an
# excuse to attempt a restart against a bad target.
SESSION_OK=1
if [ -n "$SESSION" ] && tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "VERIFY OK: tmux session '$SESSION' resolves"
else
  echo "VERIFY FAILED: tmux session '$SESSION' (stripped from '$SESSION_RAW') does not resolve to a live tmux session"
  SESSION_OK=0
fi
```

**"Properly" means, explicitly:** snapshot exists at your OWN worktree's
`.thrum/restart/<your-agent-id>.md`, non-empty, readable, AND recently written
by Step 3 of THIS session (not a leftover from a previous restart that Step 3
silently failed to overwrite) — AND the stripped session name resolves to a
real, live tmux session.

**FAIL DIRECTION — stated explicitly:** if EITHER check fails, DO NOT RESTART.
Report and hold (see the failure branch below). Refusal is safe; an unverified
self-restart, or one aimed at a target that doesn't exist, is unrecoverable —
strictly worse than waiting.

#### 6. Self-restart (tmux) or hand off (no tmux)

Use `$SESSION`, `$ROLE`, `$SNAPSHOT_OK`, and `$SESSION_OK` from Steps 4-5.

**If `$SESSION` is non-empty (you are in tmux) AND `$SNAPSHOT_OK` = 1 AND
`$SESSION_OK` = 1** — run the self-restart yourself, right now, in this turn:

```bash
thrum tmux restart "$SESSION"
```

**⚠️ PLAIN RESTART — NEVER `--force`.** `--force` **DROPS the `--model` pin**; a
plain restart re-applies it at the readiness probe. A self-restarting agent that
uses `--force` can come back on the WRONG MODEL, and `runtime-config get` will
NOT reveal it — it reports the stored pin, not the delivered keystrokes. This is
not theoretical: it has been caught live more than once, including via a plain
restart that fixed it. The command above restarts your own pane; you will not
see further output in this turn. Do not follow it with more commands. Only reach
for `--force` if a plain restart genuinely does not take — and even then,
immediately re-pin and **verify the model OFF THE PANE** after you come back,
not off `runtime-config get`.

This applies whether you are a coordinator or any other role — there is no
requirement for a senior agent to run this for you; it is the same self-executed
command `thrum:sleep` already uses for its own tmux-kill. **This ADDS a
self-initiated route and does not remove the external ones**:
force-restart-at-high-context and operator/coordinator-initiated restart still
exist for the cases where self-restart isn't possible (e.g. verification failed,
or you're not in tmux).

**If `$SESSION` is non-empty but `$SNAPSHOT_OK` = 0 or `$SESSION_OK` = 0** — DO
NOT RESTART. Report and hold:

```bash
thrum send --to @your_coordinator --stdin <<'EOF'
Restart verification FAILED — holding, not self-restarting.
Reason: <paste the VERIFY FAILED line(s) from Step 5>
Snapshot path checked: ${REPO}/.thrum/restart/${AGENT}.md
Session target checked: ${SESSION} (raw: ${SESSION_RAW})
EOF
```

If you ARE the top-level coordinator (no senior agent above you), print the same
failure reason for the operator instead of sending it, and hold.

**Else (no tmux session)** — self-restart has nothing to target (there is no
tmux pane to run `thrum tmux restart` against). Print these instructions for the
operator:

> Restart snapshot saved at `.thrum/restart/${AGENT}.md`. To continue in a new
> session:
>
> 1. Exit this session
> 2. Start a new session in the same directory
> 3. The snapshot will be auto-loaded by `thrum prime`

### When to Use

- Context window is getting full (you're seeing compaction warnings)
- You've hit rate limits and need to wait
- Your session feels stuck or unproductive
- The operator or coordinator has asked you to restart

### After Restart: Session Archive

After restart, your snapshot doesn't disappear — it moves to
`.thrum/agents/<your-agent-id>/sessions/` and stays there as a persistent log
entry. Browse the archive with:

```bash
thrum agent sessions list                    # default: this agent
thrum agent sessions list --verbose          # full §1 bodies inline
thrum agent sessions list --json             # NDJSON for scripts
thrum agent sessions list --all              # every agent, grouped
```

Permissions are user-only (`0600` for each snapshot file, `0700` for the
sessions folder). Operators on multi-user machines must copy explicitly to share
archives with another account.

Worktree-resident ephemeral agents archive into the worktree's own
`.thrum/agents/<id>/sessions/` — so the archive vanishes when the worktree is
removed. **By design.** If an ephemeral agent's history matters across the
worktree teardown, export those snapshots manually before `git worktree remove`.

The next session's `thrum prime` output includes a "Past Sessions" discovery
hint summarizing the most recent archive's §1 — so future-you gets a one-line
reminder of last session's headline without re-reading the full snapshot. That
hint is why §1 above is required.
