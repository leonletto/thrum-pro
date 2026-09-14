# Thrum for GitHub Copilot CLI

Session-context injection for GitHub Copilot CLI via a `sessionStart` hook.

## What it does

At the start of a Copilot CLI session, `scripts/session-start.sh` runs and
injects Thrum's session-context briefing (identity, project state, inbox,
restart snapshot) — the same briefing Claude Code gets via its own
SessionStart hook.

## How it's loaded

There is no manual install step and no CLI subcommands. `thrum` auto-populates
`~/.thrum/copilot-plugin` (a directory copy of this tree) the first time a
Copilot-runtime agent launches, and the runtime is pointed at it via
`--plugin-dir ~/.thrum/copilot-plugin`. Re-launching an agent re-populates the
directory, so the plugin always tracks the `thrum` binary that launched it —
there is no separate update or uninstall flow to run.

## What it ships

- `plugin.json` — the plugin manifest (`name`, `description`, `version`,
  `license`, `hooks`)
- `hooks.json` — declares the `sessionStart` hook, pointing at
  `scripts/session-start.sh`
- `scripts/session-start.sh` — the hook script itself (must stay executable)

## Security

`scripts/session-start.sh` never echoes secrets, API keys, or tokens — it
only emits the session-context briefing.
