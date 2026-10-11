---
name: using-tmux-ssh
description:
  "Use when about to ssh to a host, run a command on a VM or remote box, start a
  long test or build on another machine, inspect a remote log, or recover after
  an ssh connection dropped or a remote command timed out. Use tmux-ssh for
  remote commands, saved-watch resume, and concurrent observation."
# source: claude-plugin/skills/using-tmux-ssh/SKILL.md
# generated-by: scripts/sync-skills.sh
---

## Running Remote Commands With tmux-ssh

`tmux-ssh` drives one persistent SSH login per host in a local tmux pane. Use it
for every command on another machine or VM, short or long, including remote
tests, builds, and log reads. Use `--read` and `--status` to observe; never use
plain SSH polling or Monitor loops.

### Where the script is

From a Thrum source checkout, run `scripts/tmux-ssh` from the repository root
and read `scripts/tmux-ssh --help` for current flags. Read the design doc at
`dev-docs/proxmox/32-tmux-ssh-design.md`. If no source checkout is present, ask
the coordinator for its path rather than guessing.

### Usage

The examples below use `tmux-ssh` for the resolved executable. `HOST` is an SSH
config alias or `user@host`.

```bash
tmux-ssh HOST                                  # connect if needed; print status
tmux-ssh HOST 'uname -a'                        # finite command; return its exit code
tmux-ssh HOST --timeout 900 'make test'          # bounded observation, in seconds
tmux-ssh HOST --resume --timeout 900            # continue the saved watch; never resend
tmux-ssh HOST --status                          # session and recorded state
tmux-ssh HOST --read --settle                    # screen; usable during another call
tmux-ssh HOST --abort                           # deliberately interrupt and clear the watch
tmux-ssh HOST --kill                            # close SSH and clear saved state

tmux-ssh HOST --send 'top'                      # interactive program
tmux-ssh HOST --read
tmux-ssh HOST --send --key C-c

tmux-ssh HOST "tmux new -d -s JOB 'long-command >job.log 2>&1'"
```

Run mode waits for a command that ends. For editors, REPLs, attached tmux, and
other programs that stay open, use `--send`/`--read`. Run mode refuses obvious
interactive commands with code 2; use `--force-run` only deliberately. `--send`
types into the current program and refuses a dead session rather than
reconnecting and losing interactive state.

Quote remote commands locally so variables expand on the intended machine. They
execute in the remote login shell, which may be zsh; invoke `bash` for Bash
syntax. For long or complex content, transfer a script using `scp` or `rsync`
with the same connection options, then run a short command through `tmux-ssh`.
The wrapper transports commands, not files.

### Rules

- **One command per host session.** Mutating calls share a local per-host lock
  and wait up to 30 seconds by default. `--read` and `--status` observe without
  that lock. Coordinate drivers across machines or different `TMUX_SSH_DIR`
  values; these do not provide a global lock.
- **Resume observation, never resubmit a queued or visible command.** Code 124
  ends the wait; the command may still be running or waiting for input. Use
  `--read`, then `--resume`, which retains the watch and never sends the command
  again. Resume reuses the original timeout unless overridden. Other run calls
  refuse while a watch remains.
- **Interrupt deliberately.** `--interrupt-on-timeout` sends Ctrl-C when the
  wait expires. `--abort` sends Ctrl-C and clears the watch; code 0 reports a
  ready/finished/gone session, code 1 means the shell did not answer. Inspect
  `--read` before further input. An abort receipt does not prove job success.
- **Give long jobs an independent remote lifecycle.** Use detached remote tmux,
  retaining the job name and logs. An ordinary call can reconnect a dead SSH
  session, but a drop during foreground execution leaves completion unknown and
  may terminate that command. Check the job and its results before deciding to
  retry. `--kill` closes SSH; it does not stop an independent remote job.
- **Interpret the diagnostic and completion evidence.** Remote command exit
  codes are passed through and can overlap wrapper codes. Wrapper code 124 is a
  wait timeout; 125 is refusal or 'completion unknown', so it alone cannot prove
  nothing ran; 2 is a usage error; 3 means input state UNKNOWN after a failed
  keystroke, dropped send, or failed watch persistence. Code 3 guards later
  typing until `--kill`; `--read`, `--status`, and `--resume` still work. Do not
  blindly retry unknown completion or input, or kill another driver's session or
  lock merely because it looks stuck.

### Connection options and pool leases

Obtain the key, known-hosts file, target address, and actual remote OS hostname
from the current lease. Keep these values outside the skill.

```bash
TMUX_SSH_OPTS='-i /path/to/lease-key -o IdentitiesOnly=yes -o UserKnownHostsFile=/path/to/lease-known-hosts -o StrictHostKeyChecking=yes' \
TMUX_SSH_EXPECT_HOST='<remote-os-hostname>' \
tmux-ssh user@<lease-address> 'uname -a'
```

Options precede built-in defaults, so SSH's first `-o` wins. Allowed characters
are letters, digits, spaces, and `- _ . / = : , @ ~ + %`; paths cannot contain
spaces. A live session retains its original options: deliberately close it with
`--kill` before changing them. `--help`, `--status`, and `--kill` work with
invalid options. `--expect-host` overrides `TMUX_SSH_EXPECT_HOST` and matches
short/FQDN hostname forms case-insensitively; the SSH alias need not match the
OS hostname.

### Execution identity checks

SSH is the pane's own process; a dropped connection leaves a dead pane, not a
local shell. Run mode checks a live SSH pane, probes the recorded hostname, and
wraps execution with a hostname check. Interactive input checks the live SSH
pane because a program may own stdin. These checks catch mistaken targets; they
are not an adversarial security boundary. Remote targets reporting the local
hostname are refused; explicit `localhost`/`127.0.0.1` aliases permit
intentional local use.
