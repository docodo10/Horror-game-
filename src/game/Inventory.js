// Inventory (gameplay module). Item ids: 'flashlight', 'battery', 'key'. Notes are tracked separately (inventory.notes[]).
// Public API:
//   constructor(game); init()
//   add(id, count=1)  remove(id, count=1) -> bool  has(id) -> bool  count(id) -> number
//   list() -> [{ id, name, icon, count }]   (icon = short inline SVG string, stroke = currentColor)
//   addNote({ id, title, text, style })     notes[] the player can re-read from the pause/inventory panel
//   getNote(id) -> note | null      clear()  (new game)
// Emits: 'inventory:changed' { items: list(), notes }  (and mirrors the list to ui.setInventory for robustness)

const SVG = (body) =>
  `<svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="1.6" ` +
  `stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${body}</svg>`;

/** Item catalogue: display order, French names (singular / plural) and line icons. */
export const ITEM_DEFS = {
  flashlight: {
    name: 'Lampe de poche',
    plural: 'Lampes de poche',
    icon: SVG('<rect x="3" y="9" width="11" height="6" rx="1.2"/><path d="M14 8.5l4.5-2.5v12L14 15.5z"/><path d="M6 12h4"/><path d="M20.5 9.5l1.5-.8M20.5 14.5l1.5.8M21 12h1.5"/>'),
  },
  battery: {
    name: 'Pile',
    plural: 'Piles',
    icon: SVG('<rect x="7" y="4" width="10" height="17" rx="1.5"/><path d="M10 2.5h4"/><path d="M12 8.5v4M10 10.5h4"/><path d="M10 16.5h4"/>'),
  },
  key: {
    name: 'Clé',
    plural: 'Clés',
    icon: SVG('<circle cx="7" cy="12" r="3.6"/><circle cx="7" cy="12" r="1.2"/><path d="M10.6 12H21"/><path d="M17 12v3M20 12v2.4"/>'),
  },
};
const ORDER = Object.keys(ITEM_DEFS);

export class Inventory {
  constructor(game) {
    this.game = game;
    this.items = new Map();
    this.notes = [];
  }

  init() { this._emit(); }

  add(id, n = 1) {
    if (!id || !(n > 0)) return;
    this.items.set(id, (this.items.get(id) || 0) + n);
    this._emit();
  }

  remove(id, n = 1) {
    const c = this.items.get(id) || 0;
    if (c < n) return false;
    if (c - n > 0) this.items.set(id, c - n); else this.items.delete(id);
    this._emit();
    return true;
  }

  has(id) { return (this.items.get(id) || 0) > 0; }

  count(id) { return this.items.get(id) || 0; }

  list() {
    const ids = [...this.items.keys()].filter((id) => this.items.get(id) > 0);
    ids.sort((a, b) => {
      const ia = ORDER.indexOf(a), ib = ORDER.indexOf(b);
      return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib);
    });
    return ids.map((id) => {
      const def = ITEM_DEFS[id];
      const count = this.items.get(id);
      return { id, name: def ? (count > 1 ? def.plural : def.name) : id, icon: def ? def.icon : '', count };
    });
  }

  /** Adds (or refreshes) a readable note. Notes keep their discovery order. */
  addNote(n) {
    if (!n) return;
    const note = { id: n.id || `note${this.notes.length + 1}`, title: n.title || 'Note', text: n.text || '', style: n.style || 'note' };
    const i = this.notes.findIndex((x) => x.id === note.id);
    if (i >= 0) this.notes[i] = note; else this.notes.push(note);
    this._emit();
  }

  getNote(id) { return this.notes.find((x) => x.id === id) || null; }

  clear() { this.items.clear(); this.notes.length = 0; this._emit(); }

  _emit() {
    const items = this.list();
    const notes = this.notes;
    try { this.game.ui?.setInventory?.(items, notes); } catch (e) { console.warn('[inventory] ui.setInventory', e); }
    this.game.events?.emit('inventory:changed', { items, notes });
  }
}
