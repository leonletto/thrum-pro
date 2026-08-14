---
name: coordinator-deploying-the-fleet
description: "Use when rolling a build across ALL boxes - fleet deploy, fleet roll, rolling the fleet, deploy everywhere, ship to every box, canary then the rest, promote the canary, fleet rollout, deploying after a merge batch. Orchestrates the staged multi-box order and the promotion gate between stages, and delegates each individual box to the coordinator-deploying-a-box runbook. Load this BEFORE dispatching any box."
---

# Coordinator: Deploying a Build Across the WHOLE FLEET — staged order, canary, promotion gate

**This skill is the ORCHESTRATION layer. It does not replace
`coordinator-deploying-a-box` — it calls it, once per box.**

- **This skill answers:** which box goes first, what must be true before the next
  one goes, who runs each one, and what is owed after the last one.
- **`coordinator-deploying-a-box` answers:** how to deploy one box safely.

**Read both. Skipping the per-box runbook because you read this one is the
failure this split is designed to prevent.**

---

## 0. THE ONE RULE THAT OUTRANKS EVERYTHING HERE

🔴 **NEVER ssh-deploy INTO a box. Each box's OWN coordinator drives its OWN
deploy, LOCALLY.** (Leon, standing, binding.)

A non-interactive ssh deploy silently drops node/pnpm from PATH, `make build-ui`
exits 127, **the deploy CONTINUES and reports success**, and lands an UNBUILT
SHA. The rule exists because the failure reports green.

**So your job in a fleet roll is DISPATCH AND GATE, never execution — except on
your own box.** If you find yourself typing `ssh` and `make install` in the same
command, stop.

---

## 1. THE ORDER — ONE fixed point, the rest composed per roll

🔴 **ONLY ONE THING IS A STANDING RULE: leontest goes FIRST, ALONE, as the
canary.** That has held across every recorded roll ("start with leontest like
usual").

**EVERYTHING ELSE IS COMPOSED FRESH EACH TIME.** Recorded rolls disagree, and
they disagree deliberately:

| roll | order actually executed |
|---|---|
| 2026-07-19 | leontest canary, then zaras / ubuntu / lic_server / mock-jira dispatched as a simultaneous **prep-and-hold** batch, released one at a time; thrumtest routed separately via its own owner |
| 2026-07-28 | zaras → **primary** → ubuntu, with leontest ready and thrumtest trailing |

⚠️ **DO NOT WRITE "PRIMARY GOES LAST" INTO YOUR PLAN AS A RULE. IT IS A DEFAULT,
AND IT HAS BEEN DELIBERATELY OVERRIDDEN** — on 2026-07-28 primary went SECOND,
because the owner needed the changes demonstrable at a meetup. **The owner sets
the order; this skill sequences whatever order is set.**

**Sensible default when nobody says otherwise:** leontest → zaras + ubuntuleondev
(parallel is fine, different boxes, no shared state) → thrumtest → primary.
**Reason to keep primary late:** it hosts the most agents and is the
coordinator's own box, so a bad build there costs you the ability to drive the
recovery. **That is a reason, not a law.**

| Box | Coordinator |
|---|---|
| leontest | `coord_remote_thrum_agents` |
| zaras | `coord_thrum_zarambp14` |
| ubuntuleondev | `coord_remote_ubuntu` |
| thrumtest | `coord_thrumtest` |
| primary | `coordinator_main` |

⚠️ **thrumtest's position is INCONSISTENT across rolls** — sometimes explicitly
"in order", sometimes trailing. **Ask; do not assume.** It is always driven by
its own coordinator, never dispatched around.

### PREP-AND-HOLD — the mechanism that makes a staged roll safe
Dispatch several boxes at once to do **READ-ONLY prep only**: measure current
state, take the backup, `git pull`, capture BEFORE readings. Then:

> **"PREPARE AND HOLD. CANCEL NOTHING. DO NOT RESTART until I release you BY
> NAME."**

**Release one box at a time, by name.** This gets the slow prep done in parallel
without any box mutating itself before the canary has reported.

⚠️ **`coord_thrum_leonair` runs the PUBLIC 0.10.x line and is EXCLUDED from
0.11 rolls.** Do not dispatch it.

🔴 **RESOLVE EVERY COORDINATOR FROM `thrum team` AT DISPATCH TIME, NOT FROM THIS
TABLE.** A name is a label somebody chose; the authoritative method is a
`daemon_id` join. An agent's NAME and its WORKTREE NAME are not its location —
an agent named for a box has been found resident on a different one, and obeying
that name would have driven the forbidden ssh path.
⚠️ **`thrum agent list --all` returns ZERO for agents that certainly exist** —
do not use it as your roster instrument, and do not read its empty output as an
absence.

---

## 2. THE PROMOTION GATE — what the canary must prove before anyone else goes

**Do not release stages 2-5 on "leontest finished." Release them on these,
each measured BY EFFECT on that box:**

- Installed binary `--version` **equals the pin exactly** — not "close", not
  "the branch".
- Daemon restarted with a **NEW PID**, and `daemon status` reports the pin.
  ⇒ **MERGED == INSTALLED == RUNNING, all three agreeing.**
- Schema **before AND after** — proves migrating-vs-not by effect rather than
  from the delta.
- UI built for real (module count, signed) — **not the exit-127 shape**.
- Built from a **CLEAN detached worktree at the pin**, `git status --porcelain`
  empty ⇒ contamination closed BY CONSTRUCTION, not by inspection.
- 🔑 **`sync_checkpoints` count BEFORE and AFTER, and they match.** A reset is
  the silent peer-stranding failure that has **no repair command**. **This check
  is worthless without a BEFORE reading** — take your own; do not skip it
  because the canary's was clean.
- `crash-fatal.log` — 0 bytes, or read it before declaring success.

⚠️ **"CANARY GREEN" IS NOT "ALL THREE PASSES PROVEN."** The canary usually
proves the BINARY pass only. Say which passes you verified, every time.

🔴 **THE CANARY RESULT DOES NOT TRANSFER. EVERY BOX IS MEASURED ON ITS OWN
NUMBERS.** Measured instance: leontest's canary came back green while primary
had **207 matured tombstones over live agents**. The canary proves the BUILD is
sound; it says nothing about any other box's state. **Do not let a green canary
talk a box out of taking its own BEFORE readings.**

⏱ **GIVE A CONVERGENCE CHECK LONG ENOUGH TO DISCRIMINATE.** A short wait cannot
tell "the fix works" from "it had already converged before you looked." One roll
made a full 3-minute wait a hard requirement after a too-short check produced an
uninterpretable pass. **Pick the interval from what the mechanism needs, not
from impatience.**

### The go/no-go has never been a fixed number — get it from the owner
Recorded bars differ: one roll released on the canary alone; another on *"a
couple of fleet members reporting good deploys"*, which the coordinator
operationalised as *"zaras fully green and leontest's binary+preamble green —
that's my bar."* **Both were judgment calls stated out loud.** ⇒ **State YOUR
bar explicitly before promoting, so it can be challenged.** An unstated bar is
indistinguishable from no bar.

---

## 3. THE THREE PASSES — a "deploy" silently conflates three independent things

**Every box owes all three. They fail independently and a box can be current on
one and month-stale on another.**

| Pass | What it updates | Who runs it |
|---|---|---|
| 1. `make install` + `thrum daemon restart` | the **binary** | the box's own coordinator |
| 2. `thrum roles refresh` **then** `thrum roles deploy` | **role preambles** | the box's own coordinator |
| 3. plugin refresh / reinstall | **skills, commands, hooks** | 🔴 **the OPERATOR (Leon)** — a coordinator CANNOT self-serve this |

🔴 **PASS 2 ORDER IS LOAD-BEARING AND NOT OBVIOUS:** `refresh` FIRST (shipped
templates → role template), THEN `deploy` (role template → per-agent preamble).
**Running `deploy` alone re-renders agents from the OLD templates and reports
success.**

🔴 **RUN PASS 2 BETWEEN `make install` AND THE DAEMON RESTART, ALWAYS:**
`make install` → `thrum roles refresh` → `thrum roles deploy` → daemon restart.
Do the refresh+deploy the instant `make install` finishes and BEFORE restarting
the daemon, so the current preamble is already in place when any agent next runs
`thrum prime`, restarts, or checks its preamble.

🔴 **PASS 2 IS MANDATORY WHENEVER THE BUILD CHANGES
`internal/context/roleconfig/templates/` OR the compiled-in preamble.**
Preambles are RENDERED, not read live — installing a binary changes the source
and changes **nothing any agent reads**. There is **no staleness signal**: a box
serving a month-old render looks identical to a current one.

🔴 **PASS 3 REQUIRES A PLUGIN VERSION BUMP OR IT REACHES NOBODY.** The install
cache is keyed by version; an unchanged version means the installer skips the
re-copy and every skill edit stays invisible. Invoke the `plugin-update` skill;
do not improvise it.

### 🔴 THE BOX'S **REPO CHECKOUT** MUST BE AT THE PIN BEFORE PASS 3 — THE BINARY BEING AT THE PIN IS NOT SUFFICIENT

**Measured on a canary, 2026-07-30.** The box deployed correctly, its binary
landed at the pin, and its plugin pass then installed **the version its WORKING
TREE carried — one bump behind the pin.** The plugin source is a **LOCAL PATH**,
so pass 3 reads the checkout, not the binary.

⚠️ **AND THE BOX'S OWN VERIFICATION CANNOT SEE IT.** It compared installed
skills against its own source — byte-for-byte, 54/54, zero mismatches — and
**both sides were the stale version.** That proves the box is internally
consistent WITH ITSELF and is structurally incapable of detecting a stale
source. Same shape as render-fidelity-vs-doctrine-currency for preambles, except
**pass 3 has no equivalent of the ancestry check**, so nothing warns you.

🔴 **IT IS SELF-SEALING.** The cache is keyed by version, so at the stale version
the installer sees a match and **skips the re-copy permanently.** Re-running the
refresh does NOT fix it. Only bringing the checkout to the pin and re-running
does.

**⇒ Before handing a box to the operator for pass 3, verify BY EFFECT that all
FOUR manifests read the pin's version.** A partial bump is worse than none — the
runtimes then disagree about which build they are. And name the cache directory
**explicitly** when verifying; never `ls | tail -1`, because version directories
do not sort the way you expect (`…1.12` sorts BELOW `…1.3` and `…1.5`, and
several versions coexist).

**When reporting a deploy, name which passes you verified.** "Deployed" that
silently covers all three is how staleness hides.

---

## 4. PRE-FLIGHT — before dispatching box 1

1. **Is trunk green?** Trunk-green is defined as `make gate` passing. A green
   lane, a green package, or a clean dual review is **not** that claim.
   ⚠️ **Publishing a green without naming its invocation is the most common
   error here:** 0-of-6 and 0-of-15 are different claims in identical words.
2. **PIN AN EXACT SHA. NEVER "tip".** Tip moves under boxes mid-roll — two boxes
   told to deploy "tip" ship different code and both report success.
3. **Migrating or not?** Compare `CurrentVersion` at the pin against each box's
   running schema. A migrating roll pulls in the whole heavy-migration section
   of the per-box runbook; a non-migrating one does not.
4. **Forward-only:** each box's current SHA must be an ancestor of the pin.
   Pair the check with a control that MUST refuse (an invented SHA).
5. **Backup sizing** — the per-box runbook carries the formula. A percentage
   rule is not it, and a stale `current/` answers "are we protected?" with a
   wrong yes.
6. **Announce the pin and the order** to every coordinator before starting, so
   nobody deploys a different SHA.

---

## 5. DISPATCHING A BOX — what the message must carry

Give each coordinator, explicitly:

- **The exact pinned SHA** and the instruction to build from a clean detached
  worktree at it.
- **An instruction to load `coordinator-deploying-a-box` and follow it** — not a
  summary of it. ⚠️ **A summary you wrote reads as complete precisely because
  you wrote it**, and its omissions are silent; the documented incident is a
  coordinator working from its own bullets and skipping the backup and the role
  re-render.
- **Which passes it owes** (1 and 2; pass 3 is the operator's).
- **Its own BEFORE readings** — `sync_checkpoints`, schema, PID.
- **That acceptance is BY EFFECT, never by exit code.**
- **That it must report which passes it verified**, separately.

---

## 6. AFTER THE LAST BOX

- **Agent phase reconciliation, per box.** A restart leaves recorded `phase`
  disagreeing with reality — live agents read `stale`, dead ones can read
  `active`. Phase is local state and does not cross the peer boundary, so every
  box runs it against its own daemon.
- **Restart the orchestrators and long-lived agents** so they pick up the new
  preambles and skills. 🔴 **Agents adopt a new preamble ON THEIR NEXT RESTART,
  not immediately** — a live agent keeps behaving per the identity it was born
  with. Track adoption by session birth time, never file mtime.
- **Pre-release test suite — CHECK WHETHER IT IS OWED; do not assume it is.**
  It is documented as a gate for cutting an RC/release, and a remote box runs it
  after fleet deploys by standing arrangement. ⚠️ **A search of past rolls did
  NOT establish it as a mandatory step for a routine binary/preamble/plugin
  roll.** Read the run index: if its newest entry predates this deploy, the suite
  has not run against what is now deployed — then decide, with the owner,
  whether this roll warrants one. **Stated as a gap rather than invented as a
  rule.**
- **Update the deploy-state record** — per box: serving SHA, schema, AS OF, and
  how established. **Do not normalise every row to one SHA**; an unmeasured row
  is not a measured negative, and a tidied row is indistinguishable from a fresh
  measurement.
- **Sweep for SHA-anchored rules that just went stale.** A superseded SHA has
  two roles that fail in OPPOSITE directions: as a GUARD it refuses legitimate
  work and presents as caution; as a TARGET it validates the wrong artifact and
  produces **a green that means nothing**. The target direction is the dangerous
  one and it is the one a guard-sweep misses. Prefer re-deriving the live build
  at run time over re-anchoring, which only re-arms the trap for the next roll.

---

## 7. HOLDS

- **A fleet deploy is the OWNER'S CALL.** A lifted prohibition is not a
  permission.
- **Any box may hold its own deploy** and must say why. A box-local blocker that
  does not touch the deploy path is not a reason to hold — check whether the
  runbook's acceptance checks actually need the thing that is broken.
- **If the canary fails, the roll stops.** Do not promote on a partial result.
- **Deploy often, in small batches.** A large roll bundles unrelated changes, so
  when a box misbehaves afterwards, attribution across a hundred commits gets
  expensive fast.

---

## Red flags — STOP

- `ssh` and `make install` in the same command.
- Dispatching a box by NAME without resolving its coordinator at dispatch time.
- Promoting past the canary on "it finished" rather than on the §2 checks.
- Reporting "deployed" without saying WHICH of the three passes was verified.
- Running `roles deploy` without `roles refresh` first.
- Expecting skill changes to reach agents without a plugin version bump.
- Deploying "tip" instead of a pinned SHA.
- Reading an installer's exit 0 as proof the binary landed.
- Taking an `after` reading with no `before` — especially `sync_checkpoints`.
- Summarising the per-box runbook into a dispatch instead of telling the
  coordinator to load it.
