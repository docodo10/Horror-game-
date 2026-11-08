## Runs the game flow (main_like.gd = scenes/main.gd's order) as the current scene. Usage:
##   godot --headless --path pc --quit-after 900 -s res://scripts/game/tests/main_runner.gd -- --autostart [--stage=code]
extends SceneTree

func _initialize() -> void:
	var main := Node3D.new()
	main.name = "Main"
	main.process_mode = Node.PROCESS_MODE_ALWAYS
	main.set_script(load("res://scripts/game/tests/main_like.gd"))
	root.add_child(main)
	current_scene = main
