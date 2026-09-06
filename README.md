# Thrum Pro

**The distribution point for the Thrum Pro plugin.**

Thrum Pro is a multi-agent coordination system for AI coding assistants. It lets a
fleet of agents — coordinators, implementers, researchers, orchestrators — message
each other, share memory, track work, and merge code through review gates, all from
inside your existing runtime (Claude Code, Codex, Cursor, OpenCode, or GitHub
Copilot CLI).

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

**Updating is one command** — Claude Code re-pulls the repo's latest commit:

```bash
claude plugin marketplace update thrum
```

### Codex — install straight from GitHub

```bash
codex plugin marketplace add leonletto/thrum-pro
codex plugin add thrum@thrum-marketplace
```

Update with `codex plugin marketplace upgrade thrum-marketplace`, then repeat
the `codex plugin add` command.

### GitHub Copilot CLI — built into the Thrum binary (no plugin install)

Unlike the other runtimes, the GitHub Copilot plugin is **embedded in the `thrum`
binary** and installed automatically the first time you launch a Copilot runtime —
there is no marketplace or manual plugin-install step.

1. Install the GitHub Copilot CLI so `copilot` is on your `PATH`:

   ```bash
   npm install -g @github/copilot
   ```

2. Make sure the `thrum` binary is installed (see [Getting the Thrum binary](#getting-the-thrum-binary)).

3. Launch a Copilot runtime — Thrum materializes and wires the plugin for you (via
   its `SessionStart` hook), no further setup:

   ```bash
   thrum tmux create <name> --runtime copilot
   ```

If `copilot` is not found on your `PATH`, Thrum reports the runtime as unavailable
rather than failing mid-launch.

### Cursor — install straight from GitHub

```bash
curl https://cursor.com/install -fsS | bash
agent login
agent plugin marketplace add --git-ref main https://github.com/leonletto/thrum-pro.git
agent
```

In Cursor Agent, open `/plugin list`, switch to **Marketplace**, search for
`thrum`, and install it at user or project scope. Update the marketplace with
`agent plugin marketplace update thrum`.

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
To configure it manually, add the package to `opencode.json` (or the global
`~/.config/opencode/opencode.jsonc`).

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
(or global `~/.config/opencode/opencode.json`):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["file:/path/to/thrum-pro/opencode-plugin"]
}
```

### Muse — install with Muse's native plugin system

Muse has its own plugin system and marketplace — it does **not** use the Claude Code
marketplace. It installs the same Thrum plugin through Muse-native commands, so there
is no separate Muse plugin to build.

Prerequisites: the `muse` binary **1.0.3 or newer** (validated on `1.0.3-R2198.1`), a
Muse account, and the `thrum` binary on your `PATH`. Run these as the same OS user
that runs your agents.

1. Add the marketplace and install the plugin:

   ```bash
   muse plugins marketplace add leonletto leonletto/thrum-pro
   muse plugins install thrum@leonletto
   ```

2. Approve the four Thrum hooks. Append `--json` for headless / non-interactive use
   (there is no `--yes` bypass — `--json` is the headless form):

   ```bash
   muse plugins approve plugin:thrum:hook:hook-603847d5ede54d44   # SessionStart prime
   muse plugins approve plugin:thrum:hook:hook-9adcbbd425e3aba1   # Stop / inbox check
   muse plugins approve plugin:thrum:hook:hook-b539dd5f1e491a55
   muse plugins approve plugin:thrum:hook:hook-deb9e6678ddeeb86
   ```

   **Re-approve after every Thrum plugin update.** Approvals pin a content hash; when
   the plugin changes they drop back to `review_needed` and the agent starts up
   **silently unprimed** until you re-approve.

3. On first run, Muse asks *"Do you trust the files in this folder?"* — priming is
   blocked until you dismiss it. Muse launches Thrum worktrees with
   `--disable-sandbox --trust-workspace`.

An MCP config at `.muse/mcp.json` is optional (advanced use); basic operation primes
through the `SessionStart` hook without it.

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
by this license — see [Getting the Thrum binary](#getting-the-thrum-binary).

---

## Support

Thrum Pro is a commercial product. For binary access, licensing, or support, contact
the Thrum Pro team at **leon@thrum.team**.
