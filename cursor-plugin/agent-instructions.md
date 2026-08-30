# Install the Thrum Cursor plugin

Install the plugin into the current Git project.

1. Confirm `git` and the `thrum` CLI are on `PATH`.
2. Clone `https://github.com/leonletto/thrum-pro.git` into the stable local path
   `~/.local/share/thrum-pro`, or update that checkout with `git pull --ff-only`.
3. Run `~/.local/share/thrum-pro/cursor-plugin/local-install.sh --target` with
   the current Git repository root.
4. Confirm `.cursor/hooks.json`, `.cursor/mcp.json`, `.cursor/skills/`,
   `.cursor/commands/`, `.cursor/agents/`, and `.cursor/rules/` exist.
5. Restart Cursor or reload its window, then confirm the Thrum skills and hooks
   are visible.

Keep `~/.local/share/thrum-pro` in place because the installed hook commands
reference its scripts. Update by pulling that checkout and rerunning the local
installer.
