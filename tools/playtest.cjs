#!/usr/bin/env node
// tools/playtest.cjs — automated end-to-end playthrough of "La Gardienne" (Playwright + software WebGL).
//
// What it does (each scenario runs in a fresh page load of ?autostart&debug&quality=<q>[&noentity]):
//   walk    physically walks the player with REAL keyboard input (KeyW held; on --mobile the touch joystick via
//           CDP touch events) along nav-graph waypoints: coffee table → dresser → stairs bottom → landing → back
//           down → laundry nook → console. Yaw is steered toward the next waypoint through the Player API
//           (player.yaw). Validates colliders, stairs, the nook doorway; reports the blocking collider when stuck.
//   story   drives the whole scenario through the Interaction API: finds each entry of game.interaction.entries
//           by its target object (world.items / world.handles / world.clues / world.tv / hideSpots), id or prompt
//           text, teleports next to it, aims the camera at it and presses E (or taps ✋ on mobile); falls back
//           to interaction.activate(id, {force}) / entry.onInteract() when the aim does not select the entry
//           (reported as WARN). Asserts intro → dark → power → code →
//           escape → win + 'game:win'. With --entity she is enabled: her visit after the breaker is logged
//           (state timeline) while the player hides in the closet.
//   caught  (entity enabled) summons her, places the player in front of her, waits for the jumpscare and
//           'entity:caught', clicks "Continuer" on the caught screen and checks the reset (night 2, then 3):
//           respawn, camera control returned, entity dormant, inventory + stage kept. --gameover adds a 3rd catch.
//
// Modals: ui.showNote / showKeypad / showCaught / showWin / showGameOver get PASSTHROUGH wrappers (the real UI is
// shown and used first; the wrapper only resolves the promise when the UI cannot be closed by clicking its buttons).
// The keypad code is injected through the showKeypad promise (puzzles.code). Win / game-over screens are held open
// so the game does not reload the page. 'input:pointerlock' {locked:false} events are swallowed (headless Chromium
// cannot hold pointer lock and would pause the game).
//
// Usage:
//   THREE_DIR=<node_modules/three> node tools/playtest.cjs [options] > report.json
//   --scenario walk,story,caught   scenarios to run (default walk,story)   --all = walk,story,caught
//   --caught            add the caught scenario            --gameover   caught scenario also tests the 3rd catch
//   --entity            story with the entity enabled (logs her visit after the breaker)
//   --mobile            Pixel-7-like landscape touch context (915x412, --dpr n, default 1)   --size WxH   desktop (1280x720)
//   --quality q         low|medium|high|ultra (default low: software GL is slow)
//   --menu              start from the main menu by clicking "Jouer" instead of ?autostart
//   --query "a&b"       extra URL params        --shots DIR   screenshot at every waypoint / story step
//   --out FILE          also write the JSON report to FILE
//   --timeout-scale k   multiply every timeout   --entity-timeout s   max game seconds for her visit (200)
//   --no-force          do not force stages with puzzles.debugGoto() when a step fails (default: force & continue)
//   --allow-stubs       exit 0 when every failure is explained by a module that is still a stub
//   --from cp           story checkpoint: start|breaker|clues|keypad|door (adds &stage=… and skips earlier steps)
//   --verbose           echo page console logs   --headed   show the browser   --max-minutes m   hard limit (90)
// Env: THREE_DIR (local three package instead of the CDN), PORT (static server port).
// Output: progress on stderr, the final JSON report on stdout. Exit code 1 when a check failed, 2 on harness crash.
'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const { chromium, devices } = require('playwright');

const ROOT = path.resolve(__dirname, '..');
const argv = process.argv.slice(2);
const has = (k) => argv.includes('--' + k);
const opt = (k, d) => {
  const i = argv.indexOf('--' + k);
  return i >= 0 && argv[i + 1] !== undefined && !argv[i + 1].startsWith('--') ? argv[i + 1] : d;
};
if (has('help') || has('h')) {
  const head = [];
  for (const l of fs.readFileSync(__filename, 'utf8').split('\n').slice(1)) { if (!l.startsWith('//')) break; head.push(l.replace(/^\/\/ ?/, '')); }
  process.stdout.write(head.join('\n') + '\n');
  process.exit(0);
}

const CFG = {
  mobile: has('mobile'),
  size: String(opt('size', '1280x720')).split('x').map(Number),
  quality: opt('quality', 'low'),
  scenarios: String(opt('scenario', 'walk,story')).split(',').map((s) => s.trim()).filter(Boolean),
  entity: has('entity'),
  gameover: has('gameover'),
  menu: has('menu'),
  query: opt('query', ''),
  shots: opt('shots', null),
  out: opt('out', null),
  tscale: Number(opt('timeout-scale', 1)) || 1,
  entityTimeout: Number(opt('entity-timeout', 200)) || 200,
  force: !has('no-force'),
  allowStubs: has('allow-stubs'),
  verbose: has('verbose'),
  headed: has('headed'),
  maxMinutes: Number(opt('max-minutes', 90)) || 90,
  from: opt('from', 'start'),
};
if (has('caught') && !CFG.scenarios.includes('caught')) CFG.scenarios.push('caught');
if (has('all')) for (const s of ['walk', 'story', 'caught']) if (!CFG.scenarios.includes(s)) CFG.scenarios.push(s);
const THREE_DIR = process.env.THREE_DIR;
// story checkpoints (--from): index, and the puzzles stage the game is started in (gameplay debug param ?stage=)
const CHECKPOINTS = ['start', 'breaker', 'clues', 'keypad', 'door'];
const CHECKPOINT_STAGE = ['intro', 'power', 'code', 'code', 'escape'];
const FROM = Math.max(0, CHECKPOINTS.indexOf(CFG.from));
if (CHECKPOINTS.indexOf(CFG.from) < 0) { console.error(`[playtest] unknown --from '${CFG.from}' (${CHECKPOINTS.join('|')})`); process.exit(2); }

const log = (...a) => console.error('[playtest]', ...a);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const r2 = (n) => (typeof n === 'number' && isFinite(n) ? Math.round(n * 100) / 100 : n);

// ------------------------------------------------------------------------------------------------ stub detection
// Module files (ARCHITECTURE.md §1). A module still containing its "// STUB" header explains expected failures.
const MODULE_FILES = {
  render: ['src/render/Renderer.js'],
  architecture: ['src/world/Architecture.js', 'src/world/Lighting.js'],
  props: ['src/world/Props.js'],
  extras: ['src/world/ExtraProps.js'],
  player: ['src/player/Player.js', 'src/core/Input.js'],
  gameplay: ['src/game/Interaction.js', 'src/game/Inventory.js', 'src/game/Puzzles.js'],
  entity: ['src/entity/Gardienne.js'],
  audio: ['src/audio/Audio.js'],
  ui: ['src/ui/UI.js'],
};
function detectStubs() {
  const out = {};
  for (const [m, files] of Object.entries(MODULE_FILES)) {
    const stub = files.filter((f) => {
      try { return /^\s*\/\/\s*STUB\b/m.test(fs.readFileSync(path.join(ROOT, f), 'utf8').slice(0, 800)); } catch (_) { return true; }
    });
    out[m] = stub.length ? 'stub' : 'real';
  }
  return out;
}
const STUBS = detectStubs();

// ------------------------------------------------------------------------------------------------ report / checks
const report = {
  tool: 'tools/playtest.cjs',
  startedAt: new Date().toISOString(),
  config: { ...CFG },
  modules: STUBS,
  sessions: [],
  checks: [],
  summary: null,
};
let CUR = null; // current session
const ICON = { pass: 'PASS', fail: 'FAIL', warn: 'WARN', skip: 'SKIP', info: 'INFO' };
function check(id, status, msg, extra = {}) {
  const deps = extra.deps || [];
  const stubDeps = deps.filter((d) => STUBS[d] === 'stub');
  const c = { id, status, msg, scenario: CUR ? CUR.name : null, wallS: CUR ? r2((Date.now() - CUR.t0) / 1000) : null };
  if (extra.details !== undefined) c.details = extra.details;
  if (status === 'fail' && stubDeps.length) c.explainedByStubs = stubDeps;
  if (extra.forced) c.forced = true;
  report.checks.push(c);
  log(`${ICON[status] || status} ${id} — ${msg}${c.explainedByStubs ? `   [stub: ${stubDeps.join(', ')}]` : ''}`);
  return status === 'pass';
}

// ------------------------------------------------------------------------------------------------ static server
const MIME = {
  '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json',
  '.glb': 'model/gltf-binary', '.jpg': 'image/jpeg', '.png': 'image/png', '.webp': 'image/webp', '.css': 'text/css',
  '.mp3': 'audio/mpeg', '.ogg': 'audio/ogg', '.wav': 'audio/wav', '.svg': 'image/svg+xml',
};
const server = http.createServer((req, res) => {
  const u = decodeURIComponent(req.url.split('?')[0]);
  const f = path.join(ROOT, u === '/' ? 'index.html' : u);
  if (!f.startsWith(ROOT) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end('nf'); }
  res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
  fs.createReadStream(f).pipe(res);
});

// ================================================================================================ in-page harness
// Installed once per page after window.__game exists. Self-contained (serialized by Playwright).
async function QA_INSTALL(opts) {
  const g = window.__game;
  if (!g) return { ok: false, error: 'window.__game is missing (the page needs ?debug)' };
  if (window.__qa) return { ok: true, reinstalled: true };
  let THREE = null;
  try { THREE = await import('three'); } catch (_) { /* fallback below */ }
  const P = g.player;
  const V3 = (P && P.position && P.position.constructor) || (THREE && THREE.Vector3);
  const R2 = (n) => (typeof n === 'number' && isFinite(n) ? Math.round(n * 100) / 100 : n);
  const v3 = (v) => (v && typeof v.x === 'number' ? { x: R2(v.x), y: R2(v.y), z: R2(v.z) } : v);
  const ser = (p, d = 0) => {
    if (p == null) return p;
    if (typeof p === 'function') return '[fn]';
    if (typeof p !== 'object') return p;
    if (p.isVector3 || (typeof p.x === 'number' && typeof p.z === 'number' && Object.keys(p).length <= 3)) return v3(p);
    if (p.isObject3D) return `[Object3D ${p.name || p.type}]`;
    if (Array.isArray(p)) return d > 1 ? `[${p.length}]` : p.slice(0, 12).map((x) => ser(x, d + 1));
    if (d > 1) return '{…}';
    const o = {};
    for (const k of Object.keys(p).slice(0, 16)) if (k[0] !== '_') o[k] = ser(p[k], d + 1);
    return o;
  };
  const qa = {
    opts, three: !!THREE, frames: 0, events: [], stages: [], entity: [], warnings: [], summons: [],
    ui: { notes: [], keypads: [], caught: [], gameover: [], win: [] },
    texts: { objective: [], subtitle: [], alert: [], hidden: [] }, prompts: new Set(),
    steer: null, chosen: {}, targetObj: {}, swallowedUnlock: 0, autoResumed: 0, allowPause: false,
    noiseCount: 0, noiseMax: 0, noiseLog: [], caughtCount: 0, winCount: 0, cameraOverrideSeen: [],
    entTrack: { minY: Infinity, minDist: Infinity, states: [] }, clues: null,
  };
  window.__qa = qa;
  const now = () => ({ t: R2(g.time || 0), rt: R2(g.realTime || 0) });
  const push = (type, data) => {
    const rec = { type, ...now(), data };
    qa.events.push(rec);
    if (qa.events.length > 4000) qa.events.splice(0, 1000);
    try { if (window.__qaEmit) window.__qaEmit(JSON.stringify(rec)); } catch (_) { /* node side gone */ }
  };
  qa.push = push;

  // ---- 1. event bus tap (all events), pointer-lock swallow, pause watchdog
  const bus = g.events;
  const origEmit = bus.emit;
  bus.emit = function (name, payload) {
    if (name === 'noise') {
      qa.noiseCount++;
      const l = +(payload && payload.loudness) || 0;
      if (l > qa.noiseMax) qa.noiseMax = l;
      if (l >= 0.14) { qa.noiseLog.push({ l: R2(l), src: payload && payload.source, ...now() }); if (qa.noiseLog.length > 200) qa.noiseLog.shift(); }
      if (l >= 0.3) push('noise', { loudness: R2(l), source: payload && payload.source, position: v3(payload && payload.position) });
    } else if (name === 'input:pointerlock' && payload && payload.locked === false && qa.opts.swallowUnlock !== false) {
      qa.swallowedUnlock++;
      return undefined; // headless Chromium cannot hold pointer lock: do not let it pause the game
    } else if (name !== 'player:stamina') {
      push(name, ser(payload));
      if (name === 'entity:caught') qa.caughtCount++;
      if (name === 'game:win') qa.winCount++;
    }
    return origEmit.call(this, name, payload);
  };
  bus.on('game:state', (p) => {
    if (p && p.state === 'paused' && !qa.allowPause && qa.autoResumed < 40) {
      qa.autoResumed++;
      setTimeout(() => { if (g.state === 'paused' && !qa.allowPause) { try { g.resume(); } catch (_) { /* ignore */ } } }, 60);
    }
  });

  // ---- 2. UI wrappers (passthrough). Modal promises can be resolved by the harness only as a last resort.
  const ui = g.ui || {};
  const wrapModal = (name, list, hold, waitIfInstantNull = false) => {
    const orig = ui[name];
    if (typeof orig !== 'function') { qa.warnings.push(`ui.${name} is missing`); return; }
    ui[name] = function (arg) {
      const rec = { arg: ser(arg), ...now(), pending: true, how: null, result: undefined, origResolved: false };
      let ext;
      const extP = new Promise((r) => { ext = r; });
      Object.defineProperty(rec, '_resolve', {
        enumerable: false,
        value: (v, how) => { if (!rec.pending) return; rec.pending = false; rec.how = how; rec.result = ser(v); ext(v); },
      });
      list.push(rec);
      push('qa:ui', { fn: name, arg: rec.arg });
      let p;
      const t0 = performance.now();
      try { p = orig.apply(this, arguments); } catch (e) { rec.error = String(e && e.message || e); p = Promise.resolve(null); }
      Promise.resolve(p).then((v) => {
        rec.origResolved = true; rec.origValue = ser(v);
        // a keypad that answers null instantly is a stub UI: keep the promise open so the harness can inject the code
        if (waitIfInstantNull && v == null && performance.now() - t0 < 40) { rec.instantNull = true; return; }
        if (!hold) rec._resolve(v, 'ui');
      }, (e) => { rec.error = String(e && e.message || e); rec._resolve(null, 'error'); });
      return extP;
    };
  };
  wrapModal('showNote', qa.ui.notes, false);
  wrapModal('showKeypad', qa.ui.keypads, false, true);
  wrapModal('showCaught', qa.ui.caught, false);
  wrapModal('showGameOver', qa.ui.gameover, true); // held: Game reloads the page when it resolves
  wrapModal('showWin', qa.ui.win, true);           // held: Game reloads the page when it resolves
  const tap = (obj, name, fn) => {
    const o = obj && obj[name];
    if (typeof o !== 'function') return false;
    obj[name] = function (...a) { try { fn(...a); } catch (_) { /* ignore */ } return o.apply(this, a); };
    return true;
  };
  tap(ui, 'setObjective', (t) => { qa.texts.objective.push({ text: t, ...now() }); push('qa:objective', { text: t }); });
  tap(ui, 'subtitle', (t) => { qa.texts.subtitle.push({ text: t, ...now() }); if (qa.texts.subtitle.length > 120) qa.texts.subtitle.shift(); });
  tap(ui, 'alert', (t) => { qa.texts.alert.push({ text: t, ...now() }); push('qa:alert', { text: t }); });
  tap(ui, 'setClues', (c) => { qa.clues = ser(c); });
  tap(ui, 'setHidden', (h) => { qa.texts.hidden.push({ hidden: !!h, ...now() }); });
  tap(ui, 'setPrompt', (t) => { if (t && qa.prompts.size < 300) qa.prompts.add(String(t)); });
  if (g.entity) tap(g.entity, 'summon', (pos, o) => { qa.summons.push({ pos: v3(pos), reason: o && o.reason, ...now() }); push('qa:summon', { pos: v3(pos), opts: ser(o) }); });

  // ---- 3. steering: applied right before player.update (yaw toward a walk target, or yaw+pitch toward an aim point)
  const tmp = V3 ? new V3() : null;
  const setYaw = (y) => {
    P.yaw = y;
    for (const k of ['targetYaw', '_targetYaw', 'yawTarget', '_yawTarget']) if (typeof P[k] === 'number') P[k] = y;
  };
  const setPitch = (p) => {
    P.pitch = p;
    for (const k of ['targetPitch', '_targetPitch', 'pitchTarget', '_pitchTarget']) if (typeof P[k] === 'number') P[k] = p;
  };
  qa.setYaw = setYaw; qa.setPitch = setPitch;
  const eye = () => {
    if (P.eyePosition) { try { return P.eyePosition(tmp); } catch (_) { /* fall through */ } }
    return tmp.set(P.position.x, P.position.y + (P.eyeHeight || 1.62), P.position.z);
  };
  if (P && typeof P.update === 'function') {
    const origUpdate = P.update;
    P.update = function (dt) {
      const s = qa.steer;
      if (s) {
        if (s.mode === 'walk') {
          const dx = s.x - P.position.x, dz = s.z - P.position.z;
          if (dx * dx + dz * dz > 1e-6) setYaw(Math.atan2(-dx, -dz));
          setPitch(0);
        } else if (s.mode === 'aim') {
          const e = eye();
          const dx = s.x - e.x, dy = s.y - e.y, dz = s.z - e.z;
          setYaw(Math.atan2(-dx, -dz));
          setPitch(Math.atan2(dy, Math.hypot(dx, dz)));
        }
        qa.steerApplied = { yaw: P.yaw };
      }
      return origUpdate.call(this, dt);
    };
  } else qa.warnings.push('player.update missing: steering disabled');

  // ---- 4. per-frame tracking (stage, entity state, camera override, fps)
  let lastStage = g.puzzles && g.puzzles.stage;
  let lastEnt = g.entity && g.entity.state;
  qa.stages.push({ stage: lastStage, prev: null, ...now() });
  qa.entity.push({ state: lastEnt, prev: null, ...now(), pos: v3(g.entity && g.entity.position) });
  const tick = () => {
    qa.frames++;
    try {
      const st = g.puzzles && g.puzzles.stage;
      if (st !== lastStage) { qa.stages.push({ stage: st, prev: lastStage, ...now() }); push('qa:stage', { stage: st, prev: lastStage }); lastStage = st; }
      const E = g.entity;
      if (E) {
        if (E.state !== lastEnt) {
          const rec = { state: E.state, prev: lastEnt, ...now(), pos: v3(E.position), player: v3(P.position), hidden: !!P.hidden };
          qa.entity.push(rec); qa.entTrack.states.push(E.state); push('qa:entity', rec); lastEnt = E.state;
        }
        if (E.active && E.position) {
          if (E.position.y < qa.entTrack.minY) qa.entTrack.minY = E.position.y;
          const d = Math.hypot(E.position.x - P.position.x, E.position.z - P.position.z);
          if (d < qa.entTrack.minDist) qa.entTrack.minDist = d;
        }
      }
      if (P.cameraOverride && (!qa.cameraOverrideSeen.length || !qa.cameraOverrideSeen[qa.cameraOverrideSeen.length - 1].on)) qa.cameraOverrideSeen.push({ on: true, ent: E && E.state, ...now() });
      if (!P.cameraOverride && qa.cameraOverrideSeen.length && qa.cameraOverrideSeen[qa.cameraOverrideSeen.length - 1].on) qa.cameraOverrideSeen.push({ on: false, ...now() });
    } catch (_) { /* keep ticking */ }
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);

  // ---- 5. helpers called from node
  const exprCache = new Map();
  qa.check = (expr, arg) => {
    try {
      let f = exprCache.get(expr);
      if (!f) { f = new Function('g', 'qa', 'arg', `return (${expr});`); exprCache.set(expr, f); }
      return f(g, qa, arg) || false;
    } catch (_) { return false; }
  };
  qa.run = (expr, arg) => {
    try { const f = new Function('g', 'qa', 'arg', `return (${expr});`); const v = f(g, qa, arg); return { ok: true, v: ser(v) }; } catch (e) { return { ok: false, error: String(e && e.message || e) }; }
  };
  // resolves right after the next rendered frame (polling once per frame keeps a slow software-GL page responsive)
  qa.nextFrame = (ms = 3000) => new Promise((res) => {
    let done = false;
    const fin = () => { if (!done) { done = true; res(); } };
    requestAnimationFrame(() => setTimeout(fin, 0));
    setTimeout(fin, ms);
  });
  qa.frameSnap = async () => { await qa.nextFrame(); return qa.snap(); };
  qa.frameCheck = async (e, a) => {
    await qa.nextFrame();
    return { v: qa.check(e, a), rt: g.realTime, f: qa.frames, pc: qa.ui.caught.some((x) => x.pending) };
  };
  qa.snap = () => {
    const E = g.entity, c = g.interaction && g.interaction.current, fl = P.flashlight || {};
    return {
      t: R2(g.time), rt: R2(g.realTime), state: g.state, stage: g.puzzles && g.puzzles.stage, night: g.night,
      x: R2(P.position.x), y: R2(P.position.y), z: R2(P.position.z), yaw: R2(P.yaw), pitch: R2(P.pitch),
      hidden: !!P.hidden, enabled: P.enabled !== false, camOverride: !!P.cameraOverride,
      modal: !!(g.ui && g.ui.isModalOpen && g.ui.isModalOpen()), power: g.world && g.world.power,
      fl: { has: !!fl.has, on: !!fl.on, battery: R2(+fl.battery || 0) },
      ent: E ? { state: E.state, active: !!E.active, x: R2(E.position && E.position.x), y: R2(E.position && E.position.y), z: R2(E.position && E.position.z) } : null,
      current: c ? (c.id || '(no id)') : null, frames: qa.frames,
      pendingCaught: qa.ui.caught.some((r) => r.pending),
    };
  };
  qa.entries = () => {
    const E = g.interaction && g.interaction.entries;
    if (!E) return [];
    if (E instanceof Map) return [...E.values()];
    if (Array.isArray(E)) return E;
    if (typeof E === 'object') return Object.values(E);
    return [];
  };
  const promptOf = (e) => { try { return typeof e.prompt === 'function' ? e.prompt() : e.prompt; } catch (_) { return null; } };
  const holdOf = (e) => { try { return +(typeof e.hold === 'function' ? e.hold() : e.hold) || 0; } catch (_) { return 0; } };
  const enabledOf = (e) => { try { return typeof e.enabled === 'function' ? !!e.enabled() : e.enabled !== false; } catch (_) { return false; } };
  qa.entryList = () => qa.entries().map((e) => ({ id: e.id, prompt: promptOf(e), enabled: enabledOf(e), hold: holdOf(e), obj: e.object ? (e.object.name || e.object.type) : null }));
  qa.resolveTarget = (t) => {
    const w = g.world;
    if (!t || !w) return null;
    const i = t.indexOf(':');
    const kind = t.slice(0, i), id = t.slice(i + 1);
    if (kind === 'item') return (w.items && w.items[id]) || null;
    if (kind === 'handle') return (w.handles && w.handles[id] && w.handles[id].object) || null;
    if (kind === 'clue') return (w.clues && w.clues[id]) || null;
    if (kind === 'tv') return (w.tv && w.tv.object) || null;
    if (kind === 'hide') { const s = (w.hideSpots || []).find((h) => h.id === id); return (s && s.door && s.door.object) || null; }
    if (kind === 'name') return g.scene.getObjectByName(id) || null;
    return null;
  };
  const chainDepth = (a, b) => { let d = 0; for (let o = a; o; o = o.parent, d++) if (o === b) return d; return -1; }; // b ancestor of a?
  const wpos = (o) => { const v = new V3(); o.getWorldPosition(v); return v; };
  qa.findEntry = (spec) => {
    const list = qa.entries();
    const targets = (spec.targets || []).map((t) => ({ t, o: qa.resolveTarget(t) })).filter((x) => x.o);
    const idRx = spec.ids ? new RegExp(spec.ids, 'i') : null;
    const prRx = spec.prompt ? new RegExp(spec.prompt, 'i') : null;
    const scored = [];
    for (const e of list) {
      let s = 0; const why = [];
      let related = false;
      for (let ti = 0; ti < targets.length && e.object; ti++) {
        const { t, o } = targets[ti];
        const pen = ti * 8; // earlier targets are preferred
        if (e.object === o) { s += 100 - pen; why.push(`object=${t}`); related = true; break; }
        const down = chainDepth(e.object, o); // entry object inside target
        if (down > 0) { s += 80 - down - pen; why.push(`object inside ${t}`); related = true; break; }
        const up = chainDepth(o, e.object); // entry object is an ancestor of target
        if (up > 0 && up <= 4 && e.object !== g.scene) { s += 60 - up * 5 - pen; why.push(`object ancestor of ${t}`); related = true; break; }
      }
      if (!related && e.object) { // no scene-graph relation: a co-located object is a weak hint
        for (const { t, o } of targets) {
          try { if (wpos(e.object).distanceTo(wpos(o)) < 0.25) { s += 15; why.push(`near ${t}`); break; } } catch (_) { /* ignore */ }
        }
      }
      if (idRx && e.id && idRx.test(String(e.id))) { s += 30; why.push('id'); }
      const pr = promptOf(e);
      if (prRx && pr && prRx.test(String(pr))) { s += 10; why.push('prompt'); }
      if (s > 0) scored.push({ e, s, why });
    }
    scored.sort((a, b) => (b.s - a.s) || (enabledOf(b.e) - enabledOf(a.e)));
    const best = scored[0];
    // ambiguous id/prompt-only matches (no object relation) are rejected when a target object exists
    const ok = best && (best.s >= 40 || !targets.length);
    if (ok) { qa.chosen[spec.key] = best.e; qa.targetObj[spec.key] = (targets[0] && targets[0].o) || best.e.object; }
    return {
      count: list.length, targetsFound: targets.map((x) => x.t),
      entry: ok ? { id: best.e.id, prompt: promptOf(best.e), enabled: enabledOf(best.e), hold: holdOf(best.e), score: best.s, why: best.why.join(',') } : null,
      top: scored.slice(0, 3).map((x) => ({ id: x.e.id, prompt: promptOf(x.e), score: x.s, why: x.why.join(',') })),
    };
  };
  qa.entryState = (key) => { const e = qa.chosen[key]; return e ? { enabled: enabledOf(e), prompt: promptOf(e), hold: holdOf(e) } : null; };
  qa.isCurrent = (key) => {
    const e = qa.chosen[key], c = g.interaction && g.interaction.current;
    return !!(e && c && (c === e || (c.id && c.id === e.id)));
  };
  qa.callInteract = (key) => {
    const e = qa.chosen[key];
    const I = g.interaction;
    if (e && I && typeof I.activate === 'function' && e.id) {
      try { const r = I.activate(e.id, { force: true }); if (r && r.catch) r.catch((err) => console.error('[qa] activate rejected', err)); return { ok: true, via: 'interaction.activate' }; } catch (err) { /* fall back to onInteract */ }
    }
    if (!e || typeof e.onInteract !== 'function') return { ok: false, error: 'no onInteract' };
    try { const r = e.onInteract(); if (r && r.catch) r.catch((err) => console.error('[qa] onInteract rejected', err)); return { ok: true }; } catch (err) { return { ok: false, error: String(err && err.message || err) }; }
  };
  qa.bbox = (obj) => {
    obj.updateWorldMatrix(true, true);
    if (THREE) {
      const b = new THREE.Box3().setFromObject(obj);
      if (!b.isEmpty()) return { min: b.min.clone(), max: b.max.clone(), c: b.getCenter(new THREE.Vector3()) };
    }
    const p = wpos(obj);
    return { min: p.clone(), max: p.clone(), c: p };
  };
  qa.isFree = (x, z, y) => {
    const r = (P.radius || 0.25) + 0.02;
    for (const c of (g.world.colliders || [])) {
      if (!c.enabled || c.maxY <= y + 0.3 || c.minY >= y + 1.7) continue;
      const cx = Math.max(c.minX, Math.min(x, c.maxX)), cz = Math.max(c.minZ, Math.min(z, c.maxZ));
      if ((x - cx) * (x - cx) + (z - cz) * (z - cz) < r * r) return false;
    }
    return true;
  };
  qa.findFree = (x, z, aim, maxReach = 1.7) => {
    const y0 = g.world.groundHeightAt(x, z);
    const cands = [[x, z]];
    for (const rad of [0.12, 0.25, 0.4, 0.55, 0.7]) for (let i = 0; i < 12; i++) { const a = (i / 12) * Math.PI * 2; cands.push([x + Math.cos(a) * rad, z + Math.sin(a) * rad]); }
    for (const [cx, cz] of cands) {
      const y = g.world.groundHeightAt(cx, cz);
      if (Math.abs(y - y0) > 0.05 || !qa.isFree(cx, cz, y)) continue;
      if (aim && Math.hypot(aim.x - cx, aim.z - cz) > maxReach) continue;
      return { x: cx, y, z: cz, moved: Math.hypot(cx - x, cz - z), blocked: false };
    }
    return { x, y: y0, z, moved: 0, blocked: true };
  };
  qa.prepare = (key, sx, sz, attempt) => {
    const e = qa.chosen[key];
    const obj = qa.targetObj[key] || (e && e.object);
    if (!obj) return { ok: false, error: 'no target object' };
    const bb = qa.bbox(obj);
    const st = qa.findFree(sx, sz, bb.c);
    const yaw0 = Math.atan2(-(bb.c.x - st.x), -(bb.c.z - st.z));
    if (typeof P.teleport === 'function') P.teleport(st.x, st.y, st.z, yaw0, 0);
    else { P.position.set(st.x, st.y, st.z); setYaw(yaw0); }
    const ey = st.y + (P.eyeHeight || 1.62);
    const near = { x: Math.max(bb.min.x, Math.min(st.x, bb.max.x)), y: Math.max(bb.min.y, Math.min(ey, bb.max.y)), z: Math.max(bb.min.z, Math.min(st.z, bb.max.z)) };
    const pts = [
      bb.c,
      { x: bb.c.x, y: bb.min.y + (bb.max.y - bb.min.y) * 0.8, z: bb.c.z },
      { x: near.x * 0.6 + bb.c.x * 0.4, y: near.y * 0.6 + bb.c.y * 0.4, z: near.z * 0.6 + bb.c.z * 0.4 },
      wpos(obj),
      { x: bb.c.x, y: bb.min.y + (bb.max.y - bb.min.y) * 0.3, z: bb.c.z },
    ];
    const ap = pts[attempt % pts.length];
    qa.steer = { mode: 'aim', x: ap.x, y: ap.y, z: ap.z };
    const dist = Math.hypot(ap.x - st.x, ap.y - ey, ap.z - st.z);
    return { ok: true, stand: { x: R2(st.x), y: R2(st.y), z: R2(st.z), moved: R2(st.moved), blocked: st.blocked }, aim: v3(ap), dist: R2(dist), bbMin: v3(bb.min), bbMax: v3(bb.max) };
  };
  qa.aimPoint = (x, y, z) => { qa.steer = { mode: 'aim', x, y, z }; return true; };
  qa.setWalk = (x, z) => { qa.steer = { mode: 'walk', x, z }; return true; };
  qa.clearSteer = () => { qa.steer = null; return true; };
  qa.teleport = (x, z, yaw = null) => {
    const y = g.world.groundHeightAt(x, z, P.position.y);
    if (typeof P.teleport === 'function') P.teleport(x, y, z, yaw == null ? P.yaw : yaw, 0); else P.position.set(x, y, z);
    return { x: R2(x), y: R2(y), z: R2(z) };
  };
  qa.navNodes = () => {
    const out = {};
    const nodes = g.world && g.world.nav && g.world.nav.nodes;
    if (nodes) for (const [id, n] of Object.entries(nodes)) out[id] = { x: n.pos.x, y: n.pos.y, z: n.pos.z };
    return out;
  };
  qa.blockers = (tx, tz) => {
    const p = P.position, y = p.y, r = (P.radius || 0.25) + 0.12;
    const dx = tx - p.x, dz = tz - p.z, L = Math.hypot(dx, dz) || 1;
    const probes = [[p.x, p.z], [p.x + (dx / L) * 0.3, p.z + (dz / L) * 0.3]];
    const out = [];
    for (const c of (g.world.colliders || [])) {
      if (!c.enabled || c.maxY <= y + 0.3 || c.minY >= y + 1.7) continue;
      for (const [px, pz] of probes) {
        const cx = Math.max(c.minX, Math.min(px, c.maxX)), cz = Math.max(c.minZ, Math.min(pz, c.maxZ));
        if ((px - cx) ** 2 + (pz - cz) ** 2 < r * r) { out.push({ tag: c.tag, box: [c.minX, c.minY, c.minZ, c.maxX, c.maxY, c.maxZ].map(R2) }); break; }
      }
    }
    let seg = null;
    try { seg = g.world.segmentBlocked(p.x, p.z, tx, tz, P.radius || 0.25, y + 0.3, y + 1.7); } catch (_) { /* ignore */ }
    return { pos: v3(p), toward: { x: R2(tx), z: R2(tz) }, colliders: out.slice(0, 6), segmentBlocked: seg };
  };
  qa.placeInFront = (dist, attempt) => {
    const E = g.entity, ep = E.position;
    const ry = (E.root && E.root.rotation && E.root.rotation.y) || 0;
    const base = ry + (attempt || 0) * (Math.PI / 2);
    for (const da of [0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, Math.PI]) {
      for (const d of [dist, dist + 0.5, dist - 0.4]) {
        const a = base + da;
        const x = ep.x + Math.sin(a) * d, z = ep.z + Math.cos(a) * d;
        const y = g.world.groundHeightAt(x, z);
        if (Math.abs(y - ep.y) > 0.3 || !qa.isFree(x, z, y)) continue;
        const from = new V3(x, y + 1.62, z), to = new V3(ep.x, ep.y + 1.6, ep.z);
        let blocked = false;
        try { blocked = g.world.lineBlocked(from, to); } catch (_) { /* ignore */ }
        if (blocked) continue;
        const yaw = Math.atan2(-(ep.x - x), -(ep.z - z));
        qa.steer = null;
        if (typeof P.teleport === 'function') P.teleport(x, y, z, yaw, -0.05); else { P.position.set(x, y, z); setYaw(yaw); }
        return { ok: true, x: R2(x), z: R2(z), d: R2(d), entity: v3(ep) };
      }
    }
    return { ok: false, entity: v3(ep) };
  };
  qa.modalCount = (kind) => qa.ui[kind].length;
  qa.modalLast = (kind) => { const l = qa.ui[kind]; const r = l[l.length - 1]; return r ? { n: l.length, pending: r.pending, how: r.how, origResolved: r.origResolved, arg: r.arg, error: r.error } : { n: 0 }; };
  qa.resolveModal = (kind, value, how) => { const l = qa.ui[kind]; const r = [...l].reverse().find((x) => x.pending); if (!r) return false; r._resolve(value, how || 'qa'); return true; };
  qa.findButton = (re) => {
    const rx = new RegExp(re, 'i');
    let best = null;
    for (const el of document.querySelectorAll('button, [role="button"], a, [data-action]')) {
      const txt = [el.textContent, el.getAttribute('aria-label'), el.getAttribute('title')].filter(Boolean).join(' ').replace(/\s+/g, ' ').trim();
      if (!rx.test(txt)) continue;
      const r = el.getBoundingClientRect();
      if (r.width < 2 || r.height < 2) continue;
      const cs = getComputedStyle(el);
      if (cs.visibility === 'hidden' || cs.display === 'none') continue;
      const cx = r.left + r.width / 2, cy = r.top + r.height / 2;
      const top = document.elementFromPoint(cx, cy);
      const hit = !!(top && (top === el || el.contains(top)));
      if (!best || (hit && !best.hit)) best = { x: cx, y: cy, text: txt.slice(0, 40), hit };
    }
    return best;
  };
  qa.findTouchButton = () => {
    const root = document.getElementById('touch') || document.body;
    const passes = [/interact|interagir|✋/i, /utiliser|action|hand|\bmain\b|\buse\b/i];
    for (const rx of passes) {
      for (const el of root.querySelectorAll('*')) {
        const cls = typeof el.className === 'string' ? el.className : '';
        const s = [el.getAttribute('aria-label'), el.getAttribute('title'), el.dataset && el.dataset.action, el.id, cls, el.children.length === 0 ? el.textContent : ''].filter(Boolean).join(' ');
        if (!rx.test(s)) continue;
        const r = el.getBoundingClientRect();
        if (r.width < 20 || r.height < 20) continue;
        return { x: r.left + r.width / 2, y: r.top + r.height / 2, label: s.slice(0, 50) };
      }
    }
    return null;
  };
  qa.resetEntTrack = () => { qa.entTrack = { minY: Infinity, minDist: Infinity, states: [] }; return true; };
  qa.sceneStats = () => {
    let meshes = 0, tris = 0, lights = 0, shadowLights = 0;
    g.scene.traverse((o) => {
      if (o.isMesh && o.visible) {
        meshes++;
        const geo = o.geometry;
        if (geo) tris += (geo.index ? geo.index.count : (geo.attributes.position ? geo.attributes.position.count : 0)) / 3;
      }
      if (o.isLight) { lights++; if (o.castShadow) shadowLights++; }
    });
    const info = g.renderer && g.renderer.webgl && g.renderer.webgl.info;
    return {
      meshes, triangles: Math.round(tris), lights, shadowLights,
      lastPass: info ? { calls: info.render.calls, triangles: info.render.triangles } : null,
      memory: info ? { geometries: info.memory.geometries, textures: info.memory.textures } : null,
      programs: info && info.programs ? info.programs.length : null,
      quality: g.renderer && g.renderer.quality, preset: g.renderer && ser(g.renderer.preset),
    };
  };
  qa.export = () => ({
    stages: qa.stages, entity: qa.entity, summons: qa.summons, warnings: qa.warnings, three: qa.three,
    texts: { objective: qa.texts.objective, alert: qa.texts.alert, subtitle: qa.texts.subtitle.slice(-40), hidden: qa.texts.hidden.slice(-20) },
    prompts: [...qa.prompts], clues: qa.clues, entries: qa.entryList().slice(0, 120),
    ui: Object.fromEntries(Object.entries(qa.ui).map(([k, l]) => [k, l.map((r) => ({ ...r }))])),
    swallowedPointerUnlock: qa.swallowedUnlock, autoResumed: qa.autoResumed,
    noise: { count: qa.noiseCount, max: R2(qa.noiseMax), loud: qa.noiseLog.slice(-60) },
    caughtCount: qa.caughtCount, winCount: qa.winCount, cameraOverride: qa.cameraOverrideSeen.slice(-20),
  });
  return { ok: true, three: !!THREE, entries: qa.entries().length };
}

// ================================================================================================ node-side helpers
let browser = null;
const call = (S, fn, ...args) => S.page.evaluate(([f, a]) => {
  const qa = window.__qa;
  if (!qa) throw new Error('QA harness missing (page reloaded?)');
  return qa[f](...a);
}, [fn, args]);
const snap = (S) => call(S, 'snap');
const frameSnap = (S) => call(S, 'frameSnap');
const run = (S, expr, arg) => call(S, 'run', expr, arg);

// Timeouts are in GAME seconds (game.realTime: dt is clamped to 0.05 s per frame, so on a slow software-GL machine
// game time runs much slower than wall time). The only wall-clock guard is a stall detector: no new frame for
// STALL_MS means the page is frozen.
const STALL_MS = 60000 * CFG.tscale;
function stalled(S, frames) {
  const g = S.stall || (S.stall = { f: -1, t: Date.now() });
  if (frames !== g.f) { g.f = frames; g.t = Date.now(); return false; }
  if (Date.now() - g.t > STALL_MS) { log(`page stalled: no frame rendered for ${STALL_MS / 1000} s`); S.stalls = (S.stalls || 0) + 1; g.t = Date.now(); return true; }
  return false;
}
async function waitFor(S, expr, arg, { game = 3, pump = true } = {}) {
  const t0 = (await snap(S)).rt;
  for (;;) {
    const r = await call(S, 'frameCheck', expr, arg);
    if (r.v) return r.v;
    if (pump && r.pc && !S.handlingCaught) await handleCaughtScreen(S);
    if (r.rt - t0 > game * CFG.tscale || stalled(S, r.f)) return null;
    await sleep(30);
  }
}
async function gameWait(S, sec) {
  const t0 = (await snap(S)).rt;
  for (;;) {
    const s = await frameSnap(S);
    if (s.pendingCaught && !S.handlingCaught) await handleCaughtScreen(S);
    if (s.rt - t0 >= sec || stalled(S, s.frames)) return;
    await sleep(30);
  }
}
async function waitFrames(S, n) {
  const f0 = (await snap(S)).frames;
  for (;;) { const f = (await frameSnap(S)).frames; if (f >= f0 + n || stalled(S, f)) return; }
}
async function touch(S, type, pts) {
  if (!S.cdp) S.cdp = await S.ctx.newCDPSession(S.page);
  await S.cdp.send('Input.dispatchTouchEvent', { type, touchPoints: pts.map((p) => ({ x: p.x, y: p.y, id: p.id || 1, radiusX: 6, radiusY: 6, force: 1 })) });
}
async function tapAt(S, x, y) {
  if (CFG.mobile) await S.page.touchscreen.tap(x, y);
  else await S.page.mouse.click(x, y);
}
async function shot(S, name) {
  if (!CFG.shots) return;
  try {
    fs.mkdirSync(CFG.shots, { recursive: true });
    S.shotN = (S.shotN || 0) + 1;
    const f = path.join(CFG.shots, `${S.name}-${String(S.shotN).padStart(2, '0')}-${name.replace(/[^\w.-]+/g, '_')}.png`);
    await S.page.screenshot({ path: f, timeout: 120000 });
    (S.shotFiles = S.shotFiles || []).push(f);
  } catch (e) { log('screenshot failed', e.message); }
}

async function startMove(S) {
  if (CFG.mobile && !S.noJoystick) {
    const vp = S.page.viewportSize();
    const sx = Math.round(vp.width * 0.2), sy = Math.round(vp.height * 0.68);
    await touch(S, 'touchStart', [{ x: sx, y: sy, id: 11 }]);
    for (let k = 1; k <= 5; k++) { await touch(S, 'touchMove', [{ x: sx, y: sy - 12 * k, id: 11 }]); await sleep(20); }
    S.moving = 'touch';
    return;
  }
  await S.page.keyboard.down('KeyW');
  S.moving = 'key';
}
async function stopMove(S) {
  if (S.moving === 'touch') await touch(S, 'touchEnd', []);
  else if (S.moving === 'key') await S.page.keyboard.up('KeyW');
  S.moving = null;
}

async function pressInteract(S, holdSec = 0) {
  if (CFG.mobile && !S.noTouchInteract) {
    const b = await call(S, 'findTouchButton');
    if (b) {
      await touch(S, 'touchStart', [{ x: b.x, y: b.y, id: 21 }]);
      await waitFrames(S, 3);
      if (holdSec > 0) await gameWait(S, holdSec + 0.4);
      await touch(S, 'touchEnd', []);
      return 'touch';
    }
    S.noTouchInteract = true;
    check('mobile.touch.interactButton', 'fail', 'no interact (✋) button found in #touch while playing; falling back to the E key', { deps: ['player'] });
  }
  await S.page.keyboard.down('KeyE');
  await waitFrames(S, 3);
  if (holdSec > 0) await gameWait(S, holdSec + 0.4);
  await S.page.keyboard.up('KeyE');
  return 'key';
}

// Close a modal through its real buttons (click/tap), else resolve its promise from the wrapper.
async function closeModal(S, kind, buttonRx) {
  for (let attempt = 0; attempt < 3; attempt++) {
    const last = await call(S, 'modalLast', kind);
    if (!last.pending) return last.how || 'ui';
    const b = await call(S, 'findButton', buttonRx);
    if (b) await tapAt(S, b.x, b.y);
    else if (attempt === 1) await S.page.keyboard.press('Enter');
    await gameWait(S, 0.35);
  }
  const last = await call(S, 'modalLast', kind);
  if (!last.pending) return last.how || 'ui';
  await call(S, 'resolveModal', kind, null, 'forced');
  return 'forced';
}
const NOTE_CLOSE_RX = 'fermer|continuer|^\\s*ok\\s*$|close|retour|ranger|reposer|terminer|j\'ai compris|×|✕|✖';

async function handleCaughtScreen(S) {
  if (S.handlingCaught) return null;
  S.handlingCaught = true;
  try {
    await sleep(400);
    await shot(S, 'caught-screen');
    const how = await closeModal(S, 'caught', 'continuer|continue|réessayer|recommencer|nuit suivante');
    S.caughtScreens = (S.caughtScreens || 0) + 1;
    if (how === 'forced') check(`caught.screen.${S.caughtScreens}.continue`, 'fail', 'caught screen has no clickable "Continuer" button (promise resolved by the harness)', { deps: ['ui'] });
    else check(`caught.screen.${S.caughtScreens}.continue`, 'pass', `caught screen closed (${how})`, { deps: ['ui'] });
    return how;
  } finally { S.handlingCaught = false; }
}

async function ensurePlaying(S) {
  for (let i = 0; i < 20; i++) {
    const s = await snap(S);
    if (s.pendingCaught) { await handleCaughtScreen(S); continue; }
    if (s.state === 'playing' && !s.modal) {
      await waitFor(S, '!g.interaction || !g.interaction.busy', null, { game: 6, pump: false });
      return true;
    }
    if (s.state === 'paused') await S.page.evaluate(() => window.__game.resume());
    if (s.modal) {
      for (const kind of ['notes', 'keypads']) if ((await call(S, 'modalLast', kind)).pending) await closeModal(S, kind, kind === 'notes' ? NOTE_CLOSE_RX : 'annuler|fermer');
    }
    await gameWait(S, 0.25);
  }
  const s = await snap(S);
  return s.state === 'playing' && !s.modal;
}

// ------------------------------------------------------------------------------------------------ interaction driver
// Interactable targets: world object (documented ids), id regex, prompt regex, stand point [x, z] near it.
const T = {
  note1:      { targets: ['item:note1'], ids: 'note.?1|coffee|table.?basse', prompt: 'lire|note|papier|mot', stand: [0.05, 1.5] },
  drawerTop:  { targets: ['handle:dresser.drawerTop'], ids: 'drawer.?top|tiroir.?haut', prompt: 'tiroir', stand: [-0.55, -1.45] },
  flashlight: { targets: ['item:flashlight'], ids: 'flashlight|lampe|torch', prompt: 'lampe', stand: [-0.55, -1.35] },
  boxDoor:    { targets: ['handle:powerBox.door'], ids: 'powerbox.?door|panel|panneau', prompt: 'panneau|ouvrir', stand: [2.6, -3.6] },
  lever:      { targets: ['handle:powerBox.lever'], ids: 'lever|breaker|disjonct|levier', prompt: 'courant|levier|disjoncteur|rétablir|abaisser|lever', stand: [2.6, -3.6] },
  closet:     { targets: ['handle:door.closet', 'hide:closet'], ids: 'hide|cacher', prompt: 'cacher', stand: [-2.05, -2.05] },
  closetExit: { targets: ['handle:door.closet', 'hide:closet'], ids: 'exit|sortir', prompt: 'sortir', stand: [-2.05, -2.05] },
  boxNote:    { targets: ['handle:lockedBox.lid', 'name:lockedBox'], ids: '^lockedBox$|box.?note|coffret', prompt: 'examiner|coffret|lire', stand: [2.35, 0.15] },
  duck:       { targets: ['clue:duck'], ids: 'duck|canard', prompt: 'canard|dessous', stand: [-1.35, 0.3] },
  horse:      { targets: ['clue:horse'], ids: 'horse|cheval', prompt: 'cheval|dessous', stand: [2.15, -1.75] },
  clock:      { targets: ['clue:clock'], ids: 'clock|horloge|grandfather', prompt: 'horloge', stand: [2.6, -1.75] },
  tv:         { targets: ['tv:', 'clue:tv'], ids: '(^|\\W)tv|tele|télé|television', prompt: 'télé|allumer|éteindre', stand: [-0.55, -1.45] },
  note2:      { targets: ['item:note2'], ids: 'note.?2|drawing|dessin', prompt: 'dessin|lire|regarder', stand: [-1.4, 0.3] },
  endDrawer:  { targets: ['handle:endTable.drawer'], ids: 'endtable|end.?table|nightstand|chevet', prompt: 'tiroir', stand: [-1.5, 1.55] },
  battery1:   { targets: ['item:battery1'], ids: 'battery.?1', prompt: 'pile', stand: [-1.5, 1.55] },
  cabDrawer:  { targets: ['handle:alcoveCabinet.drawer_01'], ids: 'drawer_01', prompt: 'tiroir', stand: [1.15, -3.25] },
  battery2:   { targets: ['item:battery2'], ids: 'battery.?2', prompt: 'pile', stand: [1.15, -3.25] },
  cabDoor:    { targets: ['handle:alcoveCabinet.door_01'], ids: 'door_01', prompt: 'ouvrir|porte|armoire', stand: [1.15, -3.25] },
  note3:      { targets: ['item:note3'], ids: 'note.?3|newspaper|journal|coupure', prompt: 'journal|lire|article', stand: [1.15, -3.25] },
  lock:       { targets: ['handle:lockedBox.lock', 'handle:lockedBox.lid', 'name:lockedBox'], ids: 'lock$|cadenas|padlock|keypad|code', prompt: 'code|cadenas', stand: [2.35, 0.15] },
  key:        { targets: ['item:key'], ids: '(^|\\W)key|clé|cle', prompt: 'clé', stand: [2.35, 0.15] },
  door:       { targets: ['handle:door.upstairs'], ids: 'door.?upstairs|upstairs|porte.?haut', prompt: 'porte|déverrouiller|verrouill|ouvrir', stand: [-3.0, -2.3] },
};
const GAMEPLAY_DEPS = ['gameplay', 'props', 'player'];

// Find the entry, aim at it, press interact (or call onInteract), handle the modal, check the expectation.
async function doInteract(S, key, o = {}) {
  const spec = T[key];
  const id = `interact.${o.label || key}`;
  const deps = o.deps || GAMEPLAY_DEPS;
  const res = { key, how: null, ok: false };
  await ensurePlaying(S);
  const found = await call(S, 'findEntry', { key, ...spec });
  if (!found.entry) {
    const why = found.count === 0
      ? 'game.interaction has 0 entries (Interaction/Puzzles registers nothing — stub?)'
      : `${found.count} entries, none matches ${spec.targets.join(' / ')}${found.targetsFound.length ? '' : ' (target object missing in world)'}`;
    check(id, 'fail', `no interaction entry: ${why}`, { deps, details: { top: found.top } });
    if (o.fallback) {
      const r = await run(S, o.fallback);
      S.forcedActions.push({ key, fallback: o.fallback, ok: r.ok, error: r.error });
      log(`   fallback (direct API) for ${key}: ${r.ok ? 'done' : r.error}`);
      await gameWait(S, o.fallbackWait || 0.8);
    }
    res.how = 'missing';
    return res;
  }
  if (!found.entry.enabled && !o.allowDisabled) check(`${id}.enabled`, 'warn', `entry '${found.entry.id}' is disabled right now (prompt: ${JSON.stringify(found.entry.prompt)})`, { deps });
  const before = o.modal ? await call(S, 'modalCount', o.modal) : 0;
  // aim
  let aimed = false, prep = null;
  for (let a = 0; a < 5 && !aimed; a++) {
    prep = await call(S, 'prepare', key, spec.stand[0], spec.stand[1], a);
    if (!prep.ok) break;
    aimed = !!(await waitFor(S, 'qa.isCurrent(arg)', key, { game: 0.5 }));
  }
  const hold = o.hold != null ? o.hold : (found.entry.hold || 0);
  if (aimed) {
    await shot(S, `${o.label || key}-aim`);
    res.how = await pressInteract(S, hold);
  } else {
    const cur = (await snap(S)).current;
    check(`${id}.aim`, 'warn', `camera aim did not select '${found.entry.id}' (interaction.current = ${JSON.stringify(cur)}, stand ${JSON.stringify(prep && prep.stand)}, dist ${prep && prep.dist}); calling onInteract() directly`, { deps: ['gameplay', 'props'] });
    const r = await call(S, 'callInteract', key);
    if (!r.ok) check(`${id}.onInteract`, 'fail', `onInteract() failed: ${r.error}`, { deps });
    res.how = 'direct';
  }
  await call(S, 'clearSteer');
  // modal
  if (o.modal) {
    const opened = await waitFor(S, `qa.ui.${o.modal}.length > arg`, before, { game: 2.5 });
    if (!opened) {
      check(`${id}.modal`, 'fail', `interacting did not open ui.${o.modal === 'notes' ? 'showNote' : 'showKeypad'}()`, { deps: ['gameplay', 'ui'] });
    } else if (o.modal === 'notes') {
      await gameWait(S, 0.5);
      await shot(S, `${o.label || key}-note`);
      const how = await closeModal(S, 'notes', NOTE_CLOSE_RX);
      const closed = await waitFor(S, '!g.ui.isModalOpen()', null, { game: 1.5 });
      const last = await call(S, 'modalLast', 'notes');
      if (how === 'forced') check(`${id}.modal`, 'fail', `note opened (${JSON.stringify(last.arg && last.arg.title)}) but could not be closed with its UI buttons; resolved by the harness${closed ? '' : ' and ui.isModalOpen() stays true'}`, { deps: ['ui'] });
      else check(`${id}.modal`, closed ? 'pass' : 'fail', `note ${JSON.stringify(last.arg && last.arg.title)} shown and closed (${how})${closed ? '' : ' but ui.isModalOpen() stays true'}`, { deps: ['ui'] });
    }
  }
  // expectation
  if (o.expect) {
    const ok = await waitFor(S, o.expect, o.expectArg, { game: (o.within || 3) + hold });
    if (ok) check(id, res.how === 'direct' ? 'warn' : 'pass', `${o.what || key} ✓ (${res.how}${res.how === 'direct' ? ': aim failed' : ''})`, { deps });
    else {
      check(id, 'fail', `${o.what || key}: expectation not met within ${(o.within || 3) + hold}s game time — ${o.expect}`, { deps });
      if (o.fallback) {
        const r = await run(S, o.fallback);
        S.forcedActions.push({ key, fallback: o.fallback, ok: r.ok, error: r.error });
        await gameWait(S, o.fallbackWait || 0.8);
      }
    }
    res.ok = !!ok;
  } else res.ok = true;
  if (o.shotAfter !== false) await shot(S, `${o.label || key}-after`);
  return res;
}

async function reachStage(S, stage, within, why) {
  const ok = await waitFor(S, 'g.puzzles && g.puzzles.stage === arg', stage, { game: within });
  if (ok) { check(`story.stage.${stage}`, 'pass', `stage '${stage}' reached ${why}`, { deps: ['gameplay'] }); return true; }
  const cur = (await snap(S)).stage;
  check(`story.stage.${stage}`, 'fail', `stage '${stage}' not reached ${why} within ${within}s game time (stage is '${cur}')`, { deps: ['gameplay'] });
  if (CFG.force) {
    await S.page.evaluate((st) => { try { window.__game.puzzles.debugGoto && window.__game.puzzles.debugGoto(st); } catch (e) { console.warn('[qa] debugGoto failed', String(e)); } }, stage);
    const ok2 = await waitFor(S, 'g.puzzles && g.puzzles.stage === arg', stage, { game: 1.5 });
    S.forced.push({ stage, worked: !!ok2 });
    log(`   forced puzzles.debugGoto('${stage}') -> ${ok2 ? 'ok' : `no effect (stage '${(await snap(S)).stage}')`}`);
  }
  return false;
}

// ------------------------------------------------------------------------------------------------ session
async function openSession(name, { entity = false } = {}) {
  const stageParam = name === 'story' && FROM > 0 ? `stage=${CHECKPOINT_STAGE[FROM]}` : null;
  const params = ['debug', CFG.menu ? null : 'autostart', `quality=${CFG.quality}`, entity ? null : 'noentity', stageParam, CFG.query || null].filter(Boolean).join('&');
  const ctx = CFG.mobile
    ? await browser.newContext({ ...devices['Pixel 7'], viewport: { width: 915, height: 412 }, screen: { width: 915, height: 412 }, deviceScaleFactor: Number(opt('dpr', 1)) || 1, isMobile: true, hasTouch: true })
    : await browser.newContext({ viewport: { width: CFG.size[0], height: CFG.size[1] } });
  const page = await ctx.newPage();
  const S = {
    name, ctx, page, entity, t0: Date.now(), events: [], fps: [], forced: [], forcedActions: [],
    errors: { page: [], console: [], warnings: [], requests: [], benignRequests: 0 }, loaded: false, reloaded: false,
  };
  CUR = S;
  const addMsg = (list, text) => {
    const t = String(text).slice(0, 400);
    const e = list.find((x) => x.text === t);
    if (e) e.count++; else if (list.length < 60) list.push({ text: t, count: 1 });
  };
  page.on('console', (m) => {
    const ty = m.type();
    if (ty === 'error') addMsg(S.errors.console, m.text());
    else if (ty === 'warning') addMsg(S.errors.warnings, m.text());
    if (CFG.verbose) log(`[page ${ty}]`, m.text().slice(0, 300));
  });
  page.on('pageerror', (e) => { addMsg(S.errors.page, `${e.message} | ${(e.stack || '').split('\n').slice(1, 4).join(' | ')}`); log('[pageerror]', e.message); });
  page.on('requestfailed', async (r) => {
    const u = r.url();
    if (u.includes('fonts.g')) return;
    const err = (r.failure() && r.failure().errorText) || '';
    let resp = null;
    try { resp = await r.response(); } catch (_) { /* none */ }
    if (/ERR_ABORTED/.test(err) && resp && resp.ok()) { S.errors.benignRequests++; return; } // body fully received, reader closed
    addMsg(S.errors.requests, `${err} ${u.replace(/^https?:\/\/127\.0\.0\.1:\d+/, '')}`);
  });
  page.on('response', (r) => { if (r.status() >= 400 && !r.url().includes('fonts.g')) addMsg(S.errors.requests, `HTTP ${r.status()} ${r.url().replace(/^https?:\/\/127\.0\.0\.1:\d+/, '')}`); });
  page.on('dialog', (d) => d.dismiss().catch(() => {}));
  page.on('framenavigated', (f) => { if (f === page.mainFrame() && S.loaded) { S.reloaded = true; log('page navigated/reloaded unexpectedly'); } });
  await page.exposeFunction('__qaEmit', (s) => { try { S.events.push(JSON.parse(s)); if (S.events.length > 6000) S.events.splice(0, 2000); } catch (_) { /* ignore */ } });
  await page.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ status: 200, contentType: 'text/css', body: '' }));
  await page.route('https://fonts.gstatic.com/**', (r) => r.abort());
  if (THREE_DIR) {
    await page.route('https://cdn.jsdelivr.net/npm/three@0.170.0/**', (route) => {
      const rel = route.request().url().split('three@0.170.0/')[1].split('?')[0];
      const f = path.join(THREE_DIR, rel);
      if (!fs.existsSync(f)) return route.fulfill({ status: 404, body: 'nf' });
      return route.fulfill({ status: 200, contentType: 'text/javascript', body: fs.readFileSync(f) });
    });
  }
  S.url = `http://127.0.0.1:${server.address().port}/index.html?${params}`;
  log(`--- session '${name}': ${S.url}  (${CFG.mobile ? 'mobile 915x412' : CFG.size.join('x')})`);
  await page.goto(S.url);
  const ready = await page.waitForFunction(() => {
    const f = document.getElementById('fatal');
    if (f && getComputedStyle(f).display !== 'none') return 'fatal';
    return window.__game && window.__game.state !== 'loading' ? 'ready' : false;
  }, null, { timeout: 180000 * CFG.tscale }).then((h) => h.jsonValue()).catch(() => 'timeout');
  S.loadMs = Date.now() - S.t0;
  S.loaded = true;
  if (ready !== 'ready') {
    const fatal = await page.evaluate(() => { const f = document.getElementById('fatal'); return f ? f.innerText.slice(0, 1500) : null; }).catch(() => null);
    check('boot.ready', 'fail', ready === 'fatal' ? `game init failed: ${fatal}` : 'game did not leave the loading state within the time limit', { details: { fatal } });
    S.failedBoot = true;
    return S;
  }
  check('boot.ready', 'pass', `game ready in ${(S.loadMs / 1000).toFixed(1)} s (state '${await page.evaluate(() => window.__game.state)}')`);
  const inst = await page.evaluate(QA_INSTALL, { swallowUnlock: true });
  if (!inst.ok) { check('boot.harness', 'fail', inst.error); S.failedBoot = true; return S; }
  S.fpsTimer = setInterval(async () => {
    try {
      const r = await page.evaluate(() => ({ f: window.__qa ? window.__qa.frames : 0, now: performance.now(), fps: window.__game && window.__game.renderer && window.__game.renderer.fps }));
      if (S._lastF) {
        const df = r.f - S._lastF.f, dt = (r.now - S._lastF.now) / 1000;
        if (dt > 0.5) S.fps.push({ t: r2((Date.now() - S.t0) / 1000), fps: r2(df / dt), renderer: typeof r.fps === 'number' ? r2(r.fps) : null });
      }
      S._lastF = r;
    } catch (_) { /* page busy/closed */ }
  }, 2000);
  if (CFG.menu) {
    const st = await page.evaluate(() => window.__game.state);
    check('menu.shown', st === 'menu' ? 'pass' : 'fail', `state after load = '${st}'`, { deps: ['ui'] });
    await shot(S, 'menu');
    const b = await call(S, 'findButton', '^\\s*jouer\\s*$|jouer');
    if (b) await tapAt(S, b.x, b.y);
    let ok = await waitFor(S, "g.state === 'playing'", null, { game: 4 });
    check('menu.play', ok ? 'pass' : 'fail', ok ? `"Jouer" started the game (${b ? 'clicked' : '?'})` : `"Jouer" ${b ? 'click did not start the game' : 'button not found'}; emitting ui:start`, { deps: ['ui'] });
    if (!ok) { await page.evaluate(() => window.__game.events.emit('ui:start')); ok = await waitFor(S, "g.state === 'playing'", null, { game: 3 }); }
  }
  return S;
}

async function closeSession(S) {
  if (S.fpsTimer) clearInterval(S.fpsTimer);
  const out = {
    name: S.name, url: S.url, entity: S.entity, loadMs: S.loadMs, wallMs: Date.now() - S.t0,
    errors: S.errors, forcedStages: S.forced, forcedActions: S.forcedActions, shots: S.shotFiles || [],
  };
  if (!S.failedBoot && !S.reloaded) {
    try {
      const ex = await call(S, 'export');
      Object.assign(out, {
        stages: ex.stages, entityTimeline: ex.entity, summons: ex.summons, texts: ex.texts, prompts: ex.prompts,
        clues: ex.clues, interactionEntries: ex.entries, modals: ex.ui, harness: { three: ex.three, warnings: ex.warnings, swallowedPointerUnlock: ex.swallowedPointerUnlock, autoResumedPauses: ex.autoResumed },
        noise: ex.noise, cameraOverride: ex.cameraOverride, final: await snap(S), scene: await call(S, 'sceneStats'),
      });
    } catch (e) { out.exportError = e.message; }
  }
  if (S.walk) out.walk = S.walk;
  if (S.extra) Object.assign(out, S.extra);
  const f = S.fps.map((x) => x.fps).filter((x) => x > 0);
  out.fps = { samples: S.fps.slice(0, 200), min: f.length ? Math.min(...f) : null, avg: f.length ? r2(f.reduce((a, b) => a + b, 0) / f.length) : null, max: f.length ? Math.max(...f) : null };
  const counts = {};
  for (const e of S.events) counts[e.type] = (counts[e.type] || 0) + 1;
  out.eventCounts = counts;
  out.eventLog = S.events.filter((e) => !/^(noise|player:flashlight|inventory:changed)$/.test(e.type)).slice(-250);
  // error checks
  check(`errors.page`, S.errors.page.length ? 'fail' : 'pass', S.errors.page.length ? `${S.errors.page.length} uncaught page error(s): ${S.errors.page[0].text}` : 'no uncaught page errors');
  check(`errors.console`, S.errors.console.length ? 'fail' : 'pass', S.errors.console.length ? `${S.errors.console.reduce((a, b) => a + b.count, 0)} console.error call(s), first: ${S.errors.console[0].text}` : 'no console errors');
  check(`errors.requests`, S.errors.requests.length ? 'fail' : 'pass', S.errors.requests.length ? `${S.errors.requests.length} failed request(s): ${S.errors.requests[0].text}` : `no failed requests (${S.errors.benignRequests} benign ERR_ABORTED after full download)`);
  if (S.reloaded) check('session.reload', 'fail', 'the page reloaded/navigated during the scenario (win/game-over hold failed?)');
  check('perf.fps', 'info', `fps (software GL) min/avg/max = ${out.fps.min}/${out.fps.avg}/${out.fps.max}${out.scene ? `; scene: ${out.scene.meshes} meshes, ${out.scene.triangles} tris, ${out.scene.lights} lights (${out.scene.shadowLights} shadow), quality ${out.scene.quality}` : ''}`);
  report.sessions.push(out);
  await S.ctx.close().catch(() => {});
  CUR = null;
}

// ------------------------------------------------------------------------------------------------ API contract check
async function contractCheck(S) {
  const r = await S.page.evaluate(() => {
    const g = window.__game, miss = [];
    const need = (obj, path, kind) => {
      const parts = path.split('.');
      let o = obj;
      for (const p of parts) { o = o == null ? undefined : o[p]; }
      if (o === undefined || (kind === 'fn' && typeof o !== 'function')) miss.push(path);
    };
    const fns = {
      player: ['init', 'update', 'giveFlashlight', 'setFlashlightOn', 'addBattery', 'enterHide', 'exitHide', 'respawn', 'teleport', 'getVisibility', 'eyePosition'],
      world: ['setPower', 'moveCircle', 'segmentBlocked', 'lineBlocked', 'groundHeightAt', 'path', 'nearestNode', 'setClueDigits'],
      interaction: ['register', 'unregister', 'update'], inventory: ['add', 'remove', 'has', 'count', 'list', 'addNote'],
      puzzles: ['start', 'update', 'reset', 'debugGoto'], entity: ['init', 'update', 'reset', 'summon', 'setAggression', 'setEnabled'],
      ui: ['showMenu', 'hideMenu', 'showPause', 'hidePause', 'showCaught', 'showGameOver', 'showWin', 'fadeTo', 'setPrompt', 'subtitle', 'setObjective', 'alert', 'setInventory', 'setBattery', 'setStamina', 'setNight', 'setClues', 'showNote', 'showKeypad', 'setHidden', 'isModalOpen'],
      audio: ['play', 'loop', 'setFear', 'unlock', 'update'], renderer: ['setQuality', 'resize', 'render', 'setFear', 'flash', 'shake', 'setBlur', 'setHiddenView'],
      input: ['pressed', 'held', 'setInteractAvailable', 'lockPointer', 'unlockPointer', 'setTouchVisible'],
      'world.lighting': ['setPower', 'blowout', 'flicker', 'setStress', 'setTVLight'],
    };
    for (const [sys, list] of Object.entries(fns)) for (const f of list) need(g, `${sys}.${f}`, 'fn');
    for (const p of ['player.position', 'player.yaw', 'player.pitch', 'player.flashlight', 'entity.state', 'entity.position', 'entity.root', 'puzzles.stage', 'puzzles.code', 'puzzles.found', 'renderer.preset', 'renderer.fps', 'input.move', 'world.lighting.doorStrip']) need(g, p);
    const handles = ['door.upstairs', 'door.closet', 'dresser.drawerTop', 'dresser.drawerMid', 'dresser.drawerBottom', 'endTable.drawer', 'alcoveCabinet.drawer_01', 'alcoveCabinet.drawer_02', 'alcoveCabinet.door_01', 'alcoveCabinet.door_02', 'powerBox.door', 'powerBox.lever', 'lockedBox.lid', 'lockedBox.lock'];
    const missingHandles = handles.filter((h) => !g.world.handles[h] || !g.world.handles[h].object || typeof g.world.handles[h].open !== 'function');
    const items = ['flashlight', 'battery1', 'battery2', 'key', 'note1', 'note2', 'note3'].filter((i) => !g.world.items[i]);
    const clues = ['duck', 'horse', 'clock', 'tv'].filter((c) => !g.world.clues[c]);
    const lever = g.world.handles['powerBox.lever'];
    const closet = (g.world.hideSpots || []).find((h) => h.id === 'closet');
    const closetDoorIsHandle = !!(closet && closet.door && closet.door.object && typeof closet.door.open === 'function');
    return {
      miss, missingHandles, items, clues, leverOk: !!(lever && typeof lever.setOn === 'function' && 'isOn' in lever),
      closet: !!(closet && closet.door && closet.hidePos), closetDoorIsHandle, tv: !!(g.world.tv && typeof g.world.tv.setOn === 'function'),
      entries: window.__qa.entries().length, code: g.puzzles.code, colliders: g.world.colliders.length, occluders: g.world.occluders.length,
      entityState: g.entity.state, models: g.assets && g.assets.models ? g.assets.models.size : null,
    };
  });
  check('api.members', r.miss.length ? 'fail' : 'pass', r.miss.length ? `missing public members: ${r.miss.join(', ')}` : 'all documented public methods/members exist');
  check('api.handles', r.missingHandles.length ? 'fail' : 'pass', r.missingHandles.length ? `missing/invalid handles: ${r.missingHandles.join(', ')}` : 'all 14 documented handles exist', { deps: ['props', 'architecture'] });
  check('api.items', r.items.length ? 'fail' : 'pass', r.items.length ? `missing items: ${r.items.join(', ')}` : 'all 7 items exist', { deps: ['props'] });
  check('api.clues', r.clues.length ? 'fail' : 'pass', r.clues.length ? `missing clues: ${r.clues.join(', ')}` : 'all 4 clues exist', { deps: ['props'] });
  check('api.lever', r.leverOk ? 'pass' : 'fail', 'powerBox.lever has isOn + setOn()', { deps: ['props'] });
  check('api.hideSpot', r.closet ? 'pass' : 'fail', 'hideSpots contains the closet with door + hidePos', { deps: ['architecture'] });
  if (r.closet) check('api.hideSpot.door', r.closetDoorIsHandle ? 'pass' : 'warn', r.closetDoorIsHandle ? "hideSpots['closet'].door is the door Handle" : "hideSpots['closet'].door is NOT a Handle: `{ id, door, ...CLOSET }` lets layout CLOSET.door (plain config) overwrite it; spread CLOSET first", { deps: ['architecture'] });
  check('api.tv', r.tv ? 'pass' : 'fail', 'world.tv controller with setOn()', { deps: ['props'] });
  check('api.code', /^[1-9]{4}$/.test(String(r.code)) ? 'pass' : 'fail', `puzzles.code = ${JSON.stringify(r.code)} (4 digits 1-9 expected)`, { deps: ['gameplay'] });
  check('api.entries', r.entries > 0 ? 'pass' : 'fail', `${r.entries} interaction entries registered`, { deps: ['gameplay'] });
  check('world.colliders', r.colliders > 10 ? 'pass' : 'warn', `${r.colliders} colliders, ${r.occluders} occluders, ${r.models} models preloaded`, { deps: ['architecture', 'props'] });
  return r;
}

// ================================================================================================ scenario: walk
const WALK_LEGS = [
  { name: 'coffeeTable', via: ['sofaFront'], y: 0 },
  { name: 'dresser', via: ['kidCorner', 'tvFront'], y: 0 },
  { name: 'stairsBottom', via: ['kidCorner', 'swCorner', 'stairsBottom'], y: 0 },
  { name: 'landing', via: ['stairsMid', 'stairsTop', 'landing'], y: 2.75 },
  { name: 'backDown', via: ['stairsTop', 'stairsMid', 'stairsBottom', 'swCorner'], y: 0 },
  { name: 'laundryNook', via: ['kidCorner', 'tvFront', 'alcoveDoor', 'alcoveIn', 'alcoveEast'], y: 0 },
  { name: 'console', via: ['alcoveIn', 'alcoveDoor', 'center', 'consoleFront'], y: 0 },
];

async function walkPoints(S, label, pts, finalTol = 0.3) {
  const seg = { name: label, ok: true, points: pts.map((p) => `${p.name}(${r2(p.x)},${r2(p.z)})`), stuck: [], timeouts: [] };
  const s0 = await snap(S);
  seg.from = { x: s0.x, y: s0.y, z: s0.z };
  const tStart = s0.rt;
  let pathLen = 0, prev = { x: s0.x, z: s0.z }, maxY = s0.y;
  await startMove(S);
  for (let i = 0; i < pts.length; i++) {
    const p = pts[i];
    const last = i === pts.length - 1;
    await call(S, 'setWalk', p.x, p.z);
    const a = await snap(S);
    const dist0 = Math.hypot(a.x - p.x, a.z - p.z);
    const limit = (dist0 / 1.9) * 3 + 4;
    const tSeg = a.rt;
    let ref = { x: a.x, z: a.z, rt: a.rt };
    const tol = last ? finalTol : 0.35;
    for (;;) {
      const s = await frameSnap(S);
      if (s.pendingCaught && !S.handlingCaught) await handleCaughtScreen(S);
      pathLen += Math.hypot(s.x - prev.x, s.z - prev.z); prev = { x: s.x, z: s.z }; maxY = Math.max(maxY, s.y);
      const d = Math.hypot(s.x - p.x, s.z - p.z);
      if (d < tol) break;
      if (Math.hypot(s.x - ref.x, s.z - ref.z) > 0.04) ref = { x: s.x, z: s.z, rt: s.rt };
      else if (s.rt - ref.rt > 1.5) {
        if (S.moving === 'touch' && pathLen < 0.05) {
          check('mobile.touch.joystick', 'fail', 'touch joystick (CDP touch drag on the left half) did not move the player; falling back to KeyW', { deps: ['player'] });
          await stopMove(S); S.noJoystick = true; await startMove(S); ref = { x: s.x, z: s.z, rt: s.rt };
          continue;
        }
        const b = await call(S, 'blockers', p.x, p.z);
        seg.ok = false;
        seg.stuck.push({ at: p.name, dist: r2(d), blockers: b });
        log(`   stuck on the way to ${p.name} at (${s.x}, ${s.y}, ${s.z}), ${r2(d)} m left; blockers: ${JSON.stringify(b.colliders)} segmentBlocked=${b.segmentBlocked}`);
        await call(S, 'teleport', p.x, p.z, null);
        await gameWait(S, 0.2);
        prev = { x: p.x, z: p.z };
        break;
      }
      if (s.rt - tSeg > limit * CFG.tscale || stalled(S, s.frames)) {
        seg.ok = false;
        seg.timeouts.push({ at: p.name, dist: r2(d), pos: { x: s.x, y: s.y, z: s.z } });
        log(`   timeout on the way to ${p.name}: ${r2(d)} m left`);
        await call(S, 'teleport', p.x, p.z, null);
        await gameWait(S, 0.2);
        prev = { x: p.x, z: p.z };
        break;
      }
    }
  }
  const arrived = await snap(S);
  await stopMove(S);
  await call(S, 'clearSteer');
  await gameWait(S, 0.5);
  const e = await snap(S);
  const target = pts[pts.length - 1];
  seg.final = { x: e.x, y: e.y, z: e.z, dist: r2(Math.hypot(e.x - target.x, e.z - target.z)) };
  seg.gameTime = r2(arrived.rt - tStart);
  seg.pathLen = r2(pathLen);
  seg.speed = seg.gameTime > 0 ? r2(pathLen / seg.gameTime) : null;
  seg.maxY = r2(maxY);
  return seg;
}

async function scenarioWalk(S) {
  const deps = ['player', 'architecture', 'props', 'extras'];
  await gameWait(S, 2.0); // intro fade
  await ensurePlaying(S);
  const nodes = await call(S, 'navNodes');
  if (!Object.keys(nodes).length) { check('walk.nav', 'fail', 'world.nav.nodes missing'); return; }
  const s0 = await snap(S);
  check('walk.spawn', Math.hypot(s0.x - 0.25, s0.z - 1.5) < 0.4 ? 'pass' : 'warn', `player starts at (${s0.x}, ${s0.y}, ${s0.z}) yaw ${s0.yaw}`, { deps: ['player'] });
  S.walk = { legs: [] };
  for (const leg of WALK_LEGS) {
    const pts = leg.via.map((n) => ({ name: n, x: nodes[n].x, z: nodes[n].z }));
    const seg = await walkPoints(S, leg.name, pts);
    S.walk.legs.push(seg);
    const yOk = Math.abs(seg.final.y - leg.y) < 0.12;
    const msg = `${leg.via.join(' → ')}: ${seg.ok ? 'reached' : 'BLOCKED'} in ${seg.gameTime}s game, ${seg.pathLen} m (${seg.speed} m/s), final dist ${seg.final.dist} m, y=${seg.final.y}`;
    const details = seg.stuck.length || seg.timeouts.length ? { stuck: seg.stuck, timeouts: seg.timeouts } : undefined;
    check(`walk.${leg.name}`, seg.ok && seg.final.dist < 0.45 ? 'pass' : 'fail', msg, { deps, details });
    if (!yOk) check(`walk.${leg.name}.height`, 'fail', `floor height at arrival ${seg.final.y}, expected ${leg.y} (stairs/landing)`, { deps: ['player', 'architecture'] });
    if (seg.speed && (seg.speed < 1.2 || seg.speed > 2.7) && seg.ok) check(`walk.${leg.name}.speed`, 'warn', `average walking speed ${seg.speed} m/s (spec: 1.9 m/s)`, { deps: ['player'] });
    await shot(S, `walk-${leg.name}`);
  }
}

// ================================================================================================ scenario: story
async function hideInCloset(S, label) {
  const r = await doInteract(S, 'closet', {
    label: `${label}.enterHide`, expect: 'g.player.hidden === true', within: 3, what: 'player hidden in the closet',
    fallback: "(() => { const s = g.world.hideSpots.find((h) => h.id === 'closet'); const d = s && s.door && s.door.object ? s.door : g.world.handles['door.closet']; return g.player.enterHide({ ...s, door: d }); })()", deps: ['gameplay', 'player', 'architecture'],
  });
  return r;
}
async function exitCloset(S, label) {
  await ensurePlaying(S);
  const s = await snap(S);
  if (!s.hidden) return 'not-hidden';
  await pressInteract(S, 0);
  let ok = await waitFor(S, '!g.player.hidden', null, { game: 2.5 });
  let how = 'interact';
  if (!ok) {
    const f = await call(S, 'findEntry', { key: 'closetExit', ...T.closetExit });
    const r = f.entry ? await call(S, 'callInteract', 'closetExit') : { ok: false };
    how = r.via || 'onInteract';
    ok = r.ok && await waitFor(S, '!g.player.hidden', null, { game: 2.5 });
  }
  if (!ok) { await run(S, 'g.player.exitHide()'); how = 'player.exitHide()'; ok = await waitFor(S, '!g.player.hidden', null, { game: 2.5 }); }
  check(`interact.${label}.exitHide`, ok && how === 'interact' ? 'pass' : ok ? 'warn' : 'fail', `leave the closet: ${ok ? 'ok' : 'still hidden'} via ${how}`, { deps: ['gameplay', 'player'] });
  return how;
}
async function avoidEntity(S, why) {
  if (!S.entity) return;
  const s = await snap(S);
  if (!s.ent || !s.ent.active || s.ent.state === 'returning') return;
  log(`   entity active (${s.ent.state}) ${why}: hiding in the closet until she is dormant`);
  await hideInCloset(S, `avoid.${why}`);
  await waitFor(S, "!g.entity.active || g.entity.state === 'dormant'", null, { game: CFG.entityTimeout });
  await exitCloset(S, `avoid.${why}`);
}

async function scenarioStory(S) {
  await gameWait(S, 1.5);
  await ensurePlaying(S);
  if (FROM > 0) await waitFor(S, 'g.puzzles && g.puzzles.stage === arg', CHECKPOINT_STAGE[FROM], { game: 4 });
  const s0 = await snap(S);
  const stage0 = CHECKPOINT_STAGE[FROM];
  check(`story.stage.${FROM > 0 ? 'start.' : ''}${stage0}`, s0.stage === stage0 ? 'pass' : 'fail', `initial stage '${s0.stage}'${FROM > 0 ? ` (--from ${CFG.from}: ?stage=${stage0})` : ''}`, { deps: ['gameplay'] });
  if (FROM === 0) check('story.power.initial', s0.power === true ? 'pass' : 'fail', `world.power at start = ${s0.power}`, { deps: ['architecture'] });
  check('story.entity.mode', S.entity ? (s0.ent && s0.ent.state !== 'disabled' ? 'pass' : 'fail') : 'info', S.entity ? `entity enabled, state '${s0.ent && s0.ent.state}'` : `entity disabled (?noentity), state '${s0.ent && s0.ent.state}'`, { deps: ['entity'] });
  const tStart = s0.rt;

  const code = String((await run(S, 'g.puzzles.code')).v);
  if (FROM <= 0) {
    // 1. note 1 → blowout
    await doInteract(S, 'note1', { modal: 'notes', deps: ['gameplay', 'props', 'ui'] });
    await reachStage(S, 'dark', 8, 'after reading note 1');
    const dark = await waitFor(S, 'g.world.power === false', null, { game: 3 });
    check('story.dark.powerOff', dark ? 'pass' : 'fail', `world.power after the blowout = ${(await snap(S)).power}`, { deps: ['gameplay', 'architecture'] });

    // 2. flashlight in the dresser top drawer
    await doInteract(S, 'drawerTop', { expect: "g.world.handles['dresser.drawerTop'].isOpen === true", what: 'dresser top drawer open', fallback: "g.world.handles['dresser.drawerTop'].open()" });
    await doInteract(S, 'flashlight', {
      expect: 'g.player.flashlight.has && g.player.flashlight.on', what: 'flashlight taken and switched on',
      fallback: "(g.player.giveFlashlight(), g.player.setFlashlightOn(true), g.inventory.add('flashlight'))", deps: ['gameplay', 'props', 'player'],
    });
    const inv1 = await run(S, "g.inventory.has('flashlight')");
    check('story.inventory.flashlight', inv1.ok && inv1.v ? 'pass' : 'fail', `inventory.has('flashlight') = ${inv1.v}`, { deps: ['gameplay'] });
    await reachStage(S, 'power', 4, 'after taking the flashlight');
  }

  if (FROM <= 1) {
    // 3. breaker panel
    await doInteract(S, 'boxDoor', { expect: "g.world.handles['powerBox.door'].isOpen === true", what: 'power box door open', fallback: "g.world.handles['powerBox.door'].open()" });
    await call(S, 'resetEntTrack');
    const tBreaker = (await snap(S)).rt;
    await doInteract(S, 'lever', {
      expect: "g.world.power === true && g.world.handles['powerBox.lever'].isOn === true", what: 'breaker on, power restored', within: 4,
      fallback: "(g.world.handles['powerBox.lever'].setOn(true), g.world.setPower(true))",
    });
    await waitFor(S, 'qa.texts.alert.length > 0 && g.world.power === true', null, { game: 3 });
    const ex1 = await call(S, 'export');
    const loud = ex1.noise.loud.filter((n) => n.rt >= tBreaker - 0.1);
    check('story.breaker.noise', loud.some((n) => n.l >= 0.99) ? 'pass' : 'fail', `noise events since the breaker: ${JSON.stringify(loud.slice(0, 4))} (expects loudness 1.0)`, { deps: ['gameplay', 'props'] });
    check('story.breaker.alert', ex1.texts.alert.some((a) => /cache/i.test(a.text || '')) ? 'pass' : 'fail', `ui.alert calls: ${JSON.stringify(ex1.texts.alert.map((a) => a.text))}`, { deps: ['gameplay'] });
    const summoned = ex1.summons.filter((x) => x.rt >= tBreaker - 0.1);
    check('story.breaker.summon', summoned.length ? 'pass' : 'fail', summoned.length ? `entity.summon called (reason ${JSON.stringify(summoned[0].reason)})` : 'entity.summon() was not called after the breaker', { deps: ['gameplay'] });

    // 4. hide in the closet (her visit when enabled)
    await hideInCloset(S, 'closet');
    if (S.entity) {
      const woke = await waitFor(S, "g.entity.state !== 'dormant' && g.entity.state !== 'disabled'", null, { game: 10 });
      check('entity.visit.wakes', woke ? 'pass' : 'fail', woke ? 'she left the dormant state after the breaker' : 'she stayed dormant 10 s after the breaker', { deps: ['entity', 'gameplay'] });
      if (woke) {
        const back = await waitFor(S, "g.entity.state === 'dormant' && !g.entity.active", null, { game: CFG.entityTimeout });
        const ex = await call(S, 'export');
        const tl = ex.entity.filter((e) => e.rt >= tBreaker - 0.1).map((e) => `${e.state}@${r2(e.rt - tBreaker)}s`);
        const st = new Set(ex.entity.filter((e) => e.rt >= tBreaker - 0.1).map((e) => e.state));
        const minY = await S.page.evaluate(() => window.__qa.entTrack.minY);
        S.extra = { ...(S.extra || {}), entityVisit: { timeline: tl, minY: r2(minY) } };
        check('entity.visit.descends', minY < 0.6 ? 'pass' : 'fail', `lowest y during the visit ${r2(minY)} (she must reach the basement floor)`, { deps: ['entity'] });
        check('entity.visit.searches', st.has('searching') ? 'pass' : 'fail', `states: ${tl.join(' → ')}`, { deps: ['entity'] });
        check('entity.visit.returns', back ? 'pass' : 'fail', back ? `back to dormant after ${r2((await snap(S)).rt - tBreaker)} s` : `not dormant after ${CFG.entityTimeout} s (state '${(await snap(S)).ent.state}')`, { deps: ['entity'] });
        check('entity.visit.hiddenSafe', ex.caughtCount === 0 ? 'pass' : 'fail', ex.caughtCount ? 'she caught the player although he hid before she arrived' : 'not caught while hidden', { deps: ['entity'] });
      }
    } else await gameWait(S, 1.5);
    await shot(S, 'hidden');
    await exitCloset(S, 'closet');
    await reachStage(S, 'code', S.entity ? 15 : 12, S.entity ? 'after she went back upstairs' : 'after the breaker (entity disabled)');
  }

  if (FROM <= 2) {
    // 5. clues
    const order = ['duck', 'horse', 'clock', 'tv'];
    for (let i = 0; i < order.length; i++) {
      const k = order[i];
      await avoidEntity(S, `clue-${k}`);
      const r = await doInteract(S, k, { expect: `g.puzzles.found && g.puzzles.found.${k} != null`, what: `clue '${k}' found`, within: k === 'tv' ? 5 : 3 });
      const f = (await run(S, `g.puzzles.found && g.puzzles.found.${k}`)).v;
      if (r.how === 'missing') check(`story.clue.${k}.digit`, 'skip', 'no interaction entry (see above)');
      else check(`story.clue.${k}.digit`, f != null && String(f) === code[i] ? 'pass' : 'fail', `found.${k} = ${JSON.stringify(f)}, code[${i}] = ${code[i]} (code ${code})`, { deps: ['gameplay', 'props'] });
      if (k === 'tv') {
        await gameWait(S, 0.6);
        await doInteract(S, 'tv', { label: 'tvOff', expect: '!g.world.tv.isOn', what: 'TV switched off again', fallback: 'g.world.tv.setOn(false)' });
      }
    }
    const clues = (await call(S, 'export')).clues;
    check('story.clues.ui', clues && order.every((k) => clues[k] != null) ? 'pass' : 'fail', `last ui.setClues(${JSON.stringify(clues)})`, { deps: ['gameplay', 'props', 'ui'] });
    await avoidEntity(S, 'after-clues');

    // 6. optional pickups and notes
    await doInteract(S, 'note2', { modal: 'notes', deps: ['gameplay', 'props', 'ui'] });
    const bat0 = Number((await run(S, "g.inventory.count('battery')")).v) || 0;
    await doInteract(S, 'endDrawer', { expect: "g.world.handles['endTable.drawer'].isOpen === true", what: 'end table drawer open', fallback: "g.world.handles['endTable.drawer'].open()" });
    await doInteract(S, 'battery1', { expect: "g.inventory.count('battery') >= arg", expectArg: bat0 + 1, what: 'battery 1 picked up' });
    await doInteract(S, 'cabDrawer', { expect: "g.world.handles['alcoveCabinet.drawer_01'].isOpen === true", what: 'cabinet drawer open', fallback: "g.world.handles['alcoveCabinet.drawer_01'].open()" });
    await doInteract(S, 'battery2', { expect: "g.inventory.count('battery') >= arg", expectArg: bat0 + 2, what: 'battery 2 picked up' });
    await doInteract(S, 'cabDoor', { expect: "g.world.handles['alcoveCabinet.door_01'].isOpen === true", what: 'cabinet door open', fallback: "g.world.handles['alcoveCabinet.door_01'].open()" });
    await doInteract(S, 'note3', { modal: 'notes', deps: ['gameplay', 'props', 'ui'] });
    const notes = (await run(S, 'g.inventory.notes.length')).v;
    check('story.inventory.notes', notes >= 3 ? 'pass' : 'fail', `inventory.notes.length = ${notes} (3 notes read)`, { deps: ['gameplay'] });
    await avoidEntity(S, 'before-keypad');
  }

  if (FROM <= 3) {
    // 7. the child's note on the box lid, then the keypad: one wrong code, then the right one (digits injected
    //    through the showKeypad promise)
    await doInteract(S, 'boxNote', { modal: 'notes', deps: ['gameplay', 'props', 'ui'] });
    const wrong = code.split('').map((d) => String((Number(d) % 9) + 1)).join('');
    for (const [label, value] of [['wrong', wrong], ['right', code]]) {
      const before = await call(S, 'modalCount', 'keypads');
      const ri = await doInteract(S, 'lock', { label: `keypad.${label}`, shotAfter: false, deps: ['gameplay', 'props', 'ui'] });
      const opened = ri.how !== 'missing' && await waitFor(S, 'qa.ui.keypads.length > arg', before, { game: 2.5 });
      if (!opened) {
        if (ri.how === 'missing') check(`story.keypad.${label}.open`, 'skip', 'no interaction entry for the padlock (see above)');
        else check(`story.keypad.${label}.open`, 'fail', 'interacting with the padlock did not call ui.showKeypad()', { deps: ['gameplay'] });
        if (label === 'right') await run(S, "(g.world.handles['lockedBox.lock'].open(), g.world.handles['lockedBox.lid'].open())");
        continue;
      }
      await gameWait(S, 0.5);
      await shot(S, `keypad-${label}`);
      const lastK = await call(S, 'modalLast', 'keypads');
      await call(S, 'resolveModal', 'keypads', value, 'qa-inject');
      await gameWait(S, 0.4);
      if (await run(S, 'g.ui.isModalOpen()').then((r) => r.v)) {
        const b = await call(S, 'findButton', 'annuler|fermer|retour');
        if (b) await tapAt(S, b.x, b.y);
      }
      const closed = await waitFor(S, '!g.ui.isModalOpen()', null, { game: 1.5 });
      check(`story.keypad.${label}.modal`, closed ? 'pass' : 'fail', `keypad ${JSON.stringify(lastK.arg)} opened; code ${value} injected; modal ${closed ? 'closed' : 'still open after injecting the code (no Annuler button?)'}`, { deps: ['ui'] });
      if (label === 'wrong') {
        await gameWait(S, 1.0);
        const st = await run(S, "({ stage: g.puzzles.stage, lid: g.world.handles['lockedBox.lid'].isOpen, lock: g.world.handles['lockedBox.lock'].isOpen })");
        check('story.keypad.wrongRejected', st.v && st.v.stage === 'code' && !st.v.lid ? 'pass' : 'fail', `after a wrong code: ${JSON.stringify(st.v)}`, { deps: ['gameplay'] });
      } else {
        const ok = await waitFor(S, "g.world.handles['lockedBox.lid'].isOpen === true || g.world.handles['lockedBox.lock'].isOpen === true", null, { game: 3 });
        check('story.keypad.rightOpens', ok ? 'pass' : 'fail', ok ? 'right code opens the box' : 'the right code did not open the padlock/lid', { deps: ['gameplay', 'props'] });
        if (!ok) await run(S, "(g.world.handles['lockedBox.lock'].open(), g.world.handles['lockedBox.lid'].open())");
      }
    }
    await shot(S, 'box-open');

    // 8. key → escape
    await doInteract(S, 'key', { expect: "g.inventory.has('key')", what: 'key picked up', fallback: "g.inventory.add('key')" });
    await reachStage(S, 'escape', 4, 'after taking the key');
  }

  // 9. upstairs door (hold to unlock) → walk through → win
  await avoidEntity(S, 'before-door');
  await doInteract(S, 'door', {
    expect: "g.world.handles['door.upstairs'].isOpen === true", what: 'upstairs door unlocked and open', within: 5,
    fallback: "(g.world.handles['door.upstairs'].locked = false, g.world.handles['door.upstairs'].open())", deps: ['gameplay', 'architecture', 'player'],
  });
  await shot(S, 'door-open');
  let won = await waitFor(S, "g.state === 'won'", null, { game: 0.5 });
  if (!won) {
    await call(S, 'setWalk', -3.0, -3.6);
    await startMove(S);
    won = await waitFor(S, "g.state === 'won'", null, { game: 6 });
    await stopMove(S);
    await call(S, 'clearSteer');
  }
  const exW = await call(S, 'export');
  await gameWait(S, 1.0);
  await shot(S, 'win');
  check('story.win', won && exW.winCount > 0 ? 'pass' : 'fail', won ? `'game:win' emitted, state 'won' after ${r2((await snap(S)).rt - tStart)} s game time` : `no win (state '${(await snap(S)).state}', game:win events ${exW.winCount})`, { deps: ['gameplay', 'architecture'] });
  if (won) {
    const w = await call(S, 'modalLast', 'win');
    check('story.win.screen', w.n > 0 ? 'pass' : 'fail', w.n > 0 ? `ui.showWin(${JSON.stringify(w.arg)}) shown (held open to prevent the reload)` : 'ui.showWin was not called', { deps: ['ui'] });
  }

  // 10. stage sequence
  const seq = (await call(S, 'export')).stages.map((x) => x.stage);
  const want = ['intro', 'dark', 'power', 'code', 'escape'].slice(['intro', 'dark', 'power', 'code', 'escape'].indexOf(CHECKPOINT_STAGE[FROM]));
  let k = 0;
  for (const st of seq) if (st === want[k]) k++;
  const forcedAny = S.forced.length > 0;
  check('story.sequence', k === want.length && won && !forcedAny ? 'pass' : 'fail',
    `stages seen: ${seq.join(' → ')}${won ? ' → (won)' : ''}${forcedAny ? `; forced: ${S.forced.map((f) => `${f.stage}${f.worked ? '' : '(no effect)'}`).join(', ')}` : ''}`, { deps: ['gameplay'] });
  // French text heuristic
  const ex = await call(S, 'export');
  const texts = [...ex.prompts, ...ex.texts.objective.map((o) => o.text), ...ex.texts.alert.map((o) => o.text), ...ex.texts.subtitle.map((o) => o.text), ...ex.entries.map((e) => e.prompt)].filter((x) => typeof x === 'string');
  const en = [...new Set(texts.filter((t) => /\b(the|open|close|take|read|press|pick up|door|drawer|hide|unlock|locked|find|turn on|turn off)\b/i.test(t)))];
  check('text.french', en.length ? 'warn' : 'pass', en.length ? `possibly non-French player text: ${JSON.stringify(en.slice(0, 8))}` : `${new Set(texts).size} player-facing strings look French`, { deps: ['gameplay', 'ui'] });
}

// ================================================================================================ scenario: caught
async function scenarioCaught(S) {
  await gameWait(S, 1.5);
  await ensurePlaying(S);
  const s0 = await snap(S);
  if (!s0.ent || s0.ent.state === 'disabled') { check('caught.entity', 'fail', `entity unavailable (state '${s0.ent && s0.ent.state}')`, { deps: ['entity'] }); return; }
  await run(S, "(g.player.giveFlashlight(), g.player.setFlashlightOn(true), g.inventory.add('flashlight'), g.inventory.add('battery', 1))");
  const before = (await run(S, "({ inv: g.inventory.list().map((i) => i.id + ':' + i.count).sort().join(','), stage: g.puzzles.stage, found: JSON.stringify(g.puzzles.found) })")).v;
  const rounds = CFG.gameover ? [2, 3, 4] : [2, 3];
  for (const night of rounds) {
    const tag = night > 3 ? 'gameover' : `night${night}`;
    await ensurePlaying(S);
    const c0 = (await call(S, 'export')).caughtCount;
    const cc0 = await call(S, 'modalCount', 'caught');
    await call(S, 'resetEntTrack');
    await run(S, "(g.entity.setAggression(2), g.entity.summon(g.player.position.clone(), { reason: 'qa', aggressive: true }))");
    const woke = await waitFor(S, "g.entity.active || (g.entity.state !== 'dormant' && g.entity.state !== 'disabled')", null, { game: 10 });
    const arrived = woke && await waitFor(S, 'g.entity.active && g.entity.position.y < 0.6', null, { game: 75 });
    let manual = false;
    if (!arrived) {
      const st = (await snap(S)).ent;
      check(`caught.${tag}.summon`, 'fail', `entity.summon() did not bring her to the basement (${woke ? 'woke, not down within 75 s' : 'still dormant 10 s after summon'}; state '${st && st.state}', pos ${st && `${st.x},${st.y},${st.z}`}); emitting 'entity:caught' manually to test the reset flow`, { deps: ['entity'] });
      manual = true;
      await S.page.evaluate(() => window.__game.events.emit('entity:caught', {}));
    } else {
      check(`caught.${tag}.summon`, 'pass', `she reached the basement (${(await snap(S)).ent.state})`, { deps: ['entity'] });
      let caught = null;
      for (let attempt = 0; attempt < 4 && !caught; attempt++) {
        const pl = await call(S, 'placeInFront', 1.5, attempt);
        if (!pl.ok) { log('   could not find a free spot in front of her'); await gameWait(S, 1); continue; }
        await shot(S, `${tag}-facing-her`);
        caught = await waitFor(S, 'qa.caughtCount > arg', c0, { game: 10 });
      }
      const ex = await call(S, 'export');
      const states = ex.entity.slice(-12).map((e) => e.state);
      const co = ex.cameraOverride.filter((c) => c.on && c.ent === 'jumpscare');
      if (!caught) {
        check(`caught.${tag}.jumpscare`, 'fail', `she did not catch the player standing 1.5 m in front of her (recent states ${states.join(' → ')}); emitting 'entity:caught' manually`, { deps: ['entity'] });
        manual = true;
        await S.page.evaluate(() => window.__game.events.emit('entity:caught', {}));
      } else {
        check(`caught.${tag}.jumpscare`, states.includes('jumpscare') ? 'pass' : 'warn', `caught; states ${states.join(' → ')}; cameraOverride during jumpscare: ${co.length ? 'yes' : 'not seen'}`, { deps: ['entity'] });
      }
    }
    if (night > 3) {
      const go = await waitFor(S, "g.state === 'gameover' && qa.ui.gameover.length > 0", null, { game: 5 });
      await gameWait(S, 0.8);
      await shot(S, 'gameover');
      check('caught.gameover', go ? 'pass' : 'fail', go ? 'third catch → state gameover + ui.showGameOver() (held open to prevent the reload)' : `no game over (state '${(await snap(S)).state}')`, { deps: ['ui'] });
      break;
    }
    const inCaught = await waitFor(S, 'qa.ui.caught.length > arg', cc0, { game: 6 });
    const back = await waitFor(S, "g.state === 'playing' && g.night === arg", night, { game: 12 });
    await gameWait(S, 2.0); // fade-in
    const a = await run(S, `({ night: g.night, px: g.player.position.x, pz: g.player.position.z, hidden: g.player.hidden, camOverride: g.player.cameraOverride, enabled: g.player.enabled,
      ent: g.entity.state, entActive: g.entity.active, inv: g.inventory.list().map((i) => i.id + ':' + i.count).sort().join(','), stage: g.puzzles.stage,
      found: JSON.stringify(g.puzzles.found), fl: g.player.flashlight.has, caughtArg: (qa.ui.caught[qa.ui.caught.length - 1] || {}).arg, state: g.state })`);
    const v = a.v || {};
    const spawnD = Math.hypot((v.px || 0) - 0.25, (v.pz || 0) - 1.5);
    const deps = ['entity', 'player', 'ui'];
    check(`caught.${tag}.flow`, inCaught && back ? 'pass' : 'fail', `${manual ? '(manual entity:caught) ' : ''}state caught → playing, night ${v.night} (expected ${night}); showCaught(${JSON.stringify(v.caughtArg)})`, { deps });
    check(`caught.${tag}.respawn`, spawnD < 0.6 && !v.hidden ? 'pass' : 'fail', `player at (${r2(v.px)}, ${r2(v.pz)}), ${r2(spawnD)} m from spawn, hidden=${v.hidden}`, { deps: ['player'] });
    check(`caught.${tag}.control`, v.camOverride === false && v.enabled !== false ? 'pass' : 'fail', `cameraOverride=${v.camOverride}, player.enabled=${v.enabled}`, { deps: ['entity', 'player'] });
    check(`caught.${tag}.entityReset`, !v.entActive && (v.ent === 'dormant') ? 'pass' : 'fail', `entity state '${v.ent}', active=${v.entActive}`, { deps: ['entity'] });
    check(`caught.${tag}.kept`, v.inv === before.inv && v.stage === before.stage && v.fl ? 'pass' : 'fail', `inventory ${v.inv} (before ${before.inv}), stage ${v.stage} (before ${before.stage}), flashlight ${v.fl}`, { deps: ['gameplay'] });
    await shot(S, `${tag}-after-reset`);
  }
}

// ================================================================================================ main
async function ensureBrowser() {
  if (browser && browser.isConnected()) return;
  if (browser) log('browser disconnected (crashed or killed from outside): relaunching for the next scenario');
  browser = await chromium.launch({
    headless: !CFG.headed,
    args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required',
      '--disable-renderer-backgrounding', '--disable-background-timer-throttling', '--disable-backgrounding-occluded-windows'],
  });
}

async function main() {
  const hardStop = setTimeout(async () => {
    log(`hard time limit (${CFG.maxMinutes} min) reached`);
    check('harness.timeLimit', 'fail', `run exceeded ${CFG.maxMinutes} minutes (raise --max-minutes on a slow machine)`);
    if (CUR) await Promise.race([closeSession(CUR), sleep(30000)]).catch(() => {});
    finish(1);
  }, CFG.maxMinutes * 60000);
  hardStop.unref();
  await new Promise((r) => server.listen(Number(process.env.PORT || 0), '127.0.0.1', r));
  await ensureBrowser();
  const stubList = Object.entries(STUBS).filter(([, v]) => v === 'stub').map(([k]) => k);
  log(`modules still stubs: ${stubList.length ? stubList.join(', ') : 'none'}`);
  if (!THREE_DIR) log('THREE_DIR not set: three.js is loaded from the CDN');
  let contractDone = false;
  for (const sc of CFG.scenarios) {
    const fn = { walk: scenarioWalk, story: scenarioStory, caught: scenarioCaught }[sc];
    if (!fn) { check(`scenario.${sc}`, 'fail', `unknown scenario '${sc}'`); continue; }
    await ensureBrowser();
    const S = await openSession(sc, { entity: sc === 'caught' || (sc === 'story' && CFG.entity) });
    try {
      if (!S.failedBoot) {
        if (!contractDone) { await contractCheck(S); contractDone = true; }
        await fn(S);
      }
    } catch (e) {
      const gone = /has been closed|Target closed|crashed/i.test(e.message);
      check(`scenario.${sc}.crash`, 'fail', `scenario aborted: ${e.message.split('\n')[0]}${gone ? ' (page/browser died: renderer crash or Chromium killed from outside)' : ''}`, { details: (e.stack || '').split('\n').slice(0, 6) });
      try { await stopMove(S); } catch (_) { /* ignore */ }
    }
    await closeSession(S);
  }
  finish();
}

let finished = false;
function finish(forceCode) {
  if (finished) return;
  finished = true;
  const c = report.checks;
  const count = (s) => c.filter((x) => x.status === s).length;
  const fails = c.filter((x) => x.status === 'fail');
  const unexplained = fails.filter((x) => !x.explainedByStubs);
  report.summary = {
    ok: fails.length === 0,
    pass: count('pass'), fail: fails.length, warn: count('warn'), info: count('info'), skip: count('skip'),
    failExplainedByStubs: fails.length - unexplained.length, failUnexplained: unexplained.length,
    stubs: Object.entries(STUBS).filter(([, v]) => v === 'stub').map(([k]) => k),
    failures: fails.map((x) => `${x.scenario ? x.scenario + ': ' : ''}${x.id} — ${x.msg}${x.explainedByStubs ? ` [stub: ${x.explainedByStubs.join(',')}]` : ''}`),
    note: fails.length && unexplained.length === 0
      ? 'every failure involves a module that is still a stub (expected before the merge)'
      : undefined,
  };
  report.finishedAt = new Date().toISOString();
  const json = JSON.stringify(report, null, 2);
  if (CFG.out) { try { fs.mkdirSync(path.dirname(path.resolve(CFG.out)), { recursive: true }); fs.writeFileSync(CFG.out, json); } catch (e) { log('could not write', CFG.out, e.message); } }
  process.stdout.write(json + '\n');
  const s = report.summary;
  log(`SUMMARY: ${s.pass} pass, ${s.fail} fail (${s.failExplainedByStubs} explained by stubs: ${s.stubs.join(', ') || '-'}), ${s.warn} warn`);
  const code = forceCode != null ? forceCode : (CFG.allowStubs ? (s.failUnexplained ? 1 : 0) : (s.fail ? 1 : 0));
  Promise.resolve(browser && browser.close()).catch(() => {}).finally(() => { server.close(); process.exit(code); });
}

main().catch((e) => {
  console.error(e);
  check('harness.crash', 'fail', e.message);
  finish(2);
});
