---
name: third-party-audit-opencode
description: "Use when you want an INDEPENDENT audit of a claim, finding, defect, or review verdict - a second opinion from outside the Claude family, a third-party verification, an adversarial check on a P0/P1 filing, or a cheap way to re-verify something before acting on it. Launches a disposable opencode agent in its own worktree, has it write a findings artifact, preserves that artifact to dev-docs, then tears down the agent, its state directory, and the worktree. Also use when review token spend is a concern - the audit runs on a non-Anthropic model and costs cents."
---

# Third-Party Audit via opencode

Launch a disposable **opencode** agent to audit one claim, preserve its artifact,
then destroy every trace of the agent.

## When to use

- A P0/P1 filing needs independent confirmation before you act on it.
- A review verdict looks right and you want a second opinion that shares none of
  your framing.
- You want to spend cents instead of Claude tokens on a verification pass.
- **Latency does not matter.** An audit that takes 10 minutes is free — nobody is
  waiting on it. This is what makes a slower, cheaper runtime acceptable here,
  and it is why opencode (which supports local/Ollama inference) fits.

**Independence is the point.** opencode runs a non-Anthropic model (GLM, or
whatever the box configures). It has no auto-prime hook, so it inherits none of
your context and none of your framing. That is a feature: give it the claim, not
your conclusion.

**Don't use for:** implementation, anything needing write access to real code, or
work that must survive across sessions. This agent is disposable by design.

## The full cycle

### 1. Create worktree + agent + launch, in ONE command

```bash
thrum worktree create oc-audit-<topic> \
  --base thrum-agents \
  --name auditor_oc_<topic> \
  --role researcher \
  --module thrum \
  --runtime opencode \
  --mode ephemeral \
  --identity ephemeral \
  --intent "Third-party audit of <claim>"
```

🔴 **Do NOT hand-roll this with `git worktree add`.** A raw worktree has no
`.thrum/redirect` and `thrum tmux create` will fail provisioning against it.
`thrum worktree create` wires the redirect, registers the agent, and launches in
one step.

### 2. Send the task — BY AGENT NAME, and NOT at cold start

```bash
thrum tmux send auditor_oc_<topic> "$TASK"
```

🔴 **`create`/`launch` take the SESSION name; `send`/`capture` take the AGENT
name.** All four document the argument as `<name>`. Using the session name on
`send` fails with `rpcrouter: local agent not found`, and on `capture` it fails
outright.

🔴 **The first send after launch is SWALLOWED.** opencode runs its own startup
(and, on a thrum repo, a prime attempt) and the racing prompt is lost — the agent
comes back reporting *"first boot, no dispatched task yet"* and sits idle. **Wait
until the pane is idle, then send.** Always confirm the task landed before
walking away; a lost prompt looks exactly like a slow agent.

### 3. Expect a cold-start identity error — it is benign

```
failed to resolve agent role: identity file missing for auditor_oc_<topic>
(resolved to coordinator_main instead — refusing to adopt a different agent's identity)
```

The identity file is written a beat after the session starts. Any thrum command
in that window fails. **It refuses to adopt the neighbouring identity rather than
silently impersonating — correct behaviour.** It self-resolves; re-run the
command.

### 4. Permission modals

opencode gates directory access. Two land in practice:

| Prompt | Why | Handling |
|---|---|---|
| `/Users/<you>/dev/.../thrum/*` | `.thrum/redirect` points at the main repo, so the thrum CLI genuinely needs it | Approve |
| `/private/tmp/*` — "Access external directory" | the artifact path is outside the worktree | Approve, or pre-authorize |

**"Allow always" is a TWO-STEP modal**: select the option, then a second
`Confirm / Cancel` appears. One Enter is not enough.

⚠️ **UNVERIFIED — pre-authorizing via config.** The repo carries a git-tracked
`opencode.json` (`$schema: https://opencode.ai/config.json`), which is the
natural place to grant `/private/tmp` up front so the run never stalls. **The
exact permission key shape was NOT verified** — no schema was resolvable locally
and greps for a `permission` key came back empty (control fired). Until someone
confirms the schema, either approve the modal once by hand, or point the artifact
**inside the worktree** — but then you MUST copy it out before teardown.

🔴 **THIS IS THE ONE THING BLOCKING UNATTENDED AUDITS — `thrum-jymdg` (P1).**
A stalled agent and a slow agent look identical from outside, so a modal mid-run
means an unwatched audit simply never finishes. The fix is a
`thrum worktree create --permissions <file.json>` that takes ONE runtime-agnostic
spec and writes whatever the target runtime needs (`.claude/settings.local.json`
for claude, `opencode.json` for opencode, …). **Until that lands, treat every
opencode audit as needing a human to check the pane at least once.**

### 4b. The auditor permission profile

What an auditor actually needs (Leon, 2026-07-31):

| | scope |
|---|---|
| **Read** | **anywhere** — not scoped to the worktree |
| **Write** | the temp dir it stages in, and the final result location. Nothing else. |
| **Shell** | ordinary analysis kit — `sed`, `awk`, `grep`, `find` |

🔴 **Read-anywhere is a CORRECTNESS requirement, not a convenience.** The audit
that motivated this skill had to reach `$HOME/.claude/projects` — outside the
repo and outside the worktree — to establish that transcript resolution is
Claude-specific. **A worktree-scoped read fence would have produced a wrong
verdict rather than a blocked one, and it would have looked clean.**

🔴 **`sed`/`awk`/`perl` are read tools until they are not.** `sed -i` and
`perl -i` mutate in place, so granting the command grants the in-place form.
**The permission grant is therefore NOT the only fence** — the read-only-git and
no-repo-mutation rules in the task prompt remain load-bearing. Never rely on the
permission layer alone to keep an auditor read-only.

### 5. The task prompt

Non-negotiable elements:

- **The claim, marked UNPROVEN.** Ask for CONFIRM / REFUTE / PARTIALLY-CONFIRMED.
  Never state your own conclusion — you are buying independence.
- **A read-only git fence**, plus "work ONLY in `<worktree>`, NEVER in `<main repo>`".
- **The artifact path, written INCREMENTALLY**, "the file is the deliverable, your
  reply is only a summary."
- **Method rules** — these are what make the output worth reading:
  - every claim needs a `file:line` actually read, never cited from memory
  - every zero-hit search needs a **control** with a key known to match
  - read the hits, don't count them
  - label each finding **MEASURED** or **INFERRED**
  - an honest NOT ESTABLISHED beats a confident guess
- A closing `thrum send ... --to @<you>` so it reports completion.

Required artifact structure: Verdict · What I audited (files + SHAs) · Evidence
(`file:line`, MEASURED vs INFERRED) · Controls run (**including zero-result
controls**) · What I could NOT establish · Recommendation.

### 6. PRESERVE — before destroying anything

```bash
DEST=dev-docs/findings/$(date +%Y-%m-%d)-oc-audit-<topic>.md
cp /private/tmp/oc-audit-<topic>.md "$DEST"
# verify byte-identical BEFORE teardown
[ "$(shasum -a256 < /private/tmp/oc-audit-<topic>.md | cut -c1-16)" \
  = "$(head -c $(wc -c < /private/tmp/oc-audit-<topic>.md) "$DEST" | shasum -a256 | cut -c1-16)" ] \
  || { echo "MISMATCH — DO NOT TEAR DOWN"; exit 1; }
git add "$DEST" && git commit -m "docs(findings): third-party opencode audit of <topic>"
```

**`dev-docs/findings/`, dated filename.** Append a provenance footer naming the
agent, runtime, model, and the repo HEAD audited.

🔴 **Verify the copy before you destroy the source.** Teardown is irreversible and
the artifact is the only thing of value the run produced.

### 7. TEARDOWN — in this order

```bash
thrum tmux kill auditor_oc_<topic>                    # 1. session first
thrum tmux capture auditor_oc_<topic> --lines 2 >/dev/null 2>&1 \
  && echo "STILL ALIVE" || echo "gone"                # verify by direct observation
rm -r .thrum/agents/auditor_oc_<topic>                # 2. targeted agent state
git worktree remove --force <worktree>                # 3. force: dirty is expected
git branch -D feature/oc-audit-<topic>
git worktree prune
```

🔴 **`rm -r`, never `rm -rf`.**

🔴 **NEVER `thrum agent cleanup --force`** to tidy the leftover DB row. Its
"orphans" include live agents fleet-wide — 455 and 513 on two measured boxes.
**An orphan DB row after a clean reap is BENIGN. Leave it.**

**`--force` on the worktree is correct here.** An audit worktree accumulates
scaffolding (`AGENTS.md` rewrite, hooks, `.thrum` skeleton) and nothing in it is
needed — the artifact is already preserved and committed. This is the one place
where forcing past dirty state is right, *because step 6 already verified the only
thing worth keeping*.

**Why remove `.thrum/agents/<name>/`:** every launch creates one, and one-shot
auditors would otherwise accumulate hundreds of directories for agents that will
never run again. Removing it is cleanup, not data loss — provided step 6 ran.

## Verify it actually worked

- artifact exists in `dev-docs/findings/` **and** is git-tracked
- `thrum team | grep <agent>` returns nothing
- worktree directory is gone
- `.thrum/agents/<agent>/` is gone

## Cost

One real audit: **~$0.40, ~90K tokens, about 8 minutes** including two permission
stalls. It returned a 15.9KB artifact with six controls and independently
confirmed a P0 — plus a nuance the original filing had missed.
