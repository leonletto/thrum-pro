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

`marketplace update` only refreshes a Git-sourced marketplace. To update a
local-path install, extract the new bundle and re-register its folder:

```bash
claude plugin marketplace remove thrum
claude plugin marketplace add ./claude-plugin
claude plugin install thrum@thrum
```

`marketplace remove` uninstalls the plugin and deletes its saved data, so
avoid it while Claude Code sessions are running.

To switch an existing local-path install to this GitHub repository without
uninstalling it, point the marketplace at GitHub, then update. If
`~/.claude/settings.json` has an `extraKnownMarketplaces.thrum` entry, first
change its value to `{"source":{"source":"github","repo":"leonletto/thrum-pro"}}`;
otherwise `marketplace add` refuses the new source.

```bash
claude plugin marketplace add leonletto/thrum-pro
claude plugin update thrum@thrum
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

`marketplace upgrade` only refreshes a Git-sourced marketplace. If you added
the marketplace from a local folder (`codex plugin marketplace add ./codex-plugin`),
extract the new bundle and re-register its folder instead:

```bash
codex plugin marketplace remove thrum-marketplace
codex plugin marketplace add ./codex-plugin
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

If a `muse plugins` command reports `plugins are not available in this build`,
your Muse build ships plugins behind an experimental flag. Set
`MUSE_EXPERIMENTAL_PLUGINS=1` in the environment that runs Muse, then retry.

Approve Thrum's current runtime capabilities, then verify the installation:

```bash
muse plugins approve thrum
muse plugins inspect thrum --json
```

Run the approval command again after every plugin update.

To update the installed plugin, refresh the marketplace, then remove the
plugin and install it again. On the Muse versions validated so far,
`muse plugins update thrum` reports success but leaves the installed version
unchanged:

```bash
muse plugins marketplace update leonletto
muse plugins remove thrum
muse plugins install thrum@leonletto
muse plugins approve thrum
muse plugins list
```

`muse plugins list` must show the new version. Run the commands while no Muse
session is in the middle of a turn.

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
plugin is marked installed.

To update, remove the marketplace and add it again. Cursor pins the
marketplace to the commit it fetched when it was added, and
`agent plugin marketplace update thrum` re-indexes that same commit even when
it reports success:

```bash
agent plugin marketplace remove thrum
agent plugin marketplace add https://github.com/leonletto/thrum-pro
```

Confirm the fetched version, then open `/plugin` in Cursor Agent and install
or enable `thrum` again (or start a new agent session). A running session keeps
the version it loaded:

```bash
MP=$(find ~/.cursor/plugins/marketplaces/github.com/leonletto/thrum-pro -mindepth 1 -maxdepth 1 -type d | head -1)
python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['version'])" "$MP/cursor-plugin/.cursor-plugin/plugin.json"
```

For a project install from the command line, run the bundled installer from
that clone: `bash "$MP/cursor-plugin/local-install.sh" --target /path/to/project`.

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
  "plugin": ["file:///path/to/this/bundle/opencode-plugin"]
}
```

Updating an existing install:

OpenCode caches an npm plugin the first time it fetches it and does not fetch
it again, so re-running `opencode plugin opencode-thrum-pro` without `-f`
leaves an existing install on its old version. To move to the newest release,
force a reinstall (do not delete the cache directory by hand):

```bash
opencode plugin opencode-thrum-pro --global -f
```

This has to be repeated for each new release, and it covers the global and
every project configuration that names the plugin as `opencode-thrum-pro`.
Confirm the loaded version with:

```bash
opencode debug config --print-logs 2>&1 | grep "assets installed"
```

You can instead pin a version (`"opencode-thrum-pro@0.1.14"` in the `plugin`
array), which is fetched once into its own cache entry. Two things to know if
you pin: when a project configuration and the global one both name the
plugin, the project entry is the one used, and when both `opencode.json` and `opencode.jsonc` exist in the
same directory OpenCode uses the plugin list from `opencode.jsonc`. Put the
entry in the file that is actually read, and check the result with
`opencode debug config`.

Verification: start OpenCode and confirm its log contains the Thrum asset
installation message and per-skill install lines.
