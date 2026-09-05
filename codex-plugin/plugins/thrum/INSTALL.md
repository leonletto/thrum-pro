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

## Recommended: one-command install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/leonletto/thrum-pro/main/codex-plugin/plugins/thrum/scripts/install-plugin.sh)
```

That's it. The script registers the marketplace, stages the per-plugin cache (a
step codex 0.130.0 doesn't do automatically for third-party marketplaces),
enables the plugin, turns on the `plugin_hooks` feature, and (when run from
inside a thrum repo/worktree) ensures the `thrum-workspace` sandbox permission
profile covers that repo's audit-log dir — see "Sandbox permission profile"
below. It's idempotent — re-run any time to pull the latest revision.

Installs from the `main` branch — the only branch this distribution repo carries; there is no release-tag pinning yet.

If you have the repo cloned already, you can run it locally instead:

```bash
bash ./codex-plugin/plugins/thrum/scripts/install-plugin.sh
```

After the script completes, follow the "First-run hook approval" steps below.

### Have an AI agent do it

If you have an AI assistant (claude, codex, kiro, etc.) running locally, point
it at the agent-instructions doc — it handles everything up to the manual
`/hooks` approval:

```text
Please install the Thrum codex plugin by following:
https://github.com/leonletto/thrum-pro/blob/main/codex-plugin/plugins/thrum/agent-instructions.md
```

Your agent will read the file, run the installer, and tell you when it's time to
restart codex and approve hooks.

## Manual: low-level marketplace flow — INCOMPLETE, ADVANCED-ONLY, UNSUPPORTED FOR PERMISSIONS

> ⚠️ **This flow does NOT set up the sandbox permission profile, and Codex's
> plugin manifest schema has no post-install hook to do it for you.**
> Confirmed by reading `.codex-plugin/plugin.json` in full: there is no
> `postInstall`/`install`/`lifecycle`/`scripts` key anywhere in Codex's
> marketplace-plugin manifest schema, so nothing in Codex's own native
> install path can auto-run `ensure-permission-profile.sh` for you. The ONLY
> supported routine that yields a fully-permissioned install is
> **`install-plugin.sh`** (the "Recommended: one-command install" section
> above) — it runs exactly the same marketplace steps below PLUS the required
> permission-profile step at the end, and fails loudly if that step fails.
> If you follow the raw steps below instead, you MUST run
> `ensure-permission-profile.sh` yourself as a final, required step (step 4)
> — skipping it leaves thrum commands blocked by Codex's sandbox (see
> "Sandbox permission profile" below for exactly what it grants and why).

If you'd rather drive the install steps yourself:

```bash
# 1. Register marketplace
codex plugin marketplace add leonletto/thrum-pro

# 2. Stage cache (codex 0.130.0 doesn't do this for third-party marketplaces)
VERSION=$(jq -r '.version' ~/.codex/.tmp/marketplaces/thrum-marketplace/codex-plugin/plugins/thrum/.codex-plugin/plugin.json)
mkdir -p ~/.codex/plugins/cache/thrum-marketplace/thrum/$VERSION
cp -R ~/.codex/.tmp/marketplaces/thrum-marketplace/codex-plugin/plugins/thrum/. ~/.codex/plugins/cache/thrum-marketplace/thrum/$VERSION/

# 3. Enable plugin + plugin_hooks feature
printf '\n[plugins."thrum@thrum-marketplace"]\nenabled = true\n' >> ~/.codex/config.toml
# Then add plugin_hooks = true under [features] in ~/.codex/config.toml

# 4. REQUIRED — install-plugin.sh does this automatically; the raw flow above
#    does not, so you must run it yourself or thrum commands stay blocked by
#    Codex's sandbox:
./codex-plugin/plugins/thrum/scripts/ensure-permission-profile.sh
```

The marketplace manifest at the repo root
(`<repo>/.agents/plugins/marketplace.json`) points at
`./codex-plugin/plugins/thrum` — codex's Git-source flow looks for
marketplace.json at the staging root, so the repo-root manifest is required (the
`codex-plugin/.agents/plugins/marketplace.json` is kept for local-source
installs from a clone).

To upgrade later:

```bash
codex plugin marketplace upgrade thrum-marketplace
# Then re-stage the cache (steps 2-4 above), or just re-run install-plugin.sh.
```

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
3. **Filesystem read to the redirect-resolved `.thrum` directory itself**
   (allowlist). A codex agent's own sandboxed Read-tool calls need this to
   load ordinary thrum monitor/support material (`.thrum/role_templates`,
   `.thrum/hotpath-gate.json`, `.thrum/philosophy.md`, `.thrum/config.json`,
   etc.) — in a worktree with a redirect, this directory lives outside the
   current worktree/workspace root, the same way the audit-log dir and
   daemon socket do, so it isn't covered by `extends = ":workspace"` either.
   `.codex/skills` needs no equivalent grant: it is never redirected, so it
   always lives inside the current worktree/workspace root and is already
   covered by `extends = ":workspace"`.

`install-plugin.sh` runs `scripts/ensure-permission-profile.sh` at the end of
install to fix all three automatically. It resolves this repo's
redirect-aware audit-log dir, daemon-socket path, and `.thrum` dir and, in
`~/.codex/config.toml`, append-if-absent:

- ensures the root-level scalars `approval_policy = "on-request"`,
  `approvals_reviewer = "auto_review"`, and
  `default_permissions = "thrum-workspace"` exist (never clobbers a value
  already set by the user);
  **scoping note:** these three scalars are pre-existing —
  this bead's diff only adds the `.thrum` filesystem-read grant below.
  Codex has no Bash-pattern command allowlist; ordinary `thrum` command
  invocations are not prompted because of the pre-existing
  `approvals_reviewer = "auto_review"` policy, not because of anything this
  bead added. Do not cite this profile as a command-level allowlist grant —
  it is a filesystem/network scope grant only;
- ensures a `[permissions.thrum-workspace]` profile exists (`extends =
  ":workspace"`) with:
  - a `[permissions.thrum-workspace.filesystem]` table granting
    `"<audit-log-dir>" = "write"` and `"<thrum-dir>" = "read"` for this
    repo's resolved paths;
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
