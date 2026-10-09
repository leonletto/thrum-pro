---
name: using-monitors
description: "Use when scheduling a reminder, watching a log, or running a periodic check that must reach an agent - thrum monitor start, cron --schedule, --match, --notify-on-success, --debounce, recurring nudge, script check with exit codes, why a monitor message did not arrive, how to verify a monitor delivered."
---

# Thrum Monitors - Reminders And Script Checks

## Overview

A monitor runs a command, keeps the output lines that match a regex, and
delivers them as Thrum messages to a target: a continuous monitor sends each
kept line, a scheduled monitor sends all the lines of a run in one message. With
`--schedule` it runs the command once per cron tick; without it the command runs continuously
and restarts with backoff when it exits. Monitors persist across daemon
restarts and run only on the daemon that owns them.

Every flag below appears in `thrum monitor start --help`. Re-read the help
before relying on a flag not listed here.

## Command Surface

```bash
thrum monitor start --name <n> --match <re> --to @agent [--schedule "<cron>"] \
  [--notify-on-success] [--debounce 60s] [--env K=V] [--cwd <dir>] -- <cmd> [args...]
thrum monitor list [--all]
thrum monitor show <name|id>
thrum monitor logs <name|id> [-n 50]
thrum monitor update <name|id> [--match <re>] [--to <t>] [--debounce <d>] [--schedule "<cron>"]
thrum monitor stop <name|id>
thrum monitor restart <name|id>
thrum monitor delete <name|id>
```

- `--name`, `--match` and `--to` are required; the command follows `--`.
- `--schedule` takes a 5-field cron expression. `update --schedule` changes the
  cron of a scheduled monitor at any time. Setting a first schedule or removing
  it (`--schedule ""`) switches the mode, which is refused while the monitor is
  running and allowed while it is stopped.
- `--debounce` is leading-edge with a 30s minimum (default 1m).
- `stop` leaves a stopped record that still holds the name; `delete` frees the
  name. Use a unique name per monitor.

## What Is Delivered

Each output line is tested against `--match` on its own. A line is truncated at
2048 bytes with a marker appended.

A scheduled (`--schedule`) job is a one-shot run, so its exit code is
authoritative. It delivers ONE message at exit that carries every matched line,
in order. A continuous job has no exit code per line, so it classifies and
delivers and classifies each matched line on its own, by its words.

| Scheduled job                                                   | Delivered as                                  |
| --------------------------------------------------------------- | --------------------------------------------- |
| Non-zero exit, or the command failed to start                   | `[FAIL] <name>: exit code N` with the output tail, then the matched lines |
| Exit 0, a matched line starts `ERROR:`, `FATAL:` or `FAIL:`     | `[FAIL] <name>: matched error pattern` + all matched lines |
| Exit 0, highest prefix is `WARN:`, `WARNING:` or `ALERT:`        | `[WARN] <name>: matched WARNING` + all matched lines |
| Exit 0, lines matched, no such prefix                           | All matched lines, in order, verbatim         |
| Exit 0, nothing matched, `--notify-on-success`                  | `[OK] <name>: succeeded`                      |
| Exit 0, nothing matched                                         | Nothing (logged only)                         |

Cadence: the first non-zero scheduled run sends its `[FAIL]` notice; repeats of
that failure are not sent again until the outcome changes or the re-escalation
interval (30 minutes) passes. An exit-0 run that matched lines sends its message
on every run.

On a scheduled job only these prefixes, at the very start of a line, label the
output, with the colon directly after the word: `ERROR:`, `FATAL:` and `FAIL:`
fail it; `WARN:`, `WARNING:` and `ALERT:` warn. Any other prefix, including
`ALERT-<NAME>:`, `ERROR :`, `INFO:`, `OK:`, `NOT_OK:` and lowercase forms, is
neutral. They are read before any wording in the body, and
the highest one decides the label. Words such as `done`, `ok`, `complete`, `failures` or `error` neither
drop nor relabel a line, and `WARN: batch not complete` stays a warning.
`--notify-on-success` adds the generic `[OK]` only for a run in which nothing
matched; an empty matched line counts as a match and is announced as
`[matched N empty line(s)]`.

The whole message, including its label and framing, never exceeds the daemon's
configured message-body limit. Matched lines are sent whole while they fit both
budgets: the in-memory retention budget (each line costs its bytes plus a small
fixed overhead, so a line close to the limit, or many short lines, can be cut
or omitted earlier than their plain total would suggest) and the final rendered
message including its label. Lines that do not fit are replaced by `[N more
matched lines omitted]`, and a first line that does not fit is cut and
marked. The limit is never below 1024 bytes (the configuration floor), enough for
the framing and an omission marker with ordinary job names; when variable
framing such as a very long job name does not fit, the monitor sends a bounded
summary that starts with `+N omitted` instead of the lines. A run keeps only a bounded prefix of its lines in memory (at most
the delivery limit, or 1 MiB when the limit is disabled, counting a small fixed
overhead per line) but
counts every match, so the omitted count is exact and an `ERROR:`/`WARN:` line
past the retained prefix still sets the label.

| Continuous job (no `--schedule`)                                | Delivered as                                  |
| --------------------------------------------------------------- | --------------------------------------------- |
| Contains `error`, `fatal`, `fail`, `permission denied`          | `[FAIL] <name>: matched error pattern` + line |
| Contains `warn` or `warning`                                    | `[WARN] <name>: matched WARNING` + line       |
| Contains a whole word `success`, `succeeded`, `complete`, `completed`, `done`, `ok` | Not delivered (logged only)   |
| Any other matched line                                          | The line, verbatim                            |

A continuous job checks a line for a negated completion word (`not complete`)
first, then for a level prefix (`ERROR:`, `WARN:`, `INFO:`, optionally after a
timestamp), then for the words above. Tokens such as `fail=0` are not failures;
the phrase `0 errors` still contains `error`.

Delivery limits:

- A continuous job delivers the first matching line in each debounce window at
  once and holds later ones for a trailing summary. A scheduled job has no
  debounce; its lines are aggregated as above.
- The `[FAIL]` body for a non-zero exit carries only the last 500 bytes of
  output, so the message that matters goes last.

## Prompt-Only Reminder

A reminder is a monitor whose command only prints a fixed line. Give the line a
stable prefix and match exactly that prefix.

```bash
thrum monitor start --name standup-nudge --to @me \
  --match '^REMINDER-STANDUP:' --schedule "0 9 * * 1-5" -- \
  echo "REMINDER-STANDUP: post the status update, then reply to the open review"
```

- Schedule the reminder; words in its text, including "failures", "error" and
  "done", then neither relabel nor drop it, and the exit code decides success.
- Make the body an instruction with the next concrete step; a bare "reminder"
  carries no action.
- Add `--notify-on-success` only when a delivered line must be guaranteed for a
  run that matched nothing.
- A delivered reminder shows the schedule fired. It does not show that the work
  moved. Check the work itself (commits, queue, state) before treating the
  reminder as progress.

## Script Check

A script check runs a bounded, synchronous probe and reports through its exit
code and one structured line.

```bash
thrum monitor start --name disk-check --to @me \
  --match '^CHECK-DISK:' --schedule "*/15 * * * *" -- \
  bash -c 'u=$(df --output=pcent / | tail -1 | tr -dc 0-9)
  [ "$u" -lt 90 ] && exit 0
  echo "CHECK-DISK: root volume at ${u} percent used, free space then rerun df -h /"
  exit 3'
```

Rules:

1. Bound every probe with `timeout <secs>`; a hung probe holds the tick.
2. Exit 0 for healthy and print nothing matching, which keeps the run quiet.
3. Exit non-zero for a failure; the daemon sends the `[FAIL]` notice with the
   exit code and output tail.
4. Print a matching line that names the subject, the observed value and the
   next action. A generic `OK` or `done` line carries no information.
5. Use a distinct stable prefix per outcome (`CHECK-DISK:` for a finding,
   `REMINDER-DISK:` for a nudge) so `--match` selects what must reach the
   target.

| Outcome  | Script does                              | Target receives                    |
| -------- | ---------------------------------------- | ---------------------------------- |
| Quiet    | Exit 0, no matching line                 | Nothing                            |
| Failure  | Non-zero exit, finding line last         | One `[FAIL] <name>: exit code N` message with the tail and the finding line |
| Finding  | Exit 0, matching line(s)                 | The line(s), verbatim (labeled only by an `ERROR:`/`FATAL:`/`FAIL:` or `WARN:`/`WARNING:`/`ALERT:` prefix) |
| Reminder | Exit 0, one stable-prefix instruction    | The line, verbatim                 |

A `--match` that never matches the script's real output delivers nothing and
raises no error. Test the regex against the exact output before starting.

## Verify By Delivery

Start the monitor with a unique name, `--to` the verifying agent, and a
one-minute schedule, then read the delivered message back in full.

```bash
thrum monitor start --name verify-<unique> --to @me --match '^VERIFY-<unique>:' \
  --schedule "* * * * *" -- echo "VERIFY-<unique>: delivery body check"
thrum inbox --unread
thrum message get <message-id>      # the complete delivered body
thrum monitor logs verify-<unique>  # the matches the daemon recorded
thrum monitor delete verify-<unique>
```

Confirm the body carries the prefix, the wording and no unexpected `[FAIL]`
or `[WARN]` label. Delete the monitor when done; never alter a monitor another
agent owns.

## Troubleshooting

- Nothing arrived: `thrum monitor show` for state and last exit, `thrum
  monitor logs` for recorded matches. No recorded match means the regex did not
  match, or (continuous job) the line was completion-classified and suppressed;
  run the command by hand and compare its output with the regex.
- Message labeled `[FAIL]` unexpectedly: the job exited non-zero, the line starts
  with `ERROR:`/`FATAL:`/`FAIL:`, or (continuous job) the line contains a fail or
  error substring.
- Name already in use: a stopped record holds it. `thrum monitor delete` it.
