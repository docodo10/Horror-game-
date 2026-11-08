## World module headless test (SceneTree entry point). Run from the repo root:
##   godot --headless --fixed-fps 60 --path pc -s res://scripts/world/tests/world_test.gd
## The driver (world_test_driver.gd) is loaded at runtime because a SceneTree script cannot reference the autoloads
## (Game, Events…) at compile time. Prints "WORLD TEST OK" (exit 0) or the failures (exit 1).
extends SceneTree

func _initialize() -> void:
	var script := load("res://scripts/world/tests/world_test_driver.gd") as GDScript
	if script == null or not script.can_instantiate():
		printerr("FAIL: the world test driver does not compile")
		quit(1)
		return
	var drv: Node = script.new()
	drv.name = "WorldTest"
	root.add_child(drv)
