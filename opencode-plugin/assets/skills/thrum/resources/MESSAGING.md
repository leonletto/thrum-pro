# Messaging Protocol

## Message Lifecycle

1. **Send** — `thrum send --to @name --body-file msg.md` (direct; see
   §Shell-Safe below for heredoc form)
2. **Deliver** — Daemon writes to recipient's inbox (JSONL in
   `.git/thrum-sync/`)
3. **Receive** — `thrum inbox` or `thrum wait` (blocking)
4. **Verify sent state** — `thrum sent` or `thrum message get <msg-id>`
5. **Read** — Auto-marked read when displayed via `thrum inbox`; use
   `thrum inbox --unread` to peek without marking. Explicit:
   `thrum message read --all`
6. **Search — do not page through the inbox to find old messages.** The
   default page is 10, newest-first, so stale unread sorts LAST exactly when
   it has waited longest. Use `thrum message search "<term>"` (full-text,
   positional query, no `--limit`) or `thrum inbox -q "<term>"` (same search
   scoped to your inbox). `thrum message reindex` rebuilds the FTS index if
   search looks wrong.
7. **Reply** — `thrum reply <msg-id> --body-file reply.md` (same audience; **no
   `--to`** — the recipient is derived from the parent message; use
   `thrum send --to @name` for a new thread)

## Addressing

| Target              | Routing                                                       | When to use                          |
| ------------------- | ------------------------------------------------------------- | ------------------------------------ |
| `--to @lead_agent`  | **Direct** — routes to the named agent                        | Default for all task messages        |
| `--to @coordinator` | **Role fanout** — ALL agents with that role (warning emitted) | Only when you want every coordinator |
| `--to @everyone`    | **Broadcast** — all registered agents                         | Critical alerts                      |

**Critical:** `@coordinator` is a role, not an agent name. Sending
`--to @coordinator` fans out to every agent registered with that role. Use
`thrum team` to find agent names, then send `--to @<name>` for direct messages.

- **Reply:** `thrum reply <msg-id>` — same audience as original; takes **no
  `--to`** (recipient derived from the message)
- **Unknown recipient** — hard error; verify names with `thrum team`

## Shell-Safe Message Bodies (backticks, `$(...)`, `$VAR`, quotes)

**The trap:** a double-quoted body is processed by your shell _before_ thrum
runs. Backticks and `$(...)` are command-substituted, `$VAR` is expanded, and
the original text never reaches thrum — it cannot detect or repair the
corruption. A real dispatch once lost a backticked word (`` `img` `` ran as a
command → "command not found: img") and the recipient silently got mangled
instructions. Single-quoting is only a stopgap — it breaks on apostrophes in
prose.

**The safe default:** read the body from stdin or a file instead of passing it
as a quoted argument. A **quoted** heredoc (`<<'EOF'` — note the quotes around
`EOF`) disables _all_ shell interpretation, so backticks, `$`, apostrophes, and
quotes all pass through literally. Available on `send`, `reply`, and
`message edit`:

```bash
# Preferred: quoted heredoc via --stdin (safe for backticks, $, apostrophes)
thrum send --to @agent_name --stdin <<'EOF'
Run `make build` then check $(git rev-parse HEAD). It's done.
EOF

# Reply the same way (no --to — recipient comes from the parent message)
thrum reply msg_01HXE... --stdin <<'EOF'
Done — see `internal/foo.go`. Cost was $(estimate).
EOF

# From a file
thrum send --to @agent_name --body-file ./body.md

# '-' as the body argument is a --stdin alias (good for pipes)
some-generator | thrum send --to @agent_name -
```

Rules:

- `--stdin` and `--body-file` are mutually exclusive, and neither may be
  combined with a positional body (the command errors on ambiguity).
- A single trailing newline (the one the heredoc adds) is stripped; additional
  blank lines are preserved.
- All bodies must be supplied via `--stdin` (or `-`), or `--body-file` —
  positional body arguments are refused to prevent silent shell substitution
  (thrum-6lrd9).

## Permission-Prompt Routing

Runtime permission prompts (e.g. "Allow this tool?") route to recipients listed
in `permission_supervisors` in `.thrum/config.json`. **The array is
authoritative** — the daemon sends the nudge to each entry in order, with no
auto-detect or broadcast fallback behind it.

```jsonc
{
  "permission_supervisors": [
    "coordinator", // role → fans out to every active coordinator
    "@your_coordinator", // specific agent (name-based)
    "@user:jane-doe", // user → auto-bridges to Telegram if configured
  ],
}
```

**Invariant:** the list must include at least one coordinator-role recipient —
either the bare role `"coordinator"` or an `@coordinator_*` agent name. When
absent or empty, the resolver defaults to `["coordinator"]`. If the list is
non-empty but has no coordinator entry, the daemon warns at start and continues
(prompts may still go undelivered if the listed agents are offline).

## Threading

Replies auto-create implicit threads. When you `thrum reply`, the daemon assigns
a shared `thread_id` to both parent and reply. No explicit thread creation
needed. The UI groups conversations by `thread_id`.

## Context Management

### Session Initialization

`thrum prime` gathers all context in one call:

- Agent identity (name, role, module)
- Team (active agents and their intents)
- Inbox (unread messages with summaries)
- Git context (branch, uncommitted files)
- Daemon health and sync state

The **SessionStart** hook prompts you to run `/thrum:prime`. The **PreCompact**
hook auto-saves context to a backup file.

### After Compaction

Context auto-recovers via the PreCompact hook. The agent sees:

1. Their identity and session state
2. Any unread messages accumulated during compaction
3. Current team state
4. Quick command reference

### Identity Persistence

Agent identities are stored in `.thrum/identities/<name>.json` and persist
across sessions. Registration via `thrum quickstart` is idempotent —
re-registering with the same name updates the existing identity.

For multi-worktree setups, see [WORKTREES.md](WORKTREES.md) for identity setup.

## Unified Workflow: Thrum + Beads

```bash
# Find work
thrum issue ready

# Claim and announce → Beads + Thrum
bd update bd-123 --status in_progress
thrum send --to @lead_agent --stdin <<'EOF'
Starting bd-123
EOF

# Work, update → Thrum
thrum send --to @lead_agent --stdin <<'EOF'
Progress: auth module complete
EOF

# Complete → Beads + Thrum
bd close bd-123 --reason "Done with tests"
thrum send --to @reviewer1 --stdin <<'EOF'
bd-123 done, ready for review
EOF
```
