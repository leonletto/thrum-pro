---
name: researcher-answering-queries
description: "Use when another agent has asked you a research question, when fielding a research request, or when responding to a query. Loads the lookup-and-respond protocol so cached findings get reused before fresh investigation starts."
---

# Researcher: Answering Queries

## Reconcile your queue first

Lift this query into a bundle (`thrum queue add --from-message <msg-id>`),
then `thrum queue start <bundle-id>`; drop/close finished bundles. Full
lifecycle: `using-the-queue`.

## Lookup order: index → thrum memory → staleness check → respond

**Why:** A query that's already been answered shouldn't trigger a fresh
investigation. The cached `research_note` entries (tagged `research-<slug>`)
exist precisely so repeat questions resolve cheaply. Skipping the cache and
re-investigating duplicates effort, burns context, and introduces drift between
the cached entry and the new answer. (Source: spec section "Researcher skills"
row 3 — "Lookup order: (1) check `research.md` index, (2) fetch the cached
memory by slug, (3) verify if stamp is stale, (4) respond".)

**How to apply:** When a query lands, work the steps in order:

1. **Index check.** Read `.thrum/context/research.md`. Does any Tracked Topic
   line look relevant? Note the `research-<slug>` tag handles.
2. **Content fetch.** For each candidate slug, escalate zoom per the shared
   3-step read pattern (`memory-read-discipline`): `thrum memory search --tag
   research-<slug>` returns the matching entry IDs; triage with
   `thrum memory show <id> --zoom short` before fetching the full body with
   `thrum memory show <id> --zoom full`.
3. **Staleness check.** Use the protocol from `researcher-maintaining-memory`:
   `git diff --name-only <stamp-sha> HEAD` filtered by the entry's cited paths.
   If empty, the entry stands. If any cited path appears, re-verify (re-read the
   cited code, refresh the footer with `Verified: <today> @ <new-sha>`) before
   responding.
4. **Respond.** With the certainty level from the section below.

If the index has no relevant entry, the query is fresh-investigation territory —
invoke the `researcher-investigating` skill's discipline instead.

## Structure responses by certainty level

**Why:** A response that conflates "I just verified this against HEAD" with "I'm
pulling this from a stale cached entry" misleads the requester into trusting
outdated state. Calibrated certainty lets the requester decide whether to act
now or ask for re-verification.

**How to apply:** Three response shapes:

- **Verified now.** "<answer>. Verified at HEAD `<sha>`: <evidence>." Use after
  a fresh investigation or a successful staleness re-verify.
- **Cached + stamp.** "<answer>. Cached entry `research-<slug>`, Verified
  `<date>` @ `<stamp-sha>`. Cited paths unchanged in
  `git diff <stamp-sha>..HEAD`." Use when the staleness check returns empty.
- **Unknown / partial.** "I don't have a verified answer for X. The closest
  cached entry is `research-<slug>` (last verified <date>) but it doesn't fully
  cover the question. Want me to investigate?" Use when no entry covers the
  question, or the cached entry only partially addresses it.

Don't fudge by saying "Yes" without a level qualifier. The qualifier costs five
words; the cost of silently propagating stale state is real.

## Point at the slug for follow-up — don't dump the whole entry inline

**Why:** A long cached entry quoted inline burns tokens and clutters the
requester's context. The slug is the durable handle; the requester can
`thrum memory search --tag research-<slug>` + `thrum memory show <id>`
themselves if they want the full body.

**How to apply:** In the response, cite the slug (`research-<slug>`) and a
one-paragraph summary (or the specific sub-fact the requester asked for). If the
requester needs more, they fetch via `thrum memory search --tag research-<slug>`
→ `thrum memory show <id>`. Reserve full quotes for short entries (<5 lines)
where inlining is genuinely cheaper than the round-trip.

## Project-specific rules (already loaded)

Project-local rules of kind `agent_rule` at `--scope role` were loaded at
session start by your preamble (see your role template's Memory model block). If
a project-local rule conflicts with a universal rule above, the project-local
rule wins; surface the conflict in your reply so the user can decide whether to
graduate or remove the override.

If you accumulate a new rule mid-session (the user corrects you), capture it via
the `researcher-maintaining-memory` skill — it references the
`memory-write-discipline` common for the canonical `thrum memory create` shape.

## Pattern D self-write — set `agent_status=idle` on response/DONE (thrum-9neg)

When reporting a research finding back to the requester (or closing a DONE on a
research task), write `agent_status="idle"` to your local identity file. This
closes the `working→idle` transition opened by the ACK protocol in the sibling
skill `researcher-investigating`.

```bash
# Step 1: Report finding back to requester
thrum send --to @<requester> --stdin <<'EOF'
Research <task-id>: <finding>. Evidence: <file:line refs>.
EOF

# Step 2: Mark yourself idle (writes local identity file directly)
thrum agent set-status idle
```

The local-write path is identical to the implementer side
(`cmd/thrum/agent.go:671-690`).
