---
name: project-hotpath-gate
description: "Use when a project needs its hot-path gate configuration established or updated - the canonical config at .thrum/hotpath-gate.json defining trigger directories, subprocess patterns, lock patterns, shared resources, reference patterns, and incident prose for the coordinator-hotpath-merge-gate skill. First invocation generates from project inspection; subsequent invocations reconcile against current project state and propose diffs."
---

# Project Hot-Path Gate

## Canonical path

`.thrum/hotpath-gate.json` — the single authoritative location.
`coordinator-hotpath-merge-gate` reads from this path only.

## Run modes and dispatch order

On every invocation, dispatch in this order. Earlier branches short-circuit
later ones.

1. **First-run** (config absent) — generate a new `.thrum/hotpath-gate.json`
   from project inspection. Optionally accept seeded prose context (incident
   descriptions, fix patterns) from the invoker.
2. **Re-run-unchanged** (config present, matches current project state) — report
   "hotpath-gate.json is current; no changes needed" and exit without writing.
3. **Re-run-evolved** (config present, project has drifted) — compute a
   sectional diff, present for approval, write only on confirmation.

The modes are idempotent — running the skill repeatedly on a stable project
should produce no file changes after the first run.

> **Note: human-in-the-loop required.** This skill uses interactive prompts for
> first-run incident-prose seeding and re-run-evolved diff approval. It cannot
> run unattended in CI.

## First-run mode

Triggered when `.thrum/hotpath-gate.json` does not exist.

### Step 1: Detect language and framework

Inspect the repo root for manifest files (`go.mod`, `package.json`,
`Cargo.toml`, etc.). Record the primary language and framework. This determines
the grep patterns used in subsequent steps.

### Step 2: Detect trigger directories

Scan for directories containing code that matches hot-path patterns:

```bash
# Go: find RPC handler directories
grep -rl 'func Handle\|func.*Handler\|http\.Handle\|rpc\.' --include='*.go' | \
  sed 's|/[^/]*$||' | sort -u

# Find projection/writer directories
grep -rl 'func apply.*Tx\|Projector\.\|INSERT OR' --include='*.go' | \
  sed 's|/[^/]*$||' | sort -u

# Find storage/DB directories
grep -rl 'sql\.Open\|schema\.Open\|OpenDB\|OpenReadDB' --include='*.go' | \
  sed 's|/[^/]*$||' | sort -u

# Find sync directories
grep -rl 'sync\.\|Sync\|merge\.\|push\.' --include='*.go' | \
  sed 's|/[^/]*$||' | sort -u

# Find listener/boot directories
grep -rl 'net\.Listen\|http\.Serve\|daemon\.' --include='*.go' | \
  sed 's|/[^/]*$||' | sort -u
```

Collapse subdirectories under their parent when the parent already matches
(e.g., `internal/daemon/rpc/` under `internal/daemon/`). Record the deduplicated
list as `trigger_directories`.

### Step 3: Scan for subprocess patterns (Lens 1)

```bash
# Find all subprocess call patterns
grep -rn 'exec\.Command\|exec\.CommandContext' --include='*.go' | head -30
# Find project-specific wrappers
grep -rn 'safecmd\.\|cmd\.Exec\|runCommand' --include='*.go' | head -30
```

Record unique patterns as `subprocess_patterns`. Identify hot-path functions
(request handlers, heartbeat handlers, sweeper ticks) as `hot_path_indicators`
and `hot_path_files`.

Check for existing mitigations:

- Pre-flight guards: `grep -rn 'os\.Stat\|os\.IsNotExist' --include='*.go'`
- Non-blocking cache reads:
  `grep -rn 'Peek\|snapshot\|cache\.Get' --include='*.go'`
- Native alternatives:
  `grep -rn 'syscall\.\|unix\.\|SYS_\|/proc/' --include='*.go'`

Record as `pre_flight_guard_pattern`, `non_blocking_read_pattern`, and
`native_alternatives` respectively.

### Step 4: Scan for lock patterns (Lens 2)

```bash
# Find lock acquisition patterns
grep -rn '\.Lock()\|\.RLock()\|sync\.Mutex\|sync\.RWMutex' --include='*.go' | head -30
# Find background-detach patterns
grep -rn 'context\.WithoutCancel\|context\.Background' --include='*.go' | head -20
# Find cache peek patterns
grep -rn 'Peek\|snapshot\|Load\b' --include='*.go' | head -20
# Find singleflight patterns
grep -rn 'singleflight' --include='*.go' | head -10
```

Record as `lock_patterns`, `background_detach_pattern`, `cache_peek_pattern`,
`singleflight_pattern`, `post_commit_pattern`.

### Step 5: Scan for silent-fail-open patterns (Lens 3)

```bash
# Find fallback patterns
grep -rn 'fallback\|FallBack\|if !exists\|default.*return' --include='*.go' | head -20
# Find unconditional write patterns
grep -rn 'INSERT OR REPLACE\|INSERT OR IGNORE' --include='*.go' | head -20
# Find identity validation patterns
grep -rn 'loadIdentity\|validateIdentity\|THRUM_HOME\|SESSION_ID' --include='*.go' | head -20
```

Record as `fallback_patterns`, `append_patterns`,
`identity_validation_patterns`. Check for canonical predicates (liveness/state
functions that all call sites should use) — record as `canonical_predicate`.

### Step 6: Scan for dual-source write paths (Lens 4)

```bash
# Find shared apply paths
grep -rn 'Projector\.\|Apply\|applyTx\|apply.*Tx' --include='*.go' | head -20
# Find conflict guard patterns
grep -rn 'lww\.\|GuardSQL\|GuardTarget\|timestamp.*guard\|version.*check' --include='*.go' | head -20
# Find side-effect gating
grep -rn 'RowsAffected\|rowsAffected' --include='*.go' | head -20
```

Record as `shared_apply_path`, `unconditional_write_patterns`,
`conflict_guard_patterns`, `side_effect_gating_pattern`,
`reference_guarded_writers` (the file with the established correct pattern).

### Step 7: Scan for shared-resource poisoning patterns (Lens 5)

```bash
# Find DB open patterns (read-write and read-only)
grep -rn 'OpenDB\|OpenReadDB\|sql\.Open\|sql\.OpenDB' --include='*.go' | head -20
# Find WAL checkpoint triggers
grep -rn 'wal_checkpoint\|PRAGMA\|checkpoint\|Checkpoint' --include='*.go' | head -20
# Find raw sql usage on daemon path (bypasses safedb)
grep -rn 'db\.Query\|db\.Exec\|sql\.DB' --include='*.go' | head -20
# Find safedb wrapper
grep -rn 'safedb\.\|safedb\.DB' --include='*.go' | head -20
# Find file append patterns
grep -rn 'O_APPEND\|>>' --include='*.go' --include='*.sh' --include='*.tmpl' | head -20
# Find atomic write patterns
grep -rn 'os\.Rename\|temp.*rename\|WriteFile.*tmp' --include='*.go' | head -20
```

Record as `read_write_db_open_patterns`, `read_only_db_open`,
`reference_read_only`, `wal_checkpoint_patterns`, `raw_sql_patterns`,
`safedb_wrapper`, `append_patterns`, `atomic_write_patterns`.

### Step 8: Detect reference patterns (Lens 6)

For each of these pattern categories, find the established working example in
the codebase:

- **Listener serve**: find `net.Listen` calls that ARE followed by `Serve()` or
  `Accept()` — this is the reference pattern. Record the file and any tripwire
  test.
- **Read-only DB**: find `OpenReadDB` usage — the established read-only pattern.
- **LWW guards**: find `lww.Guard` usage in projection writers — the established
  guard pattern.
- **Canonical liveness**: find the canonical predicate function (e.g.,
  `phaseFor`/`PhaseOf`) and any tripwire test enforcing it.
- **Typed handlers**: find the typed handler pattern (e.g.,
  `safehandler.SafeHandler`) vs the legacy pattern (e.g., `json.RawMessage`).

Record each as an entry in `reference_patterns` with `name`, `check`,
`current_pattern` (the established correct pattern), `legacy_pattern` (the
deprecated pattern, if one exists), `reference_file`, `tripwire_test`. Normalize
all entries to use `current_pattern`/`legacy_pattern` consistently — some
patterns may only have one of the two. Also detect: safedb wrapper as the
established DB access pattern (vs raw sql.DB).

### Step 9: Detect tripwire test patterns (Lens 7)

```bash
# Find existing tripwire/regression tests
grep -rln 'Tripwire\|tripwire\|nosubprocess\|NoAdHoc\|Regression' --include='*_test.go' | head -20
# Find assertion-free test patterns
grep -rn 'require\.NoError\|assert\.NoError' --include='*_test.go' | head -20
```

Record as `tripwire_patterns`, `assertion_free_patterns`, `test_file_pattern`.
Clarify: `assertion_free_patterns` grep produces raw match counts — the recorded
value is the set of assertion function names that, if they are the ONLY
assertion in a test, indicate a coincidence-detector (e.g. `require.NoError`
alone without any state/equality assertion). Synthesize the list by inspecting
which assertion functions appear in isolation in existing tests.

### Step 10: Detect shared resources for sibling enumeration (Lens 8)

For each shared resource type (projection writers, vault/identity paths, network
listeners, DB open calls), find all write sites:

```bash
grep -rn 'func apply.*Tx' --include='*.go' | head -30
grep -rn 'vault\.\|Vault\|loadIdentity' --include='*.go' | head -30
grep -rn 'net\.Listen\|net\.FileListener' --include='*.go' | head -20
grep -rn 'schema\.OpenDB\|schema\.OpenReadDB\|sql\.Open' --include='*.go' | head -20
```

Record each as an entry in `shared_resources` with `resource`, `grep`,
`directory`.

### Step 10a: Scan for dead-row pre-filter patterns (Lens 9)

```bash
# Find candidate queries using weak liveness proxies
grep -rn 'ended_at IS NULL\|session.*not.*closed\|phase IS NULL' --include='*.go' | head -20
# Find canonical liveness predicate usage
grep -rn 'phaseFor\|PhaseOf\|phase.*IN\|live.*filter' --include='*.go' | head -20
# Find worktree-exists checks before per-row cost
grep -rn 'os\.Stat.*worktree\|worktree.*exists' --include='*.go' | head -20
```

Record as `candidate_query_patterns`, `canonical_predicate`,
`worktree_exists_check`, `live_phases` (the set of phase values that indicate a
live agent).

### Step 10b: Scan for peer-dial circuit-breaker patterns (Lens 10)

```bash
# Find peer/network call patterns
grep -rn 'DialFunc\|Dial(\|wait_pairing\|ReconcileOne\|ReconcileAll' --include='*.go' | head -20
# Find timeout patterns on peer calls
grep -rn 'context\.WithTimeout\|context\.WithDeadline' --include='*.go' | head -20
# Find circuit-breaker patterns
grep -rn 'circuitBreaker\|CircuitBreaker\|backoff\|maxRetries' --include='*.go' | head -20
# Find dispatch handler patterns that fan out to peers
grep -rn 'HandleSend\|HandleList\|HandleRegister\|fanout\|broadcast' --include='*.go' | head -20
```

Record as `peer_call_patterns`, `timeout_patterns`, `circuit_breaker_patterns`,
`dispatch_handler_patterns`.

### Step 10c: Scan for frozen-identity-key patterns (Lens 11)

```bash
# Find functions whose output is persisted to disk or used as a licensing/comparison key
grep -rn 'GenerateRepoID\|NormalizeGitURL\|stableRepoAccount\|sha256\.Sum' --include='*.go' | head -20
# Find persisted-identity / licensing write and compare sites
grep -rn 'SaveIdentityFile\|identities/.*\.json\|license\.\|GrantsOSS' --include='*.go' | head -20
```

Record as `frozen_output_candidates` (functions whose result is persisted to
disk, hashed into a persisted value, or compared with exact string/hash
equality) and `frozen_consumer_candidates` (the call sites that persist or
compare that output). A function with no persisted/licensing consumer is not
a candidate for this lens — the finding is the PAIR (a shared primitive +
a persisted/licensing consumer downstream of it), not the function alone.

### Step 10d: Scan for async-I/O-decoupling patterns (Lens 12)

```bash
# Find goroutines spawned inside boot stages or the OnReady closure
grep -rn 'go func\|go bootstage\.Run' --include='*.go' | head -30
# Find boot-stage/dependency wiring
grep -rn 'bootstage\.Run\|OnReady\|SetOnReady\|DependsOn\|Await(' --include='*.go' | head -20
# Find bulk I/O work patterns (compaction, migration, walk, batch DB work)
grep -rn 'CompactAll\|MergeGroup\|filepath\.Walk\|os\.ReadDir\|io\.Copy' --include='*.go' | head -20
# Find cancellation/pacing discipline (or its absence)
grep -rn 'ctx\.Done()\|ctx\.Err()\|r\.Beat(\|context\.WithoutCancel' --include='*.go' | head -20
# Find dropped-context params — a discipline gap, not a pattern to seed as "good"
grep -rn '_ context\.Context' --include='*.go' | head -20
```

Record as `io_work_candidates`, `boot_coupling_patterns`,
`async_discipline_patterns`, `dropped_ctx_candidates`. The finding this lens
exists to catch: a bulk-I/O call (from `io_work_candidates`) reachable from a
boot stage / `OnReady` / dispatch handler (`boot_coupling_patterns`) with no
matching cancellation/pacing pattern (`async_discipline_patterns`) nearby. A
goroutine spawn alone (`go func`) is not sufficient evidence of either
presence or absence — check the body for the discipline patterns.

### Step 10e: Scan for generalizable reliability classes

Read `../project-philosophy/resources/reliability-class-library.md` (shared
with the `project-philosophy` generator — see G-3). Walk only the classes
tagged `Consumers: ... hotpath` (their "hot-path facet" name is given in
parentheses). For each, run the per-language probe matching the language
detected in Step 1, and enrich the matching existing lens's `context` field
with the adapted finding (do not invent a new lens key; every hot-path-tagged
class maps onto a lens already scanned above, including the two just added):

| Library class | Hot-path facet | Enriches lens |
| --- | --- | --- |
| Class 1 — Injectable fault seam | per-request expensive-call | `subprocess_hot_path` (Step 3) |
| Class 2 — Unrecovered async failure | unrecovered-async-crash | `async_io_decoupling` (Step 10d) |
| Class 5 — Synchronous palliative vs. bounded async queue | shared-lock-across-I/O | `dispatch_blocking` (Step 4) |
| Class 5 — Synchronous palliative vs. bounded async queue | unbounded-wait | `peer_dial_circuit_breaker` (Step 10b) |

`shared_resource_poisoning` (Step 7) already has a dedicated first-run
detection step with no library counterpart needed — Class 4 (guard-adequacy)
is philosophy-only and not walked here.

A class with zero hits is not an error — record it as walked-and-not-found.

### Step 11: Accept seeded prose context

Use `AskUserQuestion` for per-lens prose seeding. With 10 lenses, prefer
sequential category→item questions (one prompt per lens, ≤4 options each) rather
than packing all lenses into a single prompt — the same pattern
`project-philosophy` uses for its per-category prompts.

Prompt the invoker for incident descriptions, fix patterns, and project-specific
nuances for each lens. These become the `context` prose fields in the config.

If the invoker has no incident prose to seed (first-time setup on a new
project), leave the `context` fields as empty strings with a
`<!-- TODO: seed with incident history -->` comment. The gate skill still
functions without prose context — it just provides less guidance to the
reviewer.

### Step 12: Generate `.thrum/hotpath-gate.json`

Assemble all discovered values into the JSON structure, now 12 lenses
(Steps 3–10d) plus Step 10e's class-library-enriched `context` fields. Write
to `.thrum/hotpath-gate.json`. Ensure the file is not gitignored (add a `!`
exception in `.gitignore` if needed, following the `.thrum/philosophy.md`
pattern).

Announce the path and summarize what was discovered, including which
reliability classes (Step 10e) were found vs. walked-and-not-found.

## Re-run-unchanged mode

Triggered when `.thrum/hotpath-gate.json` exists.

### Step 1: Read the existing config

Read `.thrum/hotpath-gate.json` in full. Parse all lens sections.

### Step 2: Sanity-check against current project state

Re-run the detection steps from first-run mode, but compare rather than write:

- Are the `trigger_directories` still correct? Any new directories with hot-path
  code?
- Are the `subprocess_patterns` still complete? Any new wrapper functions?
- Are the `reference_patterns` still accurate? Any new established patterns?
- Are the `shared_resources` complete? Any new write sites?

Each check is a boolean "matches" vs. "differs".

### Step 3: If nothing differs — no-op exit

Print: `.thrum/hotpath-gate.json` is current; no changes needed.

### Step 4: If anything differs — hand off to evolved mode

## Re-run-evolved mode

Triggered when the config exists AND the unchanged-mode sanity check flagged
drift.

> **Never silently overwrite.** The config may contain hand-seeded incident
> prose that must survive every re-run. A write without explicit confirmation is
> a bug.

### Step 1: Detect drift

Four drift categories:

- **New trigger directories** — new directories with hot-path code not in the
  config
- **New patterns** — new subprocess wrappers, lock patterns, or shared resources
- **Renamed/removed patterns** — functions renamed, files moved
- **New reference patterns** — new established working patterns or tripwire
  tests

### Step 2: Compute a proposed diff

Present drift as a readable sectional diff. Each item should have:

- The detected change in plain language
- A proposed edit (addition / removal / update to a config field)
- A one-line rationale

### Step 3: Present for approval

Present the diff. On approval, apply edits in-place, preserving surrounding
content. Append a provenance comment:
`// updated YYYY-MM-DD via project-hotpath-gate re-run-evolved`.

On decline — do NOT write. Record the skipped proposal for future runs.

## Reference

- `.thrum/hotpath-gate.json` — the config file this skill generates
- `../project-philosophy/resources/reliability-class-library.md` — the
  generalizable reliability class library Step 10e probes (hot-path-tagged
  subset); shared with `project-philosophy`
- `coordinator-hotpath-merge-gate` — the gate skill that reads this config
- `project-philosophy` — the sibling skill that generates `.thrum/philosophy.md`
  (this skill follows the same generate-first / reconcile-on-reinvoke pattern;
  run both at the same onboarding moment)
- `dev-docs/brainstorms/hotpath-merge-gate/` — the locked brainstorm with
  evidence, lens details, and design decisions
