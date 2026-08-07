# Reliability Class Library

Shared reference loaded by `project-philosophy` (all 7 classes) and
`project-hotpath-gate` (classes tagged `hotpath` below, via their hot-path
facet). Distilled from thrum's own 15 anti-patterns (`.thrum/philosophy.md`)
plus the Hipp/SQLite crash-recovery lessons
(`dev-docs/thrum-test-strategy-update/`). Each class is a generalizable failure
SHAPE, not a thrum-specific rule — adapt the probes to the target repo's
detected language before writing anything into a generated doc.

For each class found in the target repo, render it as a BAD/GOOD anti-pattern
using the repo's own language and idioms — never paste thrum's Go examples into
a non-Go repo's philosophy.md.

## Class 1 — Injectable fault seam

**Consumers:** philosophy, hotpath (hot-path facet: per-request expensive-call)
**thrum source:** AP#1 (`.thrum/philosophy.md`); the VFS lesson (SQLite's OS
layer is a swappable driver so every I/O failure mode is testable without
touching a real disk).

**Definition:** A call into the OS, filesystem, or network that can fail
(process exec, file open/read/write, socket dial, DNS) is made directly from
business logic, with no seam through which a test can inject failure. Production
and test share one code path with zero swap point.

**Why it's expensive:** The only tested failure mode is "call succeeds." Real
failures (ENOSPC, EMFILE, a hung subprocess, a network partition) are exercised
for the first time in production, and the fix usually lands as an ad hoc special
case rather than a reusable fault-injection seam.

**Detection heuristic:** grep the language's process-exec, file-open, and
network-dial primitives; a hit directly inside a request-handler or
business-logic file (not an isolated adapter/driver/VFS-shaped module) is a
finding.

**Per-language probes:**

- Go:
  `grep -rn 'exec\.Command\|exec\.CommandContext\|os\.Open\|net\.Dial' --include='*.go'`,
  excluding `*_test.go` and any package with `driver`/`fault`/`vfs` in its path.
- Python:
  `grep -rn 'subprocess\.\(run\|Popen\|call\)\|open(\|socket\.\(connect\|create_connection\)' --include='*.py'`
- JS/TS:
  `grep -rn 'child_process\.\(exec\|spawn\)\|fs\.\(readFile\|writeFile\)Sync\?\|net\.connect\|http\.request' --include='*.ts' --include='*.js'`
- Rust:
  `grep -rn 'std::process::Command\|std::fs::File::open\|TcpStream::connect' --include='*.rs'`
- Fallback: search the language's canonical process-spawn and low-level
  file/socket primitives; a hit inside business logic rather than an adapter
  module is the finding.

## Class 2 — Unrecovered async failure kills the host process

**Consumers:** philosophy, hotpath (hot-path facet: unrecovered-async-crash)
**thrum source:** the goroutine-crash finding behind hotpath lens
`async_io_decoupling` (new I/O work added inside a daemon boot stage or dispatch
handler with no recovery if that work panics/throws).

**Definition:** Work is moved onto a background thread/goroutine/async task for
latency reasons, but a panic, unhandled rejection, or unrecovered exception on
that path is not caught — it kills (or silently wedges) the whole host process
instead of failing just that one unit of work.

**Why it's expensive:** The failure is invisible until the specific input that
trips it arrives in production; the symptom (daemon down, service restarted)
points nowhere near the async call site that caused it.

**Detection heuristic:** every `go func`/async-task/background-thread spawn on a
request or boot path needs a recover/catch immediately inside it. A spawn with
no enclosing recover/catch in the same function is a finding.

**Per-language probes:**

- Go: `grep -rn 'go func' --include='*.go' -A3 | grep -B3 -L 'recover()'`
  (spawns not immediately followed by a deferred recover)
- Python: `grep -rn 'asyncio\.create_task\|Thread(target=' --include='*.py'`
  then check the target/coroutine body for a bare `try/except`
- JS/TS:
  `grep -rn 'setTimeout\|setImmediate\|\.then(\|async function' --include='*.ts' --include='*.js'`
  then check for an unhandled-rejection or `.catch()` immediately at the call
  site
- Rust: `grep -rn 'tokio::spawn\|std::thread::spawn' --include='*.rs'` then
  check for `catch_unwind` or a supervised-restart wrapper
- Fallback: find the language's background-task/thread-spawn primitive; a spawn
  with no local recovery wrapper is the finding.

## Class 3 — Destructive reconcile on fresh install (empty canonical is a wipe)

**Consumers:** philosophy only **thrum source:** AP#13 (`.thrum/philosophy.md`)
— fresh-install blast radius.

**Definition:** A reconcile/sync/cleanup routine treats an EMPTY canonical
source (first boot, no state yet) the same as a canonical source that says
"delete everything" — so the very first run of the tool wipes whatever
pre-existing data it finds, because "nothing here yet" and "delete everything"
are indistinguishable to the code.

**Why it's expensive:** The bug only fires once per install, on the very first
run, against whatever real data happens to already be present — by the time
anyone notices, the data is gone and the repro is hard to reconstruct.

**Detection heuristic:** find any routine that deletes/prunes/reconciles a
directory or table against a canonical list, and check whether an empty
canonical list is special-cased (hold/no-op) or falls through to "delete
everything not in the list."

**Per-language probes:**

- Go:
  `grep -rn 'os\.RemoveAll\|DROP TABLE\|DELETE FROM.*WHERE.*NOT IN' --include='*.go'`
- Python:
  `grep -rn 'shutil\.rmtree\|os\.remove\|DELETE FROM.*NOT IN' --include='*.py'`
- JS/TS:
  `grep -rn 'fs\.rm\(Sync\)\?\|rimraf\|DELETE FROM.*NOT IN' --include='*.ts' --include='*.js'`
- Fallback: find the language's recursive-delete primitive and any "reconcile
  against canonical list" SQL/logic; check for an explicit empty-canonical
  guard.

## Class 4 — Guard-adequacy: presence verified, capability not

**Consumers:** philosophy only **thrum source:** AP#12 (`.thrum/philosophy.md`)
— marked "universal" in the spec.

**Definition:** A guard checks that something EXISTS (a file, a flag, a config
key, a permission record) but never checks that it actually WORKS or grants the
capability the caller assumes it grants. The guard passes on a
present-but-broken/present-but-insufficient state.

**Why it's expensive:** Code downstream of the guard trusts it fully, so a
present-but-inadequate state produces a confident wrong action instead of a loud
failure — the guard is worse than no guard because it suppresses the obvious
symptom.

**Detection heuristic:** find `if <thing> exists/present/!= nil` checks
immediately gating a privileged or destructive action; check whether the check
verifies capability (a successful no-op call, a real permission check) or only
presence.

**Per-language probes:**

- Go: `grep -rn 'if.*!= nil {' --include='*.go' -B2` near privileged actions,
  cross-checked against whether the referenced value is ever exercised (called)
  before use
- Python: `grep -rn 'if os\.path\.exists\|if.*is not None' --include='*.py'`
  near privileged actions
- JS/TS: `grep -rn 'if\s*(\w+)\s*{' --include='*.ts' --include='*.js'` near
  privileged actions
- Fallback: find presence-only guards (existence/non-null checks) immediately
  preceding a privileged or destructive call, with no accompanying capability
  check.

## Class 5 — Synchronous palliative vs. bounded async queue

**Consumers:** philosophy, hotpath (hot-path facets: shared-lock-across-I/O,
unbounded-wait) **thrum source:** AP#11 (`.thrum/philosophy.md`) — synchronous
palliative on a shared serialization point; the Hipp/SQLite lesson of removing a
slow component rather than patching around it with more synchronous work.

**Definition:** A shared serialization point (a global lock, a single writer
connection, a single dispatch queue) is under contention, and the fix adds MORE
synchronous work inside that same critical section (a retry loop, a longer
timeout, a synchronous fan-out call) instead of moving the work off the
serialization point onto a bounded async queue.

**Why it's expensive:** Each palliative fix narrows the failure window without
removing the root cause, so contention resurfaces under slightly higher load,
and the critical section keeps growing — eventually turning a brief lock hold
into an unbounded wait that stalls every caller behind it.

**Detection heuristic:** find a lock/mutex/single-connection acquisition
immediately followed by I/O (network call, subprocess, blocking file op) inside
the same critical section, or a synchronous call on a request/dispatch path with
no timeout/circuit breaker.

**Per-language probes:**

- Go: `grep -rn '\.Lock()\|\.RLock()' --include='*.go' -A10` then check whether
  a network/exec/blocking call appears before the matching `Unlock()`;
  separately
  `grep -rn 'context\.WithTimeout\|context\.WithDeadline' --include='*.go'` to
  check whether peer/network calls on a dispatch path have one
- Python: `grep -rn 'with.*[Ll]ock' --include='*.py' -A10` for I/O inside the
  block; `grep -rn 'requests\.\(get\|post\)\|socket\.' --include='*.py'` for
  missing `timeout=`
- JS/TS:
  `grep -rn 'await mutex\.\|\.acquire()' --include='*.ts' --include='*.js' -A10`
  for I/O inside the held span
- Fallback: find the language's lock-acquisition primitive; check whether I/O
  happens while held, and whether outbound calls on a hot path carry an explicit
  timeout.

## Class 6 — Controlled-zero: a green check that cannot come back negative

**Consumers:** philosophy only (universal review discipline, not a hot-path
lens) **thrum source:** universal review discipline, generalized from thrum's
own merge-gate meta-checks.

**Definition:** A test, health check, or CI gate that reports "clean" or "zero
findings" whether or not it actually ran — an empty result set is
indistinguishable from "nothing wrong" and "the check silently didn't execute"
(wrong filter, empty fixture, mocked-away dependency, a `--dry-run` flag left
on).

**Why it's expensive:** Confidence in the check compounds — a green check that
cannot come back negative is worse than no check, because it is relied upon
precisely where a real problem would otherwise have been caught.

**Detection heuristic:** for any assertion-free or count-based check (a test
asserting only "no error," a CI step asserting only exit code 0), ask whether
there is a companion negative control proving the check COULD have failed (a
deliberately broken fixture, an invented-symbol probe).

**Per-language probes:**

- Go:
  `grep -rln 'require\.NoError(t, err)$\|assert\.NoError(t, err)$' --include='*_test.go'`
  (assertion-free tests: NoError with no accompanying state/equality assertion)
- Python: `grep -rn 'assert.*is None\|# no assert' --include='test_*.py'`
- JS/TS: `grep -rn 'expect(.*\.not\.toThrow()' --include='*.test.ts'`
- Fallback: find tests/checks whose only assertion is "no error raised," with no
  accompanying positive assertion on state, and no adjacent negative-control
  test.

## Class 7 — Crash/power-loss recovery and migration against real old data

**Consumers:** philosophy only **thrum source:** the SQLite core disciplines
(Hipp/SQLite talk); ties to thrum's own REL-1 migration-corpus work.

**Definition:** A durable store's crash-recovery path (WAL replay, journal
recovery, migration-on-boot) is tested only against synthetic in-memory fixtures
created by the current code version — never against a real on-disk snapshot from
an OLDER schema version, and never by actually killing the process mid-write and
restarting it.

**Why it's expensive:** The disciplines that matter (does recovery converge on a
truly random torn write? does a migration handle a customer's real months-old
on-disk state, not a freshly-created one?) are exactly the ones a synthetic
in-code fixture cannot exercise — bugs here surface only against a real
customer's real old data, in production.

**Detection heuristic:** find the migration/recovery entrypoint (schema version
check, WAL/journal replay on boot) and check whether any test kills the process
mid-write (not just simulates a corrupt file) and whether any test runs a
migration against a captured real on-disk snapshot rather than a freshly-created
fixture.

**Per-language probes:**

- Go:
  `grep -rn 'CurrentVersion\|migrat\|wal_checkpoint\|journal_mode' --include='*.go'`,
  then `grep -rln 'os\.Kill\|SIGKILL\|process\.Kill' --include='*_test.go'` for
  mid-write kill tests
- Python: `grep -rn 'alembic\|migration' --include='*.py'`, then check test
  fixtures for a captured real DB snapshot vs. a freshly-created one
- Node/TS: `grep -rn 'migrate\|knex\.' --include='*.ts'`, same fixture check
- Fallback: find the migration/recovery entrypoint; check for a mid-write-kill
  test and a real-old-snapshot migration test, not just synthetic fixtures.
