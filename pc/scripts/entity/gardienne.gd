## STUB — entity module replaces it (ARCHITECTURE_PC.md §Gardienne).
## Public API (keep): build() (await), state: String, fear: float, active: bool, root: Node3D,
##   summon(target: Vector3, reason := ""), set_aggression(level: int), set_enabled(on: bool), reset_after_caught()
## Signals via Events: entity_state, entity_spotted, entity_caught. Listens: Events.noise, Events.player_hide.
extends Node3D

var state := "dormant"
var fear := 0.0
var active := false
var root := Node3D.new()

func build() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(root); root.visible = false

func summon(_target: Vector3, _reason := "") -> void: pass
func set_aggression(_l: int) -> void: pass
func set_enabled(_on: bool) -> void: pass
func reset_after_caught() -> void: state = "dormant"; active = false
