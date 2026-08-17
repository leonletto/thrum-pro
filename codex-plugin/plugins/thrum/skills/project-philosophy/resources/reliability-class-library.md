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

## Class 8 — Silent fail-open

**Consumers:** hotpath **thrum source:** hotpath lens `silent_fail_open` (Step
5, `project-hotpath-gate/SKILL.md`) — fallback/default-return patterns that mask
a missing or invalid dependency instead of failing loudly.

**Definition:** A code path that should fail when a required dependency,
credential, or lookup is missing instead falls back to a default value (a
default credential, a default user, an empty-but-valid-looking result) with no
log line or error surfaced to the caller.

**Why it's expensive:** The failure never announces itself — the system keeps
running on a silently-substituted default, and the divergence between "the real
thing" and "the fallback" only becomes visible once its downstream effects
(wrong data, wrong permissions) are noticed far from the fallback site.

**Detection heuristic:** find `fallback`/`default`-shaped branches immediately
following a lookup, existence check, or dependency-load attempt; a branch that
returns a default value with no accompanying log/ error/metric emission is a
finding.

**Per-language probes:**

- Go:
  `grep -rn 'fallback\|FallBack\|if !exists\|default.*return' --include='*.go'`
- Python: `grep -rn 'except:\s*pass\|\.get(\w+,\s*default_' --include='*.py'`
  (bare `except: pass` swallowing an error, or a `.get(k, default_creds)` shaped
  silent substitution)
- JS/TS:
  `grep -rn 'catch\s*{\s*}\|??\s*default' --include='*.ts' --include='*.js'` (an
  empty catch block, or a `??` fallback onto a default-shaped value with no
  logging)
- Fallback: find lookup/dependency-load call sites; check whether the failure
  branch logs/surfaces the failure or silently substitutes a default.

## Class 9 — Unconditional write on a dual-source path

**Consumers:** hotpath **thrum source:** hotpath lens for dual-source write
paths (Step 6, `project-hotpath-gate/SKILL.md`) — unconditional writes with no
last-writer-wins or version guard.

**Definition:** A shared record is writable from two or more independent sources
(an API path and a webhook/sync path, a UI edit and a background reconciler),
and at least one of those write paths performs an unconditional upsert/replace
with no last-writer-wins timestamp check or version guard — so whichever source
writes last silently wins, even when it holds stale data.

**Why it's expensive:** The two write paths race under real concurrent load, and
the bug only manifests as an occasional stale overwrite — intermittent, hard to
reproduce, and easy to misdiagnose as a caching issue rather than a missing
guard.

**Detection heuristic:** find upsert/replace statements on a path reachable from
more than one caller/trigger, and check whether a timestamp or version
comparison gates the write (vs. an unconditional `INSERT OR REPLACE`-shaped
statement).

**Per-language probes:**

- Go: `grep -rn 'INSERT OR REPLACE\|INSERT OR IGNORE' --include='*.go'` for the
  unconditional write; cross-check against
  `grep -rn 'lww\.\|GuardSQL\|GuardTarget' --include='*.go'` for an adjacent
  guard — a write-site hit with no guard hit nearby is the finding.
- Python: `grep -rn 'ON CONFLICT DO UPDATE\|session\.merge(' --include='*.py'`
  with no accompanying version/timestamp comparison in the same transaction.
- JS/TS: `grep -rn 'upsert(' --include='*.ts' --include='*.js'` on a route
  reachable from both an API handler and a webhook handler, with no
  `updatedAt`/version guard in the upsert's `where`/conflict clause.
- Fallback: find upsert/replace call sites reachable from more than one caller;
  check for a timestamp or version guard gating the write.

## Class 10 — Shared-resource poisoning

**Consumers:** hotpath **thrum source:** hotpath lens
`shared_resource_poisoning` (Step 7, `project-hotpath-gate/SKILL.md`) — a
read-only worker or side process performing writes/maintenance against a
resource other callers assume is read-only or externally managed.

**Definition:** A process or code path documented or assumed to be read-only (a
read replica, a reporting worker, a "just reads" script) actually performs
writes, schema changes, or maintenance operations (a checkpoint, a VACUUM, a
lock-escalating write) against the shared resource — poisoning it for every
other consumer that assumed read-only access was safe to run concurrently.

**Why it's expensive:** Every other caller's concurrency assumptions were built
on that resource being safely shareable for reads; a write or maintenance op
from the "read-only" side blows up those assumptions without warning, producing
lock contention or corruption that shows up in an unrelated caller.

**Detection heuristic:** find DB/file-open calls in code paths labeled or
assumed read-only, and check whether any write or maintenance statement
(checkpoint, VACUUM, PRAGMA, write query) appears in the same process.

**Per-language probes:**

- Go: `grep -rn 'OpenDB\|OpenReadDB\|sql\.Open\|sql\.OpenDB' --include='*.go'`
  for the open call, cross-checked against
  `grep -rn 'wal_checkpoint\|PRAGMA\|checkpoint\|Checkpoint' --include='*.go'`
  in the same file/package for a write/maintenance op reachable from a
  read-labeled path.
- Python: `grep -rn 'sqlite3\.connect\|open(.*[\'"]r[\'"]' --include='*.py'` in
  a worker/script documented as read-only, cross-checked for
  `.execute( ' *(INSERT|UPDATE|DELETE|VACUUM)` in the same module.
- JS/TS: `grep -rn 'fs\.open\|db\.prepare' --include='*.ts' --include='*.js'` in
  a script/worker documented as read-only, cross-checked for a write call
  (`fs.write`, an `INSERT`/`UPDATE`/`DELETE`/`VACUUM` statement) in the same
  file.
- Fallback: find the resource-open call in a read-only-labeled process; check
  whether any write or maintenance statement is reachable from the same process.

## Class 11 — Pattern divergence from the repo's own reference implementation

**Consumers:** hotpath **thrum source:** hotpath lens for reference-pattern
detection (Step 8, `project-hotpath-gate/SKILL.md`) — the repo already has an
established, correct way to do something; some call sites diverge from it.

**Definition:** The repo has an established/reference implementation of a shared
pattern (e.g. thrum's `net.Listen`-followed-by-`Serve()` vs. a listener never
served, `OpenReadDB` vs. raw `sql.Open`, a typed `safehandler.SafeHandler` vs.
legacy `json.RawMessage` handling) — and one or more call sites use an
older/legacy/ad hoc variant of the same operation instead of the current
pattern, usually because the legacy variant predates the reference
implementation and was never migrated.

**Why it's expensive:** The legacy variant misses whatever correctness or safety
property motivated the reference implementation in the first place (a missed
`Serve()` call, a missing typed-validation layer, a bypassed guard) — and
because it still compiles and runs, nothing forces the migration; the divergence
persists indefinitely as a live footgun sitting next to its own fix.

**Detection heuristic:** identify the established/reference implementation of a
shared pattern in the repo (the version most call sites use, or the one with a
tripwire test enforcing it), then find call sites performing the same operation
via a different, non-canonical route. Go: illustrative categories from
`project-hotpath-gate/SKILL.md` Step 8 — listener-serve pairing, read-only-DB
access, LWW guard usage, canonical liveness predicate, typed vs. raw handler
dispatch — are examples of the pattern class, not a single literal grep;
identify the repo's own reference pattern for each category before searching for
divergent call sites.

**Per-language probes:**

- Go: no single grep — per `project-hotpath-gate/SKILL.md` Step 8, identify the
  repo's reference pattern per category (e.g.
  `grep -rn 'net\.Listen' --include='*.go'` cross-checked for a following
  `Serve()`/`Accept()` call; `grep -rn 'OpenReadDB\|sql\.Open' --include='*.go'`
  to find both the canonical and legacy DB-open routes) and diff call sites
  against it.
- Python: repo idiom probe — find the repo's own established retry decorator
  (e.g. `grep -rn '@retry' --include='*.py'`), then
  `grep -rn 'while True:.*try:\|for _ in range(' --include='*.py'` for raw/ad
  hoc retry loops that should have used the decorator instead.
- JS/TS: apiClient vs. raw fetch — find the repo's established API-client
  wrapper (e.g.
  `grep -rln 'class ApiClient\|export.*apiClient' --include='*.ts'`), then
  `grep -rn 'fetch(\|axios\.' --include='*.ts' --include='*.js'` for call sites
  bypassing it with a raw `fetch`/`axios` call.
- Fallback: identify the repo's own reference implementation for a shared
  operation (the version most call sites use, or the one with a tripwire test);
  grep for call sites performing the same operation via a different route.

## Class 12 — Coincidence-detector tests on the hot-path test suite

**Consumers:** hotpath **thrum source:** hotpath lens `assertion_free_patterns`
(Step 9, `project-hotpath-gate/SKILL.md`) — same underlying shape as Class 6
("Controlled-zero") in this library, applied specifically to the hot-path test
suite rather than as a general review discipline.

**Definition:** A test on the hot-path test suite asserts only "no error raised"
(`require.NoError`/`assert.NoError` with no accompanying state/equality
assertion, an `assert-free` test body, a sole `.not.toThrow()` expectation) with
no assertion on the actual resulting state — see Class 6 for the general shape;
this entry targets hot-path-adjacent tests specifically, since a coincidence
detector guarding a request-handling or concurrency-sensitive path is more
expensive to leave undetected than one guarding an unrelated code path.

**Why it's expensive:** A hot-path regression (a race, a silent fallback, a
dropped write) passes the suite because the test never checked the state the
regression would have corrupted — the team's confidence that the hot path is
covered is unearned exactly where the cost of being wrong is highest.

**Detection heuristic:** for each test file touching a hot-path handler/lens
area, check whether its assertions include a state/equality check or only a bare
no-error check.

**Per-language probes:**

- Go: `grep -rn 'require\.NoError\|assert\.NoError' --include='*_test.go'`
  scoped to hot-path test files, then check whether the same test function has
  any accompanying state/equality assertion.
- Python: `grep -rln 'assert-free' 'test_*.py'` — a Python test file with no
  `assert` beyond error-absence checks (e.g. no
  `assertEqual`/`assert result ==`), scoped to hot-path-adjacent test modules.
- JS/TS: `grep -rn 'expect(.*\.not\.toThrow()' --include='*.test.ts'` as the
  sole assertion in a hot-path-adjacent test.
- Fallback: find tests covering hot-path handlers/lenses whose only assertion is
  "no error raised," with no accompanying state assertion.

## Class 13 — Incomplete class fix: sibling writers left unfixed

**Consumers:** hotpath **thrum source:** hotpath lens for sibling-resource
enumeration (Step 10, `project-hotpath-gate/SKILL.md`) — a fix applied to one
writer/handler of a shared resource while sibling writers of the same resource
type were never enumerated or checked.

**Definition:** A bug fix (a guard added, a race closed, a validation tightened)
is applied to one call site that writes a shared resource type (a projection
writer, a vault/identity file, a network listener, a DB open call) — but the
codebase has other call sites writing the same resource type that were never
enumerated during the fix, and so never received the equivalent fix.

**Why it's expensive:** The class of bug is not actually closed — only the one
instance that happened to be noticed is. The sibling call sites carry the
identical defect and will surface it later, independently, looking like a "new"
bug rather than the same one recurring, wasting a second investigation on a
problem already solved once.

**Detection heuristic:** when reviewing a fix to a shared-resource writer,
enumerate every other call site of the same resource type (via the resource's
canonical open/write primitive) and check whether each one received the
equivalent guard/fix.

**Per-language probes:**

- Go: `grep -rn 'func apply.*Tx' --include='*.go'` (projection writers),
  `grep -rn 'vault\.\|Vault\|loadIdentity' --include='*.go'` (vault/identity
  writers), `grep -rn 'net\.Listen\|net\.FileListener' --include='*.go'`
  (listeners),
  `grep -rn 'schema\.OpenDB\|schema\.OpenReadDB\|sql\.Open' --include='*.go'`
  (DB opens) — enumerate all hits per resource type and diff against which ones
  received the fix.
- Python: enumerate all writers across `*.py` —
  `grep -rn '\.execute(\|\.commit(\|session\.add(' --include='*.py'` scoped to
  the same resource/table the fix targeted, then check each hit for the
  equivalent fix.
- JS/TS: enumerate all save/write across `*.ts` —
  `grep -rn '\.save(\|\.update(\|\.write(' --include='*.ts' --include='*.js'`
  scoped to the same resource the fix targeted, then check each hit for the
  equivalent fix.
- Fallback: find the resource's canonical open/write primitive; enumerate every
  call site; check each one for the fix that was applied to the
  originally-reported site.

## Class 14 — Dead-row pre-filter: a weak liveness proxy feeding per-row cost

**Consumers:** hotpath **thrum source:** hotpath lens `dead_row_prefilter` (Step
10a, `project-hotpath-gate/SKILL.md`) — a candidate query using a weak liveness
proxy instead of the canonical liveness predicate, feeding dead rows into a
per-row-expensive operation.

**Definition:** A query selecting candidate rows for a per-row-expensive
operation (an N+1 lookup, a per-row filesystem/subprocess check) filters on a
weak proxy for "is this row still live" (a nullable timestamp column, a
loosely-named status flag) instead of the repo's canonical liveness predicate —
so rows that are actually dead by the canonical definition still pass the
pre-filter and pay the expensive per-row cost anyway.

**Why it's expensive:** The per-row cost this pre-filter exists to avoid still
gets paid, just for a population that should have been excluded — the pre-filter
creates a false sense that the expensive path is already bounded, when it is
only bounded by an approximation that under-filters.

**Detection heuristic:** find queries selecting candidates for a per-row loop
and check whether the WHERE/filter clause uses the canonical liveness predicate
(a function or well-defined phase set) or a weaker ad hoc proxy
(nullable-timestamp check, loosely-named boolean).

**Per-language probes:**

- Go:
  `grep -rn 'ended_at IS NULL\|session.*not.*closed\|phase IS NULL' --include='*.go'`
- Python: N+1 ORM loop without `select_related`/`prefetch_related` —
  `grep -rn 'for \w+ in \w+\.objects\.\(all\|filter\)(' --include='*.py'` with
  no accompanying `select_related(`/`prefetch_related(` on the same queryset.
- JS/TS: N+1 for-loop issuing per-item queries —
  `grep -rn 'for\s*(.*of.*)\s*{' --include='*.ts' --include='*.js' -A5` checked
  for an `await db.query(` or equivalent per-row call inside the loop body
  instead of a single batched query.
- Fallback: find the candidate-selection query feeding a per-row-expensive loop;
  check whether its filter uses the repo's canonical liveness predicate or a
  weaker ad hoc proxy.

## Class 15 — Frozen identity key: a shared primitive whose output is persisted

**Consumers:** hotpath **thrum source:** hotpath lens `frozen_identity_key`
(Step 10c, `project-hotpath-gate/SKILL.md`) — a shared normalizer/hash primitive
whose output is persisted or compared as a licensing/identity key, so changing
the primitive silently breaks every previously-persisted key.

**Definition:** A shared normalization or hashing primitive (a URL normalizer, a
stable-ID generator, a `sha256.Sum`-shaped function) has its output persisted to
disk, embedded in a cache/DB key, or compared for exact equality against a
stored licensing/identity value downstream. The finding is the PAIR — the
primitive plus a persisted/licensing consumer of its output — not the primitive
alone; a normalizer with no persisted consumer is not a candidate for this
class.

**Why it's expensive:** Once a primitive's output is persisted anywhere, the
primitive is effectively frozen — any change to its normalization logic (a bug
fix, a new edge case handled) silently invalidates every previously-persisted
key, and the failure mode (a returning user's license no longer matching, a
stale identity mismatch) surfaces far from the primitive that changed and long
after the change shipped.

**Detection heuristic:** find normalizer/hash primitives whose result feeds a
persisted value (a saved file, a DB column, a cache key, a JWT claim) or an
exact-equality comparison against a stored value; check whether the primitive's
contract is documented as frozen/versioned, and whether any test pins its output
against a fixed input to catch accidental drift.

**Per-language probes:**

- Go:
  `grep -rn 'GenerateRepoID\|NormalizeGitURL\|stableRepoAccount\|sha256\.Sum' --include='*.go'`
  for the primitive, cross-checked against
  `grep -rn 'SaveIdentityFile\|identities/.*\.json\|license\.\|GrantsOSS' --include='*.go'`
  for a persisted/licensing consumer downstream.
- Python: normalizer → disk/cache/DB key —
  `grep -rn 'def normalize_\| hashlib\.sha256' --include='*.py'` for the
  primitive, cross-checked against
  `grep -rn 'pickle\.dump\|redis\.set\|\.save(' --include='*.py'` for a
  persisted consumer of its output.
- JS/TS: hash → localStorage/DB key/JWT —
  `grep -rn 'crypto\.createHash\|normalize' --include='*.ts' --include='*.js'`
  for the primitive, cross-checked against
  `grep -rn 'localStorage\.setItem\|jwt\.sign\|\.save(' --include='*.ts' --include='*.js'`
  for a persisted consumer.
- Fallback: find normalizer/hash primitives; check whether their output feeds a
  persisted value or licensing comparison downstream, and whether a
  pinned-output test guards against accidental drift.

## Class 16 — Unauthenticated hot-path route

**Consumers:** hotpath **thrum source:** New for language-agnostic hotpath
onboarding (N1, dev-docs/plans/2026-08-08-language-agnostic-generators-plan.md)
— authored against docs/security_model/master.md §1.2/§1.5 scoping discipline,
not derived from an existing thrum anti-pattern.

**Definition:** A request-handling route on a hot path — one reachable by an
external, unauthenticated caller off the box (a customer-facing HTTP/RPC
endpoint) — has no authentication or authorization check in its call chain
before it touches business logic or data.

**Why it's expensive:** An externally-reachable handler with no auth check is a
direct path to data or actions the caller was never granted. This is scoped
narrowly on purpose: it applies only to a route that is actually reachable by an
unauthenticated caller off the box — an internal-only route (behind
internal-network middleware, admin-only binding, loopback-only listener), or a
deliberately open endpoint (health check, static asset, login/signup route
itself), is not a finding. Per `docs/security_model/master.md` §1.5/§1.5.2: "an
attacker not named in scope justifies nothing," and a local/internal-trust
surface is not the same threat as an externally-reachable one. This distinction
is also why thrum's own hot-path handlers get **no probe for this class in Go**
(see below) — thrum's daemon RPC surface sits behind an mTLS + pairing perimeter
that already authenticates every non-loopback caller, so "route lacking auth" is
not a coherent finding against thrum's own hot path. Do not import that
exemption into a customer repo: a typical Flask/Express/Go web service has no
equivalent perimeter, and a route handler in its public API is presumptively
externally reachable unless there is clear evidence of an internal-only guard
(internal-network middleware, admin-only bind address, an explicit auth-exempt
allowlist).

**Detection heuristic:** find route/handler registrations on the hot path (per
the target repo's routing framework) and check whether an auth
decorator/middleware/dependency guard appears in the handler's own chain (not
just declared somewhere in the app and never wired to this route). A route with
no such guard, and no adjacent evidence that it is internal-only or
intentionally public, is a finding.

**Per-language probes:**

- Go: none — thrum's own hot-path handlers sit behind the mTLS perimeter
  (docs/security_model/master.md §1.5.2); this concept targets customer repos
  with no equivalent perimeter, not thrum itself. Emit no Go probe (existing
  behavior stays byte-identical).
- Python:
  `grep -rn '@app\.\(route\|get\|post\|put\|delete\|patch\)\|@router\.\(get\|post\|put\|delete\|patch\)' --include='*.py'`,
  then for each match check the surrounding function/decorator stack for
  `@requires_auth`, `@login_required`, or a
  `Depends(verify_token)`/`Depends(get_current_user)`-shaped FastAPI dependency;
  a route with none of these, and no `# public`/`# internal-only` marker, is a
  finding.
- JS/TS:
  `grep -rn "app\.\(get\|post\|put\|delete\|patch\)(\|router\.\(get\|post\|put\|delete\|patch\)(" --include='*.ts' --include='*.js'`,
  then check whether an auth middleware (e.g. `requireAuth`,
  `passport.authenticate`, `verifyToken`) appears in the same handler's
  middleware chain before the handler body.
- Rust: open gap — the plan table specifies Go/Python/JS-TS only for this
  concept; no Rust probe has been derived here. Note as a follow-up if Rust
  hotpath support is added.
- Fallback: find the target language's route/handler registration primitive;
  check whether an auth guard (middleware, decorator, dependency-injection
  check) sits in that specific handler's chain, and treat internal-only-bound or
  explicitly-public routes as out of scope rather than findings.

## Class 17 — Secret or token value flows into a log

**Consumers:** hotpath **thrum source:** New for language-agnostic hotpath
onboarding (N2, dev-docs/plans/2026-08-08-language-agnostic-generators-plan.md)
— authored against docs/security_model/master.md §1.2/§1.5 scoping discipline,
not derived from an existing thrum anti-pattern.

**Definition:** A hot-path handler logs or prints a request object, auth header,
bearer token, API key, or other secret-shaped value — directly or via a
wholesale dump of headers/request state — rather than a redacted or field-scoped
log line.

**Why it's expensive:** Logs are typically retained far longer than the request,
read by a wider audience (log aggregators, on-call engineers, third-party
log-shipping services) than the original caller intended, and rarely treated
with the same access control as the primary datastore. A token or secret that
lands in a log is effectively broadcast to every downstream consumer of that log
stream, and the leak is invisible until someone greps the logs.

**Detection heuristic:** find log/print calls on the hot path and check whether
their arguments include a whole request/headers object, or a variable
named/typed like a token, secret, password, or API key, without an intervening
redaction step.

**Per-language probes:**

- Go: none — same caveat as Class 16 (open question, not silently invented): the
  plan table marks this concept absent for Go. Whether thrum's own daemon
  logging should get a probe for this pattern is an open question left for a
  future pass, not resolved here. Emit no Go probe (existing behavior stays
  byte-identical).
- Python:
  `grep -rn 'log\(ger\)\?\.\(info\|debug\|warning\|error\)(.*\(token\|request\.headers\|authorization\|api_key\|secret\)\|print(.*\(token\|request\.headers\|authorization\)' --include='*.py' -i`
- JS/TS:
  `grep -rn 'console\.\(log\|error\|warn\|info\)(.*\(req\.headers\|token\|authorization\|apiKey\|secret\)' --include='*.ts' --include='*.js' -i`
- Rust: open gap — the plan table specifies Go/Python/JS-TS only for this
  concept; no Rust probe has been derived here.
- Fallback: find the language's logging/print primitives on the hot path; check
  whether any call site passes a whole headers/request object or a
  token/secret/password/api-key-named variable without a redaction step first.

## Class 18 — Hot-path handler or proxy loop with no concurrency cap

**Consumers:** hotpath **thrum source:** New for language-agnostic hotpath
onboarding (N3, dev-docs/plans/2026-08-08-language-agnostic-generators-plan.md)
— authored against docs/security_model/master.md §1.2/§1.5 scoping discipline,
not derived from an existing thrum anti-pattern.

**Definition:** A hot-path handler or proxy/fan-out loop issues unbounded
concurrent work (unbounded `Promise.all`, an unguarded per-request loop dialing
out to N downstream calls, a proxy relay with no semaphore/limiter) with no cap
on in-flight concurrency and no rate limiter protecting the entry point.

**Why it's expensive:** Without a concurrency cap, load on this path scales
directly with caller-controlled fan-out (request volume, or the size of a
caller-supplied list/batch) rather than with any server-chosen bound. A burst of
legitimate traffic — or a single caller sending a large batch — can exhaust
downstream connections, memory, or file descriptors, causing backpressure
collapse for every other caller on the same process. This is a request-shape and
resource-exhaustion concern, distinct from `docs/security_model/master.md`
§1.5's out-of-scope on-path network adversary (ARP poisoning, packet drops):
sizing a concurrency cap or rate limiter against ordinary caller-controlled load
is in scope even where sizing against a network-level adversary is explicitly
not.

**Detection heuristic:** find the hot-path handler or proxy/relay loop and check
for (a) a rate limiter or throttle guarding the entry point, and (b) a
concurrency cap (semaphore, worker pool, bounded queue) around any per-request
fan-out to downstream calls. A loop or `Promise.all`-shaped fan-out with neither
is a finding; a rate-limiter decorator/middleware that was present and has since
been removed (a diff-visible regression) is also a finding.

**Per-language probes:**

- Go: none — same caveat as Class 16/17: the plan table marks this concept
  absent for Go. Emit no Go probe (existing behavior stays byte-identical).
- Python: `grep -rn 'for .* in .*:\s*$' --include='*.py' -A5` in
  proxy/relay-shaped modules, checked for an absent
  `Semaphore`/`BoundedSemaphore` around the loop body; separately
  `grep -rn '@limiter\.\(limit\|exempt\)\|@ratelimit' --include='*.py'`
  cross-checked via `git log -p` for a removed `@limiter` decorator on a
  hot-path route.
- JS/TS: `grep -rn 'Promise\.all(' --include='*.ts' --include='*.js'`, checked
  for whether the mapped array length is caller-controlled (request body/query
  param) and no chunking/`p-limit`/semaphore wraps it; separately
  `grep -rn 'rateLimit\|express-rate-limit\|limiter' --include='*.ts' --include='*.js'`
  to confirm a limiter exists on the entry point.
- Rust: open gap — the plan table specifies Go/Python/JS-TS only for this
  concept; no Rust probe has been derived here.
- Fallback: find the hot-path handler or proxy/fan-out loop; check for a rate
  limiter at the entry point and a concurrency cap (semaphore, bounded worker
  pool) around any per-request fan-out, and check version history for a removed
  limiter on that route.
