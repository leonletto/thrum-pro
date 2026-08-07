# Thrum Plugin — Install Instructions

This bundle contains the Thrum plugin for four coding-agent runtimes, each in
its own top-level directory:

```text
claude-plugin/
codex-plugin/
cursor-plugin/
opencode-plugin/
```

Each plugin talks to the `thrum` CLI on your `PATH`. This bundle ships plugin
text only — no `thrum` binary. Install `thrum` separately first.

Every command below is written relative to the directory this file lives in
(the bundle root). Run them from there, or substitute the full path to the
extracted bundle.

## Claude Code

```bash
claude plugin marketplace add ./claude-plugin
claude plugin install thrum@thrum
```

Verification steps (run 2026-08-06 against this bundle's build): fresh install
via an isolated `CLAUDE_CONFIG_DIR`, `claude plugin list` reports `thrum@thrum`
installed and enabled. Re-run the same two commands with `CLAUDE_CONFIG_DIR`
pointed at a scratch dir to reproduce.

## Codex

```bash
codex plugin marketplace add ./codex-plugin
codex plugin add thrum@thrum-marketplace
```

Verification steps (run 2026-08-06 against this bundle's build): fresh install
via an isolated `CODEX_HOME`, `codex plugin list` reports
`thrum@thrum-marketplace` installed and enabled. Re-run the same two commands
with `CODEX_HOME` pointed at a scratch dir to reproduce.

To install the Codex skills into `~/.agents/skills` as well (used by some
other runtimes' agents, not required for Codex itself):

```bash
./codex-plugin/plugins/thrum/scripts/install-skills.sh
```

## Cursor

```bash
./cursor-plugin/local-install.sh --target /path/to/your/project
```

This copies the plugin into `<project>/.cursor/` and writes `.cursor/hooks.json`
with an absolute path back into this bundle's `cursor-plugin/` directory — keep
the extracted bundle in place after installing, or re-run the install script if
you move it.

Verification steps (run 2026-08-06 against this bundle's build): fresh install
against a scratch git project populated `.cursor/hooks.json`,
`.cursor/mcp.json`, `.cursor/skills/`, `.cursor/commands/`, `.cursor/agents/`,
and `.cursor/rules/`. Re-run the same command with `--target` pointed at a
scratch project dir to reproduce.

## Open Code

Open Code loads this plugin as a Node package, so it needs to be built once
before use:

```bash
cd opencode-plugin
npm install
npm run build
```

Then add it to your project's `opencode.json` (or global
`~/.config/opencode/opencode.json`) as a local `file:` plugin:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["file:/path/to/this/bundle/opencode-plugin"]
}
```

Verification steps (run 2026-08-06 against this bundle's build): fresh install
via isolated `XDG_CONFIG_HOME`/`XDG_DATA_HOME`/`XDG_CACHE_HOME`, `opencode run`
logged `opencode-thrum v0.3.7 assets installed` and per-skill install lines.
Re-run the same build + `opencode.json` `file:` reference with those three
`XDG_*_HOME` vars pointed at scratch dirs to reproduce.
