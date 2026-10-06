---
name: thrum-restart-extended
description:
  Save a comprehensive 16-section restart snapshot and prepare for session
  restart. Use for designer/architect-grade handoffs needing wire contracts,
  capability matrix, anticipated Q&A, and design rationale that the standard
  $thrum:thrum-restart compact format cannot carry.
# source: claude-plugin/commands/restart-extended.md
# generated-by: scripts/sync-skills.sh
---

# Thrum Restart Extended

Use this skill when the user explicitly wants the `restart-extended` Thrum
workflow. Prefer the umbrella `thrum` skill when the request spans multiple
commands or needs broader coordination judgment.

## Session Restart — Extended (16-section snapshot)

Compose a comprehensive 16-section prose continuation, write it directly to your
restart file, then orchestrate the handoff. The extended structure is
fundamentally different from standard: it preserves wire contracts (types +
signatures + file:line cites), capability matrices (per-surface row-by-row
tables), anticipated implementer Q&A, design inventory (entanglement classes /
pattern catalogue), and locked decision rationale. Use this variant when the
next session may be cold and must recover the full design grammar from this
artifact alone.

### When to use extended vs standard

- **Use `$thrum:thrum-restart` (standard)** for routine context-exhaustion or
  rate-limit restarts where the work is well-trafficked and future-you can
  reconstruct from project state + recent inbox + a compact 11-section snapshot.
- **Use `$thrum:thrum-restart-extended` (this variant)** for
  designer/architect-grade handoffs: locking a complex brainstorm with multiple
  owner-decided forks, handing off a fanout implementation (≥3 call sites or ≥2
  epics), or any session where the next session may be a fresh restart and must
  recover wire-contract precision without re-reading the source files.

### Steps

#### 1. Resolve identity and your worktree (run BEFORE reading the partial)

```bash
# $REPO must be YOUR worktree — the directory `thrum prime` reads the restart
# snapshot back from. Resolve it ONLY via the daemon's authoritative,
# peercred-resolved identity (`thrum agent worktree --authoritative`) — NEVER
# via `thrum whoami --field worktree` or `git rev-parse --show-toplevel`
# (both cwd-resolved). A cwd-derived pattern could silently
# resolve to a DIFFERENT agent's worktree, or the main repo. There is NO git
# fallback — if the daemon can't answer, refuse and stop rather than guess.
REPO=$(
  thrum agent worktree --authoritative 2>/dev/null
) || { echo "ERROR: cannot authoritatively resolve your worktree via the daemon. Refusing to fall back to cwd/git-toplevel — that would risk silently saving this snapshot to the wrong repo. Check daemon connectivity and retry."; exit 1; }
[ -n "$REPO" ] || { echo "ERROR: thrum agent worktree --authoritative returned empty"; exit 1; }
AGENT=$(thrum whoami --field agent_id) || { echo "ERROR: agent not registered"; exit 1; }
[ -n "$AGENT" ] || { echo "ERROR: empty agent_id"; exit 1; }
mkdir -p "${REPO}/.thrum/restart"
```

(Step 1 is inlined here because the partial's own path resolves through
`$REPO`.)

#### 2. Read the shared snapshot-composition partial

Invoke the $thrum:snapshot-protocol skill and follow it.

It carries the CRITICAL DISCIPLINE block and BOTH the standard 11-section
structure and the EXTENDED 16-section structure with per-section guidance.

**Use the EXTENDED 16-section structure.** The structure block is `§1.` through
`§16.` with the per-section guidance documented in the partial.

#### 3. Write the continuation

First run this PREP block (it mints the path and a per-run nonce):

```bash
# The Bash tool does NOT persist shell state across calls, so this block
# re-resolves identity itself. Fail closed: no cwd/git fallback.
REPO=$(
  thrum agent worktree --authoritative 2>/dev/null
) || { echo "ERROR: cannot authoritatively resolve your worktree via the daemon. Refusing to fall back to cwd/git-toplevel — that would risk silently saving this snapshot to the wrong repo. Check daemon connectivity and retry."; exit 1; }
[ -n "$REPO" ] || { echo "ERROR: thrum agent worktree --authoritative returned empty"; exit 1; }
AGENT=$(thrum whoami --field agent_id) || { echo "ERROR: agent not registered"; exit 1; }
[ -n "$AGENT" ] || { echo "ERROR: empty agent_id"; exit 1; }
mkdir -p "${REPO}/.thrum/restart"
SNAPSHOT="${REPO}/.thrum/restart/${AGENT}.md"
NONCE="zn6fx-$(date +%s)-$$-${RANDOM}${RANDOM}"
echo "SNAPSHOT_PATH=${SNAPSHOT}"
echo "SNAPSHOT_NONCE=${NONCE}"
```

Write to EXACTLY the printed `SNAPSHOT_PATH` (not a path you re-derive), and
make sure the file contains the marker below (as its final line), with the
printed `SNAPSHOT_NONCE` — verify searches the whole file for it:

```text
<!-- snapshot-nonce: <SNAPSHOT_NONCE> -->
```

**Record both values** — the verify step pastes them into its verify block,
which fails closed unless the file at that exact path carries that nonce.

Then, per Step 3 of the partial, use the Write tool to save your composed
continuation to that exact path. `thrum prime` auto-injects this file on next
session start regardless of whether wake comes from `thrum tmux restart` or
operator-initiated `thrum tmux create`.

#### 4. Check session type and your role

```bash
SESSION_RAW=$(thrum whoami --field tmux_session)
# thrum whoami --field tmux_session returns a PANE-QUALIFIED value
# (e.g. "thrum-xyz-lifecycle-cmds:0.0"), not a session name. `thrum tmux restart`
# takes a session NAME and the daemon sanitizes ":"/"." to "-", so passing the
# raw value produces a lookup key ("thrum-xyz-lifecycle-cmds-0-0") that does not
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
SNAPSHOT="<PASTE SNAPSHOT_PATH FROM STEP 3>"
NONCE="<PASTE SNAPSHOT_NONCE FROM STEP 3>"
# Fresh authoritative re-resolution (shell state does NOT persist across Bash
# calls); it must agree with the path you actually wrote in Step 3.
REPO=$(
  thrum agent worktree --authoritative 2>/dev/null
) || { echo "ERROR: cannot authoritatively resolve your worktree via the daemon. Refusing to fall back to cwd/git-toplevel — that would risk silently verifying the wrong repo's snapshot. Check daemon connectivity and retry."; exit 1; }
[ -n "$REPO" ] || { echo "ERROR: thrum agent worktree --authoritative returned empty"; exit 1; }
AGENT=$(thrum whoami --field agent_id) || { echo "ERROR: agent not registered"; exit 1; }
[ -n "$AGENT" ] || { echo "ERROR: empty agent_id"; exit 1; }
SESSION_RAW=$(thrum whoami --field tmux_session)
SESSION=${SESSION_RAW%%:*}
EXPECTED="${REPO}/.thrum/restart/${AGENT}.md"
BIND_OK=1
if [ -z "$SNAPSHOT" ] || [ -z "$NONCE" ] || [[ "$SNAPSHOT$NONCE" == *"<PASTE"* ]]; then
  echo "VERIFY FAILED: SNAPSHOT/NONCE not filled in — paste SNAPSHOT_PATH and SNAPSHOT_NONCE from Step 3. SNAPSHOT_OK=0"; BIND_OK=0
elif [ "$SNAPSHOT" != "$EXPECTED" ]; then
  echo "VERIFY FAILED: identity/worktree DRIFT between write time and verify time. Written path: $SNAPSHOT — re-resolved path: $EXPECTED. SNAPSHOT_OK=0"; BIND_OK=0
fi
NOW=$(date +%s)
# mtime: choose the stat dialect explicitly. GNU `stat -f` means --file-system
# (succeeds with multiline garbage), so the `stat -f %m || stat -c %Y` one-liner
# breaks on Linux — branch on which dialect this box speaks.
if stat -f %m . >/dev/null 2>&1; then
  MTIME=$(
    stat -f %m "$SNAPSHOT" 2>/dev/null
  )
else
  MTIME=$(
    stat -c %Y "$SNAPSHOT" 2>/dev/null
  )
fi
AGE=$(( NOW - ${MTIME:-0} ))
SNAPSHOT_OK=1

if [ "$BIND_OK" = 0 ]; then
  SNAPSHOT_OK=0   # binding failure already reported above
elif [ ! -f "$SNAPSHOT" ]; then
  echo "VERIFY FAILED: no snapshot at $SNAPSHOT"; SNAPSHOT_OK=0
elif [ ! -s "$SNAPSHOT" ]; then
  echo "VERIFY FAILED: snapshot at $SNAPSHOT is empty"; SNAPSHOT_OK=0
elif [ ! -r "$SNAPSHOT" ]; then
  echo "VERIFY FAILED: snapshot at $SNAPSHOT is not readable"; SNAPSHOT_OK=0
elif [ "$AGE" -gt 300 ]; then
  echo "VERIFY FAILED: snapshot at $SNAPSHOT is ${AGE}s old — stale (from a prior restart), not this session's write"; SNAPSHOT_OK=0
elif ! grep -qF -- "$NONCE" "$SNAPSHOT"; then
  echo "VERIFY FAILED: nonce not found in $SNAPSHOT — file at that path is not this session's write"; SNAPSHOT_OK=0
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
echo "SNAPSHOT_OK=${SNAPSHOT_OK} SESSION_OK=${SESSION_OK}"
```

**Fail-closed binding rule:** the block passes only for the exact path and nonce
the Step 3 PREP block printed (paste them into its first two lines). Empty or
placeholder values, identity/worktree drift between write and verify time, or a
file at that path without the nonce all mean VERIFY FAILED — a fresh file merely
sitting at the re-derived path is NOT proof you wrote it. Use the
`SNAPSHOT_OK`/`SESSION_OK` values it prints in Step 6.

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
NOT reveal it — it reports the stored pin, not the delivered keystrokes. The
command above restarts your own pane; you will not see further output in this
turn. Do not follow it with more commands. Only reach for `--force` if a plain
restart genuinely does not take — and even then, immediately re-pin and **verify
the model OFF THE PANE** after you come back, not off `runtime-config get`.

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
Restart (extended) verification FAILED — holding, not self-restarting.
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

### After Restart: Session Archive

After restart, your snapshot moves to `.thrum/agents/<your-agent-id>/sessions/`
and stays there as a persistent log entry. Same mechanism as standard restart —
see `$thrum:thrum-restart` for archive browsing commands.
