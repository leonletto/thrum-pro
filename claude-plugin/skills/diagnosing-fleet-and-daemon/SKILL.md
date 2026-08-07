---
name: diagnosing-fleet-and-daemon
description: "Use when the daemon or fleet looks broken and you need to find something FAST — daemon down, daemon not running, connection refused, dial unix, thrum.sock, socket refused, daemon crashed, daemon wedged, daemon hangs, fleet dark, fleet outage, agents unreachable, can't send, send failed, messages not delivering, no agents responding, daemon status wrong, daemon won't start, restart the daemon, is the daemon alive, where is the daemon log, which log file, searching logs, hooklog query, command log, jq returned nothing, empty log search, agent looks dead, agent stale, last_seen stale, is this agent alive, schema mismatch, cannot downgrade, migration on restart, SIGBUS, WAL poison, 522, database locked. Also use BEFORE restarting any daemon — the pre-restart migration check lives here."
---

# Diagnosing the Fleet and the Daemon

**This is a LOOKUP TABLE, not a procedure.** You are here because something is
broken and you need an answer in one command. Read the row you need and go.

**If you are about to restart a daemon, read § Pre-restart check FIRST.** It is
the only step here that can cause harm rather than merely waste time.

---

## § Canonical paths — get these wrong and you will report a false zero

| What | Where | NOT |
|---|---|---|
| **Daemon log** | `.thrum/var/log/daemon.log` | ❌ `.thrum/var/daemon.log` |
| Hook log | `.thrum/var/log/hooklog.jsonl` | |
| Command log | `.thrum/var/log/command.jsonl` | |
| Monitor log | `.thrum/var/log/monitor_log.jsonl` | |
| Pane-inject log | `.thrum/var/log/inject.jsonl` | |
| Database | `.thrum/var/messages.db` | |
| Socket | `.thrum/var/thrum.sock` | |

✅ **`daemon.log` now lives in the `log/` subdirectory, like every other log.**
This was not always true — an older layout kept it at `.thrum/var/daemon.log`
directly, and that mismatch previously produced a false "no crash evidence"
that was used to justify a restart without knowing the cause. **A missing-file
error is not a finding — it is a wrong path until you have proven the file's
absence.** If you are on an old checkout or an unmigrated install, check both
locations before concluding the file doesn't exist.

Worktrees redirect `.thrum/` to the main repo via `.thrum/redirect` — read that
file to find the real path before concluding anything is missing.

---

## § Searching logs — use the primitive, never raw jq

```bash
thrum log search <logname> <query> [-i] [-n N]
# logname: command | monitor_log | hooklog | ...
thrum log search hooklog "thrum daemon start" -n 5
```

Brute-force line scan of **today's file only**. Older history is in `.gz`
rotations under `.thrum/var/log/` — unzip and search those directly.

🔴 **DO NOT hand-roll jq against the JSONL.** In `hooklog.jsonl`, `tool_input` is
a **double-encoded JSON string**, not an object. Every one of these returns a
clean, well-formed, WRONG empty:

```bash
jq '.tool_input.command'                       # empty — tool_input is a string
jq '.raw_payload | .tool_input.command'        # empty — raw_payload is null
jq 'select(.tool_name=="Bash") | .tool_input.command'  # empty — same
```

The decode that works is `.tool_input | fromjson | .command` — but prefer
`thrum log search`, which needs no knowledge of the encoding and also matches
record shapes a `tool_name=="Bash"` filter silently excludes (`PreToolUse` /
`PostToolUse`). Four successive silent zeros have already been burned here.

**Whatever you search: if you get zero, run a control** (see § Controls).

---

## § Is the daemon actually down?

Ask in this order. **Do not stop at the first answer.**

```bash
thrum daemon status                    # may be WRONG during boot — see below
pgrep -fl "thrum daemon run"           # process table
thrum team | head -3                   # BY EFFECT — the real test
```

🔴 **`thrum daemon status` reports "not running" during background boot stages.**
Boot takes roughly **25 seconds**. Checking at 3s and 15s and concluding
"the status command is lying" is wrong twice over — it is accurate about a
daemon that is not yet ready. **Wait, then re-ask.** Reach for
instrument-failure only after the process table and a by-effect test disagree
with it *at the same moment*.

**By-effect beats status.** A successful `thrum team` / `thrum inbox` proves
service; a status line proves only what status believes.

---

## § Pre-restart check — THE ONE THAT CAN CAUSE HARM

**A restart can be a MIGRATING restart. Establish that before you type it.**

```bash
# What the DB is at now:
sqlite3 "file:$PWD/.thrum/var/messages.db?mode=ro" \
  "SELECT version FROM schema_version ORDER BY version DESC LIMIT 1;"
# What binary is installed:
thrum --version
```

**Have you CHANGED the binary since the daemon last ran?**

- **NO (same binary, e.g. it crashed or was stopped)** → **restart is
  non-migrating. Safe.** The inference: a daemon migrates on start, so if the
  installed binary had wanted a higher schema it would already have taken it.
  A daemon that ran at binary X with the DB at version N proves X wants N.
- **YES (you upgraded, or ran an install)** → **the restart MAY MIGRATE,
  one-way.** Take a backup first and treat it as its own decision.

🔴 **A migrating restart can trigger a known crash class** — the migration
rewrites the SQLite `-shm` sidecar, and the same process's next reader can fault
on the now-stale shared mapping (SIGBUS, or a `SQLITE_IOERR_522` poison storm).
Before a migrating restart: **take a backup, do it deliberately, and do not let
it ride along on a decision about something else.**

**Migration size is NOT a waiver.** A migration consisting of one `ADD COLUMN`
plus one `UPDATE` has been observed to trigger this. Do not reason "this upgrade
is small, so it is safe."

> *Dev-fleet note (ignore if you are running a release build): tracked as
> `thrum-j8i5l` / `bmrrz`; the fix is a boot-seam pool recycle.*

⚠️ Read the DB with `mode=ro`. **Never `immutable=1`** — it reads the stale base
file past a live `-wal` and answers confidently wrong.

---

## § Did it crash, or was it stopped?

```bash
grep -icE "SIGBUS|panic:|fatal error|walIndexRecover" .thrum/var/log/daemon.log
tail -40 .thrum/var/log/daemon.log
```

- **Hits** → a crash. Capture the trace before restarting; it may be `bmrrz`.
- **Zero, and the log simply stops** → it was *stopped*, not crashed. Look for
  who stopped it (§ Who did that) rather than hunting a nonexistent crash.

**"No crash evidence" and "I looked in the wrong place" are indistinguishable
without a control.** Confirm the file exists and is non-empty first.

---

## § Who did that?

```bash
thrum log search hooklog "daemon stop" -n 10
thrum log search hooklog "daemon restart" -n 10
thrum log search hooklog "<the command you're hunting>" -n 10
```

Read `cwd` on each hit — it identifies the worktree, and therefore the agent.
**Beware two traps:**

1. **Message bodies match too.** The hooklog stores full `thrum send` payloads,
   so prose *about* a command matches a search *for* that command. Check whether
   the hit is a command or someone talking about one.
2. **`thrum daemon start` spawns `thrum daemon run --repo <path>`.** Seeing that
   argv in the process table does **not** mean someone invoked it raw.

---

## § Is this AGENT alive? (different question from the daemon)

| Signal | Legitimately supports | NEVER supports |
|---|---|---|
| Live tmux pane / ppid chain | **liveness** | |
| `pid` + `start_time` | age, staleness | ❌ liveness verdict — wrong-DEAD on in-process restart |
| `last_seen` | age of last **RPC contact** | ❌ liveness — it advances only when the agent calls the daemon |
| DB row / tombstone / state file | nothing | ❌ liveness — the DB is often the thing that is wrong |

🔴 **`last_seen` is an RPC-activity proxy.** Measured: agents reading **838m** and
**552m** stale while their panes were live and actively working. An agent in a
long tool run, thinking, or sitting at a permission prompt looks identically
"stale" to a dead one.

**Definitive-dead is by DIRECT OBSERVATION only.** Peek the pane.

---

## § Controls — the discipline that makes all of the above trustworthy

**Every zero gets a control before you report it.** A control is a second
instrument, aimed at something you KNOW is present, run the same way.

Worked example from a real incident: a structured query for daemon invocations
returned **0**, while `grep -c` on the same file returned **33**. Two instruments
disagreeing about one file is what proved the *query* was broken rather than the
answer being "nobody did it." Without that control, the report would have been a
confident, well-formatted, wrong "no agent invoked a daemon command."

If a must-exist control ALSO returns zero, **your instrument is broken, not your
hypothesis confirmed.**

---

## § Known-noisy log lines — recognise, don't chase

| Line | Meaning |
|---|---|
| `sync.apply: M1 relay loop detected … dropped` | Working as designed — loop suppression. |
| `storagegw: gossip: peer … not connected` | Peer offline. Routine. |
| `storagegw: gossip: peer call failed … caller-peer lacks required capability` | **NOT routine** — a live capability gap. Worth a bead if sustained. |
| `dead_agent_sweeper: marked dead agent offline` | Routine sweeper work. |

---

## § Filing a bug report

When the answer is "this is a defect in thrum, not in my setup", a report with
the right artifacts is worth many times one without. **Collect these before you
write the report** — several are lost or overwritten on the next restart.

```bash
thrum --version                                  # binary build
thrum daemon status                              # or the exact failure text
sqlite3 "file:$PWD/.thrum/var/messages.db?mode=ro" \
  "SELECT version FROM schema_version ORDER BY version DESC LIMIT 1;"
tail -200 .thrum/var/log/daemon.log
grep -icE "SIGBUS|panic:|fatal error" .thrum/var/log/daemon.log
uname -a                                         # OS + arch
```

A good report states, in this order:

1. **What you expected and what happened** — the observable symptom, not your
   theory of it.
2. **Whether it reproduces**, and the smallest sequence that does it.
3. **What changed just before** — an upgrade, an install, a restart, a config
   edit, a migration. Most fleet faults are downstream of a change.
4. **Which of your conclusions are MEASURED vs INFERRED.** A report that marks
   its own guesses is far more useful than one that presents them as findings.
5. The artifacts above.

⚠️ **Redact before sending.** `daemon.log` and the JSONL logs can contain message
bodies, file paths, hostnames, agent names, and anything an agent pasted —
including secrets. Skim what you are attaching. If you cannot skim it all, send
the version/status/schema lines and the specific error, and offer the full log
separately.

**Do not send the database.** It contains your full message history. If a
maintainer needs schema state, the `schema_version` query above is what they
want.

---

## § Contributing back

**This skill is shared diagnostic memory. When you find a faster or more correct
way — or get burned by a path, an encoding, or a command that lies — EDIT THIS
FILE.** A lookup you had to rediscover is a defect in this page.

Rules for edits: add the *command that works*, not a description of the problem;
name the wrong path or wrong query explicitly, so the next reader recognises
their own mistake rather than just reading the right answer; and if a claim is
about runtime behaviour, say how it was measured.

> *Dev-fleet only: after editing, run `scripts/sync-skills.sh` so every runtime
> plugin picks it up.*
