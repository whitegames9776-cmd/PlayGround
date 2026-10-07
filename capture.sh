#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
/usr/bin/time -p pwd
if [ -z "${CAPTURE_URL:-}" ]; then
  /usr/bin/time -p echo "capture.sh: CAPTURE_URL is required" >&2
  exit 1
fi
if [ -z "${CAPTURE_DIR:-}" ]; then
  /usr/bin/time -p echo "capture.sh: CAPTURE_DIR is required" >&2
  exit 1
fi
/usr/bin/time -p mkdir -p "$CAPTURE_DIR"
/usr/bin/time -p echo "capture URL=$CAPTURE_URL dir=$CAPTURE_DIR"
/usr/bin/time -p node --version
HELPER="$(/usr/bin/time -p mktemp /tmp/neon-capture-XXXXXX.mjs 2>/dev/null || mktemp /tmp/neon-capture-XXXXXX.mjs)"
/usr/bin/time -p cat > "$HELPER" <<'NODEJS'
import { readFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { createRequire } from 'node:module';
const runtime = join(process.env.HOME || '/home/runner', '.local/share/omgithub-playwright');
const require = createRequire(join(runtime, 'node_modules', 'package.json'));
const { chromium } = require('playwright');
const linuxCfg = join(runtime, 'linux.json');
const metalCfg = join(runtime, 'metal.json');
const cfgPath = process.platform === 'darwin' ? metalCfg : linuxCfg;
const config = JSON.parse(readFileSync(cfgPath, 'utf8'));
if (process.platform === 'linux') {
  try { process.env.DISPLAY ||= ':' + readFileSync(join(runtime, 'display'), 'utf8').trim(); } catch {}
}
const url = process.env.CAPTURE_URL, output = process.env.CAPTURE_DIR;
if (!url || !output) { console.error('Set CAPTURE_URL and CAPTURE_DIR.'); process.exit(1); }
mkdirSync(output, { recursive: true });
const transient = (error) => { throw Object.assign(error instanceof Error ? error : new Error(String(error)), { exitCode: 75 }); };
let browser;
try {
  browser = await chromium.launch({ ...config.browser.launchOptions, timeout: 30000 }).catch(transient);
  for (const [name, width, height] of [['desktop', 1440, 900], ['mobile', 390, 844]]) {
    const page = await browser.newPage({ viewport: { width, height } }).catch(transient);
    page.setDefaultTimeout(30000);
    page.on('pageerror', (e) => console.error('pageerror:', e.message));
    const response = await page.goto(url, { waitUntil: 'load', timeout: 45000 }).catch(transient);
    const status = response?.status();
    if (!response || !response.ok()) {
      const code = !response || [408, 429, 500, 502, 503, 504].includes(status) ? 75 : 1;
      throw Object.assign(new Error(`HTTP ${status} loading preview ${url}`), { exitCode: code });
    }
    await page.locator(process.env.CAPTURE_READY_SELECTOR || 'body').waitFor({ state: 'visible' }).catch(transient);
    try { await page.waitForFunction(() => document.fonts.status === 'loaded', null, { timeout: 10000 }); } catch {}
    // auto-start: click single Start/Play button if present (same rule as runtime helper)
    try {
      const sel = process.env.CAPTURE_START_SELECTOR || '';
      const candidate = sel ? page.locator(sel) : page.locator('button, input[type="button"], input[type="submit"], [role="button"]');
      const deadline = Date.now() + 3000;
      let clicked = false;
      do {
        const els = await candidate.all();
        const matches = [];
        for (const el of els) {
          if (!(await el.isVisible().catch(() => false))) continue;
          if (!(await el.isEnabled().catch(() => false))) continue;
          const ok = await el.evaluate((node, explicit) => {
            if (node.closest('a[href], form') || node.getAttribute('aria-disabled') === 'true') return false;
            if (explicit) return true;
            const label = node.getAttribute('aria-label') || node.value || node.textContent || '';
            return /^(?:start|play)(?:\s+(?:game|now))?$/i.test(label.trim());
          }, Boolean(sel)).catch(() => false);
          if (ok) matches.push(el);
        }
        if (matches.length === 1) {
          try { await matches[0].click({ trial: true, timeout: 2000 }); } catch { break; }
          await matches[0].click({ timeout: 2000, noWaitAfter: true }).catch(() => {});
          clicked = true; break;
        }
        if (matches.length > 1) break;
        if (Date.now() >= deadline) break;
        await page.waitForTimeout(200);
      } while (Date.now() <= deadline);
      console.log(`Capture ${name}: auto-start ${clicked ? 'clicked' : 'skipped'}`);
    } catch (e) { console.log(`Capture ${name}: auto-start check failed: ${e.message}`); }
    await page.waitForTimeout(1200);
    // rendering-defect check: body must have visible content and canvas
    const probe = await page.evaluate(() => {
      const bodyText = (document.body?.innerText || '').slice(0, 4000);
      const canvas = document.querySelector('canvas');
      let canvasPixels = 0;
      if (canvas) { try { canvasPixels = canvas.width * canvas.height; } catch {} }
      return { bodyLen: bodyText.length, hasCanvas: Boolean(canvas), canvasPixels, title: document.title };
    }).catch((e) => { throw Object.assign(e, { exitCode: 1 }); });
    console.log(`Capture ${name}: probe ${JSON.stringify(probe)}`);
    if (!probe.hasCanvas || probe.canvasPixels < 10000) {
      throw Object.assign(new Error(`rendering defect: canvas missing/small ${JSON.stringify(probe)}`), { exitCode: 1 });
    }
    if (probe.bodyLen < 10) {
      throw Object.assign(new Error('rendering defect: empty body text'), { exitCode: 1 });
    }
    await page.screenshot({ path: join(output, `final-${name}.png`), timeout: 30000 }).catch((error) => {
      if (error.name === 'TimeoutError' || !browser.isConnected()) transient(error);
      throw error;
    });
    console.log(`Capture ${name}: saved final-${name}.png`);
    await page.close().catch(transient);
  }
} catch (error) {
  console.error(error);
  process.exitCode = error.exitCode || 1;
} finally {
  await browser?.close().catch((error) => { console.error(error); process.exitCode ||= 75; });
}
NODEJS
/usr/bin/time -p node "$HELPER"
/usr/bin/time -p rm -f "$HELPER"
/usr/bin/time -p ls -l "$CAPTURE_DIR"
/usr/bin/time -p test -f "$CAPTURE_DIR/final-desktop.png"
/usr/bin/time -p test -f "$CAPTURE_DIR/final-mobile.png"
/usr/bin/time -p bash -c 'test -s "$0/final-desktop.png" && test -s "$0/final-mobile.png"' "$CAPTURE_DIR"
/usr/bin/time -p echo "capture done, app left running"
