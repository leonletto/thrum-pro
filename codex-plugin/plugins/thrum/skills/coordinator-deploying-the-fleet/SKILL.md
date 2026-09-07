---
name: coordinator-deploying-the-fleet
description:
  "Use when rolling a build across ALL boxes - fleet deploy, fleet roll, rolling
  the fleet, deploy everywhere, ship to every box, canary then the rest, promote
  the canary, fleet rollout, deploying after a merge batch. Orchestrates the
  staged multi-box order and the promotion gate between stages, and delegates
  each individual box to the coordinator-deploying-a-box runbook. Load this
  BEFORE dispatching any box."
# source: claude-plugin/skills/coordinator-deploying-the-fleet/SKILL.md
# generated-by: scripts/sync-skills.sh
---

## Coordinator: Deploying a Build Across the WHOLE FLEET — staged order, canary, promotion gate

**This skill is the ORCHESTRATION layer. It does not replace
`coordinator-deploying-a-box` — it calls it, once per box.**

- **This skill answers:** which box goes first, what must be true before the
  next one goes, who runs each one, and what is owed after the last one.
- **`coordinator-deploying-a-box` answers:** how to deploy one box safely.

> # 🔴🔴 LOAD `coordinator-deploying-a-box` FOR EVERY BOX — **INCLUDING THE BUILD BOX, YOUR OWN BOX. NO EXCEPTIONS.**
>
> **This is the #1 way this skill fails, and it has failed this way MORE THAN
> ONCE (Leon, 2026-09-03).** You dispatch the per-box runbook to every REMOTE
> coordinator — and then you drive your OWN box (the build box) by hand,
> improvising the install and restart, because _"I'm the coordinator, I'll just
> do it."_ **That improvisation IS the failure.** The per-box runbook carries
> steps that are invisible until they bite:
>
> - 🔴 **On macOS you MUST restart via `scripts/mac-daemon-restart-via-cron.sh`,
>   NEVER a bare `thrum daemon restart`** — a terminal/VSCode-parented daemon is
>   silently DENIED Local Network (TCC) permission and cannot dial LAN peers. A
>   new binary is a new cdhash, so the "Allow devices on the local network"
>   prompt MUST re-fire and the operator MUST click Allow. **A bare restart on
>   the build box looks successful and leaves every LAN peer bridge hanging
>   "connecting" forever** (§6b-mac of the per-box runbook).
> - the backup sizing formula, the SHA-CONTAINS-the-fix ancestry check, the
>   by-effect verification, the strand-gate, the phase reconcile — none of which
>   you carry in your head.
>
> **⇒ THE MOMENT YOU REACH YOUR OWN BOX (or ANY box you drive yourself), STOP
> AND LOAD `coordinator-deploying-a-box`.** Executing-directly (not dispatching)
> is the ONLY thing that differs on your own box — you still LOAD IT AND FOLLOW
> IT, step for step. Reaching for `thrum daemon restart`, `install.sh`, or
> `thrum backup` on your own box WITHOUT the per-box runbook loaded is the red
> flag; if you're doing that, you have already skipped this.

**Read both. Skipping the per-box runbook because you read this one — or because
the box is your OWN and you'll "just do it" — is the failure this split is
designed to prevent.**

---

### 0. THE ONE RULE THAT OUTRANKS EVERYTHING HERE

🔴 **NEVER ssh-deploy INTO a box. Each box's OWN coordinator drives its OWN
deploy, LOCALLY.** (Leon, standing, binding.)

A non-interactive ssh deploy silently drops node/pnpm from PATH, `make build-ui`
exits 127, **the deploy CONTINUES and reports success**, and lands an UNBUILT
SHA. The rule exists because the failure reports green.

**So your job in a fleet roll is DISPATCH AND GATE, never execution — except on
your own box, which you EXECUTE directly (not dispatch) but STILL under
`coordinator-deploying-a-box`, loaded and followed step for step (see the 🔴🔴
block above).** "Except on your own box" means you run the commands yourself
instead of dispatching them — it does NOT mean you improvise them from memory.
If you find yourself typing `ssh` and `make install` in the same command, stop —
and if you find yourself running `thrum daemon restart` / `install.sh` /
`thrum backup` on your own box without having loaded the per-box runbook, stop
there too.

⚠️ **CLARIFICATION — an `scp` of the signed pro-bundle zip into a box's
`~/.thrum/update/` is DISTRIBUTION OF AN ARTIFACT, not a remote build or
install, and does NOT violate this rule.** The rule forbids driving a box's
build/install/restart FROM another machine. Copying an already-built,
already-signed bundle to where that box's own coordinator will unzip and install
it FROM is the sanctioned distribution mechanism (see §4) — the box still does
its own unzip + `install.sh` + `thrum daemon restart`, locally, on its own
account. Never conflate "the bytes moved over the network" with "the box was
remote-driven."

---

### 1. THE ORDER — ONE fixed point, the rest composed per roll

🔴 **ONLY ONE THING IS A STANDING RULE: the designated canary (per
`.fleet.deploy_roster`) goes FIRST, ALONE.**

**EVERYTHING ELSE IS COMPOSED FRESH EACH TIME.** Recorded rolls disagree, and
they disagree deliberately.

🔴 **"COMPOSED FRESH" IS THE ORDER, NOT THE MEMBERSHIP.** Every box in the
roster MUST be rolled — the roster is the fleet. Compose the order per roll,
never the set. Deferring a box requires the owner's explicit sign-off for that
roll and a message to that box's coordinator that it is deferred.

⚠️ **DO NOT WRITE "THE BUILD BOX GOES LAST" INTO YOUR PLAN AS A RULE. IT IS A
DEFAULT, AND IT HAS BEEN DELIBERATELY OVERRIDDEN** — on 2026-07-28 the build box
went SECOND, because the owner needed the changes demonstrable at a meetup.
**The owner sets the order; this skill sequences whatever order is set.**

**Sensible default when nobody says otherwise:** the canary → the remaining
boxes (parallel where they share no state) → the build box last. **Reason to
keep the build box late:** it hosts the most agents and is the coordinator's own
box, so a bad build there costs you the ability to drive the recovery. **That is
a reason, not a law.**

Each box's coordinator and deploy target are defined in `.thrum/config.json`
under `.fleet.deploy_roster` — read them there; **never hardcode box identities
in this skill.**

🔑 **This skill runs from the fleet orchestrator's own box (the build box); the
roster lives in that box's config.** Resolve the box list and, for each box, its
`ssh_alias` / `coordinator` / `daemon_id` from that same `.fleet.deploy_roster`
entry:

```bash
jq -r '.fleet.deploy_roster | keys[] | select(startswith("_") | not)' .thrum/config.json
                                                                  # box list — underscore-prefixed
                                                                  # keys (e.g. `_note`) are roster
                                                                  # metadata, not boxes; filter them
jq '.fleet.deploy_roster["<box>"]' .thrum/config.json            # one box's entry
                                                                  # (ssh_alias, coordinator, daemon_id)
```

**Resolve coordinators by `daemon_id` JOIN, NEVER by name** — a name is a label
somebody chose; an agent named for a box has been found resident on a different
one. **The public-line box is EXCLUDED** (public 0.10.x line — see below).

⚠️ **At least one box's position in the roll is INCONSISTENT across rolls** —
sometimes explicitly "in order", sometimes trailing. **Ask; do not assume.** It
is always driven by its own coordinator, never dispatched around.

#### PREP-AND-HOLD — the mechanism that makes a staged roll safe

Dispatch several boxes at once to do **READ-ONLY prep only**: measure current
state, take the backup, `git pull`, capture BEFORE readings. Then:

> **"PREPARE AND HOLD. CANCEL NOTHING. DO NOT RESTART until I release you BY
> NAME."**

**Release one box at a time, by name.** This gets the slow prep done in parallel
without any box mutating itself before the canary has reported.

⚠️ **The public-line box's coordinator runs the PUBLIC 0.10.x line and is
EXCLUDED from 0.11 rolls.** Do not dispatch it.

🔴 **RESOLVE EVERY COORDINATOR FROM `thrum team` AT DISPATCH TIME, NOT FROM A
CACHED NAME.** A name is a label somebody chose; the authoritative method is a
`daemon_id` join — join the `daemon_id` from `.fleet.deploy_roster` against
`thrum team`'s live roster, never match on name. An agent's NAME and its
WORKTREE NAME are not its location — an agent named for a box has been found
resident on a different one, and obeying that name would have driven the
forbidden ssh path. ⚠️ **`thrum agent list --all` returns ZERO for agents that
certainly exist** — do not use it as your roster instrument, and do not read its
empty output as an absence.

---

### 2. THE PROMOTION GATE — what the canary must prove before anyone else goes

**Do not release stages 2-5 on "the canary finished." Release them on these,
each measured BY EFFECT on that box:**

- Installed binary `--version` **equals the pin exactly** — not "close", not
  "the branch".
- Daemon restarted with a **NEW PID**, and `daemon status` reports the pin. ⇒
  **MERGED == INSTALLED == RUNNING, all three agreeing.**
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
NUMBERS.** Measured instance: the canary came back green while another box had
**207 matured tombstones over live agents**. The canary proves the BUILD is
sound; it says nothing about any other box's state. **Do not let a green canary
talk a box out of taking its own BEFORE readings.**

⏱ **GIVE A CONVERGENCE CHECK LONG ENOUGH TO DISCRIMINATE.** A short wait cannot
tell "the fix works" from "it had already converged before you looked." One roll
made a full 3-minute wait a hard requirement after a too-short check produced an
uninterpretable pass. **Pick the interval from what the mechanism needs, not
from impatience.**

#### The go/no-go has never been a fixed number — get it from the owner

The go/no-go has never been a fixed number. **State YOUR bar explicitly before
promoting, so it can be challenged.** An unstated bar is indistinguishable from
no bar.

---

### 3. THE THREE PASSES — a "deploy" silently conflates three independent things

**Every box owes all three. They fail independently and a box can be current on
one and month-stale on another.**

| Pass                                                                                                                                                          | What it updates             | Who runs it                                                       |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------- | ----------------------------------------------------------------- |
| 1. install the pre-built, Developer-ID-signed pro-bundle via its own `install.sh`, **then** `thrum daemon restart`                                            | the **binary**              | the box's own coordinator                                         |
| 2. `thrum roles refresh` **then** `thrum roles deploy`                                                                                                        | **role preambles**          | the box's own coordinator                                         |
| 3. plugin refresh / reinstall (installs the BUNDLE's plugins — already made correct/complete by the plugin-bundle spine — rather than the box's own checkout) | **skills, commands, hooks** | 🔴 **the OPERATOR (Leon)** — a coordinator CANNOT self-serve this |

🔴 **THE BOX NEVER BUILDS OR SIGNS ITS OWN BINARY. IT INSTALLS A DELIVERED
ARTIFACT.** `make install` (build-from-local-checkout-and-sign) is retired from
the Pass-1 fleet/box binary-update path. The box's job is: obtain the pro-bundle
zip (see §4), unzip it, run its `install.sh`, restart the daemon. Nothing on the
box compiles Go or codesigns.

🔴 **PASS 2 ORDER IS LOAD-BEARING AND NOT OBVIOUS:** `refresh` FIRST (shipped
templates → role template), THEN `deploy` (role template → per-agent preamble).
**Running `deploy` alone re-renders agents from the OLD templates and reports
success.**

🔴 **RUN PASS 2 BETWEEN THE BUNDLE INSTALL AND THE DAEMON RESTART, ALWAYS:**
bundle `install.sh` → `thrum roles refresh` → `thrum roles deploy` → daemon
restart. Do the refresh+deploy the instant `install.sh` finishes and BEFORE
restarting the daemon, so the current preamble is already in place when any
agent next runs `thrum prime`, restarts, or checks its preamble.

🔴 **PASS 2 IS MANDATORY WHENEVER THE BUILD CHANGES
`internal/context/roleconfig/templates/` OR the compiled-in preamble.**
Preambles are RENDERED, not read live — installing a binary changes the source
and changes **nothing any agent reads**. There is **no staleness signal**: a box
serving a month-old render looks identical to a current one.

🔴 **PASS 3 REQUIRES A PLUGIN VERSION BUMP OR IT REACHES NOBODY.** The install
cache is keyed by version; an unchanged version means the installer skips the
re-copy and every skill edit stays invisible. Invoke the `plugin-update` skill;
do not improvise it.

#### 🔴 THE BOX'S **REPO CHECKOUT** MUST BE AT THE PIN BEFORE PASS 3 — THE BINARY BEING AT THE PIN IS NOT SUFFICIENT

The plugin source is a **LOCAL PATH**, so pass 3 reads the checkout, not the
binary — a box whose binary is at the pin can still install a plugin version one
bump behind if its working tree lags.

⚠️ **AND THE BOX'S OWN VERIFICATION CANNOT SEE IT.** It compared installed
skills against its own source, byte-for-byte, zero mismatches — and **both sides
were the stale version.** That proves the box is internally consistent WITH
ITSELF and is structurally incapable of detecting a stale source. Same shape as
render-fidelity-vs-doctrine-currency for preambles, except **pass 3 has no
equivalent of the ancestry check**, so nothing warns you.

🔴 **IT IS SELF-SEALING.** The cache is keyed by version, so at the stale
version the installer sees a match and **skips the re-copy permanently.**
Re-running the refresh does NOT fix it. Only bringing the checkout to the pin
and re-running does.

**⇒ Before handing a box to the operator for pass 3, verify BY EFFECT that all
FOUR manifests read the pin's version.** A partial bump is worse than none — the
runtimes then disagree about which build they are. And name the cache directory
**explicitly** when verifying; never `ls | tail -1`, because version directories
do not sort the way you expect (`…1.12` sorts BELOW `…1.3` and `…1.5`, and
several versions coexist).

**When reporting a deploy, name which passes you verified.** "Deployed" that
silently covers all three is how staleness hides.

---

### 4. PRE-FLIGHT — before dispatching box 1

0. 🔴 **FIRST ACTION, NON-OPTIONAL: `git fetch origin` then fast-forward-only
   pull the repo root to `origin/<branch>`.** If the pull is not
   fast-forwardable, STOP and surface it — never blind-merge in a shared tree.
   Do this before reading any other pre-flight state below; a stale checkout
   makes every subsequent check (trunk-green, pin, schema) a check against the
   wrong tree.
1. **Is trunk green?** Trunk-green is defined as `make gate` passing. A green
   lane, a green package, or a clean dual review is **not** that claim. ⚠️
   **Publishing a green without naming its invocation is the most common error
   here:** 0-of-6 and 0-of-15 are different claims in identical words.
2. **PIN AN EXACT SHA. NEVER "tip".** Tip moves under boxes mid-roll — two boxes
   told to deploy "tip" ship different code and both report success.
3. **Migrating or not?** Compare `CurrentVersion` at the pin against each box's
   running schema. A migrating roll pulls in the whole heavy-migration section
   of the per-box runbook; a non-migrating one does not.
4. **Forward-only:** each box's current SHA must be an ancestor of the pin. Pair
   the check with a control that MUST refuse (an invented SHA).
5. **Backup sizing** — the per-box runbook carries the formula. A percentage
   rule is not it, and a stale `current/` answers "are we protected?" with a
   wrong yes.
6. **Announce the pin and the order** to every coordinator before starting, so
   nobody deploys a different SHA.
7. 🔴 **BUILD ONCE, DISTRIBUTE THE SAME ZIP TO EVERY BOX.** The build box
   produces exactly ONE `make pro-bundle` at the pinned SHA. That single zip —
   never rebuilt per box — is what every box in the roll installs from. The
   staged roll therefore orchestrates three phases in order: **build once** (the
   build box, `make pro-bundle` at the pin) **→ distribute** (hand the same zip
   to each box's coordinator, via drop-folder or direct hand-off — see below)
   **→ each box installs from the delivered bundle** (§3 Pass 1). No box
   re-derives the artifact; every box's binary is byte-identical because it came
   from the same zip.
   - **Distribution mechanism 1 — drop-folder:** the built zip is placed where
     each box's own sync/fetch path picks it up into its local
     `~/.thrum/update/` for that box's coordinator to find and unzip.
   - **Distribution mechanism 2 — hand-off:** the coordinator running the roll
     hands the zip directly to a box's coordinator (e.g. `scp` into
     `~/.thrum/update/` — see §0's clarification: this is artifact distribution,
     not remote build/install).
   - Whichever mechanism is used, confirm the box installed from the SAME bundle
     (matching version/checksum) that was built at the pin — never a
     locally-reconstructed one.
   - 🔴 **NEVER pass `PRO_BUNDLE_VERSION=$(git describe)` when building the pro
     bundle — trust the Makefile default** (`v0.11.0-rc.1` as of this writing,
     re-check the current default before citing it). `git describe` falls back
     to the nearest ancestor tag when the exact commit isn't tagged, which can
     silently produce a WRONG version string — this is exactly how a stale
     `v0.10.6-rc.4` string previously shipped in a v0.11 build: the
     `v0.11.0-rc.1` tag was stranded on an unmerged release branch, so
     `git describe` fell back to an ancestor v0.10.6 tag.

---

### 5. DISPATCHING A BOX — what the message must carry

🔑 **Resolve the box's `ssh_alias` / `coordinator` / `daemon_id` from
`.fleet.deploy_roster` in `.thrum/config.json` before dispatching** (see §1) —
never from a remembered name. Join the coordinator by `daemon_id` against
`thrum team`'s live roster, NEVER by name.

Give each coordinator, explicitly:

- **The exact pinned SHA** and the instruction to build from a clean detached
  worktree at it.
- **An instruction to load `coordinator-deploying-a-box` and follow it** — not a
  summary of it. ⚠️ **A summary you wrote reads as complete precisely because
  you wrote it**, and its omissions are silent.
- **Which passes it owes** (1 and 2; pass 3 is the operator's).
- **Its own BEFORE readings** — `sync_checkpoints`, schema, PID.
- **That acceptance is BY EFFECT, never by exit code.**
- **That it must report which passes it verified**, separately.

---

### 6. AFTER THE LAST BOX

- 🔴 **ROSTER COMPLETENESS GATE — first.** Re-enumerate the roster from config,
  not from propagated deploy-state (a box with a wedged sync never propagates
  its row). Confirm every box is rolled on the pin or owner-deferred with its
  coordinator notified. Name each box and its disposition in the roll-complete
  report.
- **Agent phase reconciliation, per box.** A restart leaves recorded `phase`
  disagreeing with reality — live agents read `stale`, dead ones can read
  `active`. Phase is local state and does not cross the peer boundary, so every
  box runs it against its own daemon.
- **Restart the orchestrators and long-lived agents** so they pick up the new
  preambles and skills. 🔴 **Agents adopt a new preamble ON THEIR NEXT RESTART,
  not immediately** — a live agent keeps behaving per the identity it was born
  with. Track adoption by session birth time, never file mtime.
- **Pre-release test suite — CHECK WHETHER IT IS OWED; do not assume it is.** It
  is documented as a gate for cutting an RC/release, and a remote box runs it
  after fleet deploys by standing arrangement. ⚠️ **A search of past rolls did
  NOT establish it as a mandatory step for a routine binary/preamble/plugin
  roll.** Read the run index: if its newest entry predates this deploy, the
  suite has not run against what is now deployed — then decide, with the owner,
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

### 7. HOLDS

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

### Red flags — STOP

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
