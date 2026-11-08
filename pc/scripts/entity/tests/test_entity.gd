## La Gardienne AI test (SceneTree script). Run from the repo root:
##   godot --headless --path pc --fixed-fps 60 -s res://scripts/entity/tests/test_entity.gd [-- --entity-log]
## Prints the state timeline of each scenario and "[entity-test] PASS n checks" (exit 0), or the failures (exit 1).
## The driver is loaded at runtime because a SceneTree script cannot reference the autoloads (Game, Events...) at compile time.
extends SceneTree

func _initialize() -> void:
	var script := load("res://scripts/entity/tests/entity_test_driver.gd") as GDScript
	if script == null or not script.can_instantiate():
		printerr("[entity-test] FAIL: the test driver does not compile")
		quit(1)
		return
	var drv: Node = script.new()
	drv.name = "EntityTest"
	root.add_child(drv)
