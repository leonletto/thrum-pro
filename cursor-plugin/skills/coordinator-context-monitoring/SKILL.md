---
name: coordinator-context-monitoring
description:
  Use when managing live implementer/brainstormer agents during a long
  coordination session, at epic merge gates, after a busy dispatch hour, or
  whenever you suspect an agent is approaching context limits. Prevents
  97%-context silent blow-ups by running a sweep + pre-emptive restart before
  the agent degrades. Safe to wire into a recurring cron that INVOKES this skill
  — the skill applies tier-ladder judgment, surfacing (and, only when explicitly
  opted in via config, autonomously restarting) at the >85% tier. What's
  forbidden is a cron/script that fires restarts unconditionally without going
  through this skill's tier ladder.
---

# Coordinator: Context Monitoring and Pre-emptive Restart

## When to invoke

Trigger this pattern at each of:

- Receipt of an `ALERT: flagged=…` message from the `context-monitoring` thrum
  monitor (the canonical scheduled sweep, outer tick `@every 30m`, self-gated
  per D3 so effective rate is slower; see "How the scheduled sweep works")
- Epic merge gates (after merging a sub-epic — E6.4, E6.5, etc.)
- After dispatching 3+ tasks in quick succession
- After any agent has been running for 60+ minutes without a restart
- When you observe slow or degraded responses from an implementer
- Manually whenever the session feels "intense" (lots of cycles in a short
  window)

The skill applies tier-ladder judgment: the >85% tier surfaces a
`recommend-restart-extended` reason (or, when `restart_actuation=true` in
config, runs a snapshot-gated restart) only on actual ctx %, not on every sweep.
What's forbidden is a script that bypasses this skill and fires
`thrum tmux restart --force` unconditionally (that violates
`feedback_restart_discipline` — burn the runway, don't restart on schedule).

## Coordinator self-restart — ALWAYS `/thrum:restart-extended`

This skill's tier ladder (Steps 3–5) governs how the coordinator restarts
**other** agents. When the **coordinator restarts ITSELF**, a different rule
applies and it is absolute:

> **The coordinator ALWAYS self-restarts via `/thrum:restart-extended`, NEVER
> `/thrum:restart`.**

Rationale: the coordinator is the nerve center. Its handoff must carry the full
16-section snapshot (wire contracts, capability matrix, cycle history, open
L-questions, anticipated Q&A, design rationale) so the next session resumes
steady-state coordination without re-deriving fleet state. The standard
`/thrum:restart` compact format drops that load-bearing context and strands the
next session. This holds regardless of which tier the coordinator's own context
sits in — there is no ctx-band at which the coordinator downgrades to the
compact restart.

Practical trigger points for coordinator self-restart:

- A warn-tier context nudge fires on the coordinator's own pane (e.g. 70%+).
- The coordinator hits a clean checkpoint and elects a fresh session.
- Rate-limit / stuck-state recovery on the coordinator itself.

In every one of these, run `/thrum:restart-extended`. (Captured as role-rule
`coord-always-restart-extended` /
`Coordinator ALWAYS uses /thrum:restart-extended`; this skill is the
always-loaded home so the rule survives even when memory isn't consulted.)

Note the distinction from Steps 3–5 below: those steps drive `/thrum:restart`
(Step 4) and `/thrum:restart-extended` (Step 5) into
**implementer/brainstormer** panes per their ctx tier — that tiering is correct
for worker agents. The carve-out here is ONLY about the coordinator's own
restart, which is unconditionally the extended form.

## How the scheduled sweep works (v0.10.6+ — thrum monitor)

The sweep runs as a daemon-managed `thrum monitor` job named
`context-monitoring`, registered with an `@every 30m` schedule. The 30-min tick
is the outer envelope — the sweep is self-gated (D3): daytime ticks only fire
when the fleet is busy (`agent_status=working`), and overnight ticks fire only
every other tick (effective 60-min rate), so most ticks may be silent no-ops.
There is a SINGLE monitor for ALL lenses in v1 (I9) — not one per lens. The job
invokes
`scripts/error-and-context-agent-sweep.sh --no-nudge --out /tmp/agent-sweep.txt`.
The script emits a single consolidated `ALERT:` line to stdout when ANY agent
crosses a threshold (ctx >= 50% OR api-error OR capture-fail); when the fleet is
clean, the script is silent so no message fires. The monitor's
`--match '^ALERT:'` filter routes the ALERT line as a message to the
`coordinator` role (fanned out to every LIVE local coordinator — D8/R2: if no
coordinator is currently live, the sweep is a silent no-op rather than queuing
for an offline one), which triggers this skill.

Format of the ALERT line:

```text
ALERT: flagged=N stuck=S stuck_working=W tier3=T tier2=U — agent_a(92%,api-err,STUCK,stuck-working); agent_b(88%); …
```

or, on a benign-only tick once the periodic heartbeat interval has elapsed:

```text
ALERT: all-clear — N agents healthy, 0 actionable (sweep alive)
```

- `flagged` — total agents needing attention
- `stuck` — api-errored on TWO consecutive sweeps (state file tracks this across
  runs)
- `stuck_working` — agent_status=working AND tmux quiet > threshold AND no
  recent JSONL tool calls (thrum-9neg L5; threshold tunable via the sweep
  script's --silence-threshold-min flag, default 10 min)
- `tier3` — count with ctx >= 85% (snapshot-gated restart candidates; see
  Step 5)
- `tier2` — count with 70-84% ctx (tmux-send nudge candidates)
- Per-agent segment: `name(ctx%,reason-if-any,classifier)` joined by `;`

### RUN vs DELIVER (thrum-xg1zh / sweep-deliver-on-actionable)

The sweep now ALWAYS computes flags every scheduled tick (daytime; overnight
keeps its even-tick-only cadence) — RUN is no longer gated on a coarse
fleet-busy signal, which used to silently suppress genuinely actionable signals
before flags were even computed (a waiting-on-coord researcher was once
invisible ~8h this way).

DELIVERY of the `ALERT:` line is a separate decision, made AFTER flags are
computed:

- **ACTIONABLE** (delivers the real ALERT) — tier2/tier3 ctx, workstall, stuck /
  stuck_working, waiting-on-coord, blocked-on-human, capture-fail,
  ctx-unknown-idle, api-err, idle-mid-task (abandoned), finished-impl (recommend
  teardown), awaiting-restart, pending-human.
- **BENIGN-ONLY** (never delivers on its own) — idle-no-task and/or bare ctx
  tier1 (50-69%) alone. `flagged=20 tier3=0` where every one of those 20 is
  benign-only does **not** fire an ALERT — `flagged` counts everything written
  to the per-agent report; it does not imply delivery.
- **Periodic all-clear heartbeat** — configurable via `.thrum/config.json`
  `heartbeat.allclear_interval_min` (default 60). If no actionable ALERT has
  fired for that long, the sweep emits the minimal `all-clear` line above so a
  benign-quiet fleet is never mistaken for a dead monitor. Any delivered ALERT
  (actionable or all-clear) resets this clock.

The full per-agent report stays at `/tmp/agent-sweep.txt` (overwritten each
sweep) for on-demand drill-down — read it AFTER receiving an ALERT to see which
specific panes are at risk.

The previous keepalive-cron pattern (CronCreate `5fdb627b`) is deprecated in
favor of this scheduled monitor. The bookkeeping responsibility moves out of the
coordinator's per-session re-add chore and into the daemon's durable monitors
table (survives daemon restart, no per-session re-init needed for this monitor —
though OTHER CronCreate jobs may still require it per
`feedback_cron_reinit_each_session`).

## Lenses

Every lens SURFACES or RECOMMENDS by default — none take autonomous action on
their own. The ONLY exception is `context_tiers`' snapshot-gated restart, and
even that requires an explicit `restart_actuation: true` opt-in in config. There
is a single monitor for all lenses in v1 (I9), not one per lens.

### Default-ON lenses (implemented, E1–E6)

| Lens                        | Default | Disposition                                                                                                                                                       |
| --------------------------- | ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `context_tiers`             | ON      | The ctx%/stuck-working ladder (L1). Sole autonomous actuator when `restart_actuation=true`; otherwise RECOMMEND via `recommend-restart-extended` reason in ALERT. |
| `idle_mid_task`             | ON      | L2 — 30-min idle-with-open-task detection (bead cross-ref). RECOMMEND `/thrum:sleep-extended`; a no-task variant REPORTs `idle-no-task` at lower priority.        |
| `snapshot_awaiting_restart` | ON      | L3 — pane text + fresh-snapshot two-signal heuristic. RECOMMEND `thrum tmux restart <agent>` (never autonomous).                                                  |
| `blocked_on_human_modal`    | ON      | L4 — detects spend-limit/permission/consent modal prompts. DETECTION ONLY, never auto-answers; routes into the L5 ledger.                                         |
| `pending_human_ledger`      | ON      | L5 — flat JSONL ledger of items awaiting a human. EXEMPT from D5 backoff — surfaces every tick. `hb_ledger_resolve` (the resolution path) is defined but has zero call sites (thrum-ce317) — nothing marks an entry resolved, so today the ledger is append-only-forever, not "until resolved." |
| `waiting_on_coord`          | ON      | L9 — 21-rule pattern match (folded in from the standalone waiting-on-coord sweep) + warm-hold exemption. RECOMMEND coordinator answer.                            |

### Default-OFF lenses (E8, flag-gated — NOT YET IMPLEMENTED as of E7)

These lenses are reserved for E8. They exist as config flags for future work but
produce no output until enabled.

| Lens                    | Default | Disposition                      |
| ----------------------- | ------- | -------------------------------- |
| `merge_ready_queue`     | OFF     | L6 — REPORT                      |
| `merge_reconciliation`  | OFF     | L7 — REPORT                      |
| `base_deploy_staleness` | OFF     | L8 — REPORT                      |
| `ready_vs_capacity`     | OFF     | L10 — RECOMMEND                  |
| `stale_agent_gc`        | OFF     | L11 — propose-only GC, RECOMMEND |
| `daemon_wedge_trend`    | OFF     | L12 — REPORT                     |

## Configuration

The heartbeat system is configured under the `heartbeat` key in
`.thrum/config.json` (Go type: `HeartbeatConfig` in
`internal/config/heartbeat.go`). Example:

```json
{
  "heartbeat": {
    "schema_version": 1,
    "enabled": true,
    "cadence_minutes_day": 30,
    "cadence_minutes_overnight": 60,
    "busy_only_daytime": true,
    "busy_signal": "working_or_activity_30m",
    "overnight_window": {
      "from": "22:00",
      "to": "07:00",
      "tz": "America/New_York"
    },
    "backoff": { "start_after": 2, "multiplier": 2, "floor_every": 4 },
    "lenses": {
      "context_tiers": {
        "enabled": true,
        "params": {
          "restart_actuation": false,
          "degrading_flag_after_ticks": 3
        }
      },
      "idle_mid_task": { "enabled": true },
      "...": "..."
    }
  }
}
```

**Field reference:**

| Field                                                    | Purpose                                                                                                                                                                |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `cadence_minutes_day`                                    | Daytime cadence target (default 30 min). The underlying monitor runs `@every 30m` and self-gates so only busy-fleet daytime ticks fire.                                |
| `cadence_minutes_overnight`                              | Overnight cadence target (default 60 min). The monitor fires every other `@every 30m` tick overnight (effective 60-min rate).                                          |
| `busy_only_daytime`                                      | When `true`, daytime ticks are skipped unless any agent has `agent_status=working` (D3 busy-signal gate).                                                              |
| `busy_signal`                                            | Algorithm for "is the fleet busy?" Default `working_or_activity_30m`: any agent working OR activity in the last 30 min.                                                |
| `overnight_window.tz`                                    | **MUST be an explicit IANA timezone** (e.g. `"America/New_York"`). If unset, the sweep warns and falls back to always-daytime-rate rather than silently guessing (M1). |
| `backoff.start_after`                                    | Number of consecutive unchanged detections of the same problem before D5 progressive backoff begins.                                                                   |
| `backoff.multiplier`                                     | Each backoff step multiplies the surface interval by this factor (default 2×).                                                                                         |
| `backoff.floor_every`                                    | The surface interval is capped at this many ticks — the problem is never fully silenced (always surfaces at least once per `floor_every` ticks).                       |
| `lenses.<name>.enabled`                                  | Enable/disable a lens individually.                                                                                                                                    |
| `lenses.<name>.params`                                   | Per-lens parameters. The only actuation opt-in in the whole system is `context_tiers.params.restart_actuation` (default `false`).                                      |
| `lenses.context_tiers.params.degrading_flag_after_ticks` | After this many consecutive tier3 surfaced ticks without a successful restart, a `degrading-no-restart` reason is added to the ALERT (A2 backstop, default 3).         |

### Editing the config (there is NO `thrum config set`)

`thrum config` only has a `show` subcommand — you **hand-edit
`.thrum/config.json`** to configure the heartbeat. Two gotchas make this
non-obvious; both bite silently.

**1. All-or-nothing merge (the sharp footgun).** The loader
(`internal/config/daemon.go`, `LoadThrumConfig`) applies
`DefaultHeartbeatConfig()` **only when the stanza is effectively absent**
(`schema_version == 0` AND zero lenses):

```go
if cfg.Heartbeat.SchemaVersion == 0 && len(cfg.Heartbeat.Lenses) == 0 {
    cfg.Heartbeat = DefaultHeartbeatConfig()
}
```

There is **no field-level deep merge.** The moment you write a stanza with
`"schema_version": 1`, every field you _omit_ takes its Go zero-value —
`cadence_minutes_day: 0`, `enabled: false`, and **all 12 lenses disabled**. So
"I'll just set the timezone" with a three-line stanza silently turns the whole
sweep off. **Always write the COMPLETE stanza** — copy
`DefaultHeartbeatConfig()` (`internal/config/heartbeat.go`) in full, then change
only what you need.

**2. `overnight_window.tz` MUST be an explicit IANA zone.** Default is `""` (the
source comment reads "TZ set by operator"). Left unset, the sweep prints
`warning: heartbeat.overnight_window.tz not configured — using local time for gating`
and falls back to the box's local clock (M1 — it warns rather than silently
guessing). Set it to the operator's zone, e.g. `"America/Los_Angeles"` (PST/PDT)
or `"America/New_York"` (EST/EDT). Never `"local"`.

**Procedure** — back up, write the full stanza, validate, done (no restart):

```bash
cp .thrum/config.json .thrum/config.json.bak
# Build a COMPLETE heartbeat block mirroring DefaultHeartbeatConfig with your tz,
# then splice it in (jq keeps the rest of config.json intact):
jq --slurpfile hb /tmp/hb-block.json '.heartbeat = $hb[0]' .thrum/config.json > /tmp/c.json \
  && mv /tmp/c.json .thrum/config.json
jq -e '.heartbeat.overnight_window.tz != "" and (.heartbeat.lenses|length)==12' .thrum/config.json
```

**No daemon restart is required.** The scheduled monitor invokes the sweep
_script_, which reads `.thrum/config.json` directly on every tick — the new tz
takes effect on the next sweep. (`thrum config show` reflects the daemon's
in-memory config, cached at boot, so it will lag until the next daemon start;
that lag does not affect the script-driven sweep.) Avoid a
restart-just-for-config — it needlessly risks the 04qyb cold-boot WAL-replay
brick.

## Subagent model selection

> **Model tiers:** pass an explicit `model:` on every dispatch — `sonnet`
> (low effort) mechanical, `sonnet` (medium effort) judgment, Opus only on
> operator-ask or a skill step that names it. See the
> `choosing-subagent-models` skill for the full policy.

## Step 1 — Run the sweep

```bash
bash scripts/error-and-context-agent-sweep.sh --out /tmp/agent-sweep.txt
grep -E 'ctx_used:|^===== ' /tmp/agent-sweep.txt
```

The script emits one `ctx_used: X.X%` line per live agent. It captures the
Claude Code status bar footer, normalizing UTF-8 non-breaking spaces
(`\xc2\xa0`) before matching `Ctx Used: X.X%`. Runtimes without that footer
(Codex, Cursor) fall back to `(n/a)`.

## Step 2 — Threshold logic

### 🔴 ORCHESTRATORS ARE NOT ON THE CONTEXT LADDER — they restart on a PLAN BOUNDARY

**The context thresholds below are a COORDINATOR rule. Orchestrators inherited it
rather than being chosen for it, and it is not cost-optimal for them.** Do not
hold an orchestrator open to reach 70–75%, and do not restart one mid-plan to
chase the cost curve.

**The orchestrator rule:**

> **Restart an orchestrator at PLAN COMPLETION — where completion means the plan
> is MERGED *and* the follow-up beads filed during that plan have been FIXED.**
> Not at the merge report. Not at the merge.

**Why the follow-ups clause is load-bearing, not a detail.** The standing
fix-while-warm rule says a bug found mid-work gets FIXED while warm, because
file-and-move-on costs ~10x — the research has to be redone before the fix can
start. Bugs found during a plan are therefore filed and swept up at the END of
the plan, while the orchestrator *and its implementers* still hold the context.
**A restart at the merge boundary destroys exactly that warmth, and does so
INVISIBLY — the follow-ups still get done, just cold and at the 10x price.** A
restart rule keyed to "the merge" does not merely mistime a restart; it silently
repeals fix-while-warm.

**Why the split is real, not stylistic** (measured 2026-07-22):

- Per-turn cost scales LINEARLY with context size (the whole prefix is re-sent
  and billed at the cache-read rate every turn), so cumulative session cost is
  roughly QUADRATIC in how far context is allowed to grow. Break-even for a
  restart is **under one turn** once context is meaningfully above the re-prime
  floor.
- **Orchestrators re-prime far cheaper than coordinators, and it is structural:**
  `internal/cli/prime_filter.go` gives ONLY `role=="coordinator"` the full
  project-state passthrough. Measured orchestrator re-prime ≈ 30k tokens.
- Coordinators keep the ladder below for a stated reason — larger re-entry cost,
  plus decision-dense context a snapshot cannot faithfully reconstruct.

**What the plan boundary buys:** it is the one point where the cost argument and
the preserve-in-flight-judgment argument AGREE. The work has just been handed off
in a merge report and the follow-ups are closed, so in-flight judgment is at its
minimum and state is externalised into beads.

**Confidence: medium.** Turns-per-plan is measured at n=4 and per-*plan* (as
opposed to per-restart-session) figures are UNESTABLISHED — plan boundaries and
restart boundaries do not currently align. If plans are typically smaller than
the observed ~45-turn cycle, the gain is larger than stated, not smaller.

**Applying it in this sweep:** an orchestrator flagged in the 50–85% bands is
NOT a restart candidate on context alone. Check whether its plan is complete
(merged + follow-ups closed). If it is, restart regardless of how low its
context is. If it is not, leave it alone regardless of how high.



| ctx_tier | stuck_working | Action                                                                                                                                                                                                                                                                   |
| -------- | ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| < 50%    | N             | No action — agent has runway                                                                                                                                                                                                                                             |
| < 50%    | Y             | Tmux-send "are you stuck? `/continue` if waiting" nudge; if not recovered in next sweep, surface to operator                                                                                                                                                             |
| 50-70%   | N             | **NOT a warning** (thrum-xg1zh core policy) — OPTIONAL restart-if-IDLE only: directed inbox restart request when the agent is idle. A BUSY agent (or a coordinator, or a warm-hold/on-call/parked consultant) at 50-70% gets no action — see role/state carve-out below. |
| 50-70%   | Y             | Tmux-send nudge; defer the tier-1 directed restart request until the next sweep confirms the pane is active again AND ctx is still in this band                                                                                                                          |
| 70-85%   | N             | Tmux-send `/thrum:restart` (bypasses inbox; more forceful) — for coordinators/warm-hold consultants ACTIVELY WORKING, this band doesn't apply until the role/state carve-out's higher floor (75%, see below)                                                             |
| 70-85%   | Y             | Surface to operator immediately (degraded + stuck → human-eyes-needed)                                                                                                                                                                                                   |
| > 85%    | any           | Snapshot-gated restart (opt-in, D4): surface `recommend-restart-extended` by default; autonomous restart only when `restart_actuation=true` in config (see Step 5)                                                                                                       |
| `(n/a)`  | any           | Pane capture failed OR runtime has no Ctx footer — check tmux session manually                                                                                                                                                                                           |

**Role/state-aware carve-out (thrum-xg1zh refinement 5, LOCKED FINAL
2026-07-05):** coordinators, and any agent explicitly standing by as a
warm-hold:/on-call:/parked: consultant in an ongoing impl, are treated exactly
like a coordinator — while ACTIVELY WORKING (not idle) they only flag at
**ctx >= 75%**, not the normal 50% `CTX_THRESHOLD`. An IDLE coordinator (or idle
consultant) still flags at the normal threshold — idle restarts are cheap, no
exemption needed there. Implemented as `hb_effective_ctx_threshold` in
`scripts/heartbeat-lib.sh` — the 75% floor is a named var
(`HB_COORD_CTX_THRESHOLD_WORKING`), a one-line swap if it ever changes. Locked
test scenarios: coord@72%+working → NOT flagged; coord@76%+working → flagged;
coord@60%+idle → flagged; non-coordinator roles are unaffected (still 50% while
working or idle).

**Warm-hold/on-call/parked exemption (per thrum-9neg L4, extended by thrum-xg1zh
refinement 2):** if the agent's `intent` field starts with `^warm-hold:`,
`^on-call:`, or `^parked:`, skip nudge + restart for all tiers below >85% (and
apply the coordinator-equivalent 75% floor above while working). The >85%
bracket still fires regardless. These are EXPLICIT DECLARED states, not a
heuristic guess at coordination intent — a consultant/on-call/done-planning
researcher must set one of these prefixes ITSELF via
`thrum agent set-intent "warm-hold: <reason>"` (or `on-call:`/`parked:`).

**A coordinator CANNOT set another agent's intent.** `thrum agent set-intent`
takes TEXT only — it sets the intent for the CURRENT SESSION and accepts no
agent argument and no `--to`. To get an intent onto another agent, message that
agent and have it set its own; then verify by reading `thrum agent list --json`
rather than by counting acks.

**Background-child-aware busy detection (thrum-xg1zh refinement 1 — the #1
fix):** an agent with an OPEN in-progress bead, a recent JSONL tool_use
(`state == "working"`), or a pane showing it's driving background sub-agents
(`Waiting for N background agent...`) is BUSY, not idle — even if pane-silent.
This is checked BEFORE the idle/abandoned classification (`hb_idle_classify`'s
`is_busy` param) so an orchestrator quietly waiting on its own dispatched
sub-agents is never misread as abandoned just because it hasn't committed
recently.

**Finished-impl teardown (thrum-xg1zh refinement 4):** a closed bead + idle + no
new dispatch classifies as `finished`, which surfaces a `recommend-teardown`
ALERT to the coordinator — it is a RECOMMENDATION only, never autonomous;
teardown itself stays coordinator-actuated (kill-tmux → worktree-teardown per
lifecycle discipline in `implementer-status-and-handoff`).

## Step 2.5 — Stuck-working axis (thrum-9neg)

`stuck_working` is **orthogonal** to `ctx_tier`. They can compound. Treat the
table above as a composite lookup: the action depends on the _cell_, not on
either axis alone.

`stuck_working` measures "is this agent currently unable to make progress?"
while `ctx_tier` measures "how soon will this agent degrade if left alone?" An
agent can be:

- ctx-fine but stuck-working (waiting on a hung tool call) → nudge to unstick
- ctx-degraded but not stuck-working (working normally but burning context) →
  restart cleanly
- both → composite action per the table; high-degradation cases skip the nudge
  step since the agent likely can't recover from the nudge alone

The sweep's STUCK-WORKING classification (sweep script's per-agent
`stuck_working` line + ALERT-line `stuck_working=N` axis) fires when:

1. `agent_status = "working"` (the agent claims to be mid-work; set by the
   Pattern D self-write in role skills), AND
2. tmux silence > `SILENCE_THRESHOLD_MIN` minutes (default 10; tunable via
   `--silence-threshold-min N`), AND
3. JSONL transcript's last assistant message has `stop_reason = tool_use` AND
   was emitted more than `SILENCE_THRESHOLD_MIN` minutes ago (Claude runtime
   only; non-Claude runtimes use tmux silence alone)
4. `intent` does NOT start with `^warm-hold:` (warm-hold exemption)

The classification is sweep-side only — it does NOT write to identity files. The
identity-file `agent_status="stuck"` semantic stays reserved for
`permission.markAgentStuck` writes (permission-cadence give-up).

**Reliability ladder rationale:** the inbox → tmux-send → snapshot-gated restart
progression goes from polite to forceful. Inbox messages can fail (delivery
bugs, agent too degraded to check inbox at high ctx, or the documented self-echo
regression). Tmux-send types literally into the agent's input field — bypasses
inbox entirely. The snapshot-gated restart (Step 5) bypasses the agent's
willingness but not the worktree safety: it first solicits a snapshot, then
restarts gracefully only after one lands.

The thresholds reflect the pattern session-2-ago coordinator established: agents
degrade _silently_ before they blow, and 50% is the "still coherent enough to
write a good snapshot" window.

## Step 3 — Directed inbox restart request for 50% – 70% agents

```bash
thrum send --to @<agent_name> --stdin <<'EOF'
Your context is at ~X%. Please run /thrum:restart now — write your snapshot and I will re-dispatch after.
EOF
```

The agent writes their restart snapshot to
`.thrum/agents/<agent>/sessions/<timestamp>-restart.md` and goes idle.
Coordinator waits for the "snapshot written" acknowledgement before
re-dispatching the next task.

If the agent acks without writing the snapshot first (anti-pattern), gently
remind them to write the snapshot before going idle so the next session restores
cleanly.

If the agent doesn't respond within ~5 minutes OR you see them keep working,
escalate to Step 4 (tmux-send nudge).

## Step 4 — Tmux-send nudge for 70% – 85% agents

The inbox path may not be reaching them at this context level. Bypass the inbox
by typing the restart command directly into their input field:

```bash
thrum tmux send <tmux_session_name> '/thrum:restart'
```

(Find the tmux session name in sweep output — it's typically the worktree
basename, e.g. `b-b1-impl`, NOT the agent_id.)

This causes the runtime to immediately execute `/thrum:restart` as if the user
typed it. The agent writes their snapshot + restarts.

If the tmux-send doesn't trigger a restart within ~5 minutes (agent may be too
degraded to process input), escalate to Step 5 (snapshot-gated restart).

## Step 5 — Snapshot-gated restart for >85% agents (D4)

The >85% tier is the ONLY autonomous actuator in the whole heartbeat system —
and even it is **opt-in, off by default**. The behavior is controlled by
`heartbeat.lenses.context_tiers.params.restart_actuation` in config (default:
`false`).

### When `restart_actuation` is `false` (the default)

The sweep does NOT restart anything. It emits a `recommend-restart-extended`
reason in the ALERT line, surfacing the situation to the coordinator role. As
coordinator, when you see this reason you decide whether to run
`/thrum:restart-extended` on the agent yourself — a deliberate, human-in-the-
loop action. No automatic restart fires.

### When `restart_actuation` is `true` (explicitly enabled by the operator)

The sweep runs a 4-step snapshot-gated procedure automatically:

1. **Capture pre-send timestamp** — record the current wall-clock time.
2. **Send `/thrum:restart-extended` via raw tmux send-keys** — types the restart
   command directly into the agent's pane (bypasses inbox).
3. **Sleep a settle window** — default 180 s, tunable via `HB_SNAPSHOT_SETTLE`
   env var.
4. **Check for a FRESH snapshot file** — looks for a `*-restart.md` file in
   `.thrum/agents/<agent>/sessions/` written within the freshness window
   (default 200 s, tunable via `HB_SNAPSHOT_WINDOW` — a distinct env var from
   Step 3's settle window, `HB_SNAPSHOT_SETTLE`):
   - **Fresh snapshot found:** runs `thrum tmux restart <agent_id>` (graceful).
     **NEVER `--force`.** The `thrum tmux restart` call in this path takes no
     `--force` flag, by design — if the agent wrote a snapshot, there is no
     reason to force-interrupt mid-call.
   - **No fresh snapshot:** does NOT force anything. The agent is tracked in a
     `no_snapshot` backstop instead (see A2 note below).

**NEVER `--force`.** This path does not use `--force` under any circumstances.
Forceful interruption of a mid-tool-call agent is not worth the risk when the
graceful path is available and the agent has runway before catastrophic
degradation.

### Safety checks that still apply

The following guards from "Pre-restart safety checks" carry forward and are
checked BEFORE the snapshot-gated procedure fires:

- **Warm-hold exemption** — if `intent` starts with `^warm-hold:`, skip ALL
  restart actions for this agent (the >85% bracket is NOT exempt from warm-hold
  in the snapshot-gated model; an operator who sets warm-hold is taking explicit
  responsibility).
- **Cooldown** — do not restart the same agent twice within 30 minutes. If an
  agent crosses threshold again that fast, surface to operator rather than
  restart-loop.
- **No-restart-mid-merge** — never restart an agent whose pane shows a Git merge
  conflict or active rebase. Surface to operator instead.

### A2 — "degrading-no-restart" backstop

If an agent stays at tier3 without a successful restart landing — whether
because `restart_actuation` is `false`, or because a snapshot never appeared
within the settle window — for N consecutive surfaced ticks (default: 3,
config-tunable via
`heartbeat.lenses.context_tiers.params.degrading_flag_after_ticks`), the sweep
adds a distinct `degrading-no-restart` reason to the ALERT. This ensures the
coordinator still sees that the agent needs eyes even when the system alone
cannot fix it.

### After a successful restart

After the restart fires (this step or Step 4):

1. Surface a brief status note to the coordinator: "Snapshot-restarted
   @\<agent_name\> at \<ctx\>% — snapshot at
   `.thrum/agents/<agent>/sessions/<timestamp>-restart.md`".
2. Re-send the agent's current dispatch as if it were a fresh dispatch — treat
   them as a fresh implementer who needs the full briefing.
3. Note any WIP files in their worktree from the prior attempt (they'll audit
   salvage-vs-discard before substantive code).

## Step 6 — API-error recovery (who nudges depends on how the sweep runs)

When you run the sweep **manually** (the command in Step 1, no flags), it still
auto-nudges every agent whose pane shows an `API Error` line — it types
`continue` into the affected pane via `tmux send-keys` (bypassing the
`thrum tmux send` wrapper queue, which stalls on fully-silent panes per
`thrum-7yhs`). The report header lists who was auto-nudged:

```text
# auto-nudged 3 agent(s) on api_errors with 'continue':
#   - impl_foo @ foo-impl:0.0
#   ...
```

Pass `--no-nudge` (alias `--report-only`) to get a pure detection run with **no
pane writes** — useful when you want to inspect before acting.

**The daemon does NOT auto-nudge from the sweep.** The daemon-hosted built-in
sweep (`internal.sweep_coordinator_sweep`, thrum-d007.2) always runs the script
with `--no-nudge`: a daemon must not silently type into agent panes as a
side-effect of a _detection_ sweep. It reports flagged agents to the coordinator
role only.

**Deliberate daemon auto-remediation is a separate, opt-in feature**
(`internal.api_error_remediation`, thrum-sdzk;
`daemon.auto_remediation.enabled`, **default OFF**). When an operator turns it
on, the daemon — not this skill — applies the recovery tier ladder:

- 1st detection of an agent's API error → one `continue` nudge.
- Still erroring on the next tick (nudge didn't clear it) → it escalates
  SUSPECTED-STUCK to the operator chain instead of re-nudging (no nudge-loops).
- It skips panes mid git merge/rebase, audits every nudge/escalation, and resets
  an agent's state on recovery.

So if `daemon.auto_remediation.enabled` is on, you don't manage API-error
recovery by hand — the daemon does, with the same no-repeat + escalate
safeguards described here.

Anthropic 529s and rate limits are transient (typically resolve in
seconds-to-minutes); the agent's previous tool call is queued in-session, so a
single `continue` reactivates them without losing in-flight state.

**When to escalate (manual runs / daemon off):** if the same agent shows an API
error on TWO consecutive sweeps despite a nudge, the issue isn't transient —
surface to operator as SUSPECTED-STUCK and investigate manually
(status.claude.com, network, account limits). (When daemon auto-remediation is
on, it raises this escalation for you.)

**When NOT to nudge:** if you're about to ship a release and you'd prefer an
agent's stuck-state held to fold one more fix into the current cycle, run with
`--no-nudge` (or hold the manual sweep). Once `continue` fires, the agent
resumes its previous tool call immediately — there's no recovery window.

## Pre-restart safety checks

Whether triggered by the scheduled `context-monitoring` thrum monitor or by the
coordinator manually invoking the skill, run these guards BEFORE firing a
restart:

1. **Verify the daemon is reachable**:
   `thrum team --json | jq '.members | length'` — if 0 or error, daemon is down;
   skip the sweep, surface to operator.
2. **Confirm the monitor is alive**: `thrum monitor list` should show
   `context-monitoring` in `running` status with a non-empty `SCHEDULE` column.
   If absent or dead, the scheduled ALERTs aren't firing and the skill must be
   invoked manually from a recurring cron until the monitor is restored. (See
   "Re-register the monitor" below.)
3. **Check if any agent is mid-commit** (active tool call): look for
   `Running bash` or active spinner in the sweep pane lines — if so, defer
   restart for that agent until the tool completes.
4. **Never restart (graceful or otherwise) an agent whose pane shows a Git merge
   conflict or active rebase** — that corrupts the worktree. Surface to operator
   instead.
5. **Cooldown**: do not restart the same agent twice within 30 minutes. If an
   agent crosses threshold again that fast, something's wrong with their
   workload — surface to operator rather than restart-loop.

### Re-register the monitor

If `thrum monitor list` doesn't show `context-monitoring`, register it from the
main repo. The script path must be absolute (the daemon runs the command from a
clean env, not the coordinator's shell), so resolve it from the repo root first:

```bash
SCRIPT="$(git -C /path/to/thrum/main-repo rev-parse --show-toplevel)/scripts/error-and-context-agent-sweep.sh"
thrum monitor add \
  --name context-monitoring \
  --schedule "@every 30m" \
  --match '^ALERT:' \
  --to coordinator \
  -- bash "$SCRIPT" --no-nudge --out /tmp/agent-sweep.txt
```

(Or substitute the literal absolute path if you don't have a shell handy in the
daemon's environment.) The monitor fires one-shot per scheduled tick; in between
ticks the child does not run, so there's no continuous CPU cost from the sweep.
Note that `@every 30m` is the outer envelope — the sweep script self-gates (D3)
so most ticks produce no ALERT output and thus no message fires.

## What to do post-restart

When a restart fires (Step 4 or 5 — tmux-send nudge or snapshot-gated restart):

1. Wait for the agent to come back online (`thrum team` shows them active again,
   or their pane shows the runtime prompt).
2. Re-send their current dispatch with the full scope + plan refs + AC targets —
   treat them as a fresh implementer who needs the full briefing again.
3. Note any WIP files they may have left in their worktree from the prior
   attempt (they'll audit salvage-vs-discard before substantive code).
4. If they had a partial DONE, the coordinator's git log should still have it;
   the agent may need a pointer to commits they shipped before the blow.

## Reference

- **Sweep script**: `scripts/error-and-context-agent-sweep.sh` (captures
  `ctx_used: X.X%` from Claude JSONL transcript; falls back to pane scan for
  non-Claude runtimes). Renamed from `tmux-agent-sweep.sh` 2026-05-20 per
  thrum-e1n0 — now part of a sweep-script family (sibling:
  `waiting-on-coord-agent-sweep.sh`).
- **Pattern source**: Session 70 (`2026-05-17T14:40-19:00Z`) coordinator
  established the broadcast-at-50% + snapshot-gated-restart-at-85% threshold
  pattern (D4 replaced the original blind force-restart with opt-in gated
  actuation).
- **Memory key**: project-local `coordinator-rule-context-check-broadcast` may
  capture project-specific tweaks; load via
  `thrum memory list --kind agent_rule --scope role`.
- **Related discipline**:
  - `feedback_restart_discipline` — burn the runway; don't preempt-restart at
    clean checkpoints
  - `feedback_byte_equality_pane_detection` — pane-snapshot byte diffs are
    unreliable; use structural anchors + settle windows
- **Why thresholds matter**: agents at 97% context silently produce degraded
  output (missed instructions, partial tool calls, slow responses) before they
  blow. The 70%/85% thresholds give the system 15-30% runway to extract a
  snapshot or trigger a graceful restart cleanly.
