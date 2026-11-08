## World x gameplay integration test (SceneTree entry point). Runs the real scenes/main.tscn (world + gameplay Interaction
## and Puzzles + whatever player / entity / UI are present), aims the player camera at every interactable of the level and
## checks that the gameplay interaction ray resolves the right entry through the world's LAYER_INTERACT bodies.
##   godot --headless --fixed-fps 60 --path pc -s res://scripts/world/tests/interact_test.gd -- --autostart
## Prints "INTERACT TEST OK" (exit 0) or the failures (exit 1).
extends SceneTree

func _initialize() -> void:
	var script := load("res://scripts/world/tests/interact_test_driver.gd") as GDScript
	if script == null or not script.can_instantiate():
		printerr("FAIL: the interact test driver does not compile")
		quit(1)
		return
	var drv: Node = script.new()
	drv.name = "InteractTest"
	root.add_child(drv)
