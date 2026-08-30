# Thrum Plugin — Install Instructions

This bundle contains the Thrum plugin for five coding-agent runtimes. GitHub
Copilot CLI reuses the Claude marketplace payload.

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
claude plugin marketplace add leonletto/thrum-pro
claude plugin install thrum@thrum
claude plugin marketplace update thrum
```

Offline / local-path alternative (no GitHub access needed — points at this
extracted bundle instead of cloning `leonletto/thrum-pro`):

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
codex plugin marketplace add leonletto/thrum-pro
codex plugin add thrum@thrum-marketplace
```

Update with:

```bash
codex plugin marketplace upgrade thrum-marketplace
codex plugin add thrum@thrum-marketplace
```

Verification: `codex plugin list` must report `thrum@thrum-marketplace` as
`installed, enabled`.

To install the Codex skills into `~/.agents/skills` as well (used by some
other runtimes' agents, not required for Codex itself):

```bash
./codex-plugin/plugins/thrum/scripts/install-skills.sh
```

## GitHub Copilot CLI

```bash
copilot plugin marketplace add leonletto/thrum-pro
copilot plugin install thrum@thrum
```

Update with `copilot plugin update thrum`. Verification: `copilot plugin list`
must report `thrum`, and `/skills list` must include the Thrum skills.

## Cursor

Until Thrum is listed in the public Cursor Marketplace, pass this prompt to
Cursor Agent:

```text
Please install the Thrum Cursor plugin by following:
https://github.com/leonletto/thrum-pro/blob/main/cursor-plugin/agent-instructions.md
```

From an existing clone:

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

## OpenCode

After `opencode-thrum-pro` is published to npm, add it to the project or global
configuration. OpenCode installs npm plugins automatically with Bun:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["opencode-thrum-pro"]
}
```

Local-repo fallback:

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

Verification: start OpenCode and confirm its log contains the Thrum asset
installation message and per-skill install lines.
