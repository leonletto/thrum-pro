import test from "node:test"
import assert from "node:assert/strict"
import fs from "fs"
import os from "os"
import path from "path"
import { installAssets, sanitizeSkillsSubdir } from "./installer.js"

const ctx = { client: { app: { log: async () => {} } } } as any

function withConfig(fn: (dir: string) => Promise<void>) {
  return async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "oc-inst-"))
    const prev = process.env.XDG_CONFIG_HOME
    process.env.XDG_CONFIG_HOME = dir
    try {
      await fn(path.join(dir, "opencode"))
    } finally {
      if (prev === undefined) delete process.env.XDG_CONFIG_HOME
      else process.env.XDG_CONFIG_HOME = prev
      fs.rmSync(dir, { recursive: true })
    }
  }
}

const pkgVersion = JSON.parse(
  fs.readFileSync(path.resolve(import.meta.dirname, "..", "package.json"), "utf8"),
).version

test("open-core: flat skills/<name>, marker in skills/thrum", withConfig(async (cfg) => {
  await installAssets(ctx, { skillsSubdir: "thrum" })
  assert.ok(fs.existsSync(path.join(cfg, "skills", "thrum", ".thrum-plugin-version")))
  assert.ok(fs.existsSync(path.join(cfg, "skills", "configure-roles")))
  assert.ok(!fs.existsSync(path.join(cfg, "skills", "thrum-pro")))
  assert.equal(fs.readFileSync(path.join(cfg, "skills", "thrum", ".thrum-plugin-flavor"), "utf8"), "open-core")
}))

test("pro: skills nested under skills/thrum-pro, marker there", withConfig(async (cfg) => {
  await installAssets(ctx, { skillsSubdir: "thrum-pro" })
  const v = fs.readFileSync(path.join(cfg, "skills", "thrum-pro", ".thrum-plugin-version"), "utf8")
  assert.equal(v, pkgVersion)
  assert.ok(fs.existsSync(path.join(cfg, "skills", "thrum-pro", "configure-roles")))
  assert.ok(!fs.existsSync(path.join(cfg, "skills", "configure-roles")))
  assert.equal(fs.readFileSync(path.join(cfg, "skills", "thrum-pro", ".thrum-plugin-flavor"), "utf8"), "pro")
}))

test("pro: leaves an existing skills/thrum install untouched", withConfig(async (cfg) => {
  const legacy = path.join(cfg, "skills", "thrum")
  fs.mkdirSync(legacy, { recursive: true })
  fs.writeFileSync(path.join(legacy, ".thrum-plugin-version"), "9.9.9")
  await installAssets(ctx, { skillsSubdir: "thrum-pro" })
  assert.equal(fs.readFileSync(path.join(legacy, ".thrum-plugin-version"), "utf8"), "9.9.9")
}))

test("invalid subdir falls back to default", () => {
  for (const bad of ["../evil", "a/b", "", "..", ".", undefined]) {
    assert.equal(sanitizeSkillsSubdir(bad), "thrum")
  }
  assert.equal(sanitizeSkillsSubdir("thrum-pro"), "thrum-pro")
})
