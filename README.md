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

<!-- PLACEHOLDER: exact per-runtime install commands land once the first plugin
     bundle is committed. The structure below is the shape; the specific paths and
     commands will be filled to match the real trees. -->

### Claude Code

```bash
# Clone (or pull) this repo
git clone https://github.com/leonletto/thrum-pro.git

# Point Claude Code at the plugin tree
# <PLACEHOLDER: exact marketplace / plugin-install command for claude-plugin/>
```

### Codex

```bash
# <PLACEHOLDER: install steps for codex-plugin/>
```

### Cursor

```bash
# <PLACEHOLDER: install steps for cursor-plugin/>
```

### OpenCode

```bash
# <PLACEHOLDER: install steps for opencode-plugin/>
```

### Updating

New plugin versions are published here as commits. To update, pull the latest and
re-run your runtime's plugin refresh:

```bash
git -C thrum-pro pull
# <PLACEHOLDER: refresh command per runtime>
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
