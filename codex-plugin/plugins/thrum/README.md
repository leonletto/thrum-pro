# Thrum — Codex Plugin

Git-backed messaging for AI agent coordination. This plugin gives Codex agents
persistent identity, role discipline, an inbox for cross-session/cross-worktree
messages, and a SessionStart auto-prime that loads project state and unread mail
before the first turn.

## Install

```bash
codex plugin marketplace add leonletto/thrum-pro
codex plugin add thrum@thrum-marketplace
```

See [INSTALL.md](./INSTALL.md) for prerequisites, the local-clone install path,
and one-time migration notes.

## Contents

| Surface                                  | What it provides                                                                                                                                                                                                                                        |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `skills/`                                | 29 skills — `thrum` umbrella + `orchestrate` + 16 role-discipline + 11 command-derived                                                                                                                                                                  |
| `hooks/hooks.json`                       | Wires SessionStart (`startup\|resume\|clear`), PreToolUse (Bash), Stop                                                                                                                                                                                  |
| `scripts/`                               | Stable `thrum hook run` commands with five bundled legacy handlers, including `stop-check-messages.sh` and its `stop-set-idle.sh` helper (plus an install helper) |
| `.codex-plugin/plugin.json`              | Manifest (kept version-aligned with `claude-plugin/.claude-plugin/plugin.json` via `make ci`)                                                                                                                                                           |
| `../../.agents/plugins/marketplace.json` | Marketplace wrapper at `codex-plugin/.agents/plugins/marketplace.json`; `source.path: "./plugins/thrum"` (mirrors openai-bundled layout)                                                                                                                |

## Repository

Source of truth for skills, commands, and hook contracts is the parent
[thrum](https://github.com/leonletto/thrum-pro) repository. Most contents under
`skills/` are generated from the canonical skill sources during plugin maintenance.

## Security

Report vulnerabilities via the parent repository's issue tracker.

## License

Apache-2.0 — see the [thrum-pro repository LICENSE](https://github.com/leonletto/thrum-pro/blob/main/LICENSE).
