## Garderie inside the REAL game: runs scenes/main.tscn (world, player, entity, interaction, puzzles, audio, UI as
## they are in this branch), adds the Garderie the way main.gd will (Garderie.new() + add_child + await build(Game.world))
## and drives it through the real systems: interactables registered with Game.interaction, the door opened through
## the interaction, the player teleported onto every floor level, both slide rides (camera_override, landing on the
## hall floor, noise 0.8), hiding in the tunnel and getting out, the ball pit. Fails on any error logged by the garderie.
##   godot --headless --path pc --fixed-fps 60 -s res://scripts/garderie/tests/test_garderie_game.gd -- --autostart
extends SceneTree

class ErrLog extends Logger:
	var errors: Array[String] = []
	var mutex := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		if error_type == 1:
			return
		mutex.lock()
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
		var scr: Script = load("res://scripts/garderie/tests/garderie_game_driver.gd")
		if scr == null or not scr.can_instantiate():
			printerr("GARDERIE GAME TEST FAILED: driver does not compile")
			quit(1)
			return false
		create_timer(400.0).timeout.connect(func() -> void:
			printerr("GARDERIE GAME TEST FAILED: timeout")
			quit(1))
		var drv: Node = scr.new()
		drv.name = "GarderieGameDriver"
		get_root().add_child(drv)
		drv.call("run", _log)
	return false
