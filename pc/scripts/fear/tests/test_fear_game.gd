## Fear module inside the REAL game: runs scenes/main.tscn (world, garderie, player, entity, interaction, puzzles, audio,
## UI as they are in this branch), adds the FearDirector exactly the way main.gd will, then forces every scare of the
## repertoire through the real systems: the glimpses through the real entity (top of the stairs, garderie corridor,
## dark doorway found by the torch, outside the closet louvers while hiding), the physics fake-outs (box off a shelf,
## ball down the stairs), the house (door handle + strip shadow, rocking chair, old CRT, bulb pop, ceiling run...), and
## a real jumpscare -> caught -> night 2 (layers, slow motion, silence, recovery). Fails on any error logged.
##   godot --headless --path pc --fixed-fps 60 -s res://scripts/fear/tests/test_fear_game.gd -- --autostart
extends SceneTree

class ErrLog extends Logger:
	var errors: Array[String] = []
	var mutex := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		if error_type == 1:
			return   # warnings
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
		var scr: Script = load("res://scripts/fear/tests/fear_game_driver.gd")
		if scr == null or not scr.can_instantiate():
			printerr("FEAR GAME TEST FAILED: driver does not compile")
			quit(1)
			return false
		create_timer(420.0).timeout.connect(func() -> void:
			printerr("FEAR GAME TEST FAILED: timeout")
			quit(1))
		var drv: Node = scr.new()
		drv.name = "FearGameDriver"
		get_root().add_child(drv)
		drv.call("run", _log)
	return false
