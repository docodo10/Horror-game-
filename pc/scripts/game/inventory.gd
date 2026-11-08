## STUB — gameplay module replaces it. Items: "flashlight", "battery", "key". Notes tracked separately.
## Public API (keep): add(id, n := 1), remove(id, n := 1) -> bool, has(id) -> bool, count(id) -> int, list() -> Array[{id, name, count}],
##   add_note({id, title, text, style}), notes: Array. Emits Events.inventory_changed.
extends Node

var items := {}
var notes: Array = []

func add(id: String, n := 1) -> void: items[id] = items.get(id, 0) + n; _emit()
func remove(id: String, n := 1) -> bool:
	if items.get(id, 0) < n: return false
	items[id] -= n; _emit(); return true
func has(id: String) -> bool: return items.get(id, 0) > 0
func count(id: String) -> int: return items.get(id, 0)
func list() -> Array:
	var out := []
	for k in items: if items[k] > 0: out.append({"id": k, "name": k, "count": items[k]})
	return out
func add_note(n: Dictionary) -> void: notes.append(n); _emit()
func _emit() -> void: Events.inventory_changed.emit(list(), notes)
