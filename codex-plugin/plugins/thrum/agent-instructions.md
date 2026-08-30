# Install the Thrum Codex plugin

Install the plugin from its GitHub marketplace:

```bash
codex plugin marketplace add leonletto/thrum-pro
codex plugin add thrum@thrum-marketplace
codex plugin list
```

Confirm `thrum@thrum-marketplace` is `installed, enabled`. If the marketplace
is already registered, run `codex plugin marketplace upgrade
thrum-marketplace` before the `plugin add` command.

Restart Codex after installation. If Codex reports hooks awaiting review, open
`/hooks`, inspect and trust the Thrum SessionStart, PreToolUse, and Stop hooks,
then restart once more. The next session should load the Thrum prime briefing.

If native installation registers the marketplace but does not stage the plugin,
run the compatibility installer:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/leonletto/thrum-pro/main/codex-plugin/plugins/thrum/scripts/install-plugin.sh)
```

Report command failures verbatim. Do not copy the plugin cache or edit Codex
configuration manually.
