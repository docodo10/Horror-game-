import { Game } from './core/Game.js';

// URL parameters (handy for testing):
//   ?debug=1        exposes window.__game, logs extra info
//   ?autostart=1    skips the menu
//   ?quality=low|medium|high|ultra
//   ?cam=x,y,z,yawDeg,pitchDeg   teleport the player camera after start (debug)
//   ?power=off      start with the power cut (debug)
//   ?noentity=1     disables the entity (debug)
const q = new URLSearchParams(location.search);
const params = {
  debug: q.has('debug'),
  autostart: q.has('autostart'),
  quality: q.get('quality'),
  cam: q.get('cam'),
  power: q.get('power'),
  noentity: q.has('noentity'),
  expose: true,
};

const game = new Game({
  canvas: document.getElementById('game'),
  uiRoot: document.getElementById('ui'),
  touchRoot: document.getElementById('touch'),
  params,
});

game.init().catch((e) => {
  console.error(e);
  const el = document.getElementById('fatal');
  if (el) { el.style.display = 'flex'; el.querySelector('pre').textContent = String(e?.stack || e); }
});
