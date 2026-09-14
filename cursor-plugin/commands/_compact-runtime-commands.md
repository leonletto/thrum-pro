---
description:
  Per-runtime compact-equivalent command table consumed by compact.md,
  compact-extended.md, and scripts/sync-skills.sh. Not user-invocable
  directly.
---

# Per-Runtime Compact Command Table (shared partial)

Consumers: `claude-plugin/commands/compact.md`, `compact-extended.md`
(reference this table for the command each runtime's synced copy sends), and
`scripts/sync-skills.sh`'s `compact_command_for_runtime()` (the executable
mirror of this table — keep the two in lockstep; a row added/changed here
without a matching case in that function is a defect at review, not a style
nit).

This is the canonical, cited source of truth for what "the compact command"
means on each runtime thrum drives. Do NOT invent a command for a runtime not
listed here or not sourced — an unverified guess sent to a runtime's pane is
worse than no compaction at all (it either no-ops or does something
unintended). A runtime found to have no equivalent is recorded as such, not
silently omitted.

| Runtime      | Compact command                 | Source                                                                                                      | Confidence                    |
| ------------ | -------------------------------- | -------------------------------------------------------------------------------------------------------------- | ------------------------------ |
| `claude`     | `/compact`                       | Claude Code built-in slash command (already established in this project).                                       | Verified — first-party.        |
| `codex`      | `/compact`                       | OpenAI Codex CLI context-compaction architecture (server-side `POST /v1/responses/compact`, manual trigger `/compact`). | Verified — corroborated by two independent technical write-ups; not fetched from `codex --help` directly. |
| `opencode`   | `/compact` (alias `/summarize`)  | opencode.ai official docs, keybinds reference — `session_compact` action, default slash command `/compact`.     | Verified from official docs. **Caveat:** a differently-named community fork lacks this command — confirm against the specific `opencode` binary before relying on it blindly. |
| `cursor`     | `/summarize` (alias `/compress`) | cursor.com CLI reference, slash-commands page.                                                                   | Verified from official docs. **Differs from Claude's `/compact`** — this is the one runtime where the sent text must actually change. `/clear` (aliases `/new`, `/new-chat`) is a separate full-reset command, not compaction — do not confuse the two. |
| `copilot`    | `/compact`                       | docs.github.com, "Managing context in GitHub Copilot CLI".                                                       | Verified from official docs. **Not currently shippable**: `copilot-plugin/` has no skills/commands-loading mechanism at all (pre-existing, documented in `scripts/sync-skills.sh`'s header) — this row exists for completeness/future readiness, not because the skill ships there today. Coverage tracked as a build-vs-accept scope call, owner-owned. |
| `muse`       | **NONE FOUND**                   | musecodes.io official docs — documented commands are `/plan`, `/grill`, `/goal`, `/workflows`, `/model`, `/effort`, `Esc Esc` (rewind), `muse replay`. No manual compact/summarize trigger is documented; marketing copy describing context "compaction" refers to an automatic/internal mechanism only, not a user-invocable command. | Verified absence, not an inferred gap. Per E9 (owner-ruled), muse falls to the `restart-extended` exception — it does not receive compact.md/compact-extended.md. |
| `gemini`     | **UNVERIFIED**                   | Not researched — no plugin tree exists for this runtime, and it was never included in this table's original research pass. | **Not a confirmed negative.** Go-side `internal/runtime.RuntimePreset` exists for this runtime with `CompactCommand` deliberately left empty (falls back to `/thrum:restart-extended`, never invented). This research is not yet done — do not research here; treat future work on this row as owned elsewhere. |
| `kiro-cli`   | **UNVERIFIED**                   | Same as `gemini` — not researched, no plugin tree.                                                              | Same as `gemini` — empty `CompactCommand`, safe fallback, research pending. |
| `amp`        | **UNVERIFIED**                   | Same as `gemini` — not researched, no plugin tree.                                                              | Same as `gemini` — empty `CompactCommand`, safe fallback, research pending. |
| `shell`      | **UNVERIFIED**                   | Same as `gemini` — not researched, no plugin tree.                                                              | Same as `gemini` — empty `CompactCommand`, safe fallback, research pending. |

## Notes

- `codex` and `opencode` resolve to the same literal string Claude uses
  (`/compact`), so their synced copies are a functional no-op substitution —
  still routed through the same mechanism for consistency and so a future
  table change (e.g. if `opencode`'s fork situation resolves differently)
  propagates without a second code path.
- `cursor` is the one runtime whose synced copy's sent command differs from
  Claude's and must be verified after every sync run (`grep` step in
  `scripts/sync-skills.sh`'s `compact_command_for_runtime` block).
- `muse` and `copilot` are both absent from compact/compact-extended's sync
  targets today, for two *different* reasons — `muse` because no native
  command exists to send, `copilot` because the plugin has no delivery
  mechanism at all. Neither is a silent drop: both are recorded here and
  reported in the completion report for this table's original research pass.
- `gemini`/`kiro-cli`/`amp`/`shell` are recorded as **UNVERIFIED**, not
  merged into the `muse`/`copilot` "no equivalent" rows above — those two are
  confirmed negatives (verified by reading official docs); the four
  UNVERIFIED rows are an absence of research, not an absence of a command.
  `scripts/sync-skills.sh`'s `compact_command_for_runtime()` already returns
  `""` for any of these four via its `*` default case, so the executable
  mirror and this table already agree — no code change is needed to keep
  them in lockstep, only this documentation. See also
  `dev-docs/reference/compaction-lifecycle-attach-points.md` for the same
  four runtimes' hook-attach-point status.
