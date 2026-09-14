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
claude plugin update thrum@thrum
```

Restart Claude Code after updating the plugin.

Offline / local-path alternative (no GitHub access needed — points at this
extracted bundle instead of cloning `leonletto/thrum-pro`):

```bash
claude plugin marketplace add ./claude-plugin
claude plugin install thrum@thrum
```

Verify with `claude plugin list`; `thrum@thrum` must be installed and enabled.

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

Update the marketplace, then the installed plugin:

```bash
copilot plugin marketplace update thrum
copilot plugin update thrum
```

Verification: `copilot plugin list` must report `thrum`, and `/skills list` must
include the Thrum skills.

Inside a Copilot CLI session, the same plugin-management actions are also
available through:

```text
/plugin marketplace add leonletto/thrum-pro
/plugin install thrum@thrum
/plugin update thrum
/plugin list
```

## Muse Code

Muse installs Thrum from its native marketplace; no separate `muse-plugin/`
directory is needed:

```bash
muse plugins marketplace add leonletto leonletto/thrum-pro
muse plugins install thrum@leonletto
```

Approve Thrum's current runtime capabilities, then verify the installation:

```bash
muse plugins approve thrum
muse plugins inspect thrum --json
```

Run the approval command again after every plugin update.

To update the installed plugin:

```bash
muse plugins marketplace update leonletto
muse plugins update thrum
muse plugins approve thrum
```

## Cursor

Install the Cursor Agent CLI, log in, and add this GitHub repository as a
marketplace:

```bash
curl https://cursor.com/install -fsS | bash
agent login
agent plugin marketplace add --git-ref main https://github.com/leonletto/thrum-pro.git
agent
```

In Cursor Agent, open `/plugin list`, switch to **Marketplace**, search for
`thrum`, open its details, and choose user or project scope. Verify that the
plugin is marked installed. Update the repository index with:

```bash
agent plugin marketplace update thrum
```

From an existing clone:

```bash
./cursor-plugin/local-install.sh --target /path/to/your/project
```

This copies the plugin into `<project>/.cursor/` and writes `.cursor/hooks.json`
with an absolute path back into this bundle's `cursor-plugin/` directory — keep
the extracted bundle in place after installing, or re-run the install script if
you move it.

For the local fallback, verify that `.cursor/hooks.json`, `.cursor/mcp.json`,
`.cursor/skills/`, `.cursor/commands/`, `.cursor/agents/`, and `.cursor/rules/`
exist in the target project.

## OpenCode

Install the published package and update the current project's configuration:

```bash
opencode plugin opencode-thrum-pro
```

Use `opencode plugin opencode-thrum-pro --global` for the global configuration.
OpenCode installs npm plugins automatically with Bun. To configure the package
manually, add it to the project or global configuration:

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
