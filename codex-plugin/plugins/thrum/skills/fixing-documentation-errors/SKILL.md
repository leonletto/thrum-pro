---
name: fixing-documentation-errors
description: "Use the moment you notice documentation is wrong, stale, incomplete, or contradicts what a command actually does - a doc that omits a flag or subcommand that exists, a README/llms.txt/CLI-help/docstring/comment that disagrees with observed behaviour, a version-stamped section that predates a feature, an example that would fail if run, a doc claim you were about to cite and could not confirm. Illustrative (non-exhaustive) triggers - 'the docs don't mention X', 'llms.txt is out of date', 'the help text says Y but it actually does Z', 'that flag isn't documented', 'this example is wrong', 'the docs are stale here', 'I should file a bead about the docs', 'I'll note the doc gap' - but the trigger is NOTICING A DOC DEFECT, not matching a phrase. Fires regardless of what you were originally doing; a doc error found mid-task is still in scope."
# source: claude-plugin/skills/fixing-documentation-errors/SKILL.md
# generated-by: scripts/sync-skills.sh
---


## Fixing Documentation Errors

### The rule

**You found it, you can verify it, you fix it — in this turn.**

No triage. No coordinator approval. No bead-then-wait. Documentation you can
verify is the one class where the person who found the defect is already the
best-placed person to fix it, and every step you insert between finding and
fixing destroys the thing that made you well-placed.

File a bead recording that you **did** it. Never file a bead **instead of**
doing it.

### This applies to EVERY role — what changes is the action, never whether you act

**No agent may ignore a doc defect, and no agent may file-and-move-on.** Those
are the two forbidden responses for everyone. What differs by role is only
whether you fix it yourself or ask first.

| Role | What you do, IN THIS TURN |
|---|---|
| Coordinator · orchestrator · researcher · gate · watcher | **Fix it.** You hold the authority. Verify, edit every copy, then file the record. |
| Implementer **between tasks / idle** | **Fix it.** Same as above. |
| Implementer **mid-task** | **ASK your orchestrator or coordinator, in this turn** — one line: *"Found a doc error: `<file:line>` says X, actual behaviour is Y (verified how). Want me to fix it now, or carry it?"* |
| Sub-agent | **Report it to whoever dispatched you**, in your final report, with file:line and the measured truth. Do not fix outside your assigned scope. |

**For the mid-task implementer, THE ASK IS THE ACTION.** It is not a deferral and
it is not a bead. It goes out in the turn you found the defect, while you still
hold the file, the line, and the evidence — so that whoever answers can say
"yes, now" and you are already warm.

⚠️ **Do not ask and then drop it.** If no answer arrives before you finish your
task, say so explicitly in your completion report, with the file:line and the
measured truth attached. An unanswered ask that vanishes is the same outcome as
never asking.

⚠️ **Do not ask for permission you already have.** If the fix is inside the file
you were already sent to change, and it is unambiguous, just fix it. The ask
exists for scope discipline, not as a ritual.

**Manager side — if you receive one of these asks, answer it in the turn you
read it.** "Yes, fix it" is almost always right, and it is cheapest at the moment
the reporter is still warm. Every hour you sit on it converts a five-minute edit
into a re-derivation. If you say "not now", say what happens to it instead —
never leave the reporter holding it.

### Why deferring is worse than it looks

Filing while warm does not defer the work. **It duplicates it and throws away
the expensive half.**

To write a useful doc bead you must state the file, the line, the wrong text,
the correct text, and how you know. That *is* the fix specification — writing it
costs roughly what performing the edit costs. So the real choice is never "fix
now vs fix later." It is:

- **fix once now**, or
- **specify it now**, then have someone re-read it, **re-verify it** (a bead is
  a claim, not evidence), re-acquire the context you already had, and only then
  fix it.

Four passes over work you had already finished.

**The one-question check — ask it before writing any doc bead:**

> Does this bead body contain what I would need to do the fix?

If **yes**, you are the person with the context and the decision is already
made. Do the fix. File the bead afterwards as a record.

### What defeats this rule

These are the observed failure modes, not hypotheticals. Expect them.

- **A thorough write-up registers as having acted.** A thin note nags at you; a
  well-argued bead closes the loop in your head. Diligence in the write-up is
  the *cause*, not the mitigation.
- **A severity label disguises a deferral.** "P1, do it later" reads as triage
  rather than avoidance, because assigning P1 *feels* like taking it seriously.
- **"Not my task."** A doc error found mid-task is in scope. The cost of coming
  back is what this skill exists to avoid.
- **"Someone owns these docs."** Nobody owns a stale line. Ownership is the
  reason it is still stale.

### Verify before you edit — never fix a doc from another doc

**Documentation drifts; runtime behaviour does not lie.** Correcting a doc from
your memory, from a bead, or from another doc propagates the error into a new
place while making it look freshly checked.

Establish ground truth by **direct observation**, then edit:

1. **Read the tool's own help** for every subcommand and flag you are about to
   document — `<cmd> --help`, `<cmd> <sub> --help`. Enumerate the FULL
   subcommand list; do not grep for the one you have in mind.
   ⚠️ **A too-narrow search key returns a confident wrong answer.** Grepping
   help for `^\s+start` cannot match `restart`, and "the command doesn't exist"
   is the result. Read the full list unfiltered.
2. **Exercise the behaviour on a THROWAWAY**, never on live state. This is the
   part people skip, and it is the part that settles disagreements between the
   docs, the help text, and a bead.
3. **Read bare exit codes.** Never `$?` after a pipe — it returns the last
   command's status, not the one you care about. Redirect to a file, capture the
   code, then print the file.
4. **Verify effects by re-reading state**, not by trusting a success message.

#### Worked example — the CRUD probe

To document a lifecycle (create / modify / remove) correctly, walk the whole
cycle on a disposable object and record what actually happens at each step:

```
create  -> confirm it exists, capture its ID
stop    -> does the record persist? is the name still held?
update  -> does it work while stopped? while running? which fields changed?
restart -> by name? by ID? is the ID preserved?
delete  -> is the name freed? does recreating give a NEW ID?
```

Then re-read state (`list --all`, `show`) after each step rather than trusting
the printed output. Run a step twice when the result is surprising, to exclude a
fluke.

**Safety rules for the probe, all learned the hard way:**

- Use a **unique throwaway name** that cannot collide with anything real.
- Pick parameters so **nothing actually executes** (a schedule far in the
  future, a match pattern that cannot fire).
- **Enumerate the real objects you must not touch, by name AND ID**, before you
  start.
- **Clean up, and prove it by effect** — then confirm every real object is still
  in its original state.
- Never run the probe against something live to find out whether it is
  destructive. Read the current value first so you have a BEFORE.

### Find every copy before you edit one

Documentation is almost never in one file. A point fix leaves a sibling surface,
and the copies then **contradict each other**, which is worse than one stale
copy because the reader cannot tell which is current.

1. **Grep for a distinctive phrase** from the wrong text across the repo.
2. **Establish which copies are GENERATED and which are SOURCE** before editing
   anything. Look for a sync script, a Makefile target, a generator.
3. **Edit the source; never hand-edit a generated file** and leave the generator
   to silently revert you.
4. **Check for embedded copies.** A file compiled into a binary (`go:embed`) is
   **deploy-gated**: your edit is inert until a binary carrying it ships. Say so
   explicitly in your report — otherwise the fix reads as live when it is not.
5. **Re-assert the sync invariant afterwards** (e.g. the copies are
   byte-identical) with a control that could have failed.

### 🔴 NEVER RUN A SYNC SCRIPT TO PROPAGATE YOUR FIX — USE A SUB-AGENT TO MIRROR

A repo with a source dir and a synced dir will have a script that regenerates
the target. **Running it is the single most destructive thing you can do in a
doc fix**, and it looks like the correct, sanctioned move.

**Propagate with a SUB-AGENT that mirrors your specific change into each copy,
not with the script.** A sub-agent copies the hunks you name and leaves
everything else alone; the script rewrites whole files from one side. The
sub-agent cannot destroy what it was not asked to touch.

⚠️ **THIS IS NOT LIMITED TO DOCS.** It applies to every sync/generation script
in the repo — skills, plugin assets, templates, generated reference files. Any
script whose job is "make B look like A" will erase anything that exists only in
B. The hazard does not announce itself, and knowing about it is demonstrably not
sufficient to avoid it.

**The trap:** the convention says "author in the source dir, then sync." Reality
is that people edit the target directly too. So the target can hold changes the
source has never seen. A sync run silently overwrites all of them, and the loss
is invisible — the script succeeds, the diff looks like a sync, and nobody can
tell that unrelated work was destroyed.

**The direction rule: THE NEWER CONTENT UPDATES THE OLDER ONE — whichever file
that is.** Not "source always wins." Establish direction by evidence, per
region, before you touch anything:

```
git log -1 --format="%h %ad %s" --date=short -- <source-file>
git log -1 --format="%h %ad %s" --date=short -- <target-file>
git log --format="%h %ad %s" --date=short -- <target-file>   # target-only commits = at risk
```

Then check whether any commit touched the target **without** touching the
source — those are direct edits to the sync target, and they are exactly what a
sync run would erase:

```
git show --stat --format="" <sha> | grep <basename>
```

**Then diff the two and read the drift, do not assume it:**

- Lines present only in the TARGET may be **newer content** (must be preserved,
  and must be ported back to the source) **or merely the OLD version of text the
  source has since corrected** (safe to overwrite). **These look identical in a
  diff.** Read the content and decide; never infer from position.
- If the drift is large, **do not regenerate.** Port only the hunks you are
  fixing, byte-identical, and leave every unrelated difference untouched.
- **Prove you did not over-sync:** count the non-target differences before and
  after your edit. The count must be unchanged.

**Prefer a targeted mirror over a full regeneration, always.** A targeted mirror
can only damage the region you are editing; a regeneration can damage anything.

⚠️ Sync scripts commonly also invoke formatters (prettier, markdownlint,
`gofmt -w`, `golangci-lint --fix`). Those are **write-capable**. Check what the
script actually invokes before running it, and treat any `--fix`/`-w` target as
a mutator.

### State only what you measured

When correcting a false claim, **do not replace it with another unverified
one.** A doc sentence often bundles a measured half and an untested half:

> "Stopping removes it from persistence — it won't respawn on restart."

If you measured the first half false and never tested the second, **drop the
untested clause entirely** rather than asserting it in either direction. If you
cannot phrase the correction without implying something untested, say so in your
report instead of guessing.

**A confident wrong correction propagates harder than the error it replaces**,
because it presents as the output of checking and therefore reads as already
scrutinised.

### When NOT to fix it yourself

Escalate for someone else's **authority**, never for your own **willingness**:

- The correct behaviour is **genuinely unknown** and cannot be settled by
  observation — that is a product question, not a doc fix.
- The doc is right and **the code is wrong**. Fixing the doc would document a
  bug as intended behaviour. File the code defect and leave the doc alone.
- Fixing it requires a **product decision** (which of two behaviours is
  intended).
- The doc states a **policy or ruling** owned by someone else.

In every one of those, the doc edit is not the fix. Everything else, you fix.

### Close the loop

After the edit:

1. **File a bead recording what you fixed** — the defect, the files, and how you
   verified. This is a record, not a request.
2. **Report the deploy-gating status** if any copy is embedded or generated.
3. **Name what you did NOT fix** — a sixth copy you found, an untested claim you
   dropped, a help-text defect outside your scope. An unnamed remainder is how
   the next person inherits a "fixed" area that is still wrong.
