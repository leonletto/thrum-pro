// Tests for the OpenCode permission.bash/permission.read allowlist installer
// (OpenCode leg). Offline/deterministic: uses a temp dir as the
// injected config-dir root, never the real $HOME or network.
//
// Run: npm test  (builds, then `node --test dist`)

import { test } from "node:test"
import assert from "node:assert/strict"
import fs from "fs"
import os from "os"
import path from "path"
import {
  bashExactPatternFor,
  bashPatternFor,
  readPatternFor,
  mergePermissions,
  loadAllowlist,
  installPermissions,
  getConfigDir,
  opencodeGlobalReadPaths,
  readFilePatternFor,
  resolveHomePath,
  writeConfig,
} from "./installer.js"

const ALLOWLIST_ASSET_PATH = path.resolve(
  path.dirname(new URL(import.meta.url).pathname),
  "..",
  "assets",
  "thrum_allowlist.json",
)

function mkTmpDir(): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), "oc-permtest-"))
}

// ─── (a) Fresh config ──────────────────────────────────────────────────────

test("fresh config: permission.bash/read populated for every canonical entry", () => {
  const allowlist = loadAllowlist(ALLOWLIST_ASSET_PATH)
  const merged = mergePermissions({}, allowlist)

  assert.ok(merged.permission, "permission key must exist")
  const bash = merged.permission!.bash as Record<string, string>
  const read = merged.permission!.read as Record<string, string>

  for (const cmd of allowlist.command_patterns) {
    assert.equal(bash[bashExactPatternFor(cmd)], "allow", `missing bare-command allow for ${cmd}`)
    assert.equal(bash[bashPatternFor(cmd)], "allow", `missing with-args allow for ${cmd}`)
  }
  for (const p of allowlist.read_paths) {
    assert.equal(read[readPatternFor(p)], "allow", `missing allow for ${p}`)
  }
})

// ─── (b) Idempotency ────────────────────────────────────────────────────────

test("idempotency: running installPermissions twice yields byte-identical config", async () => {
  const dir = mkTmpDir()
  try {
    await installPermissions(dir)
    const first = fs.readFileSync(path.join(dir, "opencode.json"), "utf8")
    await installPermissions(dir)
    const second = fs.readFileSync(path.join(dir, "opencode.json"), "utf8")
    assert.equal(second, first, "second run must produce byte-identical output")
  } finally {
    fs.rmSync(dir, { recursive: true })
  }
})

// ─── (c) Preserves unrelated config ────────────────────────────────────────

test("preserves unrelated config keys, including a hand-set permission.edit", () => {
  const original = {
    mcp: { thrum: { type: "local", command: ["thrum", "mcp", "serve"], enabled: true } },
    plugin: ["opencode-thrum"],
    instructions: ["AGENTS.md"],
    permission: { edit: "ask" },
  }
  const allowlist = loadAllowlist(ALLOWLIST_ASSET_PATH)
  const merged = mergePermissions(original, allowlist)

  assert.deepEqual(merged.mcp, original.mcp)
  assert.deepEqual(merged.plugin, original.plugin)
  assert.deepEqual(merged.instructions, original.instructions)
  assert.equal((merged.permission as Record<string, unknown>).edit, "ask")
})

// ─── (d) Positive controls ──────────────────────────────────────────────────
//
// NOTE (the allowlist effort consolidated round, Part B): the canonical
// command_patterns model changed upstream (owner ruling) from an
// enumerated per-subcommand list to a single family entry — "thrum" now
// represents the whole command family (any subcommand), with the
// alt-exec/metachar guard as the primary scoping boundary rather than an
// enumerated allowlist. This test previously asserted each representative
// subcommand rendered as its OWN literal bash key (true under the old
// per-subcommand model); under the family model, a subcommand invocation is
// covered by the SINGLE family pattern's with-args glob, not by a key of its
// own. Updated to assert both: (1) the sole canonical entry itself renders
// bare+with-args allow entries, and (2) representative subcommand
// invocations are covered by that same family glob (via wouldMatchBashPattern,
// defined below in this file — function declarations are hoisted, so this
// forward reference is safe).
test("positive controls: the canonical family entry renders allow entries, bare and with-args, covering representative subcommands", () => {
  const allowlist = loadAllowlist(ALLOWLIST_ASSET_PATH)
  const merged = mergePermissions({}, allowlist)
  const bash = merged.permission!.bash as Record<string, string>

  for (const cmd of allowlist.command_patterns) {
    assert.equal(bash[bashExactPatternFor(cmd)], "allow", `expected bare-command allow for ${JSON.stringify(cmd)}`)
    assert.equal(bash[bashPatternFor(cmd)], "allow", `expected allow for ${JSON.stringify(bashPatternFor(cmd))}`)
  }

  const allowPatterns = Object.entries(bash)
    .filter(([, verdict]) => verdict === "allow")
    .map(([pattern]) => pattern)

  const representative = [
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
  for (const cmd of representative) {
    assert.ok(
      allowPatterns.some((p) => wouldMatchBashPattern(p, cmd)),
      `expected some allow pattern to cover representative subcommand ${JSON.stringify(cmd)}`,
    )
    assert.ok(
      allowPatterns.some((p) => wouldMatchBashPattern(p, `${cmd} --unread`)),
      `expected some allow pattern to cover representative subcommand with args ${JSON.stringify(`${cmd} --unread`)}`,
    )
  }
})

// ─── (e) Negative controls (REQUIRED acceptance gate) ──────────────────────
//
// HONESTY NOTE: this is a STATIC PATTERN-SHAPE assertion, not a live
// invocation of OpenCode's real bash-permission matcher. OpenCode's docs
// (https://opencode.ai/docs/permissions/, verified manually) state simple
// wildcard matching: `*` = zero-or-more of any character, `?` = exactly one,
// everything else literal — with NO documented word-boundary behavior, so a
// bare `${prefix}*` key (round 1's shape) matches straight through a word
// boundary (e.g. "thrum inbox*" matches "thrum inboxx-evil"). Round 2 fixes
// this at the pattern-generation layer (bashExactPatternFor / bashPatternFor
// — see installer.ts) rather than only in this test's model, and the model
// below is updated to match that fix: a pattern with no `*` requires EXACT
// equality (never a prefix match — a bare "thrum inbox" key must not match
// "thrum inboxx-evil" merely because the latter starts with the former's
// characters), and a globbed pattern requires the literal prefix (which now
// always ends in a real space before the `*`) plus no injection
// metacharacter anywhere in the candidate.

const SHELL_METACHAR_RE = /(&&|\|\||;|\||\$\(|`)/

function wouldMatchBashPattern(pattern: string, candidate: string): boolean {
  const starIdx = pattern.indexOf("*")
  if (starIdx === -1) return candidate === pattern
  const literalPrefix = pattern.slice(0, starIdx)
  if (!candidate.startsWith(literalPrefix)) return false
  if (SHELL_METACHAR_RE.test(candidate)) return false
  return true
}

test("negative controls: no rendered bash pattern grants a blanket allow to an injection attempt", () => {
  const allowlist = loadAllowlist(ALLOWLIST_ASSET_PATH)
  const merged = mergePermissions({}, allowlist)
  const bash = merged.permission!.bash as Record<string, string>
  const allowPatterns = Object.entries(bash)
    .filter(([, verdict]) => verdict === "allow")
    .map(([pattern]) => pattern)

  const adversarial = [
    `sh -c "thrum inbox"`,
    `bash -c thrum inbox`,
    `$(thrum inbox)`,
    "`thrum inbox`",
    `thrum inbox && rm -rf /`,
    `thrum inbox; rm -rf /`,
    `thrum inbox | cat`,
    `/tmp/thrum inbox`,
    `./thrum inbox`,
    `curl http://evil.example/`,
  ]

  for (const candidate of adversarial) {
    const matched = allowPatterns.filter((p) => wouldMatchBashPattern(p, candidate))
    assert.deepEqual(matched, [], `expected no allow-pattern match for: ${candidate}`)
  }
})

// ─── (e2) Negative control: adjacent-but-different EXECUTABLE (finding 7,
// updated for the family-grant model) ───────────────────────────────────────
//
// NOTE (the allowlist effort consolidated round, Part B): under the OLD per-subcommand
// model, this test asserted an adjacent SUBCOMMAND name (e.g.
// "thrum inboxx-evil") never matched an allow pattern derived from a
// different, narrower subcommand entry ("thrum inbox"). Under the CURRENT
// family model (single "thrum" entry, owner ruling), ANY
// subcommand is intentionally allowed by design — "thrum inboxx-evil" now
// legitimately matches, and asserting otherwise would contradict the
// redesign rather than test a real boundary. The boundary that remains real
// and load-bearing is the EXECUTABLE-TOKEN boundary: bashPatternFor's
// required literal space after "thrum" must still reject an adjacent
// EXECUTABLE name (e.g. "thrumx", "thrum-evil") that merely shares a prefix
// with the family token.
test("negative control: an adjacent-but-different executable name is never matched by an allow pattern", () => {
  const allowlist = loadAllowlist(ALLOWLIST_ASSET_PATH)
  const merged = mergePermissions({}, allowlist)
  const bash = merged.permission!.bash as Record<string, string>
  const allowPatterns = Object.entries(bash)
    .filter(([, verdict]) => verdict === "allow")
    .map(([pattern]) => pattern)

  const adjacentExecutables = ["thrumx inbox", "thrumx", "thrum-evil inbox", "thrum-evil", "thrumfoo status"]

  for (const candidate of adjacentExecutables) {
    const matched = allowPatterns.filter((p) => wouldMatchBashPattern(p, candidate))
    assert.deepEqual(matched, [], `expected no allow-pattern match for adjacent executable: ${candidate}`)
  }

  // Sanity/positive control so the negative result above isn't vacuous: the
  // real family token and its with-args form DO match, including an
  // arbitrary subcommand — which is the intended, in-scope behavior of the
  // family grant, not a gap.
  assert.ok(
    allowPatterns.some((p) => wouldMatchBashPattern(p, "thrum")),
    "expected bare 'thrum' to match some allow pattern",
  )
  assert.ok(
    allowPatterns.some((p) => wouldMatchBashPattern(p, "thrum inbox --unread")),
    "expected 'thrum inbox --unread' to match some allow pattern",
  )
})

// ─── (f) Host/path-agnostic config-dir resolution ──────────────────────────

test("getConfigDir: honors XDG_CONFIG_HOME when set", () => {
  const savedXdg = process.env.XDG_CONFIG_HOME
  const savedHome = process.env.HOME
  try {
    process.env.XDG_CONFIG_HOME = "/injected/xdg-root"
    delete process.env.HOME
    assert.equal(getConfigDir(), path.join("/injected/xdg-root", "opencode"))
  } finally {
    if (savedXdg === undefined) delete process.env.XDG_CONFIG_HOME
    else process.env.XDG_CONFIG_HOME = savedXdg
    if (savedHome === undefined) delete process.env.HOME
    else process.env.HOME = savedHome
  }
})

test("getConfigDir: falls back to ~/.config/opencode derived from HOME when XDG_CONFIG_HOME is unset", () => {
  const savedXdg = process.env.XDG_CONFIG_HOME
  const savedHome = process.env.HOME
  try {
    delete process.env.XDG_CONFIG_HOME
    process.env.HOME = "/injected/home-root"
    assert.equal(getConfigDir(), path.join("/injected/home-root", ".config", "opencode"))
  } finally {
    if (savedXdg === undefined) delete process.env.XDG_CONFIG_HOME
    else process.env.XDG_CONFIG_HOME = savedXdg
    if (savedHome === undefined) delete process.env.HOME
    else process.env.HOME = savedHome
  }
})

// ─── (g) OpenCode global config/skill/plugin read paths (finding 1) ───────

test("opencodeGlobalReadPaths: derives skills/commands/config entries strictly under configDir", () => {
  const configDir = "/injected/config-root/opencode"
  const patterns = opencodeGlobalReadPaths(configDir)
  // Glob entries render through readPatternFor, which strips a leading "/"
  // (the allowlist effort round 4 by-effect finding: OpenCode's real matcher does the
  // same before comparing, so a pattern that keeps the leading slash never
  // matches — see readPatternFor's doc comment). configDirRel below mirrors
  // that same stripping for comparison in this test.
  const configDirRel = configDir.replace(/^\//, "")

  assert.ok(
    patterns.includes(path.join(configDirRel, "skills") + "/**"),
    "expected a recursive read grant for ${configDir}/skills",
  )
  assert.ok(
    patterns.includes(path.join(configDirRel, "commands") + "/**"),
    "expected a recursive read grant for ${configDir}/commands",
  )
  assert.ok(
    patterns.includes(readFilePatternFor(path.join(configDir, "opencode.json"))),
    "expected a read grant for ${configDir}/opencode.json itself, leading-slash-stripped",
  )
  // Scope check: nothing in the returned set should escape configDir. All
  // three entries render in their stripped form now (round-4 review fix —
  // the file entry was the one initially missed).
  for (const p of patterns) {
    assert.ok(p.startsWith(configDirRel), `pattern escapes configDir scope: ${p}`)
  }
})

// Round-4 review finding (cq, by-effect-confirmed): opencodeGlobalReadPaths's
// THIRD entry (the config file itself) was rendered via a raw path.join,
// bypassing the leading-slash strip readPatternFor already applies to the
// first two entries — so it stayed silently broken one round after the
// directory entries were fixed. This test pins the file entry specifically
// so a future regression can't reintroduce an unstripped file pattern.
test("opencodeGlobalReadPaths: the config-file entry is leading-slash-stripped like the directory entries", () => {
  const configDir = "/injected/config-root/opencode"
  const patterns = opencodeGlobalReadPaths(configDir)
  const fileEntry = path.join(configDir, "opencode.json")

  assert.ok(!patterns.includes(fileEntry), "config-file entry must NOT keep its leading slash")
  assert.ok(
    patterns.includes(readFilePatternFor(fileEntry)),
    "config-file entry must be rendered through readFilePatternFor",
  )
})

test("installPermissions: resulting permission.read covers OpenCode's own global install subtree", async () => {
  const savedXdg = process.env.XDG_CONFIG_HOME
  const xdgRoot = mkTmpDir()
  try {
    process.env.XDG_CONFIG_HOME = xdgRoot
    const configDir = getConfigDir()
    assert.equal(configDir, path.join(xdgRoot, "opencode"), "sanity: getConfigDir resolves under injected XDG root")

    await installPermissions()

    const written = JSON.parse(fs.readFileSync(path.join(configDir, "opencode.json"), "utf8"))
    const read = written.permission.read as Record<string, string>
    const configDirRel = configDir.replace(/^\//, "")

    assert.equal(read[path.join(configDirRel, "skills") + "/**"], "allow", "missing global skills read grant")
    assert.equal(read[path.join(configDirRel, "commands") + "/**"], "allow", "missing global commands read grant")
    assert.equal(
      read[path.join(configDirRel, "opencode.json")],
      "allow",
      "missing global config-file read grant (leading-slash-stripped)",
    )
    assert.ok(
      !(path.join(configDir, "opencode.json") in read),
      "config-file entry must not also be present in its unstripped form",
    )

    // Canonical project-relative entries must STILL be present alongside
    // the global ones (finding 1: "in addition to", not "instead of").
    assert.equal(read[".thrum/**"], "allow", "canonical project-relative read_paths must survive alongside globals")
  } finally {
    fs.rmSync(xdgRoot, { recursive: true })
    if (savedXdg === undefined) delete process.env.XDG_CONFIG_HOME
    else process.env.XDG_CONFIG_HOME = savedXdg
  }
})

// ─── (d) Malformed existing config must never be silently discarded ────────
//
// Regression for the dual-review landing-blocker: readConfig() previously
// caught BOTH "file absent" (ENOENT) and "file present but malformed JSON"
// and returned {} for both, so installPermissions() would silently overwrite
// a user's hand-edited-but-broken global opencode.json with a fresh config
// containing only thrum's permission block — discarding every other setting
// (providers, models, etc). readConfig() must now distinguish the two: {}
// ONLY on genuine ENOENT, propagate (never swallow) any other read/parse
// failure — and installPermissions() must perform NO WRITE in that case.

test("malformed config: installPermissions throws and leaves the file byte-for-byte untouched", async () => {
  const dir = mkTmpDir()
  try {
    const configPath = path.join(dir, "opencode.json")
    // Genuinely invalid JSON: stray trailing comma.
    const malformed = '{\n  "mcp": { "thrum": {} },\n  "permission": { "edit": "ask", },\n}\n'
    fs.writeFileSync(configPath, malformed)
    const before = fs.readFileSync(configPath, "utf8")

    await assert.rejects(
      () => installPermissions(dir),
      /./,
      "installPermissions must propagate a malformed-config error instead of silently swallowing it",
    )

    const after = fs.readFileSync(configPath, "utf8")
    assert.equal(after, before, "malformed config file must be left byte-for-byte unchanged on disk")
  } finally {
    fs.rmSync(dir, { recursive: true })
  }
})

test("regression: genuinely absent config still installs a fresh config with no error", async () => {
  const dir = mkTmpDir()
  try {
    const configPath = path.join(dir, "opencode.json")
    assert.equal(fs.existsSync(configPath), false, "sanity: no config file exists yet")

    await installPermissions(dir)

    const written = JSON.parse(fs.readFileSync(configPath, "utf8"))
    const bash = written.permission.bash as Record<string, string>
    const allowlist = loadAllowlist(ALLOWLIST_ASSET_PATH)
    for (const cmd of allowlist.command_patterns) {
      assert.equal(bash[bashExactPatternFor(cmd)], "allow", `missing bare-command allow for ${cmd}`)
    }
  } finally {
    fs.rmSync(dir, { recursive: true })
  }
})

// ─── (h) Bare-scalar permission.bash is never silently clobbered (finding 3) ─

test("mergePermissions: a pre-existing bare-scalar permission.bash is preserved as the object map's '*' default", () => {
  const allowlist = loadAllowlist(ALLOWLIST_ASSET_PATH)
  const original: { permission: { bash: "deny" } } = { permission: { bash: "deny" } }
  const merged = mergePermissions(original, allowlist)

  const bash = merged.permission!.bash as Record<string, string>
  assert.equal(typeof bash, "object", "permission.bash must become the object-map form")
  assert.equal(bash["*"], "deny", "the user's original blanket 'deny' must survive as the '*' default")

  // Thrum overlay entries are ADDITIONAL allow exceptions on top of the
  // preserved default, not a replacement of it.
  for (const cmd of allowlist.command_patterns) {
    assert.equal(bash[cmd], "allow", `expected thrum overlay allow for ${cmd}`)
  }

  // Order matters for OpenCode's last-match-wins evaluation: "*" must come
  // before the thrum-specific keys so the overlay can win for those exact
  // patterns while the "*" default still governs everything else.
  const keys = Object.keys(bash)
  const starIdx = keys.indexOf("*")
  assert.ok(starIdx === 0, "'*' must be the first key so more specific rules can override it (last-match-wins)")
})

test("mergePermissions: a pre-existing bare-scalar permission.read is likewise preserved as '*'", () => {
  const allowlist = loadAllowlist(ALLOWLIST_ASSET_PATH)
  const original: { permission: { read: "ask" } } = { permission: { read: "ask" } }
  const merged = mergePermissions(original, allowlist)

  const read = merged.permission!.read as Record<string, string>
  assert.equal(read["*"], "ask", "the user's original blanket 'ask' must survive as the '*' default")
  for (const p of allowlist.read_paths) {
    assert.equal(read[readPatternFor(p)], "allow", `expected thrum overlay allow for ${p}`)
  }
})

// ─── (i) owner_authorized_exceptions.opencode — /private/tmp (the allowlist effort
// round 4) ───────────────────────────────────────────────────────────────
//
// OWNER-AUTHORIZED EXCEPTION — /private/tmp (owner ruling, watcher-
// recovery P0; scope CONFIRMED all-runtimes by the fleet coordinator the same
// day — owner's wording was "global configs for all agents", the
// operational-artifact class is runtime-independent): the canonical
// allowlist's owner_authorized_exceptions grants EVERY supported runtime
// broad READ access to /private/tmp/* DESPITE it being a world-writable
// directory — explicitly ruled acceptable by the owner for
// coordinator/watcher operational artifacts. This is a DELIBERATE
// exception, not a template for widening elsewhere: READ/ACCESS ONLY —
// never execute, never shell-interpolation, never a sibling root like
// /private or /private/tmpfoo, never write/delete.

test("owner_authorized_exceptions.opencode: /private/tmp is merged into permission.read as an allow entry", () => {
  const allowlist = loadAllowlist(ALLOWLIST_ASSET_PATH)
  assert.deepEqual(
    allowlist.owner_authorized_exceptions?.opencode,
    ["/private/tmp"],
    "sanity: canonical asset must carry the expected owner-authorized exception entry",
  )

  const merged = mergePermissions({}, allowlist)
  const read = merged.permission!.read as Record<string, string>
  // "private/tmp/**" (no leading slash) — see readPatternFor's doc comment:
  // OpenCode's real permission matcher strips the leading "/" from an
  // absolute candidate path before comparing, so a pattern that keeps the
  // leading slash never matches (measured against the real binary; see the
  // by-effect fixture in permission-fixture.integration.test.ts).
  assert.equal(read["private/tmp/**"], "allow", "expected an allow entry covering private/tmp/**")
  assert.equal(read["/private/tmp/**"], undefined, "must NOT render a leading-slash form — it never matches OpenCode's real matcher")
})

test("owner_authorized_exceptions.opencode: idempotency holds with the new entry", async () => {
  const dir = mkTmpDir()
  try {
    await installPermissions(dir)
    const first = fs.readFileSync(path.join(dir, "opencode.json"), "utf8")
    await installPermissions(dir)
    const second = fs.readFileSync(path.join(dir, "opencode.json"), "utf8")
    assert.equal(second, first, "second run must produce byte-identical output")
    assert.match(first, /"private\/tmp\/\*\*": "allow"/, "sanity: the owner-exception entry must actually be present")
  } finally {
    fs.rmSync(dir, { recursive: true })
  }
})

test("owner_authorized_exceptions.opencode: interacts correctly with bare-scalar preservation (finding 3)", () => {
  const allowlist = loadAllowlist(ALLOWLIST_ASSET_PATH)
  const original: { permission: { read: "deny" } } = { permission: { read: "deny" } }
  const merged = mergePermissions(original, allowlist)

  const read = merged.permission!.read as Record<string, string>
  assert.equal(read["*"], "deny", "the user's original blanket 'deny' must survive as the '*' default")
  for (const p of allowlist.read_paths) {
    assert.equal(read[readPatternFor(p)], "allow", `expected thrum overlay allow for ${p}`)
  }
  assert.equal(
    read["private/tmp/**"],
    "allow",
    "the owner-authorized /private/tmp overlay must still be present as an allow on top of the preserved deny default",
  )
})

test("owner_authorized_exceptions.opencode: negative control — sibling roots are never matched by the rendered pattern", () => {
  const allowlist = loadAllowlist(ALLOWLIST_ASSET_PATH)
  const merged = mergePermissions({}, allowlist)
  const read = merged.permission!.read as Record<string, string>
  const allowPatterns = Object.entries(read)
    .filter(([, verdict]) => verdict === "allow")
    .map(([pattern]) => pattern)

  const pattern = "private/tmp/**"
  assert.ok(allowPatterns.includes(pattern), "sanity: the pattern under test must actually be rendered")

  // Reuse the same glob-matching model as the bash negative controls above
  // (wouldMatchBashPattern): `*` = zero-or-more of any char, everything else
  // literal, per OpenCode's documented simple-wildcard matcher. Candidates
  // here are given in the SAME leading-slash-stripped form OpenCode's real
  // matcher compares against (see readPatternFor's doc comment) — the
  // by-effect fixture proves this against the real binary using natural
  // absolute-path candidates.
  function wouldMatchReadPattern(p: string, candidate: string): boolean {
    const starIdx = p.indexOf("*")
    if (starIdx === -1) return candidate === p
    const literalPrefix = p.slice(0, starIdx)
    return candidate.startsWith(literalPrefix)
  }

  // Positive control: the pattern must match a real file under the granted
  // directory, so the negative result below isn't vacuous.
  assert.ok(
    wouldMatchReadPattern(pattern, "private/tmp/foo.txt"),
    "sanity: the pattern must match a file directly under private/tmp",
  )

  const siblings = ["private/tmp", "private", "private/tmpfoo", "private/tmpfoo/x"]
  for (const candidate of siblings) {
    assert.ok(
      !wouldMatchReadPattern(pattern, candidate),
      `expected private/tmp/** to NOT match sibling/parent path: ${candidate}`,
    )
  }
})

// ─── (j) global_read_paths.opencode — ~/.local/bin (the allowlist effort consolidated
// round, Part B) ────────────────────────────────────────────────────────────
//
// OWNER CORRECTION (owner ruling, consolidated round): global_read_paths
// grants OpenCode (like Claude and Codex) READ access to the thrum-binary
// install directory ~/.local/bin, so PATH-resolved "thrum" can actually
// execute under the runtime's sandbox. A prior round deliberately gave
// OpenCode NO entries under global_read_paths at all (its own installer
// derives its global skill/command paths dynamically — see
// opencodeGlobalReadPaths, a separate, unrelated mechanism); this is the
// first entry OpenCode gets under this key.

const FAKE_HOME = "/private/tmp/oc-permtest-fakehome-does-not-need-to-exist"
const EXPECTED_LOCAL_BIN_KEY = readPatternFor(path.join(FAKE_HOME, ".local", "bin"))

test("global_read_paths.opencode: ~/.local/bin is merged into permission.read as an allow entry", () => {
  const allowlist = loadAllowlist(ALLOWLIST_ASSET_PATH)
  assert.deepEqual(
    allowlist.global_read_paths?.opencode,
    ["~/.local/bin"],
    "sanity: canonical asset must carry the expected global_read_paths.opencode entry",
  )

  const merged = mergePermissions({}, allowlist, [], FAKE_HOME)
  const read = merged.permission!.read as Record<string, string>
  assert.equal(
    read[EXPECTED_LOCAL_BIN_KEY],
    "allow",
    `expected an allow entry covering ${EXPECTED_LOCAL_BIN_KEY}`,
  )
  // Must also hold against the real machine's actual os.homedir() default,
  // which is what production code (installPermissions with no homeDir
  // override) actually uses.
  const mergedRealHome = mergePermissions({}, allowlist)
  const readRealHome = mergedRealHome.permission!.read as Record<string, string>
  assert.equal(
    readRealHome[readPatternFor(path.join(os.homedir(), ".local", "bin"))],
    "allow",
    "expected the real-homedir-resolved key to be present when no homeDir override is given",
  )
})

test("global_read_paths.opencode: idempotency holds with the new entry", async () => {
  const dir = mkTmpDir()
  try {
    await installPermissions(dir, FAKE_HOME)
    const first = fs.readFileSync(path.join(dir, "opencode.json"), "utf8")
    await installPermissions(dir, FAKE_HOME)
    const second = fs.readFileSync(path.join(dir, "opencode.json"), "utf8")
    assert.equal(second, first, "second run must produce byte-identical output")
    assert.ok(
      first.includes(`"${EXPECTED_LOCAL_BIN_KEY}": "allow"`),
      "sanity: the ~/.local/bin entry must actually be present",
    )
  } finally {
    fs.rmSync(dir, { recursive: true })
  }
})

test("global_read_paths.opencode: preserves unrelated entries — both /private/tmp and ~/.local/bin coexist", () => {
  const allowlist = loadAllowlist(ALLOWLIST_ASSET_PATH)
  const merged = mergePermissions({}, allowlist, [], FAKE_HOME)
  const read = merged.permission!.read as Record<string, string>

  assert.equal(read["private/tmp/**"], "allow", "expected the pre-existing /private/tmp grant to still be present")
  assert.equal(read[EXPECTED_LOCAL_BIN_KEY], "allow", "expected the new ~/.local/bin grant to also be present")
  for (const p of allowlist.read_paths) {
    assert.equal(read[readPatternFor(p)], "allow", `expected pre-existing canonical read_paths entry for ${p}`)
  }
})

test("global_read_paths.opencode: interacts correctly with bare-scalar preservation (finding 3)", () => {
  const allowlist = loadAllowlist(ALLOWLIST_ASSET_PATH)
  const original: { permission: { read: "deny" } } = { permission: { read: "deny" } }
  const merged = mergePermissions(original, allowlist, [], FAKE_HOME)

  const read = merged.permission!.read as Record<string, string>
  assert.equal(read["*"], "deny", "the user's original blanket 'deny' must survive as the '*' default")
  assert.equal(
    read[EXPECTED_LOCAL_BIN_KEY],
    "allow",
    "the ~/.local/bin overlay must still be present as an allow on top of the preserved deny default",
  )
})

test("global_read_paths.opencode: negative control — sibling/parent paths are never matched by the rendered pattern", () => {
  const allowlist = loadAllowlist(ALLOWLIST_ASSET_PATH)
  const merged = mergePermissions({}, allowlist, [], FAKE_HOME)
  const read = merged.permission!.read as Record<string, string>
  const allowPatterns = Object.entries(read)
    .filter(([, verdict]) => verdict === "allow")
    .map(([pattern]) => pattern)

  assert.ok(allowPatterns.includes(EXPECTED_LOCAL_BIN_KEY), "sanity: the pattern under test must actually be rendered")

  function wouldMatchReadPattern(p: string, candidate: string): boolean {
    const starIdx = p.indexOf("*")
    if (starIdx === -1) return candidate === p
    const literalPrefix = p.slice(0, starIdx)
    return candidate.startsWith(literalPrefix)
  }

  const localBinDir = stripLeadingSlashForTest(path.join(FAKE_HOME, ".local", "bin"))
  assert.ok(
    wouldMatchReadPattern(EXPECTED_LOCAL_BIN_KEY, `${localBinDir}/thrum`),
    "sanity: the pattern must match a file directly under ~/.local/bin",
  )

  const siblings = [
    stripLeadingSlashForTest(path.join(FAKE_HOME, ".local")),
    stripLeadingSlashForTest(path.join(FAKE_HOME, ".local", "binx")),
    stripLeadingSlashForTest(path.join(FAKE_HOME, ".local", "binx", "x")),
  ]
  for (const candidate of siblings) {
    assert.ok(
      !wouldMatchReadPattern(EXPECTED_LOCAL_BIN_KEY, candidate),
      `expected ${EXPECTED_LOCAL_BIN_KEY} to NOT match sibling/parent path: ${candidate}`,
    )
  }
})

function stripLeadingSlashForTest(p: string): string {
  return p.startsWith("/") ? p.slice(1) : p
}

test("resolveHomePath: expands '~' and '~/...' against a given homeDir, leaves other paths untouched", () => {
  assert.equal(resolveHomePath("~/.local/bin", "/fake/home"), path.join("/fake/home", ".local", "bin"))
  assert.equal(resolveHomePath("~", "/fake/home"), "/fake/home")
  assert.equal(resolveHomePath("/private/tmp", "/fake/home"), "/private/tmp")
  assert.equal(resolveHomePath(".thrum", "/fake/home"), ".thrum")
})

// ─── (x) writeConfig crash-safety (Pass-3 B3) ──────────────────────────────
// The merge target is the user's REAL global opencode.json: a half-written
// file (crash mid-write) bricks every future install, because readConfig
// deliberately THROWS on malformed JSON instead of treating it as absent.
// writeConfig must therefore be atomic — write to a temp file in the SAME
// directory (same filesystem, so the final rename is atomic), flush it to
// disk, swap by rename, preserve the existing file's permission mode on
// overwrite, and leave ZERO temp residue on any failure — with the original
// file byte-identical and untouched whenever the new content did not fully
// land.

function noTempResidue(dir: string): string[] {
  return fs.readdirSync(dir).filter((name) => name.includes(".tmp-"))
}

test("writeConfig: successful write lands the content and leaves zero temp residue", () => {
  const dir = mkTmpDir()
  const configPath = path.join(dir, "opencode.json")
  writeConfig(configPath, { permission: { bash: "deny" } })

  const onDisk = JSON.parse(fs.readFileSync(configPath, "utf8"))
  assert.equal(onDisk.permission.bash, "deny", "the written config must round-trip")
  assert.deepEqual(noTempResidue(dir), [], "a successful write must leave no temp residue")
})

test("writeConfig: serialization failure leaves the original byte-identical with no residue", () => {
  const dir = mkTmpDir()
  const configPath = path.join(dir, "opencode.json")
  const sentinel = `{"keep":"me","permission":{"bash":"deny"}}\n`
  fs.writeFileSync(configPath, sentinel)

  const circular: Record<string, unknown> = {}
  circular["self"] = circular
  assert.throws(() => writeConfig(configPath, circular as never), "a non-serializable config must throw, not silently write a partial file")

  assert.equal(
    fs.readFileSync(configPath, "utf8"),
    sentinel,
    "the original config must be byte-identical after a failed write (never truncated or mixed)",
  )
  assert.deepEqual(noTempResidue(dir), [], "a failed write must clean up its temp file")
})

test("writeConfig: rename failure cleans temp residue and rethrows", () => {
  const dir = mkTmpDir()
  // The rename target exists as a DIRECTORY: rename must fail, the error
  // must propagate, and the temp file must not be left behind.
  const configPath = path.join(dir, "opencode.json")
  fs.mkdirSync(configPath)

  assert.throws(() => writeConfig(configPath, { permission: { bash: "deny" } }))
  assert.deepEqual(noTempResidue(dir), [], "a failed rename must not leave temp residue")
})

test("writeConfig: overwrite preserves the existing file's permission mode", () => {
  const dir = mkTmpDir()
  const configPath = path.join(dir, "opencode.json")
  fs.writeFileSync(configPath, `{"older":true}\n`)
  fs.chmodSync(configPath, 0o640)

  writeConfig(configPath, { permission: { read: "deny" } })

  const mode = fs.statSync(configPath).mode & 0o777
  assert.equal(mode, 0o640, "an overwrite must not widen or narrow the existing file's mode")
  const onDisk = JSON.parse(fs.readFileSync(configPath, "utf8"))
  assert.equal(onDisk.permission.read, "deny", "the overwrite itself must land")
  assert.deepEqual(noTempResidue(dir), [], "no residue after a mode-preserving overwrite")
})

test("writeConfig: overwrite swaps in a NEW inode via rename, never truncates the original in place", () => {
  const dir = mkTmpDir()
  const configPath = path.join(dir, "opencode.json")
  fs.writeFileSync(configPath, `{"version":"old"}\n`)
  const beforeIno = fs.statSync(configPath).ino

  writeConfig(configPath, { permission: { bash: "deny" } })

  const afterIno = fs.statSync(configPath).ino
  assert.notEqual(
    afterIno,
    beforeIno,
    "the overwrite must swap in a freshly-written same-directory file via atomic rename — " +
      "truncating the original inode in place leaves a half-written user config on a crash",
  )
  assert.equal(JSON.parse(fs.readFileSync(configPath, "utf8")).permission.bash, "deny")
  assert.deepEqual(noTempResidue(dir), [])
})
