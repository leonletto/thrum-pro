# The driver subagent pattern — running remote work without spending your context

Use this when the work lives somewhere your session should never go directly: a
remote host, a virtual machine, a lab box, a container, a sandboxed service. You
stay two steps removed.

```
you (parent)          holds: the question, the yes/no, a short evidence summary
  └─ named driver subagent      holds: commands, logs, retries, waiting, troubleshooting
       └─ remote environment    holds: the real system under test
```

Your context never receives build logs, file dumps, or command transcripts. The
driver holds those and answers questions about them.

## 1. One driver, named, continued by message

Create the driver once with an explicit `name` and an explicit `model`, then
continue it in rounds: GO, report, next GO. It keeps its remote session, its
findings, and its troubleshooting state across rounds.

Do this:

1. `Agent(name: "vmdriver_<slug>", model: "sonnet", prompt: <round-1 GO>)`.
2. Wait for its report.
3. `SendMessage(to: "vmdriver_<slug>", message: <round-2 GO>)`.

Do not dispatch a fresh subagent per step, and do not dispatch one told to
"monitor until done". A subagent whose turn ends is not waiting, it is gone, and
a monitor it armed in that turn never reports. Run one driver per investigation
thread and parallelize across threads, not across the steps of one thread.

## 2. Every GO carries the three clauses

State all three, every round:

1. This is the GO. Execute the sequence now. It is not another round of
   questions.
2. Drive it to completion yourself. Poll, retry, troubleshoot. Do not arm a
   monitor and end your turn.
3. Then stop and report. Nothing pending.

Clause 2 is the one that decides whether the round produces work or silence.

## 3. What a GO must contain

1. Goal, then ordered steps, each naming the exact fields to capture before and
   after.
2. The one sanctioned way to reach the environment, named explicitly, with the
   alternatives ruled out. A one-shot remote exec is usually a different shell
   with a different path and a different caller identity, so it silently tests a
   different thing than an interactive session does.
3. The exact host or target, the working directories, and the revision under
   test. A stale host alias that resolves elsewhere will pass every check while
   measuring the wrong machine, so have the driver print the resolved hostname.
4. An isolation gate, written as a numbered step, not as a caveat. See
   section 4.
5. Fences that bind the driver and anything it dispatches: read-only version
   control outside its own workspace, no installs that touch shared binaries, no
   restart of a shared service, and no recursive delete flags.
6. The report shape from section 6, including what you do not want back.

## 4. Isolation proof before acting on a shared service

If the environment also runs a shared instance of the service, every restart,
stop, or reconfigure must target the sandboxed instance. Make the driver print
the identity of the instance it is about to touch, and confirm it is the
sandboxed one, before each such action.

Verify isolation by effect rather than by intent. The sandboxed instance and the
shared one should report different identifiers, and the test participants should
be visible to the sandboxed instance and absent from the shared one.

Sandboxing is rarely total. Check what your isolation mechanism does not cover,
and have the driver clean up by hand at teardown whatever the sandbox reaper
cannot reach.

## 5. Long-running work in the remote environment

1. Prefer a persistent interactive session. Working directory, environment, and
   background jobs then survive between calls.
2. Anything longer than a couple of minutes runs detached, writing its exit code
   to its own file. A chained command hides the exit code. The driver polls that
   file. The parent never polls.
3. Run tests in the foreground with a bounded timeout and send output to a file.
   Piping through a pager or a line filter masks the real exit status and drops
   the lines that carry the stack dump.
4. When anything looks crossed or stale, tear the session down and reconnect
   rather than reasoning about which host you are on.

## 6. The report contract, driver to parent

Three sections, in this order, and nothing else:

1. Isolation proof. Which instance was touched, and evidence it was the
   sandboxed one.
2. Measured results, per step, with the exact fields captured before and after,
   and verbatim error text wherever a command failed. "It worked" without the
   fields is not a result.
3. Explicit close. Either "stopping here as instructed, nothing pending", or the
   precise point it is blocked and why.

No logs, no transcripts, no command dumps. Those stay with the driver. Ask a
follow-up round for any specific one.

## 7. Your duties as the parent

1. Verify, do not trust. An idle notification means a turn ended, not that the
   work finished. Check the agent's state before acting on it.
2. Spot-check one or two load-bearing claims from each report, such as a
   revision, an instance identifier, or a single field value. Decide which ones
   before you send the GO.
3. If a round produces no report and no progress, stop that driver and
   re-dispatch with clause 2 stated more forcefully. Do not queue another GO
   behind a dead one.
4. Never do the remote work yourself to just check quickly. That is exactly the
   context this pattern protects. Ask the driver a smaller question instead.

## 8. Anti-patterns

| Anti-pattern                              | What it produces                                 | Replacement                                                   |
| ----------------------------------------- | ------------------------------------------------ | ------------------------------------------------------------- |
| Fire-and-forget subagent told to monitor  | Long runs, large token spend, no output          | Named driver, message rounds, clause 2                        |
| One-shot remote exec instead of a session | Wrong path, wrong caller identity, wrong test    | The one sanctioned access path, stated in the GO              |
| A stale host alias                        | Results from the wrong machine, all checks green | Print the resolved hostname in the isolation proof            |
| Driving behavior from a raw shell         | Tests the unbound caller path, not the real one  | Send the command into the participant's own pane              |
| Parent reading logs to help               | Spends the context the pattern exists to protect | Ask the driver for the one field you need                     |
| Work committed on a stale base            | Invisible to everyone, diverges quietly          | Cut the workspace from current trunk, check the base revision |

## 9. Checklist before sending a GO

1. The driver is named, and I will continue it by message rather than
   re-dispatch.
2. The GO has ordered steps with captures, the sanctioned access path, the host
   and paths and revision, the isolation gate as a step, the fences, the report
   shape, and the three clauses.
3. `model` is passed explicitly.
4. I know which one or two claims I will spot-check.
5. Nothing in the GO can reach a shared service or install a shared binary.
