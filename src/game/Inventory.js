// STUB — to be replaced by the gameplay module (see ARCHITECTURE.md §Inventory).
// Item ids: 'flashlight', 'battery', 'key'. Notes are tracked separately (inventory.notes[]).
// Public API (must be kept):
//   constructor(game); init()
//   add(id, count=1)  remove(id, count=1) -> bool  has(id) -> bool  count(id) -> number
//   list() -> [{ id, name, icon, count }]   (icon = short inline SVG string or emoji-free glyph id for UI)
//   addNote({ id, title, text, style })     notes[] the player can re-read from the pause/inventory panel
// Emits: 'inventory:changed' { items: list(), notes }
export class Inventory {
  constructor(game) { this.game = game; this.items = new Map(); this.notes = []; }
  init() {}
  add(id, n = 1) { this.items.set(id, (this.items.get(id) || 0) + n); }
  remove(id, n = 1) { const c = this.items.get(id) || 0; if (c < n) return false; this.items.set(id, c - n); return true; }
  has(id) { return (this.items.get(id) || 0) > 0; }
  count(id) { return this.items.get(id) || 0; }
  list() { return [...this.items].filter(([, c]) => c > 0).map(([id, count]) => ({ id, name: id, icon: id, count })); }
  addNote(n) { this.notes.push(n); }
}
