---
name: brainstormer-dashboard-needs
description:
  "Use when running as a brainstormer or researcher whose steward/coordinator
  publishes NEEDs to the human via a dashboard board — author NEEDs as
  answerable action-picks, consume routed ANSWERS from dashboard results, and
  keep the board's view of your question in sync with reality."
# source: claude-plugin/skills/brainstormer-dashboard-needs/SKILL.md
# generated-by: scripts/sync-skills.sh
---

## Brainstormer/researcher: NEEDs on the dashboard

When your steward or coordinator runs a dashboard board for the human (the
steward-console pattern), your NEED travels as an **action-pick widget** the
human answers by clicking. This is a thin overlay on `using-the-dashboard`
(invoke it first for the CLI contract and the honesty table) and on the
queue-aware pattern you already run — same discipline, new surface: the question
leaves your hands as a structured pick, and the answer comes back as a routed
ANSWER message, exactly as before.

### Authoring a NEED for the board

Send your steward the NEED in board-ready shape — question, 2-3 discrete options
with one-line consequences, and what nuance the human might add:

```text
NEED [topic]: Does X count deleted agents' messages?
  A) Live-only — deleted history can't manufacture recency (no migration)
  B) Include deleted — needs a new (agent_id, created_at) index
  allow_text: yes (owner usually adds "but weigh X")
  context: blocks gap-analysis step 3
```

Rules with teeth:

- **Discrete options or no board.** If the NEED is genuinely open-form, say so —
  the pick is for choices, not for open essays.
- **One NEED, one pick.** Split multi-part rulings.
- **Say what it blocks.** The human triages by consequence.

### Consuming the ANSWER

The routed ANSWER arrives as a message (steward-relayed, owner's words — pick
plus typed nuance) and the board flips your question to ANSWERED. Your job:

1. Fold the answer into the design exactly as you would a terminal relay.
2. If the ANSWER changes the board's framing (follow-up question), author the
   follow-up as a NEW pick — don't mutate the answered one's meaning.
3. Never re-ask an ANSWERED question; `thrum dashboard show` marks it ANSWERED,
   and the durable record is the answer MESSAGE.

Note: if nothing has been posted for you yet, `dashboard show`/`get` return
`found: false` with an empty envelope, not an error — don't read that as a
failure.

### Honesty (same table as the commons)

While E4 (answer round-trip) is NOT landed, board picks cannot be answered in
the UI — your NEED still routes via the steward/message channel exactly as
`brainstorm-queue-aware` prescribes. The board-shaped authoring above is the
format to keep using so the transition is seamless when E4 lands. Until then, a
board is rehearsal surface only: never assume the human saw a widget.

### Refs to other skills

- `using-the-dashboard` — surface + CLI contract + honesty table (invoke first)
- `brainstorm-queue-aware` — the steward NEED/ANSWER loop this overlays
