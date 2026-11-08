## Gameplay scenario test (SceneTree script). Run from the repo root:
##   godot --headless --path pc --fixed-fps 60 -s res://scripts/game/tests/test_gameplay.gd
## Prints "[test] PASS ..." and exits 0, or lists the failures and exits 1.
## The driver is loaded at runtime because a SceneTree script cannot reference the autoloads (Game, Events...) at compile time.
extends SceneTree

func _initialize() -> void:
	var script := load("res://scripts/game/tests/gameplay_test_driver.gd") as GDScript
	if script == null or not script.can_instantiate():
		printerr("[test] FAIL: the test driver does not compile")
		quit(1)
		return
	var drv: Node = script.new()
	drv.name = "GameplayTest"
	root.add_child(drv)
