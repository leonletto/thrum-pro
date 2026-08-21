---
name: choosing-subagent-models
description: "Use when about to launch, spawn, or dispatch a subagent, sub-agent, or parallel agent - including the Agent/Task tool, an Explore agent, fanning out research, or any time you choose a model for a subagent. ALSO fires on every REVIEW dispatch - dispatching a reviewer, a code review, a code-quality review, a spec-compliance review, a dual review, a verify-against-plan or verify-against-source pass, or a merge-gate sub-agent. Reviewer dispatch is the HIGHEST-STAKES judgment-tier spawn and is the one most often done from memory. Enforces the role-based model tiering (opus-low orchestrators, sonnet-medium implementers and reviewers, sonnet-low sub-agents) and cheap parallel fan-out."
---

# Choosing Subagent Models

## Audit, review, or question? Require a file.

**Every subagent you dispatch for an answer must WRITE ITS RESULT TO A FILE
(e.g. `/tmp/<task>.md`); its reply to you is only a summary. Put this
in the prompt.**

## Pin every spawn. The floor depends on the agent's ROLE.

Every subagent you spawn MUST pass an explicit `model:` (plus effort where the
runtime supports it). Omitting it runs the subagent on YOUR model (Opus) — the
single biggest avoidable cost leak in agent work.

**Haiku is banned entirely.** There is no
mechanical-task carve-out anymore — lint runs, grep-and-collect, file maps,
config edits, and all other "simple" work now dispatch at sonnet-low, not Haiku.
Never select Haiku on own judgment — use sonnet-low instead.

### Agent tiers

Effort tier governs whether an agent does the hard thing or the expedient thing.
These are the tiers now:

| Role | Model / Effort |
| ---------------------------- | ------------------- |
| **Orchestrator** | **`opus` / low** |
| **Implementer** | **`sonnet` / medium** |
| **Verifier / reviewer** | **`sonnet` / medium** |
| **Sub-agent** (investigation, grep, mechanical) | **`sonnet` / low** |

- **`model: "sonnet"` @ low effort — sub-agents ONLY.** Investigation,
  grep-and-collect, file maps, lint runs, mechanical tasks. This is the floor for
  a *sub-agent*, NOT for an implementer or a reviewer.
- **`model: "sonnet"` @ MEDIUM effort — implementers, verifiers, reviewers.**
  Not low. A reviewer on low effort is a rubber stamp with extra steps, and
  rubber-stamped reviews are how a merge gate that ran zero tests survived six
  sessions.
- **`model: "opus"` @ low — orchestrators.** Not selectable for sub-agents —
  set by the operator on the agent's runtime-config.
- **`model: "opus"` — NOT your call.** Allowed only when (a) the operator
  explicitly asked for a deep review or prose review in this task, or (b) a
  skill you are running prescribes Opus for the specific step you are currently
  executing — NOT for every spawn under that skill. "This research is hard /
  important" is NOT a justification — hard investigation is exactly what Sonnet
  is for.

## Worked examples — LITERAL ARGUMENTS, AND EFFORT IS TOOL-DEPENDENT

**Pass `model` AND `effort` on every spawn, whichever mechanism you use.** Syntax
per mechanism — re-check the schema in front of you rather than restating from
memory, because it can change:

| Mechanism | `model` | `effort` |
|---|---|---|
| **Agent tool** | ✅ settable | ✅ **settable — pass it** |
| **Workflow `agent()`** (opts: label, phase, schema, model, effort, isolation, agentType) | ✅ settable | ✅ settable |
| **Agent DEFINITION** (`.claude/agents/*.md` / plugin `agents/*.md` frontmatter) | ✅ | ✅ — sets the default for that agent type |

**Agent tool — pass `effort` as a literal argument, alongside `model`.**

```python
Agent(subagent_type="general-purpose", model="sonnet", effort="low",
      description="Code-quality review of <branch>",
      prompt="...")
```

An agent definition can also carry a default:

```yaml
# claude-plugin/agents/message-listener.md
name: message-listener
model: sonnet
effort: low
```

**Workflow `agent()` — effort IS a literal argument. Pass it.**

```javascript
agent(prompt, { model: "sonnet", effort: "medium" })          // reviewer / implementer
agent(prompt, { model: "sonnet", effort: "low" })             // mechanical sub-agent
```

**THE DIRECTIVE, imperative and not a comment: REVIEWERS RUN SONNET AT MEDIUM
EFFORT.** Pass `effort: "medium"` literally — under Workflow AND under the Agent
tool. Never dispatch a reviewer "from memory".

**AND VERIFY, DO NOT ASSERT:** any claim about what a tool does or does not expose
must be checked against the schema in front of you.

Never select Opus or Haiku on own judgment — use Sonnet, at the floor of
sonnet-low.

## Fleet model-tiering by runtime/role

Different runtimes and roles pin different tiers. Claude tiers are canonical —
see the Agent tiers table above (orchestrator/implementer/reviewer/sub-agent),
plus brainstormer → opus-medium and brainstormer's own subagents → sonnet-low
(except reviewers → sonnet-medium). Other runtimes:

| Runtime      | Role                         | Model / effort                                      |
| ------------ | ---------------------------- | --------------------------------------------------- |
| OpenCode     | default                      | GLM-5.2 (fine as-is)                                |
| Codex        | orchestrator / reviewer      | gpt-5.5-medium                                      |
| Codex        | implementer                  | gpt-5.5-low                                         |
| Cursor-agent | default                      | composer-2.5 (fine as-is)                           |

## Pin every spawn explicitly — the floor depends on the ROLE, not the depth

Every orchestrator MUST pass an explicit `model:` and `effort:` on EVERY subagent
it spawns. An unspecified subagent SILENTLY INHERITS THE PARENT'S MODEL — so an
Opus orchestrator that forgets the pin just spent Opus tokens on a grep.

**The floor is set by what the agent DOES, not by how deep it sits** — see the
Agent tiers table above. This applies recursively: an implementer spawning its
own helpers pins them by THEIR role, not by copying its own tier down.

The check before every spawn: what is this agent's ROLE? Reviewer or implementer?
sonnet-medium. Pure investigation or mechanical work? sonnet-low. Never leave it
unspecified.

## Paste the constraint block into the child prompt — the pin is not enough

**A model pin is an ARGUMENT and travels by itself. A behavioural constraint is
PROSE and reaches the child only if you paste it.** Constrain every level: a rule
that stops at depth 1 is absent where the work happens.

**Paste verbatim, including the last line:**

```text
=== CONSTRAINTS — apply to you and anything YOU dispatch (including this line) ===
- Work SYNCHRONOUSLY. Tests in the FOREGROUND with a bounded `-timeout`.
- NO POLL LOOPS. Never `until <check>; do sleep N; done`, never
  `while kill -0 $(cat pid)`, never `$( )` in a loop condition — even when a
  tool's own guidance suggests it. It trips a permission modal, and A FROZEN
  PANE EMITS NOTHING, so nobody can tell you are blocked. If you must background
  work, wait for the completion notification.
- Every sub-agent YOU spawn gets an explicit `model:` — sonnet (low mechanical,
  medium judgment). HAIKU IS BANNED. Opus is never yours.
- READ-ONLY git outside your own worktree. NEVER `checkout`/`reset`/`restore`/
  `stash`/`clean` in ANY directory — `stash` is one shared stack across all
  worktrees and the shared tree holds live agents' uncommitted state.
- Pair every zero/empty result with a control that MUST return non-zero.
```

⚠️ Never let a child take **"don't ask again"** on a modal — it removes the only
signal this condition produces.

### Cheap subagents → fan out, don't pile up

Because sonnet-low subagents are cheap, prefer MANY small parallel subagents
over one subagent handed a pile of tasks. When a research or investigation task
has independent parts, partition it and dispatch the parts in parallel (use the
`efficient-multi-agent-research` skill) — smaller scopes are cheaper, run
concurrently (faster), and keep each subagent's context tight. One subagent
given ten tasks is the anti-pattern.

## ⚠️ The pin-verification command LIES — do not trust it

`thrum agent runtime-config get <agent>` reports the **configured** value, not the
**resolved** one.

An implementer ran Opus 4.8 while both the launch flag (`--model sonnet`) and
`runtime-config get` confirmed sonnet — the check that exists to catch a bad pin
is itself a false green.

This is the same defect class as every other surface that reports a value it never
observed (`go test -count=0` reporting PASS while running zero tests; a health RPC
reporting green off a path that cannot fail; `make ci` swallowing a critical CVE with
a warning).

**So: after launching an agent, verify with `thrum tmux capture --format=annotated`
(or `--format=json` for scripting).** It parses the footer server-side into
NBSP-free fields — no positional-window guessing, no NBSP grep trap, and the
header states `ok`/`FAILED` explicitly instead of leaving you to infer a failure
from empty stdout:

```bash
thrum tmux capture <agent-name> --format=annotated --lines 12
# ━━━ CAPTURE ok · agent=<name> · runtime=claude · lines=35 ━━━
# <pane content, verbatim>
# ─── FOOTER (parsed, NBSP-normalized) ───
# Model: Sonnet 5 | Ctx: 478.3k | Ctx Used: 48.0%
# ━━━ END CAPTURE ━━━
```

The FOOTER block is simply omitted when no footer resolved — never an empty or
garbage line to misread. For scripting, `--format=json` gives the same data as a
typed document: `{"agent","runtime","ok","line_count","footer":{"model","ctx","ctx_used_pct"}|null,"lines":[...]["error"]}`
(`footer` is `null` when none resolved).

```bash
thrum tmux capture <agent-name> --format=json | python3 -c \
  'import json,sys; b=json.load(sys.stdin); print(b["footer"]["model"] if b["footer"] else "NO FOOTER")'
```

Still check the exit status before trusting either form — a FAILED capture exits
nonzero and the annotated header says `FAILED`, but don't discard that signal by
piping straight into something that only inspects stdout.

That is the runtime reporting its RESOLVED config, and it is the only check that has
ever produced a true negative on this defect. If it disagrees with the pin, report it —
those instances are a real bug and we want them counted.

🔴 **DO NOT substitute "ask the agent what model it is running."** That is a model
introspecting on its own identity — a categorically weaker instrument.
**A check built on self-report would be a THIRD instrument that cannot fail in
the direction we need**, replacing a false green with a confident one. **SETTLED — and the reason is
categorical, not a reliability judgement: self-report is the WRONG SHAPE for the
question.** The agent sees exactly ONE value (its resolved model, injected into its own
system prompt); "does the pin disagree with the resolution?" is a question about a
RELATION between TWO values. **It cannot report a mismatch however honest it is — the
disagreement is not representable in what it can observe.** No prompting rescues that.
Only an outside comparator holding BOTH the pin AND the resolved status line answers it.
⚠️ A self-report can look right while reading back an injected assertion, so it
inherits whatever the injection got right or wrong. **A correct answer there is
survivorship, not validation.**

**Fallback — only if `--format` is unavailable (older binary):** read the bare
exit status before stdout, then grep the raw pane by position, never by content
(the raw footer's separators are U+00A0 non-breaking spaces, so `grep "Model: "`
with a trailing space returns ZERO on a pane that plainly displays a model):

```bash
out=$(thrum tmux capture <agent-name> --lines 12); rc=$?   # bare, NOT through a pipe
[ $rc -ne 0 ] && echo "CAPTURE FAILED — this is NOT an empty pane" && exit 1
printf '%s\n' "$out" | grep -v 'tmux capture' | grep 'Model:' | tail -1
```

🔴 **PASS `--model` / `--effort` TO BOTH `tmux create` AND `tmux launch`.** They are
separate cobra commands with separate flags, and **`launch` is what resolves the model**
(`resolveLaunchSpec` runs in `HandleLaunch`, never in create). `create` persists the pin
asynchronously, so a create-only pin can lose the race and leave the CLI value empty at
launch **by construction**.

⚠️ **And any FIX here must be verified with a pin the role default would NOT produce.**
An implementer pinned to sonnet, with an implementer role-default of sonnet, comes up
correct whether or not the pin landed — so "pin sonnet, confirm sonnet" passes whether
or not the fix works.
