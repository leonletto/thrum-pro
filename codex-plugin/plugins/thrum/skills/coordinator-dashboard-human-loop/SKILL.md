---
name: coordinator-dashboard-human-loop
description:
  "Use when the coordinator publishes or maintains a dashboard board FOR the
  human owner (roster, NEED queue, owner decisions, pipeline) or routes owner
  answers from a dashboard back to agents. Loads the human-loop mandate - a
  posted question is a PROMISE — it stays answerable and visible until answered,
  and nothing on the board disappears silently on your side."
# source: claude-plugin/skills/coordinator-dashboard-human-loop/SKILL.md
# generated-by: scripts/sync-skills.sh
---

## Coordinator dashboard: the human loop

You own boards the HUMAN reads — the reference shape is the Brainstorm Steward
console: ① NEED queue (unified, oldest-first, each an action-pick) ② roster
health ③ owner decisions (pending + recently-resolved) ④ pipeline status.
Surface basics live in `using-the-dashboard` — invoke it for the CLI shapes and
the live-vs-coming honesty table. THIS skill carries the loop mandate.

### 🔴 The mandate: posted questions don't disappear until answered

When a board carries a question for the human (an action-pick), that question is
a PROMISE with four parts:

1. **Visible** — it stays on the board (status PENDING) until answered or
   explicitly withdrawn by YOU (update its text to withdrawn, don't just delete
   it).
2. **Answerable** — while E4 is NOT landed, an action-pick cannot actually be
   answered in the UI. Until then, pair every board question with its answering
   channel (the NEED still routes via message/steward as today) and say so on
   the board — never let the human hit a dead control.
3. **Tracked** — check `thrum dashboard results` after every relevant nudge; an
   answer arrives as a message carrying `question_id` + pick + optional text.
   Unread answers + a PENDING widget = you broke the loop.
4. **Closed** — on consuming an answer, `thrum dashboard update <widget-id>` to
   flip that pick's `status` to `resolved` (and log the resolution in your
   decisions list). An answered question that still shows PENDING is the
   coordinator-loop failure mode. If something else wrote the board first, your
   `update` can be rejected as an `expected_rev` mismatch — re-read with
   `dashboard show` and resubmit against the fresh `rev` (see
   `using-the-dashboard`).

### Authoring discipline

- **One question, one action-pick.** Don't bundle three rulings into one widget
  — the human answers picks discretely (that's why pick+optional-text won over
  free-text).
- **Options carry the tradeoff.** Each option's label states the choice AND its
  one-line consequence ("Live-only — no new migration"); the human should not
  need `get` to understand a vote. Set `allow_text: true` — "B, but weigh X" is
  how owners actually answer.
- **Board hygiene is part of the loop.** Stale roster stats and resolved
  pipelines rot the board's credibility; refresh stat-rows when state moves and
  prune sections that no longer serve. The user can delete any widget SILENTLY
  (you are not nudged) — a widget that vanished was seen and dismissed; check
  `show` before reposting.
- **`clear` is a reset, not an archive.** Need history? It lives in the answer
  messages and your memories, not on the board.

### Routing answers

An answer message is routed to the OWNING agent of the question (for steward
consoles: relay to the originating brainstormer, in the owner's words — the pick
plus their typed nuance). Relay the TEXT the human wrote; paraphrasing away
their nuance defeats the optional-text feature.

### Ship gate

The USE-mandate blocks of this skill activate when E3 (web UI tab) + E2 (CLI)
land. Before that, the board renders nowhere — publishing is a daemon-side
rehearsal only, and the mandate sections are inert by the honesty table in
`using-the-dashboard`.

### Refs to other skills

- `using-the-dashboard` — surface + CLI contract + honesty table (invoke first)
- `coordinator-running-brainstorm-cycles` — where board NEEDs come from
- `coordinator-managing-state-and-lifecycle` — state ownership the boards
  reflect
