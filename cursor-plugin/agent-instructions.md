# Install the Thrum Cursor plugin

Prefer Cursor's GitHub marketplace flow:

1. Confirm `agent`, `git`, and the `thrum` CLI are on `PATH`; install Cursor
   Agent with `curl https://cursor.com/install -fsS | bash` if needed, then run
   `agent login`.
2. Run:

   ```bash
   agent plugin marketplace add --git-ref main https://github.com/leonletto/thrum-pro.git
   ```

3. Start `agent`, open `/plugin list`, switch to **Marketplace**, search for
   `thrum`, and install it at user or project scope.
4. Confirm the plugin is marked installed.

If marketplace installation is unavailable, install into the current Git
project from a stable clone:

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
