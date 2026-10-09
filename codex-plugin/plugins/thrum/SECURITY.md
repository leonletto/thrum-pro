# Security

## Reporting a vulnerability

Please report security issues via the parent
[thrum](https://github.com/leonletto/thrum-pro) repository — open a private security
advisory rather than a public issue. Do not disclose details publicly until a
fix is available.

## Plugin scope

This plugin runs hook scripts under your local shell with your user permissions.
The scripts are auditable plain Bash under `codex-plugin/scripts/`:

- `inject-prime-context.sh` — read-only context injection at SessionStart.
- `block-sync-worktree-cd.sh` — denies a Bash invocation if it would `cd` into
  the daemon's a-sync git worktree (read-only enforcement).
- `block-tls-key-exfil.sh` — denies a Bash invocation that stages files under
  `.thrum/var/tls/` (the daemon's CA keys) into git, or pipes a CA private key
  into a network or transmit command.
- `stop-check-messages.sh` — reads inbox and listener state; may emit a
  block-stop continuation prompt.

If `jq` is missing, or a guard hook's input cannot be read or parsed, the two
guard hooks above allow the command and print one line on stderr naming the
problem. If a guard cannot evaluate its patterns, it blocks the command.

None of the hooks write outside the `~/.thrum/` and `~/.agents/` paths the
parent `thrum` daemon already manages.
