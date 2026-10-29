// Read what the GUI renders for agents: the left-rail heading "Agents (N)", the
// five active Fleet category badges, and the incomplete-records notice.
//
// Needs Playwright and a browser: Playwright's bundled Chromium, or an installed Google Chrome. Node resolves `playwright` from the script's
// own location, so run it from inside a thrum checkout that has Playwright
// installed (the checkout root or ui/packages/web-app after
// `pnpm install --frozen-lockfile`), or copy the script into ui/packages/web-app:
//   node <path-to>/agent-count-gui.mjs <ui-url>
// <ui-url> is the "ui" line of `thrum daemon status` on the node, for example
// http://localhost:34003/#/fleet. Open the Fleet route; the rail sits beside it.
// The bundled Chromium is tried first; when it is not installed the script tries the newest
// installed chromium-<rev> under the Playwright browsers dir (PLAYWRIGHT_BROWSERS_PATH, else the
// per-user ms-playwright cache), then the installed Chrome (channel 'chrome'). It prints the
// route used on stderr (browser=...). It NEVER installs a browser: on a node with none of them,
// it exits 3 and you read the numbers by hand (the manual selectors in the skill).
// Viewport is 1280x720 so the rail is not collapsed.
//
// Prints one JSON line: { rail, fleet, categories, notice_text }. Compare it with
// agent-count-expected.py run on the node: rail must equal rail_expected and
// fleet must equal fleet_expected. The notice is information only.
import { existsSync, readdirSync, realpathSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const CATEGORIES = ['Working', 'Standby', 'EmptySession', 'RuntimeExited', 'Worktree'];

// Playwright says "Executable doesn't exist" for a missing bundled browser and
// "Chromium distribution 'chrome' is not found" for a missing channel.
const MISSING_BROWSER = /Executable doesn't exist|distribution '[^']*' is not found/i;

/** Where Playwright keeps its downloaded browsers (null when it is a package-local dir). */
export function playwrightBrowsersDir(env = process.env, platform = process.platform) {
  const custom = env.PLAYWRIGHT_BROWSERS_PATH;
  if (custom === '0') return null;
  if (custom) return custom;
  const home = env.HOME || env.USERPROFILE || homedir();
  if (platform === 'darwin') return join(home, 'Library', 'Caches', 'ms-playwright');
  if (platform === 'win32') return join(env.LOCALAPPDATA || join(home, 'AppData', 'Local'), 'ms-playwright');
  return join(env.XDG_CACHE_HOME || join(home, '.cache'), 'ms-playwright');
}

const CHROMIUM_EXECUTABLES = {
  linux: { dir: /^chrome-linux/, exe: ['chrome'] },
  darwin: {
    dir: /^chrome-mac/,
    exe: ['Chromium.app/Contents/MacOS/Chromium', 'Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing'],
  },
  win32: { dir: /^chrome-win/, exe: ['chrome.exe'] },
};

/** Installed chromium-<rev> executables under the browsers dir, newest revision first. */
export function installedChromiums(dir, platform = process.platform) {
  const layout = CHROMIUM_EXECUTABLES[platform];
  if (!dir || !layout) return [];
  let names;
  try {
    names = readdirSync(dir);
  } catch {
    return [];
  }
  const found = [];
  for (const name of names) {
    const m = /^chromium-(\d+)$/.exec(name);
    if (!m) continue;
    let subdirs = [];
    try {
      subdirs = readdirSync(join(dir, name)).filter((d) => layout.dir.test(d));
    } catch {
      continue;
    }
    const path = subdirs.flatMap((d) => layout.exe.map((e) => join(dir, name, d, e))).find((p) => existsSync(p));
    if (path) found.push({ rev: Number(m[1]), name, path });
  }
  return found.sort((a, b) => b.rev - a.rev);
}

/**
 * Launch order: Playwright's bundled browser, then the newest installed
 * chromium-<rev> under the Playwright browsers dir (a Playwright upgrade can leave
 * only other revisions behind), then installed Chrome. Never installs anything.
 * `via` names the route used: bundled, chromium-<rev> or chrome.
 */
export async function launchBrowser(chromium, opts = {}) {
  try {
    return { browser: await chromium.launch(), via: 'bundled' };
  } catch (e) {
    if (!MISSING_BROWSER.test(String(e && e.message))) throw e;
  }
  const dir = 'browsersDir' in opts ? opts.browsersDir : playwrightBrowsersDir();
  for (const c of installedChromiums(dir, opts.platform)) {
    try {
      return { browser: await chromium.launch({ executablePath: c.path }), via: c.name };
    } catch (e) {
      console.error(`agent-count-gui: ${c.name} did not start: ${String(e && e.message).split('\n')[0]}`);
    }
  }
  try {
    return { browser: await chromium.launch({ channel: 'chrome' }), via: 'chrome' };
  } catch (e) {
    if (!MISSING_BROWSER.test(String(e && e.message))) throw e;
    const err = new Error(
      'no usable browser: Playwright\'s bundled Chromium, any installed chromium-<rev> and an installed Chrome are all ' +
        'missing or failed. This script does not install one. Read the numbers by hand with the manual selectors in the ' +
        'skill (section 8d).',
    );
    err.code = 'NO_BROWSER';
    throw err;
  }
}

/**
 * The incomplete-records notice is one element (data-testid=incomplete-agents-notice)
 * whose own text is the message; read it from the element, not from a child. The
 * component and this selector are pinned together by the web-app test
 * agentCountGuiSelectors.test.tsx.
 */
export async function readNoticeText(notice) {
  return (await notice.count()) ? await notice.innerText() : '';
}

async function main() {
  const url = process.argv[2];
  if (!url) {
    console.error('usage: node agent-count-gui.mjs <ui-url>');
    return 2;
  }
  const { chromium } = await import('playwright');
  let launched;
  try {
    launched = await launchBrowser(chromium);
  } catch (e) {
    if (e.code !== 'NO_BROWSER') throw e;
    console.error(`agent-count-gui: ${e.message}`);
    return 3;
  }
  const { browser, via } = launched;
  console.error(`agent-count-gui: browser=${via}`);
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
    await page.goto(url);
    await page.waitForSelector('[data-testid="fleet-category-tabs"]', { timeout: 60000 });
    // The badges and the rail heading render from the same agent.list call; wait
    // until the rail heading shows a number so the skeleton is gone.
    const railLocator = page.locator('h3', { hasText: /^Agents \(\d+\)$/ }).first();
    await railLocator.waitFor({ timeout: 60000 });
    await page.waitForTimeout(3000);
    const rail = Number((await railLocator.innerText()).match(/\((\d+)\)/)[1]);
    const categories = {};
    for (const c of CATEGORIES) {
      const t = await page.locator(`[data-testid="category-count-${c}"]`).first().innerText();
      categories[c] = Number(t);
    }
    const fleet = Object.values(categories).reduce((a, b) => a + b, 0);
    const notice = page.locator('[data-testid="incomplete-agents-notice"]').first();
    const notice_text = await readNoticeText(notice);
    console.log(JSON.stringify({ rail, fleet, categories, notice_text }));
    return 0;
  } finally {
    await browser.close();
  }
}

// Run only when executed directly, so tests can import launchBrowser.
if (process.argv[1] && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) {
  process.exitCode = await main();
}
