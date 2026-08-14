---
name: implementer-orchestrating-execution
description: "Use when starting execution of a scoped implementation task — about to implement, ready to write code, executing a bd task. Loads the orchestration procedure — dispatch research, implementation, and verification to sub-agents and synthesize their output instead of doing the legwork inline."
# source: claude-plugin/skills/implementer-orchestrating-execution/SKILL.md
# generated-by: scripts/sync-skills.sh
---


## Implementer: Orchestrating Execution

You implement by **orchestrating sub-agents**, not by doing research, edits, and
verification yourself. Your Opus context is for judgment — synthesizing
research, targeting edits, judging verification against the plan. The legwork
goes to cheaper sub-agents. This skill is the procedure; invoke it at the start
of executing any scoped task.

### Step 0 — Scoping gate (before you dispatch anything)

Classify the WHOLE task first:

- **Tiny + fully-known** — the entire task is a bounded change (≤ ~15 lines, ≤ 2
  files) whose targets you already know, where any file-reading is purely to
  **locate** an insertion point, not to **understand** unknown structure. Do it
  inline as a correction-class edit; skip steps 1-4. This is the documented path
  for atomic tiny tasks (a known rename-everywhere, a single-symbol change).
- **Anything larger or not-fully-known** — orchestrate (steps 1-4).

The size bound (~15 lines / 2 files) is the project default; a project-local
`implementer-rule-` may tune it.

### Subagent model selection

> **Model tiers:** pass an explicit `model:` on every dispatch — `sonnet`
> (low effort) mechanical, `sonnet` (medium effort) judgment, Opus only on
> operator-ask or a skill step that names it. See the
> `choosing-subagent-models` skill for the full policy.

### Step 1 — Dispatch research

Spawn `Explore` or general-purpose sub-agent(s) to map the target files,
interfaces, and call sites and return a written report. You read the report —
you do not read the code into your own context. Label the dispatch
`description="research: <what>"`.

### Step 2 — Target and dispatch implementation

From the report, decide exactly what changes where, then dispatch
general-purpose sub-agent(s) to make the edits. Give each the bd task ID, the
exact files, the acceptance criteria, and the relevant slice of the report.
Model: `sonnet`; use `sonnet` (low effort) for purely mechanical edits
(find/replace, rename). Label `description="implement: <what>"`. Parallelize independent
edit-targets; serialize edits to shared files.

### Step 3 — Dispatch verification

Spawn a `sonnet` verifier against **the plan the implementation sub-agent was
given** — does the diff satisfy the acceptance criteria and honor the plan?
Label `description="verify: <what>"`. (For the full code-quality +
spec-compliance review at DONE, `implementer-tdd-and-quality` and the
coordinator's review cycle still apply — this per-task verify is the lightweight
in-loop check.)

### Step 4 — Synthesize and correct

Read the verifier's report. If a sub-agent's edit is wrong, you may **correct it
inline** — that is a legitimate exception, not a return to inline working. If
the work is sound, proceed to the next task or to DONE.

### The inline-vs-dispatch boundary (the rule that keeps you honest)

> **Default verb is dispatch.** Inline editing is permitted in exactly three
> cases:
>
> 1. **Correcting** a sub-agent's edit that came back wrong.
> 2. An edit whose change you **already fully know**, where any reading is
>    purely to **locate** the insertion point (not to understand), AND the
>    change is bounded (≤ ~15 lines, ≤ 2 files).
> 3. The Step-0 scoping-gate case: the whole task meets the bound in (2).
>
> **The moment you must read code to _understand what to change_ — reading to
> discover unknown structure, not to find a known target — that is a research
> dispatch, not an inline edit.**

The test is objective: _did I have to explore to do this?_ "I opened three files
to figure out the change" is exploratory and cannot be relabeled "a single edit
I already knew." A known one-liner that needs one `grep` to find its line stays
inline. This is NOT the old "Sequential (direct work)" escape hatch — that keyed
on subjective "complexity"; this keys on an objective read-purpose test plus a
hard size bound.

### Model tiers (always pass `model:` explicitly)

| Dispatch           | Model                                              |
| ------------------ | -------------------------------------------------- |
| research / explore | `sonnet` (or the `Explore` agent type)             |
| implementation     | `sonnet`; `sonnet` (low effort) for purely mechanical edits |
| verification       | `sonnet`                                           |

Use the bare `sonnet` alias (resolves to the current Sonnet); do not hard-pin a
version id. Never let a sub-agent inherit the parent (Opus) model.

### Sub-agent label convention (required)

Every dispatch's `description` starts with one of: `research:`, `implement:`,
`verify:`. This is load-bearing for the evaluation harness, which classifies
delegation shape from these labels.

### Anti-patterns

❌ **Inline Worker** — does the research and edits itself instead of
dispatching. Your Opus context is for orchestration judgment, not hand-typing
edits a Sonnet sub-agent should make.

❌ **Over-orchestrator** — dispatches a sub-agent for a known one-line change,
paying more in prompt-composition than the edit costs. The Step-0 scoping gate
and the size bound exist to prevent this; trivia stays inline.

❌ **Unlabelled dispatch** — omits the `research:`/`implement:`/`verify:`
prefix, blinding the evaluation harness.

### Project-specific rules (already loaded)

Project-local rules of kind `agent_rule` at `--scope role` were loaded at
session start by your preamble (see your role template's Memory model block). If
a project-local rule conflicts with this skill, the project-local rule wins;
surface the conflict so the user can decide. Capture new rules mid-session via
the `implementer-maintaining-memory` skill — it references the
`memory-write-discipline` common for the canonical `thrum memory create` shape.
