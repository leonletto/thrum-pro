# Installing Thrum for Codex

## Prerequisites

- Codex installed (v0.130.0+)
- `features.hooks` is enabled by default on codex 0.130.0+; no action needed.
  (If somehow disabled: `codex -c features.hooks=true ...`.)
- `features.plugin_hooks = true` MUST be set in `~/.codex/config.toml` for the
  plugin's SessionStart/PreToolUse/Stop hooks to register. As of codex 0.130.0
  this feature is "under development" but functional. Add to your `[features]`
  block:

  ```toml
  [features]
  plugin_hooks = true
  ```

- `thrum` CLI on `PATH`

## Recommended: native marketplace install

```bash
codex plugin marketplace add leonletto/thrum-pro
codex plugin add thrum@thrum-marketplace
```

Codex stages and enables the plugin from the repository marketplace. Confirm
with `codex plugin list`.

Installs from the `main` branch — the only branch this distribution repo carries; there is no release-tag pinning yet.

To update:

```bash
codex plugin marketplace upgrade thrum-marketplace
codex plugin add thrum@thrum-marketplace
```

After installation, follow the "First-run hook approval" steps below.

### Have an AI agent do it

If you have an AI assistant (claude, codex, kiro, etc.) running locally, point
it at the agent-instructions doc — it handles everything up to the manual
`/hooks` approval:

```text
Please install the Thrum codex plugin by following:
https://github.com/leonletto/thrum-pro/blob/main/codex-plugin/plugins/thrum/agent-instructions.md
```

Your agent will read the file, run the commands, and tell you when it's time to
restart codex and approve hooks.

## Compatibility installer

Older Codex releases that register a marketplace without staging its plugin can
use the compatibility installer:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/leonletto/thrum-pro/main/codex-plugin/plugins/thrum/scripts/install-plugin.sh)
```

The marketplace manifest at the repo root
(`<repo>/.agents/plugins/marketplace.json`) points at
`./codex-plugin/plugins/thrum` — codex's Git-source flow looks for
marketplace.json at the staging root, so the repo-root manifest is required (the
`codex-plugin/.agents/plugins/marketplace.json` is kept for local-source
installs from a clone).

## Alternative: Local-clone install (dev only)

For users on a clone of the thrum repo or developing the plugin, the simplest
path is to install skills directly:

```bash
./codex-plugin/plugins/thrum/scripts/install-skills.sh --force
```

Installs skills directly into `${HOME}/.agents/skills/` (canonical path as of
codex v0.130.0).

To wire the plugin's **hooks** from a local clone via the marketplace mechanism:

```bash
codex plugin marketplace add ./codex-plugin
# Then enable the plugin (codex 0.130.0 does not auto-enable local sources):
printf '\n[plugins."thrum@thrum-marketplace"]\nenabled = true\n' >> ~/.codex/config.toml
```

NOTE: codex 0.130.0's local-source `marketplace add` registers the marketplace
but does NOT stage the plugin into `~/.codex/plugins/cache/`. To populate the
cache for hook firing from a local clone, either (a) use the Git-source flow
above instead (recommended for runtime testing), or (b) manually stage:

```bash
mkdir -p ~/.codex/plugins/cache/thrum-marketplace
cp -R ./codex-plugin/plugins/thrum ~/.codex/plugins/cache/thrum-marketplace/thrum
```

## Sandbox permission profile

Codex's default `:workspace` sandbox profile only covers the current
worktree, and blocks two things thrum commands need:

1. **Filesystem write to the redirected audit-log dir.** Every thrum command
   (prime/inbox/send) appends a command-log entry to
   `<main-repo>/.thrum/var/log/` — resolved via `.thrum/redirect` when run
   from a worktree, so it can live outside the worktree codex sandboxes to.
   Without an explicit permission for that directory, codex's auto-review
   denies the write and blocks thrum commands.
2. **Network access to the thrum daemon's UNIX socket**
   (`<main-repo>/.thrum/var/thrum.sock`). Codex's sandbox also blocks
   outbound UNIX-socket connections by default, so even with the filesystem
   grant above, every RPC the thrum CLI makes to the daemon over that socket
   (which is how `prime`/`inbox`/`send` actually talk to it) is denied.

`install-plugin.sh` runs `scripts/ensure-permission-profile.sh` at the end of
install to fix both automatically. It resolves this repo's redirect-aware
audit-log dir and daemon-socket path and, in `~/.codex/config.toml`,
append-if-absent:

- ensures the root-level scalars `approval_policy = "on-request"`,
  `approvals_reviewer = "auto_review"`, and
  `default_permissions = "thrum-workspace"` exist (never clobbers a value
  already set by the user);
- ensures a `[permissions.thrum-workspace]` profile exists (`extends =
  ":workspace"`) with:
  - a `[permissions.thrum-workspace.filesystem]` table granting
    `"<audit-log-dir>" = "write"` for this repo's resolved path;
  - a `[permissions.thrum-workspace.network]` table with `enabled = true`,
    **plus** a `[permissions.thrum-workspace.network.unix_sockets]` table
    granting `"<daemon-socket-path>" = "allow"` for this repo's resolved
    socket path. Both of these are required together — `unix_sockets` alone,
    without `network.enabled = true`, loads as valid TOML but is inert (the
    daemon calls still fail). This grant is additive to the filesystem
    grant above, not a replacement for it.

It's safe to re-run from multiple thrum repos over time — each repo's
resolved paths are appended once; a path already present is left alone. If run
outside a thrum repo/worktree (no `.thrum/` found), it skips gracefully.

To run it standalone:

```bash
./codex-plugin/plugins/thrum/scripts/ensure-permission-profile.sh
```

## First-run hook approval

On the first codex session after install, codex will display:

> ⚠ 3 hooks need review before they can run. Open /hooks to review them.

Open `/hooks` and approve all three (SessionStart, PreToolUse, Stop). Codex
remembers the approval for subsequent sessions.

## SessionStart auto-prime

After install + hook approval, restart codex. The next session opens with the
Thrum prime briefing already in context — identity, project state, unread inbox
— courtesy of the SessionStart hook.

## Verification

```bash
grep -A1 '^\[marketplaces.thrum-marketplace\]' ~/.codex/config.toml   # should print the registered source
codex features list | grep -E '^(hooks|plugin_hooks) '                # hooks=stable/true; plugin_hooks=under development/true
ls ~/.codex/plugins/cache/thrum-marketplace/thrum/                    # should list one or more <version> dirs
```

You should see the thrum umbrella skill plus the role/discipline skills.

## Migration from `~/.codex/skills/` (one-time)

If you previously installed thrum via the legacy script:

```bash
mv ~/.codex/skills/thrum* ~/.agents/skills/
mv ~/.codex/skills/orchestrate ~/.agents/skills/
```

(See pm7n.2 for context on the codex v0.130.0 path change.)
