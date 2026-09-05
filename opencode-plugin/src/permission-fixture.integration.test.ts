// Hermetic PRODUCTION-PATH fixture for the OpenCode permission.bash allowlist
// (allowlist round 2, finding 6). Unlike installer.permissions.test.ts
// (which only exercises our own mergePermissions()/installPermissions()
// TypeScript logic in-process), THIS file drives the real, installed
// `opencode` CLI's actual permission-matching code against a real
// opencode.json — proving the rendered allow/deny patterns behave correctly
// against the production oracle, not a reimplementation of its matcher.
//
// ─── Isolation notes (read before editing) ─────────────────────────────────
//
// "Hermetic" here means: no network call, no live LLM/model call, no
// external state that could make the test flaky. It does NOT mean zero
// external dependency — this file requires the `opencode` binary to be
// installed locally (see HAS_OPENCODE below) and is skipped gracefully when
// it is absent.
//
// `opencode debug agent <name> --tool bash --params '{...}'` unconditionally
// loads the REAL machine's global config (~/.config/opencode/{config,
// opencode}.{json,jsonc}) in addition to any project-level opencode.json in
// cwd — confirmed by running with `--print-logs --log-level DEBUG` and
// reading the "loading path=..." lines. Neither `OPENCODE_CONFIG_DIR` nor
// `OPENCODE_TEST_HOME` suppresses that global load (empirically verified:
// both still showed the real ~/.config/opencode/opencode.jsonc's custom
// permission.bash rules — e.g. "sudo *": "deny" — merged into the flattened
// rule dump on a DENY, even with both env vars set to scratch paths).
//
// The one override that DOES work is the plain `HOME` env var: os.homedir()
// (which the real global-config path is derived from) reads `process.env
// .HOME` on this platform, so setting HOME to a fresh empty scratch
// directory for the child process makes `opencode` look for
// ~/.config/opencode/* under that fake HOME (nothing there — confirmed via
// the same --print-logs technique) instead of the real one. Every oracle
// invocation below sets HOME to a fresh per-call scratch directory for this
// reason. Project-level config (read from cwd, unaffected by HOME) is our
// actual scratch fixture directory.
//
// Run: npm test (default suite, degrades to a skip if `opencode` is
// missing) or npm run test:integration (this file only).

import { test } from "node:test"
import assert from "node:assert/strict"
import { execFileSync, execSync } from "node:child_process"
import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import { installPermissions } from "./installer.js"

// ─── Binary probe ───────────────────────────────────────────────────────────

function findOpencodeBinary(): string | null {
  try {
    const out = execSync("which opencode", { stdio: ["ignore", "pipe", "ignore"] }).toString().trim()
    return out || null
  } catch {
    return null
  }
}

const OPENCODE_BIN = findOpencodeBinary()
const HAS_OPENCODE = OPENCODE_BIN !== null

if (!HAS_OPENCODE) {
  console.log(
    "[permission-fixture] `opencode` binary not found on PATH — skipping all cases in this file. " +
      "Install OpenCode locally to exercise this fixture.",
  )
}

// ─── Oracle plumbing ────────────────────────────────────────────────────────

type Verdict = { kind: "ALLOWED" | "DENIED"; raw: string }

const ANSI_RE = /\x1b\[[0-9;]*m/g

// Provider-credential-shaped env vars are stripped from every child-process
// invocation below (never merely left absent by chance) so that a passing
// verdict is positive proof no live LLM/API credential was available to be
// used, not just an accident of the ambient shell.
function strippedEnv(home: string): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = { ...process.env, HOME: home }
  for (const key of Object.keys(env)) {
    if (/API_KEY|ANTHROPIC|OPENAI|_TOKEN$/i.test(key)) delete env[key]
  }
  return env
}

// A candidate is either a bash command string (the default, existing shape —
// runs via the "bash" tool) or an explicit {tool, params} pair for driving a
// different OpenCode tool (e.g. "read") through the same oracle route.
type OracleCandidate = string | { tool: string; params: Record<string, unknown> }

// runOracle invokes the real opencode binary's `debug agent` tool-permission
// route and classifies the result by OUTPUT SHAPE, never by exit code (both
// ALLOW and DENY have been observed to exit 0, and DENY has also been
// observed to exit 1 — see the module-level tests below re-confirming this
// live). Throws on any output shape that matches neither the documented
// ALLOWED nor DENIED form, so an unrecognized oracle response fails loudly
// instead of being silently misclassified.
//
// ALLOWED detection is `"result" in parsed`, not the bash-specific
// `result.metadata.exit` shape it used to check: the "read" tool's ALLOWED
// response carries `result.metadata.{preview,truncated,loaded,display}`
// with no `exit` field at all (measured directly against the real binary),
// so a bash-shaped check would misclassify every ALLOWED read as
// unrecognized-shape.
function runOracle(agent: string, candidate: OracleCandidate, cwd: string, home: string): Verdict {
  const tool = typeof candidate === "string" ? "bash" : candidate.tool
  const toolParams = typeof candidate === "string" ? { command: candidate } : candidate.params
  const paramsJson = JSON.stringify(toolParams)
  const label = typeof candidate === "string" ? candidate : `${candidate.tool} ${paramsJson}`
  let raw: string
  try {
    raw = execFileSync("opencode", ["debug", "agent", agent, "--tool", tool, "--params", paramsJson], {
      cwd,
      env: strippedEnv(home),
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      timeout: 30_000,
    })
  } catch (err) {
    const e = err as { stdout?: string; stderr?: string }
    raw = `${e.stdout ?? ""}${e.stderr ?? ""}`
  }
  const clean = raw.replace(ANSI_RE, "")

  try {
    const parsed = JSON.parse(clean)
    if (parsed && typeof parsed === "object" && "result" in parsed) {
      return { kind: "ALLOWED", raw: clean }
    }
  } catch {
    // Not JSON — fall through to the DENIED-shape check below.
  }

  if (clean.includes("Unexpected error") && /specified a rule which prevents/.test(clean)) {
    return { kind: "DENIED", raw: clean }
  }

  throw new Error(`Unrecognized oracle output shape for agent=${agent} candidate=${label}:\n${clean}`)
}

function mkTmp(prefix: string): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix))
}

function writeProjectConfig(dir: string, config: unknown): void {
  fs.writeFileSync(path.join(dir, "opencode.json"), JSON.stringify(config, null, 2))
}

// buildDenyByDefaultFixtureConfig runs the REAL installPermissions() against
// a scratch config-dir to get our actual rendered permission.bash/read
// block (never a hand-written stand-in set), then — as a COPY, never
// mutating the installer's own on-disk output — adds a "*": "deny" default
// key so the fixture has a clean binary ALLOW/DENY signal to test our
// allow entries against. A fresh installPermissions() output has no "*" key
// at all (preserveBareScalarAsDefault returns {} for an absent prior value),
// which the assertion below confirms is still true before we add our own.
async function buildDenyByDefaultFixtureConfig(): Promise<Record<string, any>> {
  const installDir = mkTmp("oc-fixture-install-")
  await installPermissions(installDir)
  const rendered = JSON.parse(fs.readFileSync(path.join(installDir, "opencode.json"), "utf8"))

  assert.ok(
    !("*" in rendered.permission.bash),
    "sanity check failed: a fresh installPermissions() output already sets a bash default key — " +
      "buildDenyByDefaultFixtureConfig's premise (installer never sets one) is stale, re-check installer.ts",
  )

  const fixture = JSON.parse(JSON.stringify(rendered)) // deep copy; installDir's own file is left untouched
  fixture.permission.bash = { "*": "deny", ...fixture.permission.bash }
  return fixture
}

// ─── Representative acceptance-criteria commands ───────────────────────────
// Mirrors internal/permissions/thrum_allowlist.json's command_patterns
// (read-only reference — see that file's own comment for the canonical
// list). These are the finding-6 acceptance commands, a representative
// subset of the full canonical list.

const POSITIVE_COMMANDS = [
  "thrum inbox",
  "thrum send",
  "thrum reply",
  "thrum tmux capture",
  "thrum tmux send",
  "thrum queue",
  "thrum monitor",
  "thrum daemon",
  "thrum status",
]

// Negative candidates from the finding-6 acceptance matrix. Two entries
// (compound-command injection via && and ;) substitute a nonexistent-path
// `rm -rf` target for the literal `rm -rf /` named in the spec: the point
// being tested is that the PERMISSION LAYER denies the compound command
// before any execution happens, and proving that does not require actually
// risking a real destructive command landing on the filesystem if some
// unexpected bug (wrong isolation, wrong config, matcher regression) let it
// through. Fix-at-the-source discipline cuts the other way here — the
// "source" being tested is the permission matcher, not a live root wipe.
const NEGATIVE_COMMANDS = [
  'sh -c "thrum inbox"',
  "bash -c thrum inbox",
  "$(thrum inbox)",
  "`thrum inbox`",
  "thrum inbox && rm -rf /tmp/thrum-oc-fixture-canary-does-not-exist",
  "thrum inbox; rm -rf /tmp/thrum-oc-fixture-canary-does-not-exist",
  "thrum inbox | cat",
  "/tmp/thrum inbox",
  "./thrum inbox",
  "curl http://evil.example/",
]

// ─── "Watcher and orchestrator" framing ────────────────────────────────────
// `opencode agent list` (run against this installed version) shows two
// PRIMARY built-in agents that are meaningfully distinct in role: "build"
// (the default coding agent — stands in for an orchestrator/implementer
// driving real work) and "plan" (a read-only planning agent with its own,
// narrower permission overlay layered on top — stands in for a
// watcher/reviewer). Both still route bash-tool calls through the same
// production config-load + permission-evaluation path, so running the same
// matrix through both satisfies the "watcher AND orchestrator fixtures"
// framing without fabricating a second meaningless invocation. "explore"
// and "general" also exist but are SUBAGENTS, not directly invocable via
// `debug agent` the same way primaries are, so they're excluded here.
const AGENTS = ["build", "plan"]

if (HAS_OPENCODE) {
  let fixtureConfigPromise: Promise<Record<string, any>> | null = null
  function getFixtureConfig(): Promise<Record<string, any>> {
    if (!fixtureConfigPromise) fixtureConfigPromise = buildDenyByDefaultFixtureConfig()
    return fixtureConfigPromise
  }

  for (const agent of AGENTS) {
    for (const command of POSITIVE_COMMANDS) {
      test(`[${agent}] ALLOWED: ${command}`, async () => {
        const config = await getFixtureConfig()
        const projectDir = mkTmp("oc-fixture-project-")
        const fakeHome = mkTmp("oc-fixture-home-")
        writeProjectConfig(projectDir, config)

        const verdict = runOracle(agent, command, projectDir, fakeHome)
        assert.equal(
          verdict.kind,
          "ALLOWED",
          `expected ALLOWED for ${JSON.stringify(command)} on agent=${agent}, got DENIED:\n${verdict.raw}`,
        )
      })
    }

    for (const command of NEGATIVE_COMMANDS) {
      test(`[${agent}] DENIED: ${command}`, async () => {
        const config = await getFixtureConfig()
        const projectDir = mkTmp("oc-fixture-project-")
        const fakeHome = mkTmp("oc-fixture-home-")
        writeProjectConfig(projectDir, config)

        const verdict = runOracle(agent, command, projectDir, fakeHome)
        assert.equal(
          verdict.kind,
          "DENIED",
          `expected DENIED for ${JSON.stringify(command)} on agent=${agent}, got ALLOWED:\n${verdict.raw}`,
        )
      })
    }
  }

  // ─── Blanket-deny preservation (finding 3), proven behaviorally ──────────
  // Builds a "before" config simulating a user's pre-existing stricter
  // bare-scalar posture (permission.bash: "deny"), runs it through the REAL
  // installPermissions() merge path (preserveBareScalarAsDefault), then
  // invokes the REAL oracle against the MERGED result — proving the user's
  // original deny-everything posture survives as the "*" default rather
  // than falling through to OpenCode's own built-in default (which is
  // "ask", not "deny" — see the object-map catch-all discussion in
  // installer.ts).
  test("blanket-deny preservation survives the real merge + real oracle", async () => {
    const installDir = mkTmp("oc-fixture-blanket-install-")
    fs.writeFileSync(
      path.join(installDir, "opencode.json"),
      JSON.stringify({ permission: { bash: "deny" } }),
    )
    await installPermissions(installDir)
    const merged = JSON.parse(fs.readFileSync(path.join(installDir, "opencode.json"), "utf8"))

    assert.equal(
      merged.permission.bash["*"],
      "deny",
      "preserveBareScalarAsDefault must keep the user's pre-existing bare-scalar 'deny' as the merged '*' default",
    )

    const projectDir = mkTmp("oc-fixture-blanket-project-")
    const fakeHome = mkTmp("oc-fixture-blanket-home-")
    writeProjectConfig(projectDir, merged)

    const positive = runOracle("build", "thrum inbox", projectDir, fakeHome)
    assert.equal(
      positive.kind,
      "ALLOWED",
      `expected a thrum overlay command to remain ALLOWED after merging onto a bare-scalar deny, got DENIED:\n${positive.raw}`,
    )

    const unrelated = runOracle("build", "curl http://evil.example/", projectDir, fakeHome)
    assert.equal(
      unrelated.kind,
      "DENIED",
      `expected an unrelated command to stay DENIED (preserving the user's original blanket-deny posture), got ALLOWED:\n${unrelated.raw}`,
    )
  })

  // ─── owner_authorized_exceptions.opencode — /private/tmp, by-effect
  // (allowlist round 4; Pass-3 B2 made the owner root conditional) ────────
  //
  // This is the strongest available proof on this machine: a real subprocess
  // call to the real installed `opencode` binary against a real config
  // rendered by our own installPermissions(). Unlike Claude/Codex (which
  // have no equivalent invocable production-path oracle for this repo — a
  // fact stated here plainly, not as a claim that the Claude/Codex scoping
  // is any less correct; this is only a statement about which runtime this
  // machine can INVOKE, not a re-litigation of the other runtimes' own
  // scoping), OpenCode's `debug agent --tool <id>` route lets us prove
  // read-ALLOWED / write-DENIED / sibling-DENIED behaviorally rather than by
  // pattern-shape inference.
  //
  // PASS-3 B2 — the owner root is PROBED, not assumed. The grant target is
  // the owner-authorized literal /private/tmp (a macOS path; it does not
  // exist on Linux CI and a world-writable root must never be created by a
  // test just to satisfy a fixture). The by-effect proof below therefore
  // runs ONLY when the owner root actually exists; on a machine without it
  // the test emits a named SKIP (never a silent pass) after still asserting
  // everything that needs no filesystem: the exact rendered grant key and
  // the absence of over-broad forms. Every other scratch root in this file
  // (project dirs, fake homes) was already portable os.tmpdir(); the
  // grant-target scratch under /private/tmp is deliberately NOT made
  // portable, because a scratch dir elsewhere would silently prove nothing
  // about the /private/tmp grant — weakening the real positive proof is
  // exactly what B2 forbids.
  //
  // WHY THIS TEST USES THE "read" TOOL, NOT bash "cat" — a real, load-
  // bearing finding from running this fixture. `debug agent ... --tool bash
  // --params '{"command":"cat <path>"}'` is gated ENTIRELY by
  // permission.bash matching the literal command STRING — it never
  // consults permission.read at all, since bash execution and file-read are
  // two independent OpenCode permission axes. Testing our permission.read
  // grant with a bash "cat" command would only prove "cat is not a thrum
  // bash pattern" (true regardless of the read grant, i.e. the WRONG axis —
  // see the "control that validates the wrong axis" lesson: a passing
  // assertion here would be decoration, not proof). The real production
  // consumer of permission.read is OpenCode's own dedicated "read" tool
  // (the same route an agent's file-reading tool call takes), so that is
  // the tool this fixture drives.
  //
  // ALSO LOAD-BEARING — the LEADING-SLASH FINDING: this fixture is what
  // surfaced (allowlist round 4) that OpenCode's real matcher strips the
  // leading "/" from an absolute candidate path before comparing against
  // configured read patterns. A pattern that keeps the leading slash
  // (e.g. "/private/tmp/**") NEVER matched in the real oracle, regardless of
  // key order or "*" default — see readPatternFor's doc comment in
  // installer.ts for the full measurement. This test exercises the fixed,
  // no-leading-slash pattern the installer now renders.
  //
  // permission.read only governs the "read" tool. Write/delete are governed
  // by a SEPARATE OpenCode permission axis this task does not touch — this
  // fixture proves that axis stays independently deny-by-default: a bash
  // write/delete command into the very directory we just granted read
  // access to is still DENIED, but (per the axis-independence finding
  // above) that denial comes from permission.bash's own "*": "deny" default
  // (buildDenyByDefaultFixtureConfig's flip), not from anything specific to
  // the read grant — stated honestly so this isn't read as proof of a
  // write-specific denial rule that doesn't exist here.
  const OWNER_ROOT = "/private/tmp"
  function ownerRootAvailable(): boolean {
    try {
      return fs.statSync(OWNER_ROOT).isDirectory()
    } catch {
      return false
    }
  }

  test(
    "[private-tmp] real oracle: read tool is ALLOWED under the grant, DENIED on sibling roots; bash write/delete stays DENIED",
    async (t) => {
    const config = await getFixtureConfig()

    // A separate, read-tool-specific fixture: same real installPermissions()
    // output, but with permission.read ALSO flipped to deny-by-default (the
    // installer never sets a "*" key for read on its own — mirrors the
    // sanity assertion buildDenyByDefaultFixtureConfig already makes for
    // bash), so the "read" tool oracle gets the same clean binary signal the
    // bash tests already get.
    assert.ok(!("*" in config.permission.read), "sanity: fresh installPermissions() sets no read default either")
    const readFixture = JSON.parse(JSON.stringify(config))
    readFixture.permission.read = { "*": "deny", ...readFixture.permission.read }

    // ── Rendered-grant scoping, machine-independent — ALWAYS asserted ────
    // Confirm the actual generated key in opencode.json is exactly
    // "private/tmp/**" — never a widened form like "private/**" or
    // "private/*" (which would also incidentally pass the ALLOW/DENY checks
    // below by accident of the specific paths chosen). These assertions need
    // no filesystem, so they run (and fail loudly) on every machine.
    const renderedRead = readFixture.permission.read as Record<string, string>
    assert.equal(
      renderedRead["private/tmp/**"],
      "allow",
      "expected the exact rendered key 'private/tmp/**' to be present with action 'allow'",
    )
    assert.equal(renderedRead["private/**"], undefined, "must NOT render an over-broad 'private/**' key")
    assert.equal(renderedRead["private/*"], undefined, "must NOT render an over-broad 'private/*' key")

    if (!ownerRootAvailable()) {
      t.skip(
        "owner-authorized root /private/tmp does not exist on this machine — the by-effect proof is skipped (named, not silent); rendered-grant scoping was still asserted above",
      )
      return
    }

    const projectDir = mkTmp("oc-fixture-privtmp-project-")
    const fakeHome = mkTmp("oc-fixture-privtmp-home-")
    writeProjectConfig(projectDir, readFixture)

    // Real scratch file under a real /private/tmp subdirectory.
    const scratchDir = fs.mkdtempSync(path.join(OWNER_ROOT, "thrum-oc-privtmp-fixture-"))
    const scratchFile = path.join(scratchDir, "canary.txt")
    fs.writeFileSync(scratchFile, "allowlist private-tmp fixture canary\n")

    try {
      const readVerdict = runOracle("build", { tool: "read", params: { filePath: scratchFile } }, projectDir, fakeHome)
      assert.equal(
        readVerdict.kind,
        "ALLOWED",
        `expected ALLOWED reading ${scratchFile} via the read tool, got DENIED:\n${readVerdict.raw}`,
      )

      // /private/etc/hosts: a real, existing, world-readable file that is
      // genuinely NOT under /private/tmp — the strongest form of this
      // negative control, since it rules out any ambiguity between a
      // permission denial and a file-not-found error.
      const otherRootVerdict = runOracle(
        "build",
        { tool: "read", params: { filePath: "/private/etc/hosts" } },
        projectDir,
        fakeHome,
      )
      assert.equal(
        otherRootVerdict.kind,
        "DENIED",
        `expected DENIED reading an unrelated /private path via the read tool, got ALLOWED:\n${otherRootVerdict.raw}`,
      )

      // /private/tmpfoo/x: an adjacent-name sibling root (never created —
      // confirmed above that OpenCode's permission check runs BEFORE any
      // file-existence check, so a nonexistent path under a denied pattern
      // still comes back as a genuine permission DENIED rather than a
      // "file not found" error; this is the exact acceptance-bar candidate
      // named in the task spec).
      const tmpfooSiblingVerdict = runOracle(
        "build",
        { tool: "read", params: { filePath: "/private/tmpfoo/x" } },
        projectDir,
        fakeHome,
      )
      assert.equal(
        tmpfooSiblingVerdict.kind,
        "DENIED",
        `expected DENIED reading a sibling-root path outside /private/tmp via the read tool, got ALLOWED:\n${tmpfooSiblingVerdict.raw}`,
      )

      // Write/delete: driven through the bash tool (the axis those
      // operations actually go through in this repo's Bash-tool-shaped
      // agent surface), against the ORIGINAL bash-deny-by-default fixture —
      // see the comment above the test for why this denial is attributable
      // to permission.bash's own default, not the read grant.
      const writeVerdict = runOracle("build", `echo x > ${scratchFile}`, projectDir, fakeHome)
      assert.equal(
        writeVerdict.kind,
        "DENIED",
        `expected DENIED writing to ${scratchFile} via bash, got ALLOWED:\n${writeVerdict.raw}`,
      )

      const deleteVerdict = runOracle("build", `rm ${scratchFile}`, projectDir, fakeHome)
      assert.equal(
        deleteVerdict.kind,
        "DENIED",
        `expected DENIED deleting ${scratchFile} via bash, got ALLOWED:\n${deleteVerdict.raw}`,
      )

      // ── Coordinator-prescribed bash-oracle negative controls ────────────
      // A reviewer asked for a `cat <path>` probe issued through the bash
      // tool specifically, for the parent (/private) and a sibling root
      // (/private/tmpfoo), alongside the write/delete checks above. Adding
      // them as requested: they DO come back DENIED, but — stated plainly,
      // per the measurement above — that denial is coming from
      // permission.bash's own "*": "deny" default (no bash pattern admits
      // "cat" at all), NOT from anything path-specific to /private vs
      // /private/tmp. A bash "cat" of the GRANTED path itself would be
      // denied for the identical, unrelated reason — proven directly above
      // (bash:"*":"allow" + read:"*":"deny" still lets `cat` succeed, so
      // permission.read has no bearing on bash execution either way). These
      // two assertions are therefore correct but NOT informative about the
      // read grant; they are included for completeness against the exact
      // form requested, with the caveat on record so a future reader does
      // not mistake "DENIED via bash cat" for evidence the read grant is
      // scoped correctly — the read-tool assertions above are what actually
      // prove that.
      const bashCatParentVerdict = runOracle("build", "cat /private", projectDir, fakeHome)
      assert.equal(
        bashCatParentVerdict.kind,
        "DENIED",
        `expected DENIED for bash cat of the parent /private, got ALLOWED:\n${bashCatParentVerdict.raw}`,
      )

      const bashCatSiblingVerdict = runOracle("build", "cat /private/tmpfoo/x", projectDir, fakeHome)
      assert.equal(
        bashCatSiblingVerdict.kind,
        "DENIED",
        `expected DENIED for bash cat of a sibling root /private/tmpfoo, got ALLOWED:\n${bashCatSiblingVerdict.raw}`,
      )
    } finally {
      fs.rmSync(scratchDir, { recursive: true, force: false })
    }
  })

  // Round-4 review finding (cq, by-effect-confirmed): opencodeGlobalReadPaths's
  // THIRD entry — the global config file itself, ${configDir}/opencode.json —
  // was still rendered with its leading slash kept (readFilePatternFor was
  // added for the private-tmp fix above but the file entry wasn't routed
  // through it), so a real read of the granted global config file came back
  // DENIED even though the sibling skills/** grant worked. This is a
  // by-effect regression test analogous to the private-tmp fixture above,
  // proving the fix: the REAL global opencode.json file installPermissions()
  // itself wrote is readable via the real "read" tool oracle.
  test("[global-config-file] real oracle: read tool is ALLOWED for the granted ${configDir}/opencode.json", async () => {
    // installPermissions(installDir) both renders the grant AND writes the
    // real file the grant is supposed to cover — installDir plays the role
    // of configDir here, so the file at path.join(installDir, "opencode.json")
    // is the exact real artifact this grant targets, not a synthetic stand-in.
    const installDir = mkTmp("oc-fixture-globalconfig-install-")
    await installPermissions(installDir)
    const rendered = JSON.parse(fs.readFileSync(path.join(installDir, "opencode.json"), "utf8"))

    assert.ok(
      !("*" in rendered.permission.read),
      "sanity: fresh installPermissions() sets no read default either",
    )
    const readFixture = JSON.parse(JSON.stringify(rendered))
    readFixture.permission.read = { "*": "deny", ...readFixture.permission.read }

    const projectDir = mkTmp("oc-fixture-globalconfig-project-")
    const fakeHome = mkTmp("oc-fixture-globalconfig-home-")
    writeProjectConfig(projectDir, readFixture)

    const globalConfigFile = path.join(installDir, "opencode.json")
    const verdict = runOracle("build", { tool: "read", params: { filePath: globalConfigFile } }, projectDir, fakeHome)
    assert.equal(
      verdict.kind,
      "ALLOWED",
      `expected ALLOWED reading the granted global config file ${globalConfigFile} via the read tool, got DENIED:\n${verdict.raw}`,
    )

    // Confirm the rendered key is the stripped, no-leading-slash form —
    // the exact thing that was missing before this fix.
    const strippedKey = globalConfigFile.replace(/^\//, "")
    assert.equal(
      readFixture.permission.read[strippedKey],
      "allow",
      `expected the exact stripped key ${JSON.stringify(strippedKey)} to be present with action 'allow'`,
    )
    assert.equal(
      readFixture.permission.read[globalConfigFile],
      undefined,
      "must NOT also render the unstripped (leading-slash) form",
    )
  })

  // ─── global_read_paths.opencode — ~/.local/bin, by-effect (allowlist
  // consolidated round, Part B) ─────────────────────────────────────────────
  //
  // Mirrors the [private-tmp] fixture above, with one structural difference:
  // the grant target here is HOME-RELATIVE ("~/.local/bin"), not a fixed
  // absolute path, so the fixture must isolate HOME the same way runOracle's
  // child-process invocations already do — installPermissions() is called
  // with an explicit homeDir override pointing at a fresh scratch directory
  // (NOT the real machine's actual ~/.local/bin), and the real scratch file
  // is written under that SAME fake home's .local/bin subdirectory so the
  // rendered grant and the real file agree on what "~/.local/bin" resolved
  // to. This never touches the real machine's ~/.local/bin.
  test("[global-read-paths-local-bin] real oracle: read tool is ALLOWED under ~/.local/bin, DENIED on siblings", async () => {
    const fakeHome = mkTmp("oc-fixture-localbin-home-")
    const installDir = mkTmp("oc-fixture-localbin-install-")
    await installPermissions(installDir, fakeHome)
    const rendered = JSON.parse(fs.readFileSync(path.join(installDir, "opencode.json"), "utf8"))

    assert.ok(!("*" in rendered.permission.read), "sanity: fresh installPermissions() sets no read default either")
    const readFixture = JSON.parse(JSON.stringify(rendered))
    readFixture.permission.read = { "*": "deny", ...readFixture.permission.read }

    const projectDir = mkTmp("oc-fixture-localbin-project-")
    writeProjectConfig(projectDir, readFixture)

    // Real scratch file under the FAKE home's .local/bin — never the real
    // machine's ~/.local/bin.
    const localBinDir = path.join(fakeHome, ".local", "bin")
    fs.mkdirSync(localBinDir, { recursive: true })
    const scratchFile = path.join(localBinDir, "thrum")
    fs.writeFileSync(scratchFile, "#!/bin/sh\n# allowlist local-bin fixture canary\n")

    const strippedKey = localBinDir.replace(/^\//, "") + "/**"
    assert.equal(
      readFixture.permission.read[strippedKey],
      "allow",
      `expected the exact rendered key ${JSON.stringify(strippedKey)} to be present with action 'allow'`,
    )

    const readVerdict = runOracle("build", { tool: "read", params: { filePath: scratchFile } }, projectDir, fakeHome)
    assert.equal(
      readVerdict.kind,
      "ALLOWED",
      `expected ALLOWED reading ${scratchFile} via the read tool, got DENIED:\n${readVerdict.raw}`,
    )

    // Sibling: ~/.local/binx/x — an adjacent-name sibling root, never created.
    const siblingPath = path.join(fakeHome, ".local", "binx", "x")
    const siblingVerdict = runOracle("build", { tool: "read", params: { filePath: siblingPath } }, projectDir, fakeHome)
    assert.equal(
      siblingVerdict.kind,
      "DENIED",
      `expected DENIED reading a sibling-root path ${siblingPath} via the read tool, got ALLOWED:\n${siblingVerdict.raw}`,
    )

    // Parent: ~/.local — genuinely a real, existing directory under fakeHome
    // (created above via mkdirSync of localBinDir), so this rules out any
    // ambiguity with a file-not-found error.
    const parentPath = path.join(fakeHome, ".local")
    const parentVerdict = runOracle("build", { tool: "read", params: { filePath: parentPath } }, projectDir, fakeHome)
    assert.equal(
      parentVerdict.kind,
      "DENIED",
      `expected DENIED reading the parent path ${parentPath} via the read tool, got ALLOWED:\n${parentVerdict.raw}`,
    )
  })

  // ─── No-network-dependency confirmation ──────────────────────────────────
  // Every runOracle() call above already strips every provider-credential-
  // shaped env var (ANTHROPIC_*, OPENAI_*, *_API_KEY, *_TOKEN) before
  // invoking the child process — see strippedEnv(). This test makes that
  // fact an explicit, named assertion: a plain tool-permission check
  // succeeds with a clean ALLOW/DENY verdict with no such credential
  // present anywhere in the child's environment, confirming `debug agent
  // --tool` does not need a model/API credential for this route.
  test("tool-permission oracle needs no LLM/API credential", async () => {
    const config = await getFixtureConfig()
    const projectDir = mkTmp("oc-fixture-nocred-project-")
    const fakeHome = mkTmp("oc-fixture-nocred-home-")
    writeProjectConfig(projectDir, config)

    const env = strippedEnv(fakeHome)
    const hasProviderKey = Object.keys(env).some((k) => /API_KEY|ANTHROPIC|OPENAI|_TOKEN$/i.test(k))
    assert.equal(hasProviderKey, false, "strippedEnv must remove every provider-credential-shaped var")

    const verdict = runOracle("build", "thrum inbox", projectDir, fakeHome)
    assert.equal(verdict.kind, "ALLOWED", `expected ALLOWED with no provider credential present:\n${verdict.raw}`)
  })
} else {
  test("permission-fixture (skipped: opencode binary not on PATH)", () => {
    // Intentionally a no-op assertion so this file always contributes at
    // least one passing/visible test result even when the binary this
    // whole file depends on is absent — see the console.log above for the
    // human-readable explanation.
    assert.ok(true)
  })
}
