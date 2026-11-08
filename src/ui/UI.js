// STUB — to be replaced by the UI module (see ARCHITECTURE.md §UI). All text is French.
// Public API (must be kept; every show* that returns a Promise resolves when the player closes it):
//   constructor(game, root); init(); update(dt)
//   showLoading(progress 0..1, text)            hideLoading() is implicit when showMenu()/start happens
//   showMenu() / hideMenu()                     "Jouer" button -> game.events.emit('ui:start'); options edit game.settings
//   showPause() -> Promise (resolves on "Reprendre")   hidePause()
//   showCaught({ night, nightsTotal }) -> Promise      showGameOver() -> Promise      showWin({ time, nightsUsed, nightsTotal }) -> Promise
//   fadeTo(alpha 0..1, seconds) -> Promise       black overlay
//   setPrompt(text|null, { hold?: 0..1 })        center prompt under the crosshair; crosshair turns into a hand when text
//   subtitle(text, seconds=3.5, { speaker? })    bottom subtitles (respect settings.subtitles except for critical hints)
//   setObjective(text)                           top-left objective with a short highlight animation
//   alert(text, seconds=2)                       big centered warning (e.g. 'CACHE-TOI !')
//   setInventory(items[])                        bottom-right slots
//   setBattery(v 0..1 | null)  setStamina(v 0..1)  setNight(night, total)
//   setClues({ duck, horse, clock, tv })         small "carnet" showing found digits (null = '?')
//   showNote({ title, text, style: 'note'|'child'|'newspaper' }) -> Promise
//   showKeypad({ title, length: 4 }) -> Promise<string|null>   (null = cancelled)
//   setHidden(bool)                              closet overlay hint ('Appuie sur E pour sortir')
//   isModalOpen() -> bool
export class UI {
  constructor(game, root) { this.game = game; this.root = root; this._modal = false; }
  init() {
    this.el = document.createElement('div');
    this.el.style.cssText = 'position:fixed;left:16px;top:16px;font:14px sans-serif;color:#eee';
    this.root.appendChild(this.el);
  }
  update() {}
  showLoading(p, t) { this.el.textContent = `${t} ${Math.round(p * 100)}%`; }
  showMenu() { this.el.innerHTML = '<button id="play">Jouer</button>'; this.el.querySelector('#play').onclick = () => this.game.events.emit('ui:start'); }
  hideMenu() { this.el.textContent = ''; }
  showPause() { return new Promise(() => {}); }
  hidePause() {}
  showCaught() { return Promise.resolve(); }
  showGameOver() { return Promise.resolve(); }
  showWin() { return Promise.resolve(); }
  fadeTo() { return Promise.resolve(); }
  setPrompt(t) { this.el.textContent = t || ''; }
  subtitle(t) { console.log('[sub]', t); }
  setObjective(t) { console.log('[obj]', t); }
  alert(t) { console.log('[alert]', t); }
  setInventory() {}
  setBattery() {}
  setStamina() {}
  setNight() {}
  setClues() {}
  showNote() { return Promise.resolve(); }
  showKeypad() { return Promise.resolve(null); }
  setHidden() {}
  isModalOpen() { return this._modal; }
}
