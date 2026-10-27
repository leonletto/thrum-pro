---
name: implementer-tdd-and-quality
description: "Use when writing tests, running tests, hitting a quality gate, or before reporting a task done. Loads project-specific test and quality discipline that complements superpowers:test-driven-development."
---

# Implementer: TDD and Quality

This skill **complements** `superpowers:test-driven-development` — it does not
restate the red-green-refactor discipline, the iron law on watching tests fail,
or any other content from that skill. Layer this content on top of those
universals: the rules below capture project-specific Go conventions and
quality-gate practice.

## Run the race or concurrency check your project configures

**Why:** Code with significant concurrent state (goroutines, threads, async tasks)
can pass a plain test run and still fail under the language's race or concurrency
checker, sometimes with silent data corruption that takes hours to track down later.

**How to apply:** Read `.thrum/gate-config.json` (the `per_landing` entries of kind `race`,
or the commands your project documents) and run the race or concurrency check it names
on the packages you touched. Never report tests passing without having run it, when your
project has one. If your project has none, say so in your report. (Go example:
`go test -race ./internal/<pkg>/... -count=1`.)

## Scope test runs to packages you touched

**Why:** Running the entire test tree on every iteration of a fix-test loop is
wasteful — most packages weren't touched and their tests will pass identically
every iteration. Scoping speeds the inner loop without sacrificing correctness;
the full tree gets one final run before reporting done.

**How to apply:** During the inner fix-test loop, run only the affected
packages with a test selector (Go example:
`go test -race ./internal/<pkg>/... -run <TestName>`). Once the scoped tests pass
and you're ready to report done, run the whole-lane test command from
`.thrum/gate-config.json` (`per_landing`, or `full_fallback` when selection cannot run) once
to confirm nothing else broke.

## Use `t.TempDir()` for filesystem fixtures — never hardcoded paths

**Why:** Hardcoded absolute paths (especially the implementer's home directory)
only work on one machine. A test that bakes in a literal path like
`<repo-root>` passes locally and fails everywhere else — the fix is usually as
small as swapping in `t.TempDir()`. The same pattern shows up with
`os.UserHomeDir()` results being baked into expected values.

**How to apply:** Any test that creates a temporary directory, writes files, or
needs an isolated git repo must use `t.TempDir()`. It is cleaned up
automatically and is unique per test run. If you need a git repo, initialize it
in the temp dir: `cmd := exec.Command("git", "init", t.TempDir())`. For fixtures
comparing paths, capture the temp dir into a variable and reference it in
expected values — never hardcode.

## Run the static checks before reporting

**Why:** Static analysis (a vet pass, a type check, a linter) catches a class of bugs
that compile but are wrong: unreachable code, suspicious conversions, malformed format
arguments. Code that fails the checks gets caught in CI or by review; running them
locally catches it pre-commit when the fix is one line.

**How to apply:** Before reporting done, run the lint and static-check commands from
`.thrum/gate-config.json` (`per_landing` kinds `lint`, plus `structural_checks`), or the
commands your project documents. All should pass clean. Run a check in its read-only
form, never a fix mode that rewrites tracked files (the `write_capable_targets` there).
If a finding looks like a false positive, prefer a small annotation or refactor to
silencing the warning. (Go example: `go vet ./...`.)

## Two-stage self-review before pinging the coordinator

**Why:** A self-review pass before the coordinator's dual review reduces total
review round-trips. Self-review is not ceremony; it pre-pays the cost of issues
that would otherwise come back as findings.

**How to apply:** At task close, before sending DONE:

1. **Spec compliance pass.** Read each acceptance criterion from the task
   description. For every test case the spec mentions, verify it exists in the
   test file. For every behavior change the spec specifies, verify it's
   implemented and tested.
2. **Code quality pass.** Read your full diff
   (`git --no-pager diff <base>...HEAD`). Watch for: hardcoded paths,
   `os.UserHomeDir` baked into tests, inline `exec.Command` calls that should
   use `safecmd`, swallowed errors, missing `slog` calls on recoverable
   failures.
3. **Primitive ledger pass.** If this diff adds I/O or SQL under a hot root
   (`Handle*`/tick/sweeper/`SyncApplier`/boot — see `.thrum/hotpath-gate.json`'s
   `lenses.existing_primitive_bypass.hot_root_indicators`), confirm you have a ledger row: raw op -> callee
   package searched -> primitive adopted, or none exists + bounded cost formula
   (frequency x production cardinality, at production scale). Include it in
   your DONE report.
   - Before writing a raw read-in-loop, `db.Query`-in-loop, `COUNT(DISTINCT ...)`, or a second transaction or pool acquisition per logical unit under a hot root, search the callee package for an existing targeted, cached, covering or batch primitive.

Fix what you find before sending the ping.

## Project-specific rules (already loaded)

Load the /thrum:project-rules-protocol skill and follow it.

If you accumulate a new rule mid-session (the user corrects you), capture it via
the Memory section of your role preamble — it references the
`thrum-memory` skill for the canonical `thrum memory create` shape.
