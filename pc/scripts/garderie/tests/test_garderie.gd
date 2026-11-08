## Garderie SceneTree test: assembles the REAL exported level (garderie_test_world.gd: MetaUtil.assemble + the
## world's colliders) + Garderie.build(), then checks the doorway (meshes cut, rays through the opening, blocked
## beside it), floor heights every 0.5 m from the main room to the far end of the hall, player-capsule clearance
## along the way, every nav link walkable (La Gardienne's capsule), the slide rides ending on the floor, the hide
## spot, interactables, build time, and that nothing logged an error.
##   godot --headless --path pc -s res://scripts/garderie/tests/test_garderie.gd      -> "GARDERIE TEST OK" (exit 0)
## (A SceneTree script cannot reference the autoloads at compile time: the checks live in garderie_test_driver.gd,
## loaded at runtime.)
extends SceneTree

class ErrLog extends Logger:
	var errors: Array[String] = []
	var warnings := 0
	var mutex := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		mutex.lock()
		if error_type == 1:
			warnings += 1
		else:
			errors.append("%s:%d %s %s %s" % [file, line, function, code, rationale])
		mutex.unlock()
	func _log_message(_message: String, _error: bool) -> void:
		pass

var _log := ErrLog.new()
var _started := false

func _initialize() -> void:
	OS.add_logger(_log)

func _process(_dt: float) -> bool:
	if not _started:
		_started = true
		var scr: Script = load("res://scripts/garderie/tests/garderie_test_driver.gd")
		if scr == null or not scr.can_instantiate():
			printerr("GARDERIE TEST FAILED: driver does not compile")
			quit(1)
			return false
		create_timer(240.0).timeout.connect(func() -> void:
			printerr("GARDERIE TEST FAILED: timeout")
			quit(1))
		var drv: Node = scr.new()
		drv.name = "GarderieTestDriver"
		get_root().add_child(drv)
		drv.call("run", self, _log)
	return false
