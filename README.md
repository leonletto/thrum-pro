# Thrum Pro

**The distribution point for the Thrum Pro plugin.**

Thrum Pro is a multi-agent coordination system for AI coding assistants. It lets a
fleet of agents — coordinators, implementers, researchers, orchestrators — message
each other, share memory, track work, and merge code through review gates, all from
inside your existing runtime (Claude Code, Codex, Cursor, OpenCode, Muse Code,
GitHub Copilot CLI, or Antigravity).

This repository is where the **Thrum Pro plugin** lives, so anyone with access can
install it straight from git. The plugin is the client side: skills, commands, agents,
and hooks that run inside your assistant and drive the Thrum daemon.

> **The Thrum binary is distributed separately.** This repo does **not** contain the
> `thrum` binary itself — binary access is provisioned directly by the Thrum Pro team.
> See [Getting the binary](#getting-the-thrum-binary) below.

---

## What's in this repo

Each supported runtime has its own plugin tree at the top level:

| Directory | Runtime |
|-----------|---------|
| `claude-plugin/` | Claude Code |
| `codex-plugin/` | Codex |
| `cursor-plugin/` | Cursor |
| `opencode-plugin/` | OpenCode |
| `claude-plugin/` | GitHub Copilot CLI (shared marketplace payload) |
| `copilot-plugin/` | GitHub Copilot CLI (`thrum-copilot`, loaded by Thrum at agent launch) |

Muse Code discovers and installs Thrum from its marketplace, using the
`codex-plugin/` tree; it has no separate `muse-plugin/` tree in this repository.

Every tree is plain text — skills (`SKILL.md`), slash commands, agent definitions,
and hooks. No binaries. Pick the directory that matches your assistant and follow the
matching section below.

---

## Installing the plugin

Every plugin talks to the `thrum` CLI on your `PATH`. This repo ships plugin text
only — no `thrum` binary. Install `thrum` first (see
[Getting the Thrum binary](#getting-the-thrum-binary)).

Each runtime installs differently. Full per-runtime detail, including
verification steps, lives in
[`INSTALL.md`](./INSTALL.md).

### Claude Code — install straight from GitHub (no clone)

Claude Code can add this repo as a plugin marketplace directly by URL:

```bash
claude plugin marketplace add leonletto/thrum-pro
claude plugin install thrum@thrum
```

**Updating has two steps** — refresh the marketplace, then update the installed
plugin:

```bash
claude plugin marketplace update thrum
claude plugin update thrum@thrum
```

Then run `/reload-plugins` in each running Claude Code session to load the new
version, or restart Claude Code.

### Codex — install straight from GitHub

```bash
codex plugin marketplace add leonletto/thrum-pro
codex plugin add thrum@thrum-marketplace
```

Update with `codex plugin marketplace upgrade thrum-marketplace`, then repeat
the `codex plugin add` command.

Restart running Codex agents after a plugin update; a running session does not
load the new version, and `/skills reload` does not refresh plugin skills.
Codex refreshes a Git-sourced marketplace and rebuilds its plugin cache at
every launch, so a restart alone picks up a published update. On relaunch,
Codex may also offer to update itself, and after the plugin's hooks change it
asks you to review them ("Hooks need review"); agents launched by Thrum skip
that prompt with `--dangerously-bypass-hook-trust`.

New or updated skills are still available to a running agent before the
restart: asked to use a skill by name, the agent reads the updated skill file.
The skill picker (`$`) lists them only after a restart.

If Codex is logged in with a ChatGPT account, Thrum's default Codex model
(`gpt-6-luna`) is rejected on every turn with HTTP 400 "not supported when
using Codex with a ChatGPT account" (seen with codex-cli 0.163.0). Pin a model
the account supports before launching the agent:

```bash
thrum agent runtime-config set <agent-name> --model gpt-5.6-luna
```

or pass `--model gpt-5.6-luna` to `thrum tmux create` and `thrum tmux launch`.

### GitHub Copilot CLI — install from the marketplace

From a shell:

```bash
copilot plugin marketplace add leonletto/thrum-pro
copilot plugin install thrum@thrum
```

Copilot also exposes these actions inside its CLI:

```text
/plugin marketplace add leonletto/thrum-pro
/plugin install thrum@thrum
/plugin update thrum
/plugin list
```

Refresh the marketplace before updating the installed plugin:

```bash
copilot plugin marketplace update thrum
copilot plugin update thrum
```

After updating, run `/skills reload` in each running Copilot session to load
the updated skills and commands without restarting. Hook changes need a
restart.

Agents that Thrum launches on Copilot also load a small second plugin,
`thrum-copilot`, from `~/.thrum/copilot-plugin` via `--plugin-dir`. Thrum copies
it from the `thrum` binary at each agent launch, so it has no install or update
step of its own; restarting the agent refreshes it. The `copilot-plugin/`
directory in this repository is its source.

### Cursor — install straight from GitHub

```bash
curl https://cursor.com/install -fsS | bash
agent login
agent plugin marketplace add --git-ref main https://github.com/leonletto/thrum-pro.git
agent
```

In Cursor Agent, open `/plugin list`, switch to **Marketplace**, search for
`thrum`, and install it at user or project scope.

If the Claude Code Thrum plugin is also installed on the machine, Cursor Agent
loads that copy too (`/plugin list` shows "thrum (Claude Code)"), next to its
own Cursor install. Update both, then restart each running Cursor Agent
session; a running session does not reload plugins. Update the Claude Code
copy with:

```bash
claude plugin marketplace update thrum
claude plugin update thrum@thrum
```

Update Cursor's own install (the only one on a Cursor-only machine): remove and re-add the marketplace
(`agent plugin marketplace update thrum` keeps the old commit), install `thrum`
again from `/plugin list` → **Marketplace** (re-adding does not reinstall it),
then start a new agent session:

```bash
agent plugin marketplace remove thrum
agent plugin marketplace add https://github.com/leonletto/thrum-pro
```

See [INSTALL.md](INSTALL.md#cursor) for how to check the fetched version.

From an existing clone, install into a project directly:

```bash
./cursor-plugin/local-install.sh --target /path/to/your/project
```

This copies the plugin into `<project>/.cursor/` and writes `.cursor/hooks.json`
with an absolute path back into this repo's `cursor-plugin/` directory — keep the
checkout in place after installing, or re-run the script if you move it.

### OpenCode — install from npm

Install the published [`opencode-thrum-pro`](https://www.npmjs.com/package/opencode-thrum-pro)
package and update the current project's configuration:

```bash
opencode plugin opencode-thrum-pro
```

Use `opencode plugin opencode-thrum-pro --global` for the global configuration.
That command does not update an existing install (OpenCode keeps its cached
copy); see [INSTALL.md](INSTALL.md#opencode) for the update step. A running
OpenCode session does not reload plugins or commands, so restart it after an
update. To configure it manually, add the package to `opencode.json` or
`opencode.jsonc`, in the project or in `~/.config/opencode/`; when both files
exist in one directory, OpenCode reads the plugin list from `opencode.jsonc`.
Validated on OpenCode 1.18.35.

The plugin provides the skills, commands, and hooks. To use Thrum's coordination
tooling (messaging, memory, state) you also need to wire the `thrum` MCP server,
which requires the `thrum` binary on your `PATH`. Add both the `plugin` entry and
the `mcp.thrum` block:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["opencode-thrum-pro"],
  "mcp": {
    "thrum": {
      "type": "local",
      "command": ["thrum", "mcp", "serve"],
      "enabled": true
    }
  }
}
```

Local-repo fallback:

OpenCode loads the plugin as a Node package, so build it once:

```bash
cd opencode-plugin
npm install
npm run build
```

Then reference it as a local `file:` plugin in your project's `opencode.json`
(or the global one in `~/.config/opencode/`):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["file:///path/to/thrum-pro/opencode-plugin"]
}
```

OpenCode has no launch flag for reasoning effort, so the current release ignores `--effort`
for OpenCode agents. Choose the effort inside OpenCode by picking the model
variant.

### Muse — install with Muse's native plugin system

Muse has its own plugin system and marketplace — it does **not** use the Claude Code
marketplace. It installs the same Thrum plugin through Muse-native commands, so there
is no separate Muse plugin to build.

Prerequisites: the `muse` binary (validated on `1.4.0-R4161.1`, `1.4.2-R4684.1`, `1.4.6-R6000.1` and `1.4.11`), a
Muse account, and the `thrum` binary on your `PATH`. Run these as the same OS user
that runs your agents.

1. Add the marketplace and install the plugin:

   ```bash
   muse plugins marketplace add leonletto leonletto/thrum-pro
   muse plugins install thrum@leonletto
   ```

   If a `muse plugins` command reports `plugins are not available in this build`,
   set `MUSE_EXPERIMENTAL_PLUGINS=1` in the environment that runs Muse, then retry.

2. Approve Thrum's current runtime capabilities. This plugin-level form covers every
   hook, including hooks introduced by a future plugin update:

   ```bash
   muse plugins approve thrum
   ```

   Run the command again after every Thrum plugin update. Use
   `muse plugins inspect thrum --json` to review the current capability status.

3. On first run, Muse asks *"Do you trust the files in this folder?"* — priming is
   blocked until you dismiss it. Muse launches Thrum worktrees with
   `--disable-sandbox --trust-workspace`.

To update, refresh the marketplace, then remove the plugin, install it again and
re-approve it. Do not rely on `muse plugins update thrum`: depending on the Muse
version it either fails with an error or reports success without changing the
installed version.

```bash
muse plugins marketplace update leonletto
muse plugins remove thrum
muse plugins install thrum@leonletto
muse plugins approve thrum
muse plugins list
```

Then run `/skills reload` in each running Muse session to load the updated
skills without restarting. Hook changes still need a restart.

An MCP config at `.muse/mcp.json` is optional (advanced use); basic operation primes
through the `SessionStart` hook without it.

### Antigravity — install the Claude Code plugin

Antigravity (`agy`) installs the Claude Code plugin and converts it. Install it
from the `claude-plugin` folder of this repository:

```bash
agy plugin install https://github.com/leonletto/thrum-pro/tree/main/claude-plugin
agy plugin list
```

`agy plugin list` must show `thrum` as enabled. From a local clone, use
`agy plugin install /path/to/thrum-pro/claude-plugin` instead.

To update, run the same install command again. Then, in each running `agy`
session, run `/skills reload` to load the updated skills and commands without
restarting. Hook changes need a restart of `agy`.

The conversion keeps the skills, the agent and the commands, and skips MCP.
Type `/thrum:prime` after starting an agent. Add the MCP server with
`agy mcp add` if you want it.

Install from the `claude-plugin` URL above, not from the repository root:
the root URL (and the `.git#claude-plugin` form) also installs the Copilot
payload as a second plugin, `thrum-copilot`. If that happened, remove it with
`agy plugin uninstall thrum-copilot`. `agy` 1.4.2 and 1.4.5 support only their official
marketplace, so `thrum@thrum` and `agy plugin link` fail with
"unknown marketplace". `agy plugin validate claude-plugin` also fails; that is
expected, because install converts the plugin.
Validated on `agy` 1.4.2 and 1.4.5.

---

## Getting the Thrum binary

The plugin drives the `thrum` daemon/CLI. That binary is a Thrum Pro product and is
**not** distributed from this public repo — access is provisioned directly by the
Thrum Pro team. Contact **leon@thrum.team** for access.

Once you have the binary installed and on your `PATH`, verify it:

```bash
thrum --version
thrum daemon status
```

Then register your first agent and load context — see the plugin's own quickstart
(`thrum quickstart` / the `quickstart` skill) after install.

---

## Usage

Once the plugin and binary are installed, Thrum lets your agents:

- Register + start a session
- Send and receive messages between agents
- Track work with tasks
- Coordinate merges through review gates

Full command and configuration reference ships inside the plugin.

---

## Referenced plugins

The Thrum Pro plugin *references* several third-party plugins for interoperability
— it names them and expects them to be installed, but does **not** bundle or
redistribute their code. Install each from its own source; each remains under its
own license:

| Plugin | Author | License | Source |
|--------|--------|---------|--------|
| superpowers (brainstorming, writing-plans, TDD, …) | obra / Jesse Vincent | MIT | https://github.com/obra/superpowers |
| episodic-memory | obra / Jesse Vincent | MIT | https://github.com/obra/episodic-memory |
| ralph-loop | Anthropic | Apache-2.0 | https://github.com/anthropics/claude-plugins-official |
| frontend-design | Anthropic | Apache-2.0 | https://github.com/anthropics/claude-plugins-official |
| claude-code-setup | Anthropic | Apache-2.0 | https://github.com/anthropics/claude-plugins-official |

---

## License

The Thrum Pro plugin in this repository is licensed under the
[Apache License 2.0](./LICENSE). See [`NOTICE`](./NOTICE) for attribution.

The **Thrum Pro binary** is a separate commercial product and is **not** covered
by this license — see [Getting the Thrum binary](#getting-the-thrum-binary). Its use
is governed by the [Thrum EULA](https://my.thrum.team/legal/eula),
the [Terms of Service](https://my.thrum.team/legal/terms) and the
[Privacy Policy](https://my.thrum.team/legal/privacy).

---

## Support

Thrum Pro is a commercial product. For binary access, licensing, or support, contact
the Thrum Pro team at **leon@thrum.team**.
