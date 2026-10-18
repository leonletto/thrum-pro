// Tests for installAssets skills/commands staging (o4jgf MINOR 13):
// expected content lands on first install, and the version gate makes a
// second install a no-op. Offline/deterministic: temp XDG_CONFIG_HOME,
// stub ctx, real asset tree, never the real $HOME or network.
//
// Run: npm test  (builds, then `node --test dist`)

import { test } from "node:test"
import assert from "node:assert/strict"
import fs from "fs"
import os from "os"
import path from "path"
import { getConfigDir, getSkillsSubdir, installAssets } from "./installer.js"

function stubCtx(): any {
  return { client: { app: { log: async () => {} } } }
}

test("installAssets stages skills and commands; version gate skips reinstall", async () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "thrum-oc-install-"))
  const prevXdg = process.env.XDG_CONFIG_HOME
  process.env.XDG_CONFIG_HOME = tmp
  try {
    await installAssets(stubCtx())
    const cfg = path.join(tmp, "opencode")
    assert.equal(getConfigDir(), cfg)
    // protocol skills ride the wholesale skills copy (o4jgf item 5)
    // open-core is flat (skills/<name>); the pro build nests under skills/<subdir>
    const sub = getSkillsSubdir()
    const skillsRoot = sub === "thrum" ? path.join(cfg, "skills") : path.join(cfg, "skills", sub)
    const skillFile = path.join(skillsRoot, "snapshot-protocol", "SKILL.md")
    assert.ok(fs.existsSync(skillFile))
    assert.ok(fs.existsSync(path.join(cfg, "commands", "thrum-sleep.md")))
    const mtimeBefore = fs.statSync(skillFile).mtimeMs
    await installAssets(stubCtx())
    assert.equal(fs.statSync(skillFile).mtimeMs, mtimeBefore)
  } finally {
    if (prevXdg === undefined) {
      delete process.env.XDG_CONFIG_HOME
    } else {
      process.env.XDG_CONFIG_HOME = prevXdg
    }
    fs.rmSync(tmp, { recursive: true, force: true })
  }
})
