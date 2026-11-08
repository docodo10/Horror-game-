#!/usr/bin/env node
// Headless playtest / screenshot harness (Playwright + software WebGL).
//
// Usage:
//   node tools/shot.cjs [--query "autostart&debug&cam=0.25,0,1.5,0,0"] [--out shot.png] [--wait 6000]
//                       [--eval "js run in page after load (game = window.__game)"] [--size 1280x720]
//                       [--steps steps.json] [--mobile]
// Env:
//   THREE_DIR  path to a local `three` package (node_modules/three) used instead of the CDN (offline-safe).
//   PORT       static server port (default random)
//
// --steps: JSON array of { "wait": ms } | { "eval": "code" } | { "shot": "file.png" } | { "canvas": "file.png" } (WebGL only, robust under load) | { "key": "KeyW", "ms": 800 }
// Prints console errors / page errors; exits 1 if any uncaught page error happened.
const http = require('http');
const fs = require('fs');
const path = require('path');
const { chromium, devices } = require('playwright');

const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf('--' + k); return i >= 0 ? (args[i + 1] && !args[i + 1].startsWith('--') ? args[i + 1] : true) : d; };
const ROOT = path.resolve(__dirname, '..');
const THREE_DIR = process.env.THREE_DIR;
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json', '.glb': 'model/gltf-binary', '.jpg': 'image/jpeg', '.png': 'image/png', '.webp': 'image/webp', '.css': 'text/css' };

const server = http.createServer((req, res) => {
  const u = decodeURIComponent(req.url.split('?')[0]);
  let f = path.join(ROOT, u === '/' ? 'index.html' : u);
  if (!f.startsWith(ROOT) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end('nf'); }
  res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
  fs.createReadStream(f).pipe(res);
});

// Machine-wide mutex: only one headless browser at a time (software WebGL uses 3-5 GB of RAM per page; several
// agents testing at once get OOM-killed). mkdir is atomic; stale locks (> 25 min) are broken. NO_LOCK=1 skips it.
const os = require('os');
const LOCK = path.join(os.tmpdir(), 'lagardienne-browser.lock');
async function acquireLock() {
  if (process.env.NO_LOCK) return;
  const t0 = Date.now();
  for (;;) {
    try { fs.mkdirSync(LOCK); fs.writeFileSync(path.join(LOCK, 'pid'), String(process.pid)); break; }
    catch (_) {
      try { if (Date.now() - fs.statSync(LOCK).mtimeMs > 25 * 60e3) { fs.rmSync(LOCK, { recursive: true, force: true }); continue; } } catch (_) {}
      if (Date.now() - t0 > 60 * 60e3) throw new Error('browser lock timeout');
      await new Promise((r) => setTimeout(r, 2000));
    }
  }
  console.log(`[harness] lock acquired after ${((Date.now() - t0) / 1000).toFixed(0)} s`);
  const release = () => { try { if (fs.readFileSync(path.join(LOCK, 'pid'), 'utf8') === String(process.pid)) fs.rmSync(LOCK, { recursive: true, force: true }); } catch (_) {} };
  process.on('exit', release);
  for (const sig of ['SIGINT', 'SIGTERM']) process.on(sig, () => { release(); process.exit(130); });
}

(async () => {
  await acquireLock();
  await new Promise((r) => server.listen(Number(process.env.PORT || 0), r));
  const port = server.address().port;
  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required', '--disable-gpu-watchdog', '--disable-renderer-backgrounding', '--disable-background-timer-throttling'] });
  const size = String(opt('size', '1280x720')).split('x').map(Number);
  const ctx = opt('mobile', false)
    ? await browser.newContext({ ...devices['Pixel 7'], viewport: { width: 915, height: 412 } , isMobile: true, hasTouch: true })
    : await browser.newContext({ viewport: { width: size[0], height: size[1] } });
  const page = await ctx.newPage();
  let pageErrors = 0;
  page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') console.log(`[${m.type()}]`, m.text().slice(0, 400)); else if (opt('verbose', false)) console.log('[log]', m.text().slice(0, 300)); });
  page.on('pageerror', (e) => { pageErrors++; console.log('[pageerror]', e.message, (e.stack || '').split('\n').slice(0, 4).join(' | ')); });
  page.on('requestfailed', (r) => { if (!r.url().includes('fonts.g')) console.log('[requestfailed]', r.url(), r.failure()?.errorText); });
  await page.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ status: 200, contentType: 'text/css', body: '' }));
  await page.route('https://fonts.gstatic.com/**', (r) => r.abort());
  if (THREE_DIR) {
    await page.route('https://cdn.jsdelivr.net/npm/three@0.170.0/**', (route) => {
      const rel = route.request().url().split('three@0.170.0/')[1];
      const f = path.join(THREE_DIR, rel);
      if (!fs.existsSync(f)) return route.fulfill({ status: 404, body: 'nf' });
      route.fulfill({ status: 200, contentType: 'text/javascript', body: fs.readFileSync(f) });
    });
  }
  const query = opt('query', 'autostart&debug');
  const url = `http://127.0.0.1:${port}/index.html?${query}`;
  console.log('open', url);
  await page.goto(url);
  const t0 = Date.now();
  // wait until the game finished init (window.__game with state != loading) or timeout
  await page.waitForFunction(() => window.__game && window.__game.state !== 'loading', null, { timeout: 120000 }).catch(() => console.log('[harness] game did not leave loading state'));
  console.log(`[harness] ready in ${Date.now() - t0} ms`);
  const steps = opt('steps', null) ? JSON.parse(fs.readFileSync(opt('steps'), 'utf8')) : [
    { wait: Number(opt('wait', 4000)) },
    ...(opt('eval', null) ? [{ eval: opt('eval') }, { wait: 1500 }] : []),
    { shot: opt('out', 'shot.png') },
  ];
  for (const s of steps) {
    if (s.wait) await page.waitForTimeout(s.wait);
    if (s.eval) { try { const r = await page.evaluate(s.eval); if (r !== undefined) console.log('[eval]', typeof r === 'string' ? r : JSON.stringify(r).slice(0, 2000)); } catch (e) { console.log('[eval error]', e.message); pageErrors++; } }
    if (s.key) { await page.keyboard.down(s.key); await page.waitForTimeout(s.ms || 500); await page.keyboard.up(s.key); }
    if (s.click) await page.mouse.click(s.click[0], s.click[1]);
    if (s.shot) { await page.screenshot({ path: s.shot, timeout: 180000 }); console.log('[shot]', s.shot); }
    if (s.canvas) {
      // Render one frame and read the canvas in the same task (no compositor wait; WebGL scene only, no DOM UI).
      const dataUrl = await page.evaluate(() => { const g = window.__game; g.renderer.render(0.016); return g.canvas.toDataURL('image/png'); });
      fs.writeFileSync(s.canvas, Buffer.from(dataUrl.split(',')[1], 'base64'));
      console.log('[canvas]', s.canvas);
    }
  }
  const fps = await page.evaluate(() => window.__game?.renderer?.fps).catch(() => null);
  console.log('[harness] fps(software GL)=', fps && fps.toFixed ? fps.toFixed(1) : fps, ' pageErrors=', pageErrors);
  await browser.close();
  server.close();
  process.exit(pageErrors ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
