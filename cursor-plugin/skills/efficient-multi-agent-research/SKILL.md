---
name: efficient-multi-agent-research
description: "Use when investigating, auditing, or reviewing more than 6 items across a codebase - function call sites, pattern usage, file reviews, or any research task with partitionable items that would pollute the main agent's context if read directly"
---

# Efficient Multi-Agent Research

## Overview

When investigating N items (N > 6), reading everything into the main agent's
context pollutes it and degrades decision-making. Instead, partition the work
across parallel sub-agents that write findings to disk, then consolidate into a
single report.

**Core principle:** The coordinator decides, sub-agents investigate. Keep
investigation results out of the main context until consolidated.

**REQUIRED BACKGROUND:** Read superpowers:dispatching-parallel-agents before
using this skill. That skill
covers general parallel dispatch. This skill extends it with a specific research
workflow: partition, investigate to disk, consolidate, then decide.

## When to Use

**Use when:**

- Investigating many call sites of a function (N > 6)
- Auditing usage of a pattern across a codebase
- Reviewing multiple files for a common issue
- Any research task with partitionable items

**Don't use when:**

- Simple searches (just use Grep/Glob)
- Tasks with 6 or fewer items (single agent is fine)
- Deeply interdependent items that can't be partitioned cleanly

## Core Pattern

### Partition > Parallel Investigate > Consolidate > Decide

1. **Create output directory:** `mkdir -p dev-docs/<topic>/` — if re-running,
   archive previous `findings_*.md` to a subdirectory (e.g., `run-01/`) before
   starting so the consolidation glob only picks up current results.

2. **Launch investigation agents** — all in one message, all
   `run_in_background=true`:

   ```text
   Agent(run_in_background=true,
     prompt="Investigate items A-D. Write to dev-docs/<topic>/findings_1.md
     using table schema: [columns]. Flag uncertainties.")

   Agent(run_in_background=true,
     prompt="Investigate items E-H. Write to dev-docs/<topic>/findings_2.md ...")
   ```

   Specify exact table columns and consistent formatting in every prompt.

   **Every prompt MUST scope the read-only restriction around its own output
   file, in the same breath:** `READ-ONLY EVERYWHERE EXCEPT YOUR OUTPUT FILE —
   do not modify source, tests, config, git state, or the issue tracker; you
   MUST write exactly dev-docs/<topic>/findings_N.md, and that write is
   expected and authorized.` Omitting the exception is the most common cause of
   a fan-out that returns nothing — see Common Mistakes.

3. **Wait** for all background agents to complete.

4. **Launch consolidation agent** — always request these four elements:

   ```text
   Agent(prompt="Read all dev-docs/<topic>/findings_*.md.
     Create consolidated_report.md with:
     1. Unified table merging all agent tables
     2. Cross-cutting patterns across findings
     3. Summary statistics (e.g., '12/17 need fixes')
     4. Prioritized recommendations")
   ```

5. **Review only `consolidated_report.md`** — never read individual findings
   files into the main context.

## Quick Reference

| Aspect        | Guidance                                                  |
| ------------- | --------------------------------------------------------- |
| Group size    | 4-5 items per agent                                       |
| Agent count   | Typically 3-5                                             |
| Agent mode    | Always `run_in_background=true`                           |
| Output        | `dev-docs/<topic>/findings_N.md` per agent                |
| Consolidation | Always a dedicated agent writing `consolidated_report.md` |

## Model tiers for this skill

See the `choosing-subagent-models` skill for the full policy. Applied to this
skill's fan-out:

- **Level 1 — researchers / gatherers:** scope each one DOWN to a narrow slice
  so you can run MANY in parallel. Use `model: "sonnet"` (low effort) —
  bounded gather-and-report. Smaller scope = cheaper, concurrent (faster),
  tighter per-agent context.
- **Level 2 / Level 3 — summarizers / synthesizers:** use `model: "sonnet"` —
  aggregating and reconciling Level-1 outputs is judgment work.

Prefer many narrow sonnet-low gatherers over one broad subagent. This is the cheap,
fast default — equivalent parallelism at a fraction of the token cost.

## Common Mistakes

**Skipping consolidation** - Reading 4 separate findings files into main context
defeats the entire purpose. Always launch a consolidation agent.

**Groups too large** - More than 5 items per agent gives diminishing returns.
Partition further.

**Using foreground agents** - Blocks the main agent and loses parallelism.
Always use `run_in_background=true`.

**Reading intermediate files** - The main agent should only read the
consolidated report, never individual findings files.

**Not specifying output format** - Agents produce inconsistent formats that are
hard to consolidate. Specify table columns in every prompt.

**Not specifying output file paths** - Agents may write to the working directory
or not at all. Always include the exact output path in every prompt.

**Have sub-agents write their findings file with a Bash heredoc, not the Write
tool.** The Write tool refuses subagent report files ("Subagents should return
findings as text, not write report files") regardless of how the brief is worded.
The filesystem is writable; the tool is what refuses.

**Put this in every prompt:**

```text
READ-ONLY EVERYWHERE EXCEPT YOUR OUTPUT FILE.
Do not modify source, tests, config, git state, or the issue tracker.
You MUST write your findings to exactly: dev-docs/<topic>/findings_N.md
Write it with a Bash heredoc (cat > <path> <<'EOF' ... EOF), NOT the Write tool —
Write refuses report files. That single write is expected and authorized.
```

If an agent still returns text instead of a file, persist it yourself verbatim
and mark the provenance in the file — do not paraphrase.

Put the exception in the SAME breath as the restriction, not in a later
paragraph. An agent that reads "read-only" first and the write instruction
forty lines later has already formed its posture.

## Example: Auditing 17 Call Sites

**Task:** Investigate 17 call sites of `resolveLocalAgentID()`

**Partition:** 4 agents (4-5 call sites each, grouped by source file)

**Table schema specified in every prompt:**

| Line | Command | How ID Is Used | Behavior for 0/1/multiple | Needs Fix? |
| ---- | ------- | -------------- | ------------------------- | ---------- |

**Result:** Main context stayed clean. Consolidation agent identified
cross-cutting pattern: "8/17 calls use identity for message filtering." Final
report provided prioritized recommendations.

## Variations

| Variant       | When                                   | How                                                                       |
| ------------- | -------------------------------------- | ------------------------------------------------------------------------- |
| **Quick**     | Items are independent, output is small | Lightweight consolidation: brief merged summary instead of full synthesis |
| **Deep**      | Very large N (50+)                     | Multi-level: 8 agents > 2 meta-agents > 1 final report                    |
| **Iterative** | Need to refine criteria                | Run first pass, update prompts based on patterns, re-run                  |

## See Also

- `adversarial-critique` — decision-shaped sister pattern. Use this skill when
  investigating _what's there_ across N>6 items; use `adversarial-critique` when
  deciding _which option wins_ among 2-3 design forks.
