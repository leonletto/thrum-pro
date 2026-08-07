---
name: closing-findings-while-warm
description: "Use whenever you are about to defer a finding, fix, or cleanup instead of doing it now - proposing a follow-up bead/issue/ticket, catching a sibling defect while wrapping up, feeling something is 'out of scope', or wanting to reach DONE faster. Also use on the manager side, when reviewing a completion report that proposes a deferral. Illustrative (non-exhaustive) phrasing that should trigger this - 'I'll file a follow-up', 'filing this as a P2', 'out of scope for now', 'tracked in a new bead', 'we can pick this up later', 'fast-follow', 'separate PR' - but the trigger is the ACT of deferring, not matching one of these exact phrases."
---

# Closing Findings While Warm

## The defect this skill fixes

An implementer mid-fix notices a sibling defect, or a reviewer flags a finding
during a review cycle. The cheap move is to write it down and move on: file a
bead, note "P2 fast-follow" in the report, close out DONE. That paper trail
looks like closure but frequently isn't — the bead never gets created, the
context that made the fix cheap (the file open, the failure mode fresh in
mind) is gone by the time anyone looks at it again, and "tracked" quietly
becomes "dropped."

**"A deferral's paper trail is not self-verifying."**

## Role-differentiated resolution

The trigger is the same for every role — a finding just surfaced and someone
is about to defer it. The correct response differs by who is speaking.

### Implementer: surface, don't self-authorize

An implementer who notices a finding should **surface it to whoever
dispatched them, while still warm, with the shape of the fix** — what's
broken, why, and roughly what the fix looks like. Do NOT go fix it
unilaterally, and do NOT unilaterally decide it's out of scope and drop it.

This is not a failure mode to train out. An implementer proposing a
follow-up is **correct subordinate behavior** — implementers do not own
scope, the dispatcher does. The defect this skill targets is never "the
implementer proposed a deferral instead of just fixing it." Surfacing with
the fix's shape and stopping there is the right move.

### Manager tier: you make the call, default is fix-now

Whoever dispatched the implementer — orchestrator or coordinator, whichever
tier is currently managing that thread — owns the fix-now-vs-defer decision.
The default is: **direct the fix now, while the expert is still warm.**
Re-dispatching later means re-loading context that's about to evaporate, plus
a second review cycle, plus a live bead to track in the meantime.

If you're a manager-tier reader of this skill reaching for "just tell the
implementer to go fix it themselves" as the resolution here — stop. That
phrasing is the exact defect this skill was written to close out. An
implementer does not self-authorize scope expansion; only the dispatcher
directs it. Writing "just go fix it" without you actually making and owning
that call is exactly the anti-pattern this design pass amended. It will fail
review.

Only defer when the legitimate-deferral bar below is fully met — and even
then, the deferral isn't done until its bead is verified to exist.

**Recipient duty, not just reporter duty:** before accepting any deferral,
independently run `bd show <id>` yourself — do not trust the reporter's
self-attestation that a bead was filed and confirmed. A cited bead ID is not
evidence until the RECIPIENT, not the reporter, has confirmed it resolves.

## Legitimate-deferral bar (narrow — do not let this become a rubber stamp)

A deferral is legitimate only when **all three** hold:

**(a) Genuine independence.** The finding touches a genuinely different
subsystem with no intersection with the current branch's diff, OR the fix is
blocked on an external dependency (another team's merge, an upstream release,
a design decision not yet made). "I'd rather not right now" is not
independence.

**(b) Named assignee and a dispatch date.** Not "someone will pick this up" —
a specific agent or person, and when it will be dispatched. An unowned
deferral is a deferral to nobody.

**(c) The bead exists, verified.** Create the bead, then run `bd show <id>`
and echo the ID back in your report. A deferral is not closed by the
intention to file a bead — it is closed by the bead existing and being
confirmed to exist. "I'll file a follow-up" is a promise; `bd show thrum-xyz`
returning the issue is evidence.

If any of (a)/(b)/(c) is missing, it is not a legitimate deferral — direct
the fix now instead.

## Worked example: the bead that wasn't there

During the .17 wedge-fix session, the fix split `redact.JSON`'s out-of-lock
move out as a "P2 fast-follow" — the report said so, the restart snapshot
recorded `(bead filed)` as settled fact, and the coordinator carried that
fact forward across a restart. Nobody ran `bd show` against the ID before
trusting it. The bead was never actually created. The finding sat as a
sentence in a snapshot file, not as tracked work, until it was rediscovered
independently. The paper trail read as closure; it wasn't.

This is the failure mode part (c) exists to close: verify existence with the
tool that can prove it, not by trusting the sentence that claims it.

## Project-specific rules (already loaded)

Project-local rules of kind `agent_rule` at `--scope role` were loaded at
session start by your preamble (see your role template's Memory model block).
If a project-local rule conflicts with a universal rule above, the
project-local rule wins; surface the conflict in your reply so the user can
decide whether to graduate or remove the override.

If you accumulate a new rule mid-session (the user corrects you), capture it
via the `implementer-maintaining-memory` skill (or `coordinator-maintaining-
memory` if you're operating in a manager tier) — it references the
`memory-write-discipline` common for the canonical `thrum memory create`
shape.
