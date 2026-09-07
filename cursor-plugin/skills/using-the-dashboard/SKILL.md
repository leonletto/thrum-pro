---
name: using-the-dashboard
description: "Use when you want to present an interactive board to the human user (status, options, NEEDs with A/B/C picks), or when you see a dashboard mention and wonder what is actually usable today. Carries the CLI surface, the write/read discipline, and the live-vs-coming honesty table."
---

# Using the Agent Dashboard

The Dashboard is an agent's way to put an **interactive board** in front of the
human user: typed widgets (status rows, cards, lists), optional HTML regions,
and **action-picks the user answers by clicking an option and optionally typing
nuance**. It replaces the "agent runs a TUI" pattern — it is out-of-band from
the messaging channel, so it never blocks messages and answers never scroll
away.

This is the COMMONS skill: role-agnostic surface + discipline. Role overlays
(`coordinator-dashboard-human-loop`, `brainstormer-dashboard-needs`) add the
role-specific loop on top. When an overlay and this skill conflict, the overlay
wins for role-specific behavior.

## 🔴 Honesty table — what is usable TODAY

Check this BEFORE you promise the human anything. Stale promises are worse
than no dashboard.

| Capability | Status |
|---|---|
| `dashboard.set/get/show/clear/delete` RPCs (daemon-side) | **LANDED** on trunk (merge `6c7539236f83`); usable only against daemons BUILT after that merge — verify your daemon's build before relying on the RPCs |
| `thrum dashboard` CLI (set/show/get/update/delete/clear/results) | **LANDED** on trunk (merge `108511a0`); usable only against a `thrum` binary BUILT after that merge — verify your CLI's build before relying on these commands |
| Web UI Dashboard tab (where the human SEES a board) | **BUILT, NOT YET DEPLOYED** (E3 landed on trunk, merge `49712f87` — visible after the next deploy) |
| Answer round-trip (user clicks → message + nudge to you) | **BUILT, NOT YET DEPLOYED** (E4 landed on trunk, merge `ea95318a` — visible after the next deploy) |

**Consequence until the next deploy carries E3 and E4:** publishing a board
is STILL a no-op for the human on any box running a pre-E3/pre-E4 binary —
it renders NOWHERE there and, even where it renders, an answer cannot
return to you, even though the UI and answer-round-trip code now both exist
on trunk. Do NOT substitute a dashboard for a nudge or a direct message
unless you know the box you're talking to has deployed a build containing
BOTH E3 and E4. If the human cannot see the board or their answer cannot
reach you, the question DOES disappear — the exact failure the dashboard
exists to kill.

**Consequence, now that E2 has landed:** the `thrum dashboard ...` command
shapes below are runnable — but, per the E2 row above, only against a CLI
binary built after `108511a0`. Against an older binary, or if you're
calling the daemon directly, the raw RPCs (`dashboard.set` etc. over the
daemon socket) remain the fallback surface.

## The board model

A dashboard is ONE structured document per agent: an envelope
`{v, agent_id, title, updated_at, rev, widgets[]}`. Six widget types:
`section` (labeled grouping), `stat-row` (label/value pairs),
`card` (title + markdown body), `list` (ordered rows),
`action-pick` (question + options + optional text — the interactive control),
`html` (sanitized rich region, authored from a FILE).

Semantics that matter to you as an author:

- **Append-only + rev'd.** Every change appends a new snapshot; `rev` increments.
  Your `update` keeps a widget's position; `delete` removes it; `clear` wipes
  the board. Cleared/deleted content is **GONE** — the board is ephemeral, and
  the DURABLE record of any decision is the answer MESSAGES, not the board.
- **Widget cardinality (enforced):** action-pick ≤8, html ≤4, section ≤8,
  card ≤24, stat-row ≤12, list ≤4, total ≤64. Lists have NO row cap.
- **Answer path:** when the user answers an action-pick, you get a **nudge**
  and the answer lands as a thrum MESSAGE (payload type `dashboard.answer`,
  carrying `question_id`, the option `pick`, optional `text`). You read
  answers with `thrum dashboard results`, then flip the widget's status via
  `thrum dashboard update` so the board shows it resolved.
- **User deletes are SILENT.** If a widget you posted disappears, the user
  dismissed it — you are NOT nudged. Notice it on your next `show`; do not
  repost it reflexively (the user saw it and removed it on purpose).
- **No dashboard yet is not an error.** `dashboard.get`/`dashboard.show`
  succeed with `found: false` and an empty envelope when nothing has been
  posted for you yet — do not treat that as a failure to recover from.
- **Concurrent writes are guarded by `expected_rev`, not merged.** If you pass
  `expected_rev` and it no longer matches the board's current `rev`, the write
  is rejected with `dashboard changed (rev %d, you expected %d) — re-read with
  dashboard show and resubmit`. Fix: re-fetch the current document and
  resubmit with the fresh `rev`. Omitting `expected_rev` skips the check
  entirely (last-writer-wins) — fine for your own solo edits, risky if
  something else writes the same board.

## CLI surface (runnable now, against a `thrum` binary built after `108511a0`)

```bash
# Publish/replace whole widgets (upsert by widget id — targets update in place)
cat > /tmp/board.md <<'EOF'
{"title": "My board", "widgets": [ ... ]}
EOF
thrum dashboard set --doc-file /tmp/board.md
thrum dashboard set --stdin < /tmp/board.md

# HTML regions come from FILES ONLY — never inline (backticks in shell strings EXECUTE)
thrum dashboard set --html-file /tmp/panel.html --html-id my-panel

# Read
thrum dashboard show                 # compact outline: what's on the board, what's PENDING/ANSWERED
thrum dashboard get <widget-id>      # full widget JSON
thrum dashboard results              # user answers (after your nudge), newest N selected, displayed oldest-first
thrum dashboard results --unanswered # only questions with no answer yet

# Mutate
thrum dashboard update <widget-id> --doc-file /tmp/new-widget.json   # in place, keeps position
thrum dashboard delete <widget-id>
thrum dashboard clear                # wipe the whole board (content is GONE)
```

**Validation loop:** `set`/`update` either print `posted OK (rev N)` or fail
with one of three error shapes: a per-widget schema error naming the exact
widget id + field; a per-type cardinality error naming the widget TYPE + count
(e.g. "too many action-pick widgets: 9 (max 8)"); or the aggregate/total-cap
error, which names a CATEGORY TOKEN + count + max rather than a widget type
(e.g. "too many widgets (total_widgets): 65 (max 64)" — "total_widgets" is the
violation category, not a widget type: the per-type limits sum to 60 < 64, so
a doc breaching 64 always breaches some per-type limit too, and there is no
single offending widget type to name). On any of these: fix the file and
resubmit — do not recompute the whole board inside one invocation.

**Authoring rules with teeth:**

- Widget `id`s are load-bearing — stable across updates; `update`/`delete`
  and the answer join key off them (action-picks also carry `question_id`).
- Text fields render as MARKDOWN (no raw HTML — that is the `html` widget's
  job, sanitized). Keep compact fields single-line.
- HTML files: no script/style/iframe/event-handlers — the render side strips
  them, but author clean anyway.

## When to reach for the dashboard (vs a nudge vs a message)

- **Dashboard:** state the human will consume VISUALLY and possibly answer
  interactively — rosters, queues of options, pipelines, NEEDs with discrete
  choices. Persistent board the human checks on their own rhythm.
- **Nudge:** something needs attention NOW and is small (one line). The
  dashboard does not pulse or blink; urgent + tiny = nudge.
- **Message:** conversation, anything needing prose back-and-forth, or anything
  the record must keep forever (decisions live in messages).

Anti-pattern: posting a board INSTEAD of answering a direct question. The
dashboard is a surface you maintain, not a replacement for talking.

## Refs to other skills

- `coordinator-dashboard-human-loop` — coordinator overlay: owning a board for
  the human, the human-loop mandate
- `brainstormer-dashboard-needs` — brainstormer/researcher overlay: authoring
  NEEDs as answerable action-picks
- `using-the-queue`, `using-thrum-state` — sibling agent-tied local surfaces
