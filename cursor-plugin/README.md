# Thrum Cursor Plugin

Thrum multi-agent coordination plugin for Cursor Agent.

## Prerequisites

- [Thrum CLI](https://thrum.team) installed and on PATH
- Cursor Agent with hooks support

## Install

Add the repository marketplace with Cursor Agent CLI:

```bash
curl https://cursor.com/install -fsS | bash
agent login
agent plugin marketplace add --git-ref main https://github.com/leonletto/thrum-pro.git
agent
```

In Cursor Agent, open `/plugin list`, switch to **Marketplace**, search for
`thrum`, and install it at user or project scope.

### Local-clone fallback

Run from any git repo where you want Thrum coordination:

```bash
/path/to/thrum/cursor-plugin/local-install.sh
```

Or specify a target directory:

```bash
cursor-plugin/local-install.sh --target /path/to/project
```

This deploys into `.cursor/` with:

- **rules/** — `.mdc` files for sync worktree safety and session lifecycle
- **hooks.json** — session start, shell guard, stop check, compact hooks
- **mcp.json** — Thrum MCP server configuration
- **skills/** — Thrum skills (populated by `sync-skills.sh`)
- **commands/** — Thrum commands (populated by `sync-skills.sh`)

## Updating

Refresh the repository index, then reopen `/plugin list` to apply an available
plugin update:

```bash
agent plugin marketplace update thrum
```

For a local-clone installation, update the checkout and redeploy:

```bash
git pull --ff-only
cursor-plugin/local-install.sh
```

## What's Included

| Component                 | Description                                     |
| ------------------------- | ----------------------------------------------- |
| `rules/thrum-safety.mdc`  | Blocks writes to internal sync worktree         |
| `rules/thrum-session.mdc` | Session lifecycle reminders                     |
| `hooks/hooks.json`        | Hook template (paths resolved at install)       |
| `scripts/*.sh`            | Hook scripts (shell guard, stop check, compact) |
| `local-install.sh`        | Installer that deploys to `.cursor/`            |
