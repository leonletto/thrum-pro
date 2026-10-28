# Thrum for GitHub Copilot CLI

Session-context delivery for GitHub Copilot CLI via the typed-prime path
(exactly one prime, same briefing other runtimes get).

## What it does

Copilot CLI is a typed-prime runtime: the prime arrives typed, not through a
sessionStart hook, so this tree declares no session-start hook.

It declares one hook: a `postToolUse` memory pointer. After a tool call that
writes a memory file (for example a `memory/*.md`, `AGENTS.md` or `GEMINI.md`),
`scripts/memory-pointer.sh --out additional` returns `{"additionalContext":...}`
pointing the agent at the memory-to-thrum-pointer skill. It reads the tool
payload on stdin, has a 5-second timeout, and fails open: any error exits 0
with no output, so it never blocks an edit.

## How it's loaded

There is no manual install step and no CLI subcommands. `thrum` auto-populates
`~/.thrum/copilot-plugin` (a directory copy of this tree) the first time a
Copilot-runtime agent launches, and the runtime is pointed at it via
`--plugin-dir ~/.thrum/copilot-plugin`. Re-launching an agent re-populates the
directory, so the plugin always tracks the `thrum` binary that launched it —
there is no separate update or uninstall flow to run.

## Installing the Thrum skills and slash commands

The tree above only delivers the memory pointer. The Thrum skills and the
`/thrum:prime` slash command come from the Thrum plugin in the thrum-pro
marketplace, which Copilot CLI installs under `~/.copilot/installed-plugins/`:

```bash
copilot plugin marketplace add leonletto/thrum-pro
copilot plugin install thrum@thrum
```

Update with `copilot plugin marketplace update thrum` and then
`copilot plugin update thrum`. Verify with `copilot plugin list`, which must
report `thrum`, and `/skills list` inside Copilot, which must include the Thrum
skills. A Copilot agent launched by `thrum` types `/thrum:prime`; without this
plugin installed, Copilot answers "Unknown command".

Verification status: these steps are taken from the thrum-pro install notes and
have not been run against a live Copilot CLI. They are unverified.

## What it ships

- `plugin.json` — the plugin manifest (`name`, `description`, `version`,
  `license`, `hooks`)
- `hooks.json` — one `postToolUse` command hook that runs
  `./scripts/memory-pointer.sh --out additional` (see above)
- `scripts/memory-pointer.sh` — the memory pointer hook (shared with the other
  runtimes; nothing in it branches on runtime)
- `scripts/session-start.sh` — currently unused. It documents a measured
  plugin-declared hook wire contract in its header, but `hooks.json` does not
  invoke it. Retained until removal is proved safe across
  embed/staging (the staged-tree manifest covers this file).

## Security

Session-context output never echoes secrets, API keys, or tokens — it only
emits the session-context briefing.
