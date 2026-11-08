## Inventory (gameplay module) — port of src/game/Inventory.js. Items: "flashlight", "battery", "key". Notes tracked separately.
## Public API (keep): add(id, n := 1), remove(id, n := 1) -> bool, has(id) -> bool, count(id) -> int, list() -> Array[{id, name, count}],
##   add_note({id, title, text, style}), notes: Array. Emits Events.inventory_changed.
## Additions: items: Dictionary (id -> count), get_note(id) -> Dictionary ({} if unknown), clear() (new game), emit_changed() (re-broadcast),
##   ITEM_DEFS (French singular/plural names + line icon as an SVG string, stroke="currentColor"),
##   list() entries also carry `icon` (SVG string) — the UI may render it with Image.load_svg_from_string() after replacing currentColor.
##   Also mirrors every change to Game.ui.set_inventory(items, notes) when the UI has it.
extends Node

const _SVG_HEAD := "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" width=\"24\" height=\"24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.6\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\">"
const _SVG_TAIL := "</svg>"

## Item catalogue: display order, French names (singular / plural) and line icons.
const ITEM_DEFS := {
	"flashlight": {
		"name": "Lampe de poche",
		"plural": "Lampes de poche",
		"icon": _SVG_HEAD + "<rect x=\"3\" y=\"9\" width=\"11\" height=\"6\" rx=\"1.2\"/><path d=\"M14 8.5l4.5-2.5v12L14 15.5z\"/><path d=\"M6 12h4\"/><path d=\"M20.5 9.5l1.5-.8M20.5 14.5l1.5.8M21 12h1.5\"/>" + _SVG_TAIL,
	},
	"battery": {
		"name": "Pile",
		"plural": "Piles",
		"icon": _SVG_HEAD + "<rect x=\"7\" y=\"4\" width=\"10\" height=\"17\" rx=\"1.5\"/><path d=\"M10 2.5h4\"/><path d=\"M12 8.5v4M10 10.5h4\"/><path d=\"M10 16.5h4\"/>" + _SVG_TAIL,
	},
	"key": {
		"name": "Clé",
		"plural": "Clés",
		"icon": _SVG_HEAD + "<circle cx=\"7\" cy=\"12\" r=\"3.6\"/><circle cx=\"7\" cy=\"12\" r=\"1.2\"/><path d=\"M10.6 12H21\"/><path d=\"M17 12v3M20 12v2.4\"/>" + _SVG_TAIL,
	},
}
const ORDER := ["flashlight", "battery", "key"]

var items := {}          # id -> count (> 0)
var notes: Array = []    # [{id, title, text, style}] in discovery order

func _ready() -> void:
	_emit()

func add(id: String, n := 1) -> void:
	if id == "" or n <= 0: return
	items[id] = int(items.get(id, 0)) + n
	_emit()

func remove(id: String, n := 1) -> bool:
	var c := int(items.get(id, 0))
	if c < n or n <= 0: return false
	if c - n > 0: items[id] = c - n
	else: items.erase(id)
	_emit()
	return true

func has(id: String) -> bool:
	return int(items.get(id, 0)) > 0

func count(id: String) -> int:
	return int(items.get(id, 0))

func list() -> Array:
	var ids: Array = []
	for k in items:
		if int(items[k]) > 0: ids.append(k)
	ids.sort_custom(func(a, b) -> bool: return _order(a) < _order(b))
	var out: Array = []
	for id in ids:
		var c := int(items[id])
		var def: Dictionary = ITEM_DEFS.get(id, {})
		var item_name: String = id
		if not def.is_empty(): item_name = def["plural"] if c > 1 else def["name"]
		out.append({"id": id, "name": item_name, "icon": def.get("icon", ""), "count": c})
	return out

## Adds (or refreshes) a readable note. Notes keep their discovery order.
func add_note(n: Dictionary) -> void:
	if n.is_empty(): return
	var note := {
		"id": str(n.get("id", "note%d" % (notes.size() + 1))),
		"title": str(n.get("title", "Note")),
		"text": str(n.get("text", "")),
		"style": str(n.get("style", "note")),
	}
	for i in notes.size():
		if notes[i].get("id") == note["id"]:
			notes[i] = note
			_emit()
			return
	notes.append(note)
	_emit()

func get_note(id: String) -> Dictionary:
	for n in notes:
		if n.get("id") == id: return n
	return {}

func clear() -> void:
	items.clear()
	notes.clear()
	_emit()

func emit_changed() -> void:
	_emit()

func _order(id: String) -> int:
	var i := ORDER.find(id)
	return 99 if i < 0 else i

func _emit() -> void:
	var l := list()
	var ui := Game.ui
	if ui != null and is_instance_valid(ui) and ui.has_method("set_inventory"):
		ui.call("set_inventory", l, notes)
	Events.inventory_changed.emit(l, notes)
