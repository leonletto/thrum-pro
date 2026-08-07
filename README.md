# Thrum Pro

**The distribution point for the Thrum Pro plugin.**

Thrum Pro is a multi-agent coordination system for AI coding assistants. It lets a
fleet of agents — coordinators, implementers, researchers, orchestrators — message
each other, share memory, track work, and merge code through review gates, all from
inside your existing runtime (Claude Code, Codex, Cursor, or OpenCode).

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

Every tree is plain text — skills (`SKILL.md`), slash commands, agent definitions,
and hooks. No binaries. Pick the directory that matches your assistant and follow the
matching section below.

---

## Installing the plugin

First, clone this repo — every command below is run relative to it:

```bash
git clone https://github.com/leonletto/thrum-pro.git
cd thrum-pro
```

Each plugin talks to the `thrum` CLI on your `PATH`. This repo ships plugin text
only — no `thrum` binary. Install `thrum` first (see
[Getting the Thrum binary](#getting-the-thrum-binary)).

Full per-runtime detail — including verification steps — lives in
[`INSTALL.md`](./INSTALL.md). The core steps:

### Claude Code

```bash
claude plugin marketplace add ./claude-plugin
claude plugin install thrum@thrum
```

### Codex

```bash
codex plugin marketplace add ./codex-plugin
codex plugin add thrum@thrum-marketplace
```

Optionally install the Codex skills into `~/.agents/skills` (used by some other
runtimes' agents):

```bash
./codex-plugin/plugins/thrum/scripts/install-skills.sh
```

### Cursor

```bash
./cursor-plugin/local-install.sh --target /path/to/your/project
```

This copies the plugin into `<project>/.cursor/` and writes `.cursor/hooks.json`
with an absolute path back into this repo's `cursor-plugin/` directory — keep the
checkout in place after installing, or re-run the script if you move it.

### OpenCode

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

### Updating

New plugin versions are published here as commits. Pull the latest and re-run the
relevant install/build step for your runtime:

```bash
git pull
```

---

## Getting the Thrum binary

The plugin drives the `thrum` daemon/CLI. That binary is a Thrum Pro product and is
**not** distributed from this public repo — access is provisioned directly by the
Thrum Pro team.

<!-- PLACEHOLDER: how a licensed user obtains + installs the binary, and how the
     plugin locates it (PATH / config). Leon to confirm the exact provisioning flow. -->

Once you have the binary installed and on your `PATH`, verify it:

```bash
thrum --version
thrum daemon status
```

Then register your first agent and load context — see the plugin's own quickstart
(`thrum quickstart` / the `quickstart` skill) after install.

---

## Usage

<!-- PLACEHOLDER: short "your first session" walkthrough — register an agent, send a
     message, check the inbox — once install steps are pinned. -->

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
| ralph-loop | — | MIT / Apache-2.0 | <!-- PLACEHOLDER: confirm which ralph-loop source --> |
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
