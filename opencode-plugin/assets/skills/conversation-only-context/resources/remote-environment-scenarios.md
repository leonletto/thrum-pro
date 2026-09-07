# Worked scenarios — driving remote work through a driver subagent

Five shapes you will meet. Each names what the parent keeps, what the driver
owns, and the trap specific to that shape. The pattern itself is in
`driver-subagent-pattern.md`. Placeholders: `<remote-host>` is the machine,
`<your-ssh-wrapper>` is whatever persistent-session command your project
sanctions for reaching it.

## Scenario 1 — a long lab run on a remote box

You want a multi-hour load or soak run and a verdict, not a log.

1. Spawn `vmdriver_<slug>` with `model: "sonnet"`. The GO names the run, the
   revision under test, and the exact metrics to report.
2. The driver opens a persistent session with `<your-ssh-wrapper> <remote-host>`,
   starts the run detached, and writes the exit code to its own file.
3. The driver polls that file. You do not. You go on talking to the operator.
4. The driver reports the three sections and stops.

Trap: a run started inside a one-shot remote exec dies with the connection, and
the failure reads as a crash in the thing under test. Start it detached from a
persistent session.

## Scenario 2 — a reproduction that needs a sandboxed service

The bug only appears in a running system, so a source read cannot settle it.

1. The GO orders: build the revision under test, bring up a sandboxed instance
   of the service, print that instance's identity, and confirm it differs from
   the shared instance before touching anything.
2. Only then does the driver run the reproduction steps, capturing the named
   fields before and after.
3. The report leads with the isolation proof.

Trap: sandboxing usually covers the service and its data but not every process
the service spawns. Ask the driver, in the GO, to state what its sandbox does
not cover, and to hand-clean those at teardown.

## Scenario 3 — a multi-round measurement with a parked driver

You need a baseline, a change, and a comparison, with your own judgment between
rounds.

1. Round 1 GO: take the baseline, report the fields, stop.
2. You read a short report, decide, and send round 2 by message. The driver
   still holds its session, its build, and its earlier numbers, so round 2 costs
   almost nothing to set up.
3. Round 3 asks for the comparison in the driver's own words plus the raw fields.

Trap: re-dispatching a fresh subagent between rounds throws away the warm
environment and the earlier context, then pays to rebuild both. Continue the
named driver instead.

## Scenario 4 — driving real agents inside the remote environment

You are testing behavior that only exists for a properly bound, running agent.

1. The driver brings up participants in the sandboxed environment and starts
   their runtimes.
2. It exercises behavior by sending commands into each participant's own pane,
   not from the raw shell. A raw shell is an unbound caller and tests a
   different, usually always-failing, path.
3. It reads results by capturing the pane and by inspecting the participant's
   own state files before and after.
4. It can ask a participant an investigative question and get reasoned findings
   back. These are full agents, so delegate cognition, not just keystrokes.

Trap: a pane reported alive may still be parked at a first-run trust prompt with
no runtime behind it. Verify by pane content, never by a status field.

## Scenario 5 — restart handoff of a live driver

Your context is near its limit and a driver is mid-investigation.

1. Message the driver: finish the current step, write your file, report, and
   stop.
2. Record in your restart snapshot, for that driver: its name, what it owns, its
   result file path, its model, the round it was on, and any state it left
   behind in the remote environment such as a running job, a live session, or a
   sandbox that has not been torn down.
3. State plainly which drivers have already exited.
4. Your successor respawns the driver with the result file as seed and resumes
   at the next round.

Trap: a driver left mid-flight across a restart leaves an orphaned sandbox and a
detached job nobody owns. The snapshot line about leftover state is the part
that gets skipped and the part that costs the most.

## Choosing between shapes

| Signal | Shape |
|---|---|
| One question, one long run | Scenario 1 |
| Behavior only reproduces in a live system | Scenario 2 |
| You must judge between rounds | Scenario 3 |
| The bound-caller path is what is under test | Scenario 4 |
| Your context is the binding constraint | Scenario 5 |
