// Drift guard (allowlist round 2, finding 9): the canonical allowlist
// (internal/permissions/thrum_allowlist.json, Go-owned) is copied verbatim
// into this plugin's bundled asset (opencode-plugin/assets/thrum_allowlist.
// json) by scripts/sync-skills.sh's sync_opencode step, since TypeScript
// cannot import a Go package. This test fails LOUDLY the moment the two
// diverge — a hand-edit of either copy, or a Go-side change that never got
// synced.
//
// Deliberately compares RAW BYTES, not parsed-then-reserialized JSON: a
// round-trip through JSON.parse/JSON.stringify would normalize whitespace,
// key order, and formatting, and could mask a real drift (e.g. a
// re-ordered or re-indented — but content-different — copy would compare
// "equal" after reserialization while still being a byte-for-byte
// divergence from the Go source of truth).

import { test } from "node:test"
import assert from "node:assert/strict"
import fs from "fs"
import path from "path"

// This test file compiles to dist/allowlist-sync.test.js (flat src ->
// flat dist, see tsconfig rootDir/outDir), so at runtime
// path.dirname(import.meta.url) is opencode-plugin/dist. One level up is
// opencode-plugin/ (matches the existing ALLOWLIST_ASSET_PATH convention in
// installer.permissions.test.ts); two levels up is the repo root, from
// which internal/permissions/ is reachable.
const HERE = path.dirname(new URL(import.meta.url).pathname)
const PLUGIN_ROOT = path.resolve(HERE, "..")
const REPO_ROOT = path.resolve(PLUGIN_ROOT, "..")

const OPENCODE_COPY = path.join(PLUGIN_ROOT, "assets", "thrum_allowlist.json")
const CANONICAL_SOURCE = path.join(REPO_ROOT, "internal", "permissions", "thrum_allowlist.json")

test("opencode-plugin/assets/thrum_allowlist.json is byte-identical to internal/permissions/thrum_allowlist.json", (t) => {
  // The canonical source only exists in the monorepo (github.com/leonletto/thrum);
  // the public standalone opencode-thrum-pro repo this test also ships in does not
  // carry internal/permissions/, so skip gracefully there instead of failing —
  // mirrors the binary-absent skip idiom in permission-fixture.integration.test.ts.
  if (!fs.existsSync(CANONICAL_SOURCE)) {
    t.skip(`canonical source not found at ${CANONICAL_SOURCE} — expected outside the monorepo (e.g. public opencode-thrum-pro), skipping drift check`)
    return
  }
  assert.ok(fs.existsSync(OPENCODE_COPY), `synced copy not found at ${OPENCODE_COPY}`)

  const canonical = fs.readFileSync(CANONICAL_SOURCE)
  const copy = fs.readFileSync(OPENCODE_COPY)

  assert.ok(
    canonical.equals(copy),
    "opencode-plugin/assets/thrum_allowlist.json has drifted from internal/permissions/thrum_allowlist.json — " +
      "re-run scripts/sync-skills.sh (sync_opencode step) to resync, never hand-edit either copy independently",
  )
})
