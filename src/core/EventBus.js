// Tiny synchronous event emitter shared by every module (game.events).
export class EventBus {
  constructor() { this._h = new Map(); }

  on(name, fn) {
    if (!this._h.has(name)) this._h.set(name, new Set());
    this._h.get(name).add(fn);
    return () => this.off(name, fn);
  }

  once(name, fn) {
    const off = this.on(name, (p) => { off(); fn(p); });
    return off;
  }

  off(name, fn) { this._h.get(name)?.delete(fn); }

  emit(name, payload) {
    const set = this._h.get(name);
    if (!set) return;
    for (const fn of [...set]) {
      try { fn(payload); } catch (e) { console.error(`[event ${name}]`, e); }
    }
  }
}
