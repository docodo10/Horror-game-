## STUB — gameplay module replaces it (ARCHITECTURE_PC.md §Interaction).
## Public API (keep): register(entry: Dictionary) -> void, unregister(id: String), current (Dictionary or null), busy: bool, activate(id) (await)
##   entry = {id, node: Node3D (anything under it with a CollisionObject3D on LAYER_INTERACT is a target), prompt: String or Callable,
##            enabled: Callable (optional), on_interact: Callable (may be a coroutine), hold: float seconds (optional), max_distance := 2.1}
extends Node

var entries := {}
var current = null
var busy := false

func register(e: Dictionary) -> void: entries[e.id] = e
func unregister(id: String) -> void: entries.erase(id)
func activate(id: String) -> void:
	if entries.has(id): await entries[id].on_interact.call()
