---
name: conversation-only-context
description:
  "Use at the START of any long-lived agent session (researcher, coordinator,
  orchestrator, brainstormer), and whenever the operator says we are going to
  have a long conversation, get a lot done, or keep many threads open - also
  when context is climbing, when several investigations are in flight at once,
  when you are about to read code or a multi-file doc set to investigate, or
  when you catch yourself opening a log to just check quickly."
# source: claude-plugin/skills/conversation-only-context/SKILL.md
# generated-by: scripts/sync-skills.sh
---

## Conversation-only context — spend your own context on the human, dispatch everything else

Your context is the session's scarcest resource. It buys conversation with the
operator, messaging, queue and state — nothing else. Every investigation,
verification, root-cause, code read, doc summary and VM job goes to a named
persistent subagent that writes its result to a file.

`<scratch>` below means `/private/tmp` on macOS (where `/tmp` is a symlink) and
`/tmp` on Linux. Check with `[ -L /tmp ]`; never assume from the platform name.

### Wake procedure

0. Caller binding decays to anonymous across a restart. Before the first
   mutating thrum command, re-warm it: `thrum prime >/private/tmp/rw.txt 2>&1` —
   output to a file, **not** back into context.
1. Read the **full** prime briefing with the Read tool, every page, in order.
   Name one load-bearing fact from the **middle** of it before taking any
   action.
2. Execute the resume plan from the newest restart snapshot.
3. Reconcile `thrum queue list` against
   `thrum state show personal_state:current`.
4. Read `thrum inbox --unread` **and** run `thrum message search` — stale unread
   sorts last and is missed by the inbox page. Mark each processed message read
   (`thrum message read <id>`).
5. Where the snapshot lists live subagents (§ restart handoff), respawn each one
   with its result file as seed before doing its work yourself.

### The dispatch rule

**The parent never reads code, logs, or multi-file doc sets to investigate.**
Ask a subagent a smaller question instead. "I will just check quickly" is the
failure this skill exists to prevent.

| Parent keeps inline                                                                            | Parent dispatches                             |
| ---------------------------------------------------------------------------------------------- | --------------------------------------------- |
| Reading and replying to messages (`thrum reply --stdin <<'EOF'`)                               | Any code read, grep sweep, or call-site audit |
| Queue and state reconcile                                                                      | Root-cause investigation                      |
| Talking to the human at the pane                                                               | Verification of an implementer's work         |
| Owner-only decisions, surfaced with a recommendation                                           | Summarizing a doc set                         |
| Tiny mechanical git **in its own worktree** (commit/push docs)                                 | Any VM job                                    |
| Reading a subagent's ≤20-line summary                                                          | Anything whose tool output runs to pages      |
| The ONE file a question names — a subagent's report, or a deliverable you were asked to review | Everything the named file cites               |

That row is purpose, not size: a file handed to you to act on is conversation,
not investigation.

Never spawn a subagent to operate inside another agent's worktree.

### Dispatch shape

Every dispatch carries: an explicit `name:`, an explicit `model:`, an output
file path, a ≤15-20 line reply cap, and the pasted CONSTRAINTS block. Launch
independent subagents **in one message** so they run in parallel.

Pin `model:` on every spawn. Pass `effort` only where the mechanism exposes it —
Workflow `agent()` opts, agent-definition frontmatter,
`thrum tmux launch --effort`. **The Agent tool does not take `effort`.**

```python
Agent(subagent_type="general-purpose",
      name="<prefix>_<slug>",
      model="sonnet",
      description="<3-5 words>",
      prompt="""<task>

WRITE your result to <scratch>/<prefix>-<slug>.md. Reply to me with a
summary of at most 20 lines - no logs, no transcripts, no command dumps.

=== CONSTRAINTS ... ===  # pasted verbatim, see below
""")
```

Write is fine for a NEW result file; to update an existing one, Read it first or
append with a heredoc (`cat >> <path> <<'EOF'`) — Write refuses to overwrite a
file it has not read this session.

Continue it — never respawn:

```python
SendMessage(to="<prefix>_<slug>",
            message="Answer L3 and L5 first and report a partial now. Same file, append.")
```

A name keeps working after the subagent's turn ends; a send resumes it with its
context intact. "A subagent whose turn ends is not waiting — it is gone" applies
to fire-and-forget monitors, not to a named agent you re-message.

#### Naming and tiers

| Subagent role                                | Name prefix               | Model / effort (effort only where exposed) | Result file                  |
| -------------------------------------------- | ------------------------- | ------------------------------------------ | ---------------------------- |
| Investigation, grep, doc summary, mechanical | `<topic>` (e.g. `vmdocs`) | `sonnet` / low                             | `<scratch>/<name>.md`        |
| Root-cause                                   | `<bead>_rc`               | `sonnet` / low                             | `<scratch>/<bead>-rc.md`     |
| Verifier, reviewer, design-verify            | `<bead>_verify`           | `sonnet` / medium                          | `<scratch>/<bead>-verify.md` |
| Implementer                                  | `impl_<slug>`             | `sonnet` / medium                          | `<scratch>/<slug>-impl.md`   |
| VM driver                                    | `vmdriver_<slug>`         | `sonnet` / medium                          | `<scratch>/<slug>-vm.md`     |
| Prose or deep review                         | any                       | `opus` — **only when the operator asks**   | as above                     |

Haiku is banned. Opus is never yours to grant onward.

#### CONSTRAINTS block — paste verbatim into every dispatch

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

### Relaying findings

Consolidate one pass's findings into **one** numbered message, severity-tagged
BLOCKING / IMPORTANT / MINOR — never partial batches, which get half-fixed. But
a **design-gating** answer goes out the moment it lands, even while the rest of
the pass is still running: when a downstream implementer is already building,
send the cheapest zero-cost interim guidance immediately rather than waiting for
the verifier to finish.

A result file on this box is unreadable from a remote-box coordinator. **Put the
substance in the message; never send only a path.**

Attribute what you did not verify yourself: forwarding a subagent's finding as
your own claim launders an unchecked assertion into your authority. Either read
the cited line, or write "from my verifier, cites `file:line`".

### Pane discipline

Write to the pane only when the human asked, or when the decision is one only
the human can make. Everything else goes through `thrum send` / `thrum reply`.
Surface an owner-only decision crisply, with a recommendation attached.

### Remote and VM work

Use a named persistent driver (`vmdriver_<slug>`), continued by `SendMessage`
across rounds. Reach the remote environment only through the persistent-session
command your project sanctions, never a one-shot remote exec. State the
three-clause GO (execute now · drive to completion yourself · then stop and
report), require the isolation proof before anything touches a shared service,
and require the 3-section report. Never do the remote work yourself.

The full pattern is `resources/driver-subagent-pattern.md`; five worked shapes,
including the restart handoff of a live driver, are in
`resources/remote-environment-scenarios.md`.

### Restart handoff

Subagents do not survive a restart. Before restarting:

1. Tell every live subagent to finish and write its file.
2. Record in the restart snapshot, per subagent: **name · what it owned · result
   file path · model/effort**.
3. State which subagents have already exited.

The successor respawns each one with its result file as seed.

Restart on a number read from the pane footer, never on a felt sense.

### See Also

- `efficient-multi-agent-research` — the fan-out sibling: partition, investigate
  to disk, consolidate, for N>6 items. This skill sets the session's posture;
  that one runs a single pass.
- `choosing-subagent-models` — the tier policy and source of the CONSTRAINTS
  block.
- [driver-subagent-pattern.md](resources/driver-subagent-pattern.md) — the full
  remote-work pattern: the named driver, the three-clause GO, the isolation
  proof, the report contract, the parent's duties, the anti-patterns.
- [remote-environment-scenarios.md](resources/remote-environment-scenarios.md) —
  five worked shapes, from a long lab run to a restart handoff of a live driver.

### Failure modes

- Respawning a fresh single-shot subagent for a follow-up when a named one
  already holds the context — `SendMessage` it; a respawn loses the context and
  pays the re-read.
- A fire-and-forget "monitor until done" agent that arms a monitor and ends its
  turn — measured at 70 min, 122k tokens, zero output. Put the
  drive-to-completion clause in every dispatch.
- The parent reading code or docs "to just check quickly" — message the subagent
  that already read them and ask for the one field.
- One subagent handed ten tasks — partition it and dispatch the parts in
  parallel.
- A spawn with no `name:` — it cannot be re-messaged. Name every spawn.
- A spawn with no `model:` — it silently inherits Opus. Pin `model:` on every
  spawn, and `effort` wherever the mechanism takes it.
- Holding a design-gating answer behind the rest of the pass while an
  implementer builds on the old premise — that one goes immediately; the rest
  ships as one consolidated message.
- Acting on the resume plan alone and skipping the middle of the prime — the
  falsified premise sits in the part you skipped.
- Trusting an older "not started" message over a newer "already running" one —
  verify, do not recall; that cuts both directions.
- Restarting without listing every live subagent's name and result file in the
  snapshot — the successor cannot respawn what is not written down.
- Forwarding a subagent's BLOCKING finding to a third party as your own claim —
  check the cited line, or attribute it; never state as yours what you did not
  verify.
