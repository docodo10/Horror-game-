// STUB — to be replaced by the player/input module (see ARCHITECTURE.md §Input).
// Unified keyboard/mouse (pointer lock) + touch (virtual joystick, look pad, buttons) input.
// Public API (must be kept):
//   constructor(game, touchRoot); init(); update(dt); endFrame()
//   .enabled            set by Game every frame (false while a modal is open / not playing) -> move/look read as zero
//   .isTouch            true on touch devices (coarse pointer) — touch controls are shown only then
//   .move               {x, y} in -1..1 (y = forward)
//   .look               {dx, dy} pixels this frame (already multiplied by settings.sensitivity; invertY applied)
//   pressed(action)     true only on the frame the action was pressed. Actions:
//                       'interact' (E / left click / ✋), 'flashlight' (F / 🔦), 'crouch' (C or Ctrl / ⬇ toggle),
//                       'pause' (Esc / P / ⏸ — Input itself emits 'input:pause'), 'next' (Tab / wheel)
//   held(action)        'sprint' (Shift / 🏃 hold), 'interact' (for hold-to-use), 'crouch'
//   setInteractAvailable(bool, label?)  highlights the ✋ touch button
//   lockPointer() / unlockPointer()     desktop pointer lock; emits 'input:pointerlock' {locked}
//   setTouchVisible(bool)
export class Input {
  constructor(game, touchRoot) {
    this.game = game; this.touchRoot = touchRoot;
    this.enabled = false;
    this.isTouch = matchMedia('(pointer: coarse)').matches;
    this.move = { x: 0, y: 0 };
    this.look = { dx: 0, dy: 0 };
    this._down = new Set(); this._pressed = new Set();
  }
  init() {
    addEventListener('keydown', (e) => { if (!this._down.has(e.code)) this._pressed.add(e.code); this._down.add(e.code); if (e.code === 'Escape') this.game.events.emit('input:pause'); });
    addEventListener('keyup', (e) => this._down.delete(e.code));
  }
  update() {
    const k = (c) => this._down.has(c);
    this.move.x = this.enabled ? (k('KeyD') ? 1 : 0) - (k('KeyA') ? 1 : 0) : 0;
    this.move.y = this.enabled ? (k('KeyW') ? 1 : 0) - (k('KeyS') ? 1 : 0) : 0;
  }
  endFrame() { this._pressed.clear(); this.look.dx = this.look.dy = 0; }
  pressed(a) { const map = { interact: 'KeyE', flashlight: 'KeyF', crouch: 'KeyC', next: 'Tab' }; return this.enabled && this._pressed.has(map[a]); }
  held(a) { const map = { sprint: 'ShiftLeft', interact: 'KeyE', crouch: 'KeyC' }; return this.enabled && this._down.has(map[a]); }
  setInteractAvailable() {}
  lockPointer() {}
  unlockPointer() {}
  setTouchVisible() {}
}
