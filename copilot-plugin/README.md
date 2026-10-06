# Thrum for GitHub Copilot CLI

Session-context delivery for GitHub Copilot CLI via the typed-prime path
(exactly one prime, same briefing other runtimes get).

## What it does

Copilot CLI is a typed-prime runtime: the prime arrives typed, not through a
sessionStart hook. `hooks.json` is therefore intentionally empty, and this
tree declares no hooks.

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
- `hooks.json` — intentionally `{"hooks": {}}`: the tree declares an
  intentionally empty hooks manifest (no hooks; see above)
- `scripts/session-start.sh` — currently unused. It documents a measured
  plugin-declared hook wire contract in its header, but nothing invokes it
  while `hooks.json` is empty. Retained until removal is proved safe across
  embed/staging (the staged-tree manifest covers this file).

## Security

Session-context output never echoes secrets, API keys, or tokens — it only
emits the session-context briefing.
