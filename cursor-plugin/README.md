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
- **hooks.json** — shell guard (two commands) and stop check (one command)
- **mcp.json** — Thrum MCP server configuration
- **skills/** — Thrum skills (generated at build time)
- **commands/** — Thrum commands (generated at build time)

## Updating

1. Remove the marketplace and add it again:

   ```bash
   agent plugin marketplace remove thrum
   agent plugin marketplace add --git-ref main https://github.com/leonletto/thrum-pro.git
   ```

2. In Cursor Agent, open `/plugin`, go to **Marketplace**, select `thrum`, and choose **Install for you**.
3. Start a new Cursor session.

`agent plugin marketplace update thrum` is not enough: it re-indexes the same pinned commit, so the installed plugin
stays old. Removing and adding the marketplace picks up the current one. This route is per the thrum-pro INSTALL.md and
was measured by the runtime team on Cursor, not run here. The `remove` form mirrors the `add` form and is unverified.
`/plugin list` opens with "list" as a search term, so use `/plugin` and go to Marketplace instead.

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
| `scripts/*.sh`            | Hook scripts (3 registered in hooks.json)       |
| `local-install.sh`        | Installer that deploys to `.cursor/`            |
