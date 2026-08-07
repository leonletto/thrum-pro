---
name: watcher-model-switcher
description:
  "Use when a watcher agent must fix a dropped or wrong model/effort pin, or
  when a coordinator must set a deliberate model/effort override, by driving
  Claude Code's /model and /effort TUI selectors over thrum tmux - correcting a
  model pin, correcting an effort pin, fixing a tier drift, setting a deliberate
  override, switching model or effort on a live agent's pane. Loads the
  recognize-then-actuate procedure, the confirm-modal and effort-reset hazards,
  the pin_override protocol, and the fail-loud-on-unrecognized-pane rule."
# source: claude-plugin/skills/watcher-model-switcher/SKILL.md
# generated-by: scripts/sync-skills.sh
---

## Watcher: Model/Effort Switcher

### Why (read once — everything after this is the terse per-run procedure)

`/model` and `/effort` are TUI selectors whose interface shifts over time — no
fixed keystroke sequence stays correct, which is why this lives in a
judgment-capable live agent rather than a script or the daemon (thrum-mxwii).
Your judgment surface is narrow — recognize pane state, read the current effort
position — everything else below is arithmetic and protocol, not reasoning.

Two callers use this same procedure: a **watcher**, correcting routine drift,
and a **coordinator**, setting a **deliberate** override. The two are
indistinguishable from the pane — that is why the override-recording half below
is not optional.

⚠️ **Every UI claim below is stamped `Claude Code v2.1.220`** (observed
2026-07-26, isolated `make dev` sandbox, raw tmux driving a real `claude`
process directly — bypassing the daemon RPC entirely, which also sidesteps the
identity-collision path). An earlier draft assumed a vertical Up/Down list; the
real UI is a horizontal slider, Left/Right, six positions. If your version
differs and anything below doesn't match, re-verify against a real pane the same
way before trusting this document — do not assume it still applies, and do not
assume it doesn't.

### Input contract

| Field                             | Required             | Source                                                                                                                                                                                                            |
| --------------------------------- | -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `target_model`, `target_effort`   | yes                  | supplied by your dispatcher                                                                                                                                                                                       |
| `current_model`, `current_effort` | yes (or `"unknown"`) | **no canonical provider exists yet** (thrum-wkof0/thrum-enpkc, in progress) — supplied directly in your dispatch, never self-derived by scraping the pane (that would create a second, competing source of truth) |

### Step 0 — check `pin_override` before touching anything (both callers)

Read `.thrum/agents/<watcher>/watch_params.json`'s `pin_override` field for
`target` (schema: `dev-docs/specs/2026-07-22-watch-params-schema.md`).

| You are...                       | `pin_override` for `target`                         | Do                                                                                                                                                                                                                              |
| -------------------------------- | --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Watcher, routine drift-check     | live (unexpired)                                    | **Skip.** This is deliberate, not drift — do not run the procedure.                                                                                                                                                             |
| Watcher, routine drift-check     | absent or expired                                   | Proceed to Step 1.                                                                                                                                                                                                              |
| Coordinator, deliberate override | any                                                 | Proceed to Step 1, then complete "Recording a deliberate override" below.                                                                                                                                                       |
| Either                           | `watch_params.json` does not exist for this watcher | **STOP. Escalate — do not create the file.** A missing params file means an unprovisioned watcher; manufacturing one to record an override hides that gap. (Real case today: `watcher_coord_zaras` has no `watch_params.json`.) |

### Step 1 — model (reuse existing tooling, do not reimplement)

```bash
thrum tmux model-select <session> <target_model>
```

Already opens via bare `/model` (never `/model <name>`, which jumps straight to
the freeze-prone confirm modal) and already handles the confirm-modal step
(`internal/daemon/rpc/model_select.go`). Error or unrecognized pane → **stop, do
not retry, do not send raw keys** — see "Fail-loud rules."

(`/model`'s own screen shows current effort inline, informationally only —
change effort as its own step below, not from here.)

### Step 2 — effort (recognize → compute → act → verify)

**2a. Recognize.** Open the selector and capture:

```bash
thrum tmux key <session> --type "/effort"
thrum tmux key <session> Enter
thrum tmux capture <session>
```

| Pane shows (v2.1.220)                                                                                                                  | Do                                                                                                                                 |
| -------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Horizontal scale, `▲` marker under one position, `Faster`/`Smarter` headers, footer `←/→ to adjust · Enter to confirm · Esc to cancel` | This is the selector. Record the labels left-to-right (`presented`) and which sits under `▲` (`current`, observed). Proceed to 2b. |
| Confirm/trust dialog (`1. Yes` / `2. No`)                                                                                              | Press the digit next to `Yes` (never blind `Enter`). Re-open `/effort`, re-capture.                                                |
| Usage-limit modal (`❯ Adjust monthly spend limit` / arrow-hint text)                                                                   | `Escape` only — never "wait for the limit to reset" (Leon-ruled). Re-open `/effort`, re-capture.                                   |
| Anything else                                                                                                                          | **STOP** — see "Fail-loud rules."                                                                                                  |

Live example (v2.1.220):

```
                              Faster                                Smarter
──────────▲────────────────────────────────┆──────────────────
low     medium     high     xhigh      max       ultracode
                                             xhigh + workflows
←/→ to adjust · Enter to confirm · Esc to cancel
```

The `┆` before `ultracode` is a visual separator only — confirmed live,
`ultracode` is an ordinary reachable position one `Right` past `max` (4 presses
from `medium` landed exactly there; a 5th did nothing — the scale **clamps, does
not wrap**). **Not every model presents all six** (docs record an earlier Sonnet
build lacking `xhigh`) — use what you actually see:

<!-- CANONICAL_EFFORT_ORDER: low,medium,high,xhigh,max,ultracode -->

(Enforced against `internal/effortselect.CanonicalOrder` by
`TestCanonicalOrder_MatchesSkillDocumentation`, across all three runtime copies
of this file — edit one, edit all, or CI fails.)

**2b. Compute** (mechanical — use `internal/effortselect.Delta`'s logic, don't
reason by hand): same position → 0 presses, done. Target to the right of
`current` in `presented` → that many `Right`. Target to the left → that many
`Left`. `current` unknown/not-found/`presented` empty → **stop, do not press
anything** — see "Fail-loud rules."

**2c. Act, then MANDATORY re-verify before `Enter`:**

```bash
thrum tmux key <session> Right    # or Left — exactly `presses` times
thrum tmux capture <session>      # selector still open — re-verify NOW
```

🔴 **The `▲` must sit EXACTLY under `target_effort`'s label, or stop — never
press more keys to correct it.** This is the last moment effort is verifiable at
all: the slider clamps rather than wraps, so an over-press `Right` lands on
`ultracode` — the most expensive tier — and stays there silently forever (no
verification surface exists after commit); an over-press `Left` clamps cheap but
is equally silent. A second guess would compound a possibly-wrong `current` read
rather than fix it. Match → `Enter`. Mismatch → see "Fail-loud rules."

### Recording a deliberate override (coordinator callers only)

After Steps 1–2 land successfully:

1. Write `pin_override` into `target`'s watcher's `watch_params.json`:
   `{target, model, effort, who, when, why, expires}` — `expires` is
   **mandatory** (same rule as the pre-existing `override` cadence field). Full
   shape: `dev-docs/specs/2026-07-22-watch-params-schema.md`. **Read the whole
   file fresh, modify only `pin_override`, write via temp file + atomic rename —
   never edit in place, never blind-write from a stale read** (same discipline
   as `config.json`/`peers.json`): the watcher polls this file concurrently, and
   a lost or torn write here silently reproduces the exact failure this field
   exists to prevent.
2. **Notify the watcher directly** (message) that the override is recorded — the
   file is authoritative, but a nudge avoids a blind revert in the gap before
   its next read cycle.
3. On `expires`, the record stops being authoritative and the watcher resumes
   normal drift-correction for `target` — an override with no end condition
   becomes permanent, because whoever could retire it no longer remembers why it
   started.

### Fail-loud rules — the only safe failure mode

Guessing a keystroke into an unrecognized screen is how this becomes
destructive. In every case below: **send no further keys, capture the pane
as-is, report back to your dispatcher what you saw, do not retry in a loop.**

- Pane state doesn't match any recognized row (Step 1 or 2a).
- `current_effort` is `"unknown"`/absent, or not found in `presented`.
- Your observed `current` (cursor) disagrees with the dispatched
  `current_effort`.
- The post-press `▲` doesn't sit exactly under `target_effort` (2c).
- `watch_params.json` doesn't exist where a `pin_override` write is needed (Step
  0).
- A usage-limit modal offers "wait for the limit to reset" — `Escape` only.

### Verify by effect

**Model**: PANE POSITION, never `runtime-config get` (stored intent, can't
falsify a dropped pin) and never a content grep spanning the footer's separator
(`Model:` is followed by U+00A0, not ASCII space — `"Model: "` false-zeros;
`"Model:"`, no trailing space, matches). Fixed position, wide capture window,
exclude your own typed command.

**Effort**: **no reliable verification surface after commit.** The standing
footer doesn't show it; `runtime-config get` only reflects an explicit pin
(thrum-wkof0, open). A one-time onboarding tip (`◐ medium · /effort`) was
observed once at fresh session start and gone on the next capture seconds later
— not a standing check. The 2c re-verify (while the selector is still open) is
the only real check available; say plainly there's no check after that, rather
than implying one.
