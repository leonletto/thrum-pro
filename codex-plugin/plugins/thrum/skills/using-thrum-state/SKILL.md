---
name: using-thrum-state
description: "Use when reading or writing thrum state - checking your own agent-local current state at session start, updating your status/next-actions, reading a fleet fact like deploy state or topology before acting on it, citing a SHA or box fact in a decision, deciding whether a fleet row is fresh enough to trust, or responding to a freshness-sweep ping. Also use before writing any fleet row - deploy state, topology, worktree, agent pool, or a standing ruling - to confirm you are writing from a by-effect measurement, not a guess. Triggers on: citing a fleet fact, deploying, restarting a daemon, migrating schema, reconciling state at session start, receiving a stale-row ping."
# source: claude-plugin/skills/using-thrum-state/SKILL.md
# generated-by: scripts/sync-skills.sh
---


## Using Thrum State

### Overview

`thrum state` is a two-tier current-value store. **Agent-local** state
(`thrum state set/get/list/show/delete` with an undeclared or `personal_state`
kind) is your own standing status — reconcile it like your queue, at session
start and every breakpoint. **Fleet state** (deploy_state, topology,
worktree, agent_pool, ruling) is different in kind: it describes a fact
about a DIFFERENT machine that changes elsewhere, with no owner present when
it goes stale.

**The governing invariant: a fleet row is a timestamped measurement, not a
current truth.** Every row carries `as_of`/`method`/`established_by` — read
them before you act.

### When to Use

- Checking your own agent-local current state at session start.
- Updating your own status/next-actions.
- Reading a fleet fact (deploy state, topology) before acting on it.
- Citing a SHA or box fact in a decision.
- Deciding whether a fleet row is fresh enough to trust.
- Responding to a freshness-sweep ping.
- Writing any fleet row (deploy state, topology, worktree, agent pool, or a
  standing ruling) — confirm you are writing from a by-effect measurement,
  not a guess, before you do.

### The named rot mode: "the tidied row"

A normalized or guessed value that reads byte-identically to a measured
one. This is how a coordinator acts on a confidently-wrong SHA. The
corrected intuition: **`as_of` is a measurement time, not a last-edit
time** — writing a fleet row without a fresh by-effect check, even to
"fix" a value you believe is stale, is exactly this failure.

### Reconcile, don't just read

- **Agent-local** (all roles): check at session start
  (`thrum state list`), update as you go. Carried-over state is NOT
  auto-injected into prime — you must ask.
- **Fleet** (coordinators write; everyone reads): before citing a fleet
  fact in a decision, check `as_of`/`method`. Past the kind's threshold
  (`thrum state describe <kind>`)? Re-verify by effect before acting, or
  say explicitly that you're acting on a stale value and why that's
  acceptable this once.

**Unmeasured ≠ measured-negative.** An absent row does not mean "at tip" or
"clean" — it means nobody has measured it. Do not read absence as a
negative result.

### Quick Reference

| Command | Effect |
|---|---|
| `thrum state set --kind <k> --scope <s> --value '<json>'` | Upsert (create or overwrite) |
| `thrum state get <kind>:<scope>` | Read one entry |
| `thrum state list [--kind <k>] [--agent <id>]` | List entries |
| `thrum state show <kind>:<scope>` | Full metadata for one entry |
| `thrum state delete <kind>:<scope>` | Remove outright (fleet: tombstones) |
| `thrum state describe <kind>` | Dump a declared kind's field shape + threshold |
| `thrum state history <kind>:<scope>` | Append-only write history (recovers LWW losers) |

`--method by_effect` when you measured it directly; `--method asserted`
when you're stating it without a live check; a write relayed from a message
is forced to `--method relayed` (low-trust) — never choose `relayed`
yourself.

### Common Flows

**Deploy runbook, after verifying a box's serving SHA:**

```bash
thrum state set --kind deploy_state --scope box-a \
  --value '{"serving_sha":"<sha>","schema":77}' --method by_effect
```

**Session-start reconcile (agent-local):**

```bash
thrum state list
# update anything stale; nothing auto-loads, so do this every session
```

**Responding to a freshness-sweep ping:** re-verify the named row by
effect, then `thrum state set` with the fresh value and `--method
by_effect`. Never "correct" a row you have not personally re-measured.

### Common Mistakes

- **Normalising the deploy table to one SHA "because that's probably
  right."** This is the tidied-row catastrophe. Re-verify by effect or
  leave it stale-flagged.
- Writing the same fact to both agent-local AND fleet state (coordinators
  especially — see the coordinator preamble's anti-double-add rule).
- Choosing `--method relayed` yourself instead of letting a message-relay
  path force it.
- Treating an absent fleet row as a negative result instead of "nobody has
  measured this."
