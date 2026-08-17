# Anti-Patterns

Common mistakes when using Thrum and how to avoid them.

## 1. Using Thrum for Task Management

**Wrong:** Sending messages like "TODO: implement auth" to yourself. **Right:**
Use Beads (`bd create`) for task tracking. Use Thrum for coordination messages
between agents.

## 2. Polling Instead of Waiting

**Wrong:** Looping `thrum inbox` every 10 seconds. **Right:** Use `thrum wait`
which blocks efficiently until a message arrives. Or use the message-listener
sub-agent pattern for background monitoring.

## 3. Forgetting to Re-arm the Listener

**Wrong:** Processing messages from listener, then continuing work without
re-arming. **Right:** After processing listener results, always spawn a new
message-listener:

```text
Task(subagent_type="message-listener", run_in_background=true, prompt="...")
```

## 4. Sending Without an Explicit Recipient Flag

`thrum send 'msg'` with no `--to` or `--broadcast` is a hard error (thrum-t698,
v0.10.6+). The previous default — silent broadcast to every team agent — was a
real footgun, so the CLI now requires the recipient to be explicit:

```bash
# Wrong — hard-errors with a "missing recipient" prompt
thrum send "msg"

# Right — directed send (canonical form)
thrum send --to @your_coordinator --stdin <<'EOF'
msg
EOF

# Right — explicit team-wide fanout
thrum send --broadcast --stdin <<'EOF'
msg
EOF

# Right — legacy keyword form (still works; --broadcast preferred)
thrum send --to @everyone --stdin <<'EOF'
msg
EOF
```

`--to` and `--broadcast` are mutually exclusive. `@everyone` continues to be
auto-created and handles membership dynamically.

## 5. Skipping Registration

**Wrong:** Sending messages without running `thrum quickstart` first. **Right:**
Always register at session start. Without registration, messages won't be routed
correctly and `thrum inbox` won't know who you are.

## 6. Vague Intents

**Wrong:**
`thrum quickstart --name <agent-name> --role <role> --module <module> --intent "Working on stuff"`
**Right:**
`thrum quickstart --name <agent-name> --role <role> --module <module>`
`--intent "Implementing JWT auth for login endpoint (bd-123)"`

Specific intents help other agents understand what you're doing via
`thrum team`.

## 7. Leaving Sessions Open

**Wrong:** Finishing work but not ending the session. **Right:** Run
`thrum session end` when done. Stale sessions make `thrum team` unreliable.

## 8. Reading Files Instead of Using CLI

**Wrong:** Reading `.git/thrum-sync/` files directly with the Read tool.
**Right:** Use `thrum inbox`, `thrum overview`, `thrum prime`. The SKILL.md
`allowed-tools` is `Bash(thrum:*)` — no Read permission needed.

## 9. Sending Messages to Yourself

**Wrong:** `thrum send --to @me --body-file note.md` (note to self) **Right:**
Use Beads notes (`bd update <id> --notes "..."`) for self-notes. Thrum is for
inter-agent communication.

## 10. Spamming Status Updates

**Wrong:** Sending a message after every line of code. **Right:** Batch updates
at natural breakpoints — after completing a subtask, hitting a blocker, or
finishing the main task.

## 11. Not Including Context in Messages

**Wrong:** `thrum send --to @lead --body-file done.md` with body `done`
**Right:** `thrum send --to @lead --body-file completion.md` with body
`Completed bd-123: JWT auth with tests passing. 3 files changed.`

Include Beads IDs, file paths, commit hashes — anything that helps the recipient
act on the message.

## 12. Using @role to Address One Agent

**Wrong:** `thrum send --to @implementer --body-file msg.md` — fans out to all
implementers. **Right:** `thrum send --to @alice --body-file msg.md` — use the
agent's name.

`@role` sends to **all agents** with that role (via the auto-created role group)
and emits a warning. Use `@name` for direct messages. Check names with
`thrum team`.

## 13. Sending to Unknown Recipients

**Wrong:** `thrum send --to @typo --body-file msg.md` — hard error if recipient
doesn't exist. **Right:** Verify the agent name with `thrum team` first, then
send.

## 14. Agent Name Same as Role

**Wrong:** `thrum quickstart --name coordinator --role coordinator` —
registration rejects name==role. **Right:** Use a descriptive name that differs
from the role, e.g., `--name lead-agent --role coordinator`.

## 15. Trusting the Default Inbox Page to Find Old Messages

**Wrong:** Reading `thrum inbox --unread` (default page: 10, newest-first) and
concluding there's nothing important waiting. **Right:** Stale unread sorts LAST
exactly when it has waited longest — the default page is structurally blind to
the oldest backlog. Use `thrum message search "<term>"` (full-text, no page
limit) or `thrum inbox -q "<term>"` to find it. `thrum message reindex` rebuilds
the FTS index if search looks wrong.
