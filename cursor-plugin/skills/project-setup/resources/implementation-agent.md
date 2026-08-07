# Implementation Agent Template

## Purpose

Guide an agent through implementing an epic's tasks in a designated worktree.
Supports both cold-start and resume scenarios. The agent works through beads
tasks in order, runs quality gates, and pushes completed work.

## CRITICAL: Prompt Generation Rules

<!-- STRIP THIS SECTION — it is for the coordinator filling the template, not
     for the implementation agent. project-setup must remove it along with
     ## Purpose and ## Inputs Required. -->

When filling this template to create an implementation prompt:

1. **Every section is mandatory unless explicitly marked optional.** Do not
   summarize, paraphrase, or abbreviate sections — copy them verbatim and fill
   in the `{{PLACEHOLDERS}}`. Sections marked `IMPORTANT` must appear in the
   output prompt word-for-word.
2. **The Sub-Agent Strategy section (below) must be included in full.** It
   contains the agent selection table, parallelization criteria, and verifier
   pattern. These are operational directives, not background context. Omitting
   them degrades agent performance by removing their ability to delegate and
   parallelize work.
3. **Strip ALL meta-instructions.** Lines and blocks marked with
   `<!-- STRIP ... -->` comments, and any text that addresses "the coordinator"
   or "when filling this template", must be removed from the filled prompt. The
   implementation agent should never see instructions about how to fill the
   template — only instructions about how to implement the epic.

## Inputs Required

- `{{EPIC_ID}}` — The beads epic ID to implement
- `{{WORKTREE_PATH}}` — Absolute path to the working worktree
- `{{BRANCH_NAME}}` — Git branch for this work (e.g., `feature/auth`)
- `{{BASE_BRANCH}}` — The branch this work merges into. **Resolve it from the
  project's actual merge target** (`jq -r '.orchestration.merge_target'
  .thrum/config.json`); do not assume `main` and do not carry a branch name
  from another document
- `{{DESIGN_DOC}}` — **Absolute path** to the design spec (if applicable)
- `{{REFERENCE_CODE}}` — Paths to reference implementations (if any)
- `{{QUALITY_COMMANDS}}` — Commands for test/lint, **scoped to packages this
  epic modifies** (e.g., `go test ./internal/processing/localstore/` not
  `go test ./...`). Scoping avoids false failures from pre-existing issues in
  unrelated packages.
- `{{COVERAGE_TARGET}}` — Minimum coverage threshold (e.g., >80%)
- `{{AGENT_NAME}}` — Unique name for this agent (e.g., `impl-daemon`,
  `impl-cli`)
- `{{SUPERVISOR_NAME}}` — Agent name of the supervisor — coordinator or
  orchestrator (from `thrum team`). Use for direct messages, not the role name.
- `{{PLAN_FILE}}` — **Absolute path** to the implementation plan file
- `{{PROJECT_ROOT}}` — Absolute path to the project root
- `{{ANTI_PATTERNS}}` — Epic-specific implementation standards. Injected by
  project-setup Phase 4. If empty, the generic verifier pattern still applies
  but without domain-specific checks. Refer to the `project-philosophy` skill
  for the format spec.
- `{{CROSS_EPIC_DEPS}}` — Cross-epic dependency table showing which tasks in
  this epic are blocked by tasks in other epics. Injected by project-setup
  Phase 4. If empty (no cross-epic deps), this section is omitted.

**Why absolute paths?** Design docs, plan files, and prompts typically live in
gitignored directories (`dev-docs/`, `docs/plans/`). Worktrees only share
committed files, so agents in worktrees cannot resolve relative paths to these
files. All `{{DESIGN_DOC}}`, `{{PLAN_FILE}}`, and prompt references must be
absolute paths (e.g., `/Users/you/project/dev-docs/plans/file.md`).

---

## Sub-Agent Strategy

You are an **orchestrator**. You implement by dispatching research,
implementation, and verification to sub-agents and synthesizing their output —
not by doing the legwork yourself. Your context is for judgment (synthesize
reports, target edits, judge verification); the legwork goes to cheaper
sub-agents. The full procedure is the `implementer-orchestrating-execution`
skill — it is canonical; this section only sets the default. Invoke that skill
at the start of executing any scoped task.

### Scoping gate (before dispatching anything)

Classify the whole task. If it is a bounded change (≤ ~15 lines, ≤ 2 files)
whose targets you already know and where any reading is purely to **locate**
(not to understand), do it inline as correction-class and skip orchestration.
Otherwise, orchestrate via the agent table below.

### Agent selection

| Dispatch                       | Agent type                     | Model                                   | Background? |
| ------------------------------ | ------------------------------ | --------------------------------------- | ----------- |
| Research / explore a code area | `Explore` or `general-purpose` | `sonnet`                                | yes         |
| Implement a task               | `general-purpose`              | `sonnet` (low effort if purely mechanical) | no       |
| Verify a task against the plan | `general-purpose`              | `sonnet`                                | no          |
| Run tests / lint               | `general-purpose`              | `sonnet` (low effort)                   | yes         |

Always pass `model:` explicitly — never let a sub-agent inherit your (Opus)
model. Label every dispatch's `description` with `research:` / `implement:` /
`verify:` (the evaluation harness classifies delegation shape from these
labels).

### The inline-vs-dispatch boundary

> **Default verb is dispatch.** Inline editing is permitted in exactly three
> cases:
>
> 1. **Correcting** a sub-agent's edit that came back wrong.
> 2. An edit whose change you **already fully know**, where any reading is
>    purely to **locate** the insertion point (not to understand), AND the
>    change is bounded (≤ ~15 lines, ≤ 2 files).
> 3. The scoping-gate case: the whole task meets the bound in (2).
>
> **The moment you must read code to _understand what to change_ — discovering
> unknown structure, not finding a known target — that is a research dispatch,
> not an inline edit.**

### Verifier dispatch (per task)

After an implementation dispatch returns, spawn a `sonnet` verifier against the
plan the implementing sub-agent was given — confirm the diff meets the
acceptance criteria. This is the in-loop check; the full code review still
happens at Phase 3: Self-Review Gate.

---

## MANDATORY: Register Before Any Work

**STOP. Run these commands before doing anything else.** Do not skip this
section.

```bash
cd {{WORKTREE_PATH}}
thrum quickstart --name {{AGENT_NAME}} --role implementer --module {{BRANCH_NAME}} --intent "Implementing {{EPIC_ID}}"
thrum inbox --unread
# Tip: thrum inbox --unread peeks without marking read; thrum message read --all to mark all read
# Tip: default page is 10 newest-first — stale unread sorts LAST; use `thrum message search "<term>"` to find it
thrum send --to @{{SUPERVISOR_NAME}} --stdin <<'EOF'
Starting work on {{EPIC_ID}}
EOF
```

**Verify registration succeeded** — you must see your agent name in the output
of `thrum quickstart`. If it fails, check that the daemon is running with
`thrum daemon status`.

**Finding agent names:** Run `thrum team` to see all active agents and their
names. Always send to agent names (e.g., `--to @coord_main`), not role names
(e.g., `--to @coordinator`). Sending to a role fans out to ALL agents with that
role.

**Use the message listener** — Spawn a background listener to get async
notifications. Re-arm it every time it returns (both MESSAGES_RECEIVED and
NO_MESSAGES_TIMEOUT).

When your work is complete (Phase 4), send a completion message prefixed with
the appropriate **status token** (see Status Vocabulary at the start of Phase
4):

```bash
thrum send --to @{{SUPERVISOR_NAME}} --stdin <<'EOF'
DONE: {{EPIC_ID}} complete. All tasks done, tests passing.
EOF
```

If you hit a blocker from another agent's work, escalate with the `BLOCKED`
token:

```bash
thrum send --to @{{SUPERVISOR_NAME}} --stdin <<'EOF'
BLOCKED: {{TASK_ID}} waiting on {{BLOCKER_ID}}
EOF
```

---

## Phase 1: Orient

Whether starting fresh or resuming after context loss, always begin here. This
phase is idempotent — running it multiple times is safe and expected.

🔴 **BEFORE ANYTHING ELSE — OBTAIN THE PLAN INTO YOUR WORKTREE AND CONFIRM YOU CAN OPEN IT.** Do NOT implement from plan detail relayed to you in messages or beads — relay is lossy and drifts as the plan is updated.

```bash
cd {{WORKTREE_PATH}}
git pull                 # pull the committed plan into this worktree
head -1 {{PLAN_FILE}}    # confirm the plan file actually opens here
```

If `{{PLAN_FILE}}` cannot be opened, STOP and tell {{SUPERVISOR_NAME}} — do not proceed from relayed or remembered plan text.

### Step 1: Check Epic & Task Status

```bash
# Navigate to worktree
cd {{WORKTREE_PATH}}

# Check epic status — see which tasks are done, in_progress, or pending
bd show {{EPIC_ID}}

# Check for any in-progress tasks (may be from a prior session)
bd list --status=in_progress

# Check completed tasks
bd list --status=closed
```

### Step 2: Check Git State

```bash
# Verify you're on the right branch
git branch --show-current

# Check for uncommitted work from a prior session
git status

# Review recent commits to understand what's been done
git --no-pager log --oneline -10

# Pull latest changes (if remote tracking is set up) — merge, never rebase
git pull
```

### Step 3: Explore Existing Code

Dispatch a research sub-agent (see `implementer-orchestrating-execution`) to map
what already exists — don't read the codebase into your own context:

1. Check which files/packages have been created
2. Review existing implementations for patterns to follow
3. Identify the current state of any in-progress tasks

If a design doc exists, read it: `{{DESIGN_DOC}}`

If reference code exists, explore it: `{{REFERENCE_CODE}}`

### Step 4: Determine Starting Point

- If **all tasks are complete**: Skip to Phase 3 (Verify Quality) then Phase 4
  (Complete)
- If **a task is `in_progress`**: Review its state — check what's partially
  implemented, check git diff, then continue from where it left off
- If **tasks are pending**: Start with the first unblocked pending task (lowest
  dependency order)

**CRITICAL: DO NOT redo completed work.** Trust the beads status and git
history. Pick up from exactly where the previous session stopped.

### Step 5: Check Cross-Epic Dependencies

{{CROSS_EPIC_DEPS}}

<!-- STRIP: This comment is for project-setup. When filling, replace
     {{CROSS_EPIC_DEPS}} with either a dependency table or
     "No cross-epic dependencies." Then remove this comment. -->

---

## Implementation Standards

{{ANTI_PATTERNS}}

<!-- STRIP: Replace {{ANTI_PATTERNS}} with content generated per the
     project-philosophy anti-pattern format. Then remove this comment. The
     self-review gate in Phase 3 passes these to the code-reviewer sub-agent. -->

---

## Phase 2: Implement Tasks

### Task Execution Loop

For each task (in dependency order, foundations first):

#### 1. Claim the Task

```bash
bd update {{TASK_ID}} --status=in_progress
```

#### 2. Read the Task Details

```bash
bd show {{TASK_ID}}
```

The task description is the **source of truth** for what to build. It contains
acceptance criteria that must be satisfied before closing the task.

For detailed implementation code, search the plan file for the matching task
section:

```bash
grep -n "## Task: {{TASK_ID}}" {{PLAN_FILE}}
```

Read ONLY that section (from the matching heading to the next `## Task:` heading
or end of file), not the entire plan file. Plan files can be large (50KB+) and
reading the whole file exhausts context. The plan file provides step-by-step
code; the beads task provides completion criteria. Use both.

#### 3. Implement the Task

- Follow the task description
- Write tests alongside implementation (TDD when appropriate)
- Follow existing code patterns and conventions in the codebase
- Reference `{{DESIGN_DOC}}` for architectural context when needed

#### 4. Verify the Task

```bash
# Run project quality gates
{{QUALITY_COMMANDS}}
```

All tests must pass before proceeding. If tests fail, fix them before moving on.
Do not skip failing tests or mark them as known failures without explicit
instruction.

#### 5. Commit the Work

```bash
git add <specific-files>
git commit -m "{{EPIC_TITLE}}: <concise task description>"
```

Commit after each task, not in bulk at the end. Use descriptive commit messages
that explain what was built.

#### 6. Close the Task

```bash
bd close {{TASK_ID}}
```

#### 7. Move to Next Task

Repeat from step 1 with the next unblocked pending task.

If multiple tasks are complete, close them in batch:

```bash
bd close {{TASK_ID_1}} {{TASK_ID_2}} {{TASK_ID_3}}
```

---

### Parallel Task Implementation

When multiple tasks are unblocked and independent, implement them
simultaneously. This is the biggest context and time win.

#### Identify Parallelizable Tasks

After completing a task, check for unblocked work:

```bash
bd show {{EPIC_ID}}  # Which tasks are pending and unblocked?
```

Tasks are parallelizable when they touch different files/packages and don't
depend on each other's output.

#### Launch Pattern

Give each sub-agent everything it needs to work autonomously. Each prompt must
include: worktree path, branch name, the full `bd show <task_id>` output as the
source of truth, the quality commands for the verify step, and the
commit-message format (`{{EPIC_TITLE}}: <task summary>`). Each sub-agent returns
what was built, test results, and the commit hash.

Invoke `efficient-multi-agent-research` § Core Pattern for the launch-and-wait
mechanics (dispatch all agents in ONE message, `run_in_background=true`, wait
for all completions before consolidating).

#### After Sub-Agents Complete

1. Review reported results (commit hashes, test output)
2. Check for conflicts: `git --no-pager log --oneline -5`
3. Close completed tasks: `bd close {{TASK_A}} {{TASK_B}}`
4. Run unified quality gate: `{{QUALITY_COMMANDS}}`
5. Check for newly unblocked tasks — repeat if more are available

#### Guardrails

- **2-3 concurrent sub-agents** is the sweet spot. More adds coordination
  overhead without proportional speedup.
- **Partition by file/package** to avoid git conflicts. If two tasks touch the
  same file, run them sequentially.
- **Always run a final unified test pass** after parallel work — concurrent
  sub-agents may miss interaction bugs.

---

### Tool Usage

#### Code Exploration

Use Grep, Glob, and Read tools for targeted searches. For broader exploration of
unfamiliar code areas, spawn an Explore sub-agent — it's more context-efficient
than reading entire files into your main context.

#### Subagents

The canonical procedure is the `implementer-orchestrating-execution` skill
(scoping gate, research → implementation → verification dispatch, model tiers,
label convention). The **Sub-Agent Strategy** section at the top of this
template sets the orchestrator default and points at that skill.

---

### Logging Refactoring Opportunities

During implementation you will often discover code that could be improved —
duplicated patterns, hardcoded values that should be shared, missed
abstractions, or DRY violations. **Do not fix these inline** (scope creep) and
**do not lose them** (they're valuable).

Self-filing here is limited to purely cosmetic improvements to code that
already works correctly — naming, duplication, structure. Anything that
touches correctness, or is a defect, a plan gap, a missing case, or one of a
class of sites where others are already wrong, goes to your dispatcher via the
`closing-findings-while-warm` skill — no exceptions, and regardless of how you
label it. If you cannot tell which side of that line you are on, that
uncertainty is itself the answer: surface it.

Instead, log them to the project's persistent **refactoring epic** in beads:

#### 1. Find the Refactoring Epic

```bash
bd list --type=epic | grep -i refactor
```

If no refactoring epic exists, create one:

```bash
bd create --title="Refactoring & DRY Opportunities" --type=epic --priority=3 \
  --description="Persistent backlog for refactoring, DRY improvements, and code organization opportunities discovered during feature work. Tasks are added by implementation agents as they encounter opportunities. Reviewed and prioritized by the coordinator periodically."
```

#### 2. Log the Opportunity

```bash
bd create --title="Refactor: <short description>" --type=task --parent=<refactoring-epic-id> --priority=3 \
  --description="**Discovered during:** {{EPIC_ID}}
**Files:** <file paths>
**Opportunity:** <what could be improved — duplicated code, hardcoded values, missed abstraction>
**Suggested approach:** <how to fix it>
**Effort estimate:** small/medium/large"
```

#### 3. Continue With Your Assigned Work

Do not implement the refactoring — just log it and move on. The coordinator
reviews and prioritizes these periodically. This keeps your scope tight while
ensuring good ideas aren't lost.

**Examples of what to log:**

- Two handlers with nearly identical pagination logic → extract shared helper
- Hardcoded demo values that should come from seed data
- Multiple packages importing the same 5-line utility pattern
- An interface that's grown too large and should be split
- A notification store duplicated across two packages (should be unified)

---

### Handling Blockers

If a task is blocked:

1. Check what's blocking it: `bd show {{BLOCKER_ID}}`
2. If the blocker is another task **within your epic**, work on the blocker
   first
3. If the blocker is **external** (different epic, different agent), skip the
   blocked task and work on the next unblocked one
4. Document the blocker:
   `bd update {{TASK_ID}} --notes="Blocked by {{BLOCKER_ID}}: <reason>"`
5. **Notify via Thrum** so the coordinator or blocking agent is aware:

```bash
# Ask the blocking agent for help
# NOTE: --mention @implementer is a message filter tag, not a delivery address.
# The message is delivered to @{{SUPERVISOR_NAME}}; the mention tag lets implementers
# filter for messages that mention their role. To address a specific agent directly,
# use --to @<agent-name> instead.
thrum send --mention @implementer --stdin <<'EOF'
BLOCKED: {{TASK_ID}} — waiting for {{BLOCKER_ID}}. Can you prioritize?
EOF

# Or escalate to the coordinator
thrum send --to @{{SUPERVISOR_NAME}} --stdin <<'EOF'
BLOCKED: {{TASK_ID}} by external dependency {{BLOCKER_ID}}
EOF
```

### When you hit a design fork

**If you're blocked on a genuine 2-3 way design fork** — a real tradeoff where
"just pick one" would likely be regretted — invoke `adversarial-critique` with
the options, constraints, and the decision you need made. The
`adversarial-critique` skill documents cost, threshold, and the audit artifact
path.

**If you're investigating N > 6 items** (function call sites, pattern audits,
multi-file reviews), invoke the `efficient-multi-agent-research` skill _instead
of_ reading files into this context. It partitions the work across parallel
sub-agents that write findings to disk, then consolidates into one report.

Cost: ~50-100k tokens depending on item count. Worth it to keep decision-making
context clean and produce an auditable research trail at `dev-docs/<topic>/`.
Skip it when:

- Fewer than ~6 items — just use Grep/Glob
- Items are deeply interdependent and can't be partitioned

These two gates are sister patterns: critique decides _which option wins_;
research uncovers _what's there_.

### Communicating During Work

Use Thrum to stay coordinated:

```bash
# Report progress on significant milestones
thrum send --to @{{SUPERVISOR_NAME}} --stdin <<'EOF'
Completed task {{TASK_ID}}, moving to next
EOF

# Ask for input when you need a decision
thrum send --to @{{SUPERVISOR_NAME}} --stdin <<'EOF'
Need input: should X use approach A or B? Context: ...
EOF

# If you realize your work affects another agent's files
# NOTE: --mention @implementer is a filter tag, not a delivery address.
# This tags the message so implementers can filter for it; delivery goes to @everyone by default.
# Use --to @<agent-name> to target a specific agent.
thrum send --mention @implementer --stdin <<'EOF'
Heads up: I'm modifying internal/daemon/rpc.go which may overlap with your work
EOF

# Update your intent when switching tasks
thrum agent set-intent "Working on {{TASK_ID}}: <description>"
```

---

<!-- REVIEW_GATE_TEMPLATE_START -->

## Review Gate: {{EPIC_ID}}

Before proceeding to the next epic:

1. Commit all work for this epic
2. Run tests: verify all tests pass for changes in this epic
3. Report completion via Thrum:
   `thrum send --to @{{SUPERVISOR_NAME}} --body-file done.md` (body: "DONE: Epic
   {{EPIC_ID}} complete. Ready for review.")
4. Set status: `thrum agent set-status idle`
5. **STOP.** Wait for review approval before continuing.
<!-- REVIEW_GATE_TEMPLATE_END -->

---

## Phase 3: Self-Review Gate (MANDATORY)

**You MUST complete this phase before claiming the epic is done.** Do not skip
or abbreviate it. The purpose is to catch issues before the coordinator reviews,
reducing back-and-forth rounds.

Use a **two-stage review** in this exact order: **spec compliance first, then
code quality.** Run `verify-against-plan` before `feature-dev:code-reviewer`;
fix each stage's findings before moving to the next.

### Step 1: Run Quality Gates

```bash
cd {{WORKTREE_PATH}}

# Run all tests
{{QUALITY_COMMANDS}}

# Check coverage if applicable
# Target: {{COVERAGE_TARGET}}
```

Fix any failures before proceeding. Do not submit broken code for review.

### Step 2: Spec Compliance Review (Stage 1)

Verify the implementation covers everything specified in the plan, design doc,
and each task's acceptance criteria. No code-style judgments at this stage —
only "does the code do what was asked?"

Invoke `verify-against-plan` with these inputs:

```text
/verify-against-plan plan={{PLAN_FILE}} branch={{BRANCH_NAME}}
```

The skill produces structured `BLOCKING` / `IMPORTANT` / `MINOR` findings with
plan-reference + file:line evidence.

**When findings come back:**

- For each `BLOCKING` or `IMPORTANT` finding, apply the `Suggested resolution`
  from the finding using the same TDD cycle from Phase 2. Commit each fix:
  `git commit -m "feat: cover missing scope — <description>"`. Re-run
  `verify-against-plan` until no `BLOCKING` or `IMPORTANT` findings remain.
  `MINOR` findings may be noted but do not block.
- When the skill returns with no `BLOCKING` or `IMPORTANT` findings, proceed to
  Step 3.

**Maximum iterations:** 2 rounds. If findings persist after 2 rounds, note them
in the completion message to the coordinator with status `DONE_WITH_CONCERNS`.

### Step 3: Code Quality Review (Stage 2)

Only after spec compliance is clean. Compute the diff range for the full epic:

```bash
BASE_SHA=$(git merge-base HEAD "{{BASE_BRANCH}}")   # NOT `main` — resolve the real base
HEAD_SHA=$(git rev-parse HEAD)
```

Spawn a `feature-dev:code-reviewer` sub-agent in **foreground** (you need the
results before proceeding). The reviewer is a separate agent — you cannot
influence its findings.

```text
Agent(subagent_type="feature-dev:code-reviewer", model="sonnet",
  prompt="Review code quality of the implementation on branch {{BRANCH_NAME}}
  in {{WORKTREE_PATH}}. Focus only on quality of the code that was written —
  spec compliance is covered separately by verify-against-plan.

  ## What to Review

  Run `git --no-pager diff {BASE_SHA}...{HEAD_SHA}` to see all changes.

  ## Review Criteria

  ### 1. Code Quality
  - Security: XSS, RBAC bypass, SQL injection, command injection
  - Error handling: no swallowed errors, proper HTTP status codes
  - Go idioms: proper error returns, no bare panics, correct defer usage
  - No dead code, no commented-out code, no TODO items left behind

  ### 2. Implementation Standards (Anti-Patterns)

  {{ANTI_PATTERNS}}

  Check every changed file against these rules. Grep for the red flags listed.
  Each violation is a finding.

  ## Output Format

  Return a numbered list of findings. For each finding:
  - File path and line number
  - Severity: CRITICAL / HIGH / MEDIUM / LOW
  - What's wrong
  - How to fix it

  End with: 'Ready to merge: Yes/No'

  If no issues found, return: 'Ready to merge: Yes — no issues found.'")
```

**When the review comes back**, invoke `superpowers:receiving-code-review` and
follow its response pattern:

1. **READ** the full review without reacting
2. **VERIFY** each finding against the codebase — is it actually valid? Check
   the file and line number. The reviewer can be wrong.
3. **FIX** Critical and Important issues. Push back with reasoning if a finding
   is incorrect — do not blindly implement wrong suggestions.
4. **MEDIUM** findings — use judgment, but default to fixing.
5. **LOW** findings — fix if trivial, otherwise note and move on.
6. Commit fixes:

   ```bash
   git add <fixed-files>
   git commit -m "fix: address review findings for {{EPIC_ID}}"
   ```

7. **Re-run the code-reviewer** on the new diff (`BASE_SHA` = previous
   `HEAD_SHA`, `HEAD_SHA` = new HEAD). Repeat until the reviewer returns "Ready
   to merge: Yes" with no Critical or Important issues remaining.

**If code-quality fixes introduce substantive new logic** (not just renames or
reformatting), return to Step 2 (Spec Compliance) on the new code before
re-running code quality. New logic can create new gaps.

**Maximum iterations:** 3 review rounds. If issues persist after 3 rounds,
proceed to Step 4 and note the unresolved findings in your completion message
with status `DONE_WITH_CONCERNS`. Do not loop indefinitely.

### Step 4: Final Verification

Run `{{QUALITY_COMMANDS}}` one final time. Review fixes and scope additions can
introduce regressions — do not skip this.

**If tests fail:** Fix failures before proceeding.

### Verification Checklist

Before proceeding to Phase 4, confirm:

- [ ] All tasks in the epic are closed: `bd show {{EPIC_ID}}`
- [ ] All tests pass: `{{QUALITY_COMMANDS}}`
- [ ] `verify-against-plan` returned no `BLOCKING` or `IMPORTANT` findings
- [ ] Code quality returned "Ready to merge: Yes"
- [ ] Commit history is clean and descriptive:
      `git --no-pager log --oneline -20`

---

## Phase 4: Complete & Land

### Status Vocabulary (MANDATORY)

Every completion or escalation message to your supervisor must start with one of
these four status tokens. The coordinator's handler depends on the token — wrong
token means wrong response.

| Token                | Meaning                                                        | Send When                                                              |
| -------------------- | -------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `DONE`               | Epic complete, all tasks closed, tests pass, self-review clean | Ready for coordinator review and merge                                 |
| `DONE_WITH_CONCERNS` | Work complete but with caveats the coordinator should see      | Unresolved review findings, architectural concerns, iteration caps hit |
| `NEEDS_CONTEXT`      | Cannot proceed without more information                        | Missing design decision, ambiguous spec, unclear scope                 |
| `BLOCKED`            | Cannot proceed — external dependency or tooling issue          | Cross-epic dependency, test infra broken, auth problem                 |

Prefix every completion and escalation `thrum send` with the status token, for
example: `thrum send --to @{{SUPERVISOR_NAME}} --body-file done.md` (body:
"DONE: {{EPIC_ID}} complete. Branch pushed.")

### Step 1: Close the Epic

```bash
# Verify all tasks are closed
bd show {{EPIC_ID}}

# Close the epic
bd close {{EPIC_ID}} --reason="All tasks implemented and verified"
```

### Step 2: Push Branch & Notify Coordinator

Do NOT merge to main yourself. Push your branch and notify the coordinator for
code review and merge:

```bash
# Ensure branch is up to date with {{BASE_BRANCH}} — merge forward, never rebase
git fetch origin {{BASE_BRANCH}}
git merge origin/{{BASE_BRANCH}}

# If conflicts arise, resolve them, then:
# git add <resolved files> && git commit

# Run quality gates one final time after merging forward
{{QUALITY_COMMANDS}}

# Push the branch (NOT main)
git push origin {{BRANCH_NAME}}

# Notify the coordinator
thrum send --to @{{SUPERVISOR_NAME}} --stdin <<'EOF'
DONE: {{EPIC_ID}} complete. Branch {{BRANCH_NAME}} pushed, all tests passing. Ready for review/merge.
EOF
```

The coordinator handles code review and merge to main. This ensures review gates
are not bypassed and cross-epic integration is verified.

> **For solo-agent workflows:** If no coordinator exists, override this step to
> merge directly to main after running the full quality gate.

### Step 3: Clean Up (Only If Instructed)

```bash
# Remove the worktree if no longer needed
git worktree remove {{WORKTREE_PATH}}

# Delete the feature branch
git branch -d {{BRANCH_NAME}}
```

Only clean up if explicitly instructed. The user may want to keep the worktree
for future work.

---

## Resume Quick Reference

If you're resuming after context loss (compaction, new session, etc.), here's
the minimal sequence:

```bash
# 1. Re-register with Thrum (MANDATORY — do this first)
cd {{WORKTREE_PATH}}
thrum quickstart --name {{AGENT_NAME}} --role implementer --module {{BRANCH_NAME}} --intent "Resuming {{EPIC_ID}}"
thrum inbox --unread
# Tip: thrum inbox --unread peeks without marking read; thrum message read --all to mark all read
# Tip: default page is 10 newest-first — stale unread sorts LAST; use `thrum message search "<term>"` to find it

# 2. Orient from beads and git
bd show {{EPIC_ID}}                    # What's done?
bd list --status=in_progress           # Anything mid-flight?
git --no-pager log --oneline -10       # What was committed?
git status                             # Any uncommitted work?
# Then pick up from the first incomplete task — DO NOT redo completed work
```
