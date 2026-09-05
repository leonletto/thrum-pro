import fs from "fs"
import path from "path"
import os from "os"
import { fileURLToPath } from "url"
import type { PluginInput } from "@opencode-ai/plugin"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const ASSETS_DIR = path.resolve(__dirname, "..", "assets")
const VERSION_FILE = ".thrum-plugin-version"

function getPluginVersion(): string {
  const pkgPath = path.resolve(__dirname, "..", "package.json")
  try {
    const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf8"))
    return pkg.version ?? "0.0.0"
  } catch {
    return "0.0.0"
  }
}

export function getConfigDir(): string {
  const xdg = process.env.XDG_CONFIG_HOME
  if (xdg) return path.join(xdg, "opencode")
  return path.join(os.homedir(), ".config", "opencode")
}

function copyDirRecursive(src: string, dest: string) {
  fs.mkdirSync(dest, { recursive: true })
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const srcPath = path.join(src, entry.name)
    const destPath = path.join(dest, entry.name)
    if (entry.isDirectory()) {
      copyDirRecursive(srcPath, destPath)
    } else {
      fs.copyFileSync(srcPath, destPath)
    }
  }
}

export async function installAssets(ctx: PluginInput) {
  const configDir = getConfigDir()
  const skillsDir = path.join(configDir, "skills")
  const commandsDir = path.join(configDir, "commands")
  const versionPath = path.join(skillsDir, "thrum", VERSION_FILE)

  const currentVersion = getPluginVersion()

  // Check if already installed at this version
  try {
    const installed = fs.readFileSync(versionPath, "utf8").trim()
    if (installed === currentVersion) return
  } catch {
    // Not installed yet
  }

  const log = (msg: string) =>
    ctx.client.app.log({
      body: { service: "opencode-thrum", level: "info", message: msg },
    })

  // Copy each skill subdirectory
  const assetsSkillsDir = path.join(ASSETS_DIR, "skills")
  if (fs.existsSync(assetsSkillsDir)) {
    for (const entry of fs.readdirSync(assetsSkillsDir, {
      withFileTypes: true,
    })) {
      if (!entry.isDirectory()) continue
      const src = path.join(assetsSkillsDir, entry.name)
      const dest = path.join(skillsDir, entry.name)
      copyDirRecursive(src, dest)
      await log(`Installed skill: ${entry.name}`)
    }
  }

  // Copy commands
  const assetsCommandsDir = path.join(ASSETS_DIR, "commands")
  if (fs.existsSync(assetsCommandsDir)) {
    fs.mkdirSync(commandsDir, { recursive: true })
    let count = 0
    for (const entry of fs.readdirSync(assetsCommandsDir)) {
      if (!entry.endsWith(".md")) continue
      fs.copyFileSync(
        path.join(assetsCommandsDir, entry),
        path.join(commandsDir, entry),
      )
      count++
    }
    await log(`Installed ${count} commands`)
  }

  // Write version marker
  fs.mkdirSync(path.dirname(versionPath), { recursive: true })
  fs.writeFileSync(versionPath, currentVersion)
  await log(`opencode-thrum v${currentVersion} assets installed`)
}

// ─── allowlist: OpenCode permission.bash/read allowlist ─────────────────
//
// Design decision (documented here per the allowlist task spec, since this is
// the file that implements it):
//
//   MERGE-AT-INSTALL-TIME INTO THE GLOBAL CONFIG, NOT BAKED INTO THE PER-
//   PROJECT opencode.json.tmpl.
//
// Two independent reasons, either one sufficient on its own:
//
//   1. DRY: the canonical command/read-path list lives in Go
//      (the canonical Go-side allowlist asset). The Go-rendered project
//      template (the Go-rendered opencode config template) is a
//      static text/template file with no access to that data unless the
//      call site in the CLI runtime-init wiring passes it in as template
//      data — and that file is out of scope for this change (owned by a
//      concurrent sub-agent on this task). Hand-typing the pattern list
//      into the .tmpl file instead would duplicate the canonical source,
//      which the task spec explicitly forbids.
//   2. Idempotent durability: the CLI runtime-init wiring currently wires
//      opencode.json.tmpl with the default skip-on-exists write mode (no
//      merge=true, unlike Claude's settings.json.tmpl). A baked-in block
//      would apply only to a brand-new project scaffold and would never
//      reconcile into a project's existing opencode.json. The installer
//      path below runs on every plugin load, merges non-destructively, and
//      is naturally idempotent — the property this task requires.
//
// The merge target is the GLOBAL config file (OpenCode's own documented
// precedence: global config < project opencode.json < .opencode dirs —
// https://opencode.ai/docs/config/, "Settings ... are combined ... later
// configs override earlier ones only for conflicting keys"). Global is the
// right layer for a plugin-provided baseline: it applies to every project
// where the user has this plugin installed, and a project's own
// opencode.json (if any) can still override any single key without being
// clobbered by us, since we never touch project-level files.

// AllowlistSource mirrors internal/permissions.Allowlist's JSON shape
// (Go: Version/CommandPatterns/ReadPaths -> JSON: version/command_patterns/
// read_paths). Kept structurally minimal here; this file only reads it.
interface AllowlistSource {
  version: number
  command_patterns: string[]
  read_paths: string[]
  // owner_authorized_exceptions mirrors internal/permissions.Allowlist's
  // OwnerAuthorizedExceptions field. Optional because older canonical assets
  // (pre round-4) don't carry it — see mergePermissions below, which no-ops
  // cleanly when it's absent.
  owner_authorized_exceptions?: Record<string, string[]>
  // global_read_paths mirrors internal/permissions.Allowlist's
  // GlobalReadPaths field: per-runtime, HOME-relative (may start with "~")
  // absolute directory grants outside the project root. Optional because
  // older canonical assets don't carry it, and because a prior round
  // deliberately gave OpenCode no entries here at all (its own installer
  // derives its global skill/command paths dynamically — see
  // opencodeGlobalReadPaths below, a separate, unrelated mechanism) — see
  // mergePermissions below, which no-ops cleanly when this key, or the
  // "opencode" sub-key, is absent.
  global_read_paths?: Record<string, string[]>
}

type PermissionAction = "ask" | "allow" | "deny"
type PermissionRuleMap = Record<string, PermissionAction>

interface OpenCodeConfig {
  permission?: {
    bash?: PermissionRuleMap | PermissionAction
    read?: PermissionRuleMap | PermissionAction
    [key: string]: unknown
  }
  [key: string]: unknown
}

const ALLOWLIST_ASSET_PATH = path.join(ASSETS_DIR, "thrum_allowlist.json")

// bashExactPatternFor renders the bare-command form of a canonical
// command_patterns entry (e.g. "thrum inbox" -> "thrum inbox"), with no
// trailing glob at all. OpenCode's permission matcher is documented simple-
// wildcard matching (`*` = zero-or-more of any char, `?` = exactly one,
// everything else literal — https://opencode.ai/docs/permissions/,
// verified manually) with NO built-in word-boundary behavior: `*` matches
// straight through a word boundary, so a bare `${commandPattern}*` key (the
// round-1 shape) would also allow "thrum inboxx-evil" under the "thrum
// inbox" grant. This exact-match key is the half of the two-key pair (see
// bashPatternFor below) that covers invoking the command with NO arguments
// at all, where a glob suffix would otherwise require a literal trailing
// character to exist.
export function bashExactPatternFor(commandPattern: string): string {
  return commandPattern
}

// bashPatternFor renders the with-arguments form of a canonical
// command_patterns entry (e.g. "thrum inbox" -> "thrum inbox *"). The
// literal SPACE before the glob is the word-boundary fix (the allowlist effort round
// 2, finding 7): it requires a real space character to follow the command
// prefix before the glob can start matching, so "thrum inbox *" matches
// "thrum inbox --unread" but does NOT match "thrum inboxx-evil" (no space
// after "inbox" in that string) or "thrum inboxx" (same reason). Round 1's
// bare `${commandPattern}*` (no space) is what let those adjacent-command
// false positives through — see the negative-control test added alongside
// this fix.
export function bashPatternFor(commandPattern: string): string {
  return `${commandPattern} *`
}

// readPatternFor renders one canonical read_paths entry (e.g. ".thrum")
// into an OpenCode read/external_directory glob key admitting the whole
// subtree.
//
// LEADING-SLASH STRIP — measured against the real `opencode` binary
// (the allowlist effort round 4, by-effect fixture): OpenCode's permission matcher
// normalizes an absolute candidate path with its leading "/" removed before
// comparing against configured patterns. A literal "/private/tmp/**" key
// NEVER matched a read of "/private/tmp/x" in the real oracle (fell through
// to OpenCode's own built-in default every time, regardless of "*" default
// or key order); the identical pattern with the leading slash stripped,
// "private/tmp/**", matched correctly both ways — ALLOW under the granted
// path, DENY on a sibling root. This was previously unverified: no by-effect
// test exercised an absolute-path read pattern before this round, so this
// same defect silently affected opencodeGlobalReadPaths's configDir-derived
// DIRECTORY patterns below (${configDir}/skills, ${configDir}/commands)
// since they are rendered through this same function. It is a no-op for
// the already-relative canonical read_paths entries (e.g. ".thrum"), which
// never had a leading slash to strip.
//
// The THIRD opencodeGlobalReadPaths entry, ${configDir}/opencode.json, is a
// FILE, not a directory — it is rendered through the sibling
// readFilePatternFor (same strip, no "/**" suffix), not this function; see
// that function's doc comment for a round-4-review finding where this file
// entry was initially missed and stayed silently broken one round after
// this fix landed for the directory entries.
export function readPatternFor(readPath: string): string {
  const normalized = stripLeadingSlash(readPath)
  return `${normalized}/**`
}

// stripLeadingSlash removes a leading "/" from an absolute path so it
// matches OpenCode's real permission-matcher normalization (see
// readPatternFor's doc comment above). Shared by readPatternFor (directory
// glob entries) and readFilePatternFor (exact-file entries, which must NOT
// get a "/**" suffix — a file is not a tree) so both render through the
// SAME normalization instead of two independently-maintained copies of it.
function stripLeadingSlash(p: string): string {
  return p.startsWith("/") ? p.slice(1) : p
}

// resolveHomePath expands a leading "~" (bare, or "~/...") into an absolute
// path rooted at homeDir, otherwise returns the path unchanged. Takes homeDir
// as an explicit parameter (default os.homedir()) rather than calling
// os.homedir() inline so callers (tests, the by-effect fixture) can resolve
// against an isolated fake home without mutating process.env.HOME globally —
// mirrors how installPermissions/mergePermissions already take configDir as
// an explicit parameter for the identical reason.
//
// Every OTHER absolute-path grant this file renders (opencodeGlobalReadPaths,
// owner_authorized_exceptions' /private/tmp) is either already absolute or
// derived from getConfigDir(), which itself resolves os.homedir() and never
// emits a literal "~" (confirmed pattern in this codebase — see getConfigDir
// above). global_read_paths entries are the first canonical-allowlist value
// to arrive as a literal "~"-prefixed string, so this is the one call site
// that needs to expand it before handing the result to readPatternFor —
// never emit a literal, unexpanded "~" into a rendered permission key.
export function resolveHomePath(p: string, homeDir: string = os.homedir()): string {
  if (p === "~") return homeDir
  if (p.startsWith("~/")) return path.join(homeDir, p.slice(2))
  return p
}

// readFilePatternFor renders an absolute path to a single FILE (not a
// directory subtree) into an OpenCode read-permission key: the same
// leading-slash strip as readPatternFor, but no "/**" suffix — round-4
// review finding (cq, by-effect-confirmed): opencodeGlobalReadPaths's
// ${configDir}/opencode.json entry was rendered as a raw, unstripped path
// and so was STILL silently broken by the same defect readPatternFor's
// fix addressed everywhere else. Confirmed by-effect (real opencode
// binary) that only the stripped form renders correctly.
export function readFilePatternFor(filePath: string): string {
  return stripLeadingSlash(filePath)
}

// loadAllowlist reads the canonical allowlist JSON asset bundled with this
// plugin (opencode-plugin/assets/thrum_allowlist.json — a byte-for-byte
// copy of internal/permissions/thrum_allowlist.json, kept in sync by
// scripts/sync-skills.sh's sync_opencode step; see that script's comment
// for why a copy is needed instead of a live cross-language import).
export function loadAllowlist(assetPath: string = ALLOWLIST_ASSET_PATH): AllowlistSource {
  const raw = fs.readFileSync(assetPath, "utf8")
  return JSON.parse(raw) as AllowlistSource
}

// OPENCODE_WILDCARD_KEY is the object-map form's documented catch-all key
// (https://opencode.ai/docs/permissions/, verified manually: "A common
// pattern is to put the catch-all '*' rule first, and more specific rules
// after it" — the schema's object-map form has no dedicated default-key
// field; "*" IS the default-key convention). Rule evaluation is
// last-match-wins over the map's key order, and a JS object's string keys
// iterate in insertion order — so this key must always be inserted FIRST,
// before any thrum-specific pattern, or a later "*" insertion would win and
// silently shadow every thrum allow entry.
const OPENCODE_WILDCARD_KEY = "*"

// preserveBareScalarAsDefault turns a pre-existing BARE-STRING permission
// action (the schema's PermissionActionConfig form — a blanket default for
// every command, e.g. permission.bash: "deny") into the seed of an object
// map that keeps that blanket action as the map's "*" default, so a
// caller's stricter-than-OpenCode's-own-default posture ("deny"/"ask") is
// never silently widened by our overlay (the allowlist effort round 2, finding 3).
// Confirmed against the schema before writing this: the object-map form
// DOES support a "*" default key (see OPENCODE_WILDCARD_KEY above), so this
// is the "schema supports a default key" branch, not the leave-untouched
// fallback — the fallback is unnecessary here.
function preserveBareScalarAsDefault(existing: PermissionRuleMap | PermissionAction | undefined): PermissionRuleMap {
  if (typeof existing === "string") return { [OPENCODE_WILDCARD_KEY]: existing }
  if (existing && typeof existing === "object") return { ...existing }
  return {}
}

// mergePermissions returns a NEW config object with permission.bash and
// permission.read populated from the allowlist (plus any already-rendered
// extraReadPatterns, e.g. OpenCode's own global skills/commands subtree —
// see opencodeGlobalReadPaths), preserving every other key (including any
// pre-existing permission.* sub-keys such as permission.edit) untouched.
// Pure function, no I/O — kept separate from installPermissions so it's
// directly unit-testable.
//
// If an existing permission.bash/read is a bare action string (e.g. "ask"
// or "deny") rather than an object map, that string is a blanket default
// the caller set deliberately for EVERY command/path, and is preserved
// as-is via preserveBareScalarAsDefault — never dropped, never silently
// widened by treating the overlay as a full replacement.
export function mergePermissions(
  config: OpenCodeConfig,
  allowlist: AllowlistSource,
  extraReadPatterns: string[] = [],
  homeDir: string = os.homedir(),
): OpenCodeConfig {
  const merged: OpenCodeConfig = { ...config }
  const existingPermission = merged.permission ?? {}
  const permission = { ...existingPermission }

  const bash = preserveBareScalarAsDefault(existingPermission.bash)
  for (const commandPattern of allowlist.command_patterns) {
    bash[bashExactPatternFor(commandPattern)] = "allow"
    bash[bashPatternFor(commandPattern)] = "allow"
  }

  const read = preserveBareScalarAsDefault(existingPermission.read)
  for (const readPath of allowlist.read_paths) {
    read[readPatternFor(readPath)] = "allow"
  }
  for (const pattern of extraReadPatterns) {
    read[pattern] = "allow"
  }

  // OWNER-AUTHORIZED EXCEPTION — /private/tmp (owner ruling, watcher-
  // recovery P0; scope CONFIRMED all-runtimes by the fleet coordinator the same
  // day — owner's wording was "global configs for all agents", the
  // operational-artifact class is runtime-independent): the canonical
  // allowlist's owner_authorized_exceptions grants EVERY supported runtime
  // broad READ access to /private/tmp/* DESPITE it being a world-writable
  // directory — explicitly ruled acceptable by the owner for
  // coordinator/watcher operational artifacts. This is a DELIBERATE
  // exception, not a template for widening elsewhere: it grants READ/ACCESS
  // ONLY — never execute, never shell-interpolation, never a sibling root
  // like /private or /private/tmpfoo, never write/delete. See
  // internal/permissions/thrum_allowlist.json's own "OWNER-AUTHORIZED
  // EXCEPTION" comment for the full ruling this quotes from. Rendered
  // through the same readPatternFor() glob as canonical read_paths (e.g.
  // "/private/tmp" -> "/private/tmp/**") so it goes through the identical
  // preserveBareScalarAsDefault-aware merge machinery above — never a
  // bypass path.
  const ownerExceptions = allowlist.owner_authorized_exceptions?.opencode ?? []
  for (const exceptionPath of ownerExceptions) {
    read[readPatternFor(exceptionPath)] = "allow"
  }

  // GLOBAL READ PATHS — ~/.local/bin (owner ruling, consolidated round):
  // the canonical allowlist's global_read_paths grants OpenCode (like Claude
  // and Codex) READ access to the thrum-binary install directory, so
  // PATH-resolved "thrum" can actually execute under the runtime's sandbox.
  // Rendered through the SAME readPatternFor() glob and the SAME
  // preserveBareScalarAsDefault-aware merge machinery as read_paths and
  // owner_authorized_exceptions above — never a bypass path. Each entry is
  // resolved through resolveHomePath() BEFORE readPatternFor() so a literal
  // "~" is expanded to the real absolute path first (every other absolute-
  // path grant in this file is already fully expanded before rendering; see
  // resolveHomePath's doc comment for why this is the one call site that
  // needs the expansion step). Optional chaining: absent on an older/
  // pre-round canonical asset, and a prior round deliberately left OpenCode
  // with no entries here at all (see AllowlistSource's global_read_paths
  // doc comment) — both no-op cleanly to an empty array.
  const globalReadPaths = allowlist.global_read_paths?.opencode ?? []
  for (const rawPath of globalReadPaths) {
    read[readPatternFor(resolveHomePath(rawPath, homeDir))] = "allow"
  }

  permission.bash = bash
  permission.read = read
  merged.permission = permission
  return merged
}

// readConfig is split out from installPermissions so tests can exercise
// mergePermissions in isolation without touching disk, and so
// installPermissions itself stays a thin, obviously-idempotent I/O shell.
//
// Mirrors the Go-side hookmerge Load(): an empty config is
// returned ONLY when the file genuinely does not exist (Node's ENOENT,
// matching Go's os.IsNotExist). Any other failure — malformed JSON,
// permission-denied read, or any other I/O error — is THROWN, never
// swallowed into {}. Swallowing a parse error here previously meant a
// user's hand-edited-but-broken global opencode.json (e.g. a stray comma)
// was treated as "absent" and silently overwritten by installPermissions()
// with a fresh config containing only thrum's permission block, discarding
// every other setting the user had (the allowlist effort landing-blocker).
function readConfig(configPath: string): OpenCodeConfig {
  let raw: string
  try {
    raw = fs.readFileSync(configPath, "utf8")
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return {}
    throw new Error(
      `failed to read OpenCode config at ${configPath}: ${(err as Error).message}`,
      { cause: err },
    )
  }
  try {
    return JSON.parse(raw) as OpenCodeConfig
  } catch (err) {
    throw new Error(
      `failed to parse OpenCode config at ${configPath} as JSON — it will be left untouched: ${(err as Error).message}`,
      { cause: err },
    )
  }
}

// Split out from installPermissions (like readConfig) so tests can exercise
// the crash-safety contract directly.
//
// Pass-3 B3 — ATOMIC by construction. The merge target is the user's REAL
// global opencode.json, and readConfig deliberately throws on malformed JSON
// (never treats it as absent), so a half-written file from a crash mid-write
// would brick every future install AND OpenCode's own config load. The write
// is therefore:
//   1. fully serialized in memory FIRST (a non-serializable config throws
//      before anything on disk is touched);
//   2. written to a temp file in the SAME directory as the target (same
//      filesystem, so the final rename is atomic — never a cross-device
//      EXDEV rename), with the existing file's permission mode preserved on
//      overwrite (a fresh file gets 0o600 — narrower, never wider, than the
//      old writeFileSync default on a fresh create);
//   3. fsync'd before the rename, so the bytes are durable before the name
//      flips (a crash after the rename can then only leave the old OR the
//      new complete file — never a truncated or mixed one);
//   4. swapped in by rename (atomic; the original inode is never truncated
//      in place) — and on any failure the temp file is unlinked before the
//      error propagates, so zero temp residue is ever left behind.
export function writeConfig(configPath: string, config: OpenCodeConfig): void {
  const dir = path.dirname(configPath)
  const serialized = `${JSON.stringify(config, null, 2)}\n`
  fs.mkdirSync(dir, { recursive: true })

  const tmpPath = path.join(
    dir,
    `.${path.basename(configPath)}.tmp-${process.pid}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
  )

  let mode = 0o600
  try {
    mode = fs.statSync(configPath).mode & 0o777
  } catch {
    // Target does not exist yet — keep the restrictive fresh-file default.
  }

  let fd: number | undefined
  try {
    fd = fs.openSync(tmpPath, "w", mode)
    fs.writeSync(fd, serialized)
    fs.fsyncSync(fd)
    fs.closeSync(fd)
    fd = undefined
    fs.renameSync(tmpPath, configPath)
  } catch (err) {
    if (fd !== undefined) {
      try {
        fs.closeSync(fd)
      } catch {
        // best-effort close on the error path — the original close error
        // (if any) matters more than this one
      }
    }
    try {
      fs.unlinkSync(tmpPath)
    } catch {
      // best-effort residue cleanup; never mask the real failure
    }
    throw err
  }
}

// opencodeGlobalReadPaths returns the already-rendered read-glob patterns
// for OpenCode's OWN global install subtree under configDir: exactly the
// ${configDir}/skills and ${configDir}/commands trees installAssets() (see
// above in this file) writes to, plus the global opencode.json config file
// itself. This is the allowlist effort round 2 finding 1: the canonical allowlist's
// read_paths are all PROJECT-relative (.thrum, .claude/skills, etc) and
// cannot express OpenCode's absolute, outside-the-project global config
// location — a watcher/orchestrator reading its own installed OpenCode
// skill/command files needs read access to THAT subtree too, in ADDITION
// to (never instead of) the canonical project-relative set.
//
// Deliberately scoped to configDir and its known children only — no
// broader home-dir grant. Resolved via getConfigDir() (or the configDir
// passed to installPermissions), never hardcoded, so it tracks
// XDG_CONFIG_HOME/HOME like the rest of this file.
export function opencodeGlobalReadPaths(configDir: string): string[] {
  return [
    readPatternFor(path.join(configDir, "skills")),
    readPatternFor(path.join(configDir, "commands")),
    readFilePatternFor(path.join(configDir, "opencode.json")),
  ]
}

// installPermissions merges the canonical thrum command/read-path allowlist
// — plus OpenCode's own global skills/commands/config read grant (see
// opencodeGlobalReadPaths) — into the user's GLOBAL OpenCode config
// (${configDir}/opencode.json). Idempotent: re-running with unchanged
// inputs (allowlist + prior config) produces byte-identical output, since
// mergePermissions is a pure deterministic function of its inputs and
// readConfig/writeConfig round-trip via JSON.stringify with a fixed
// 2-space indent.
//
// If the existing config is present but malformed (unreadable or invalid
// JSON), readConfig() throws rather than returning {} — this function does
// NOT catch that error, so mergePermissions/writeConfig are never reached
// and the on-disk file is left byte-for-byte untouched. The caller (see
// index.ts) is responsible for catching and logging that error without
// crashing plugin bootstrap.
// homeDir defaults to os.homedir() and is used ONLY to resolve
// global_read_paths' "~"-prefixed entries (see resolveHomePath); it is
// independent of configDir (OpenCode's own global config directory, which
// may live under XDG_CONFIG_HOME and not under homeDir at all). Threaded
// through as an explicit parameter — never read inline via os.homedir()
// inside mergePermissions' caller chain — so tests and the by-effect
// fixture can resolve against an isolated fake home without mutating
// process.env.HOME globally.
export async function installPermissions(
  configDir: string = getConfigDir(),
  homeDir: string = os.homedir(),
): Promise<void> {
  const configPath = path.join(configDir, "opencode.json")
  const existing = readConfig(configPath)
  const allowlist = loadAllowlist()
  const merged = mergePermissions(existing, allowlist, opencodeGlobalReadPaths(configDir), homeDir)
  writeConfig(configPath, merged)
}
