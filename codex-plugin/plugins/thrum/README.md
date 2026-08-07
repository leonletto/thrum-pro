# Thrum — Codex Plugin

Git-backed messaging for AI agent coordination. This plugin gives Codex agents
persistent identity, role discipline, an inbox for cross-session/cross-worktree
messages, and a SessionStart auto-prime that loads project state and unread mail
before the first turn.

## Install

```bash
codex plugin marketplace add leonletto/thrum-pro --sparse codex-plugin
```

See [INSTALL.md](./INSTALL.md) for prerequisites, the local-clone install path,
and one-time migration notes.

## Contents

| Surface                                  | What it provides                                                                                                                         |
| ---------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `skills/`                                | 29 skills — `thrum` umbrella + `orchestrate` + 16 role-discipline + 11 command-derived                                                   |
| `hooks/hooks.json`                       | Wires SessionStart (`startup\|resume\|clear`), PreToolUse (Bash), Stop                                                                   |
| `scripts/`                               | Three lifecycle hook scripts ported from claude-plugin: `inject-prime-context.sh`, `block-sync-worktree-cd.sh`, `stop-check-messages.sh` |
| `.codex-plugin/plugin.json`              | Manifest (kept version-aligned with `claude-plugin/.claude-plugin/plugin.json` via `make ci`)                                            |
| `../../.agents/plugins/marketplace.json` | Marketplace wrapper at `codex-plugin/.agents/plugins/marketplace.json`; `source.path: "./plugins/thrum"` (mirrors openai-bundled layout) |

## Repository

This plugin is published from the
[thrum-pro](https://github.com/leonletto/thrum-pro) distribution repository as
a sparse-checkout target.

## Security

Report vulnerabilities via the [thrum-pro](https://github.com/leonletto/thrum-pro)
repository's issue tracker.

## License

Apache-2.0 — see the repository [LICENSE](../../../LICENSE) and
[NOTICE](../../../NOTICE).
