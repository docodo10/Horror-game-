## La Gardienne lookdev renders (SceneTree script; needs a renderer: xvfb + Vulkan, not --headless). From the repo root:
##   pc/scripts/entity/tests/lookdev.sh /abs/out_prefix lit,lit_close,lit_side,dark,dark_close,jump,jump_lit [frames] [--fog]
## (the wrapper holds the machine-wide render lock of tools/shot.cjs / pc/tools/godot_shot.sh)
extends SceneTree

func _initialize() -> void:
	var script := load("res://scripts/entity/tests/lookdev_driver.gd") as GDScript
	if script == null or not script.can_instantiate():
		printerr("[lookdev] the driver does not compile")
		quit(1)
		return
	var drv: Node = script.new()
	drv.name = "Lookdev"
	root.add_child(drv)
