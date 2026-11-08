## Rendered preview of the garderie (needs a display: xvfb + Vulkan; see garderie_shot.sh which holds the machine-wide
## render lock). Assembles the real level + the garderie, a TEMPORARY preview environment (the look module owns the
## game's WorldEnvironment): SDFGI, SSIL, SSAO, SSR, glow, volumetric fog, AgX, depth of field; a stand-in ceiling
## light for the main room; a flashlight on the camera for the dark view.
##   godot --path pc --rendering-driver vulkan --resolution 960x540 -s res://scripts/garderie/tests/preview.gd \
##     -- --out=/abs/prefix --views=doorway,corridor,vestibule,hall,wavetop,ballpit,dark [--frames=40]
extends SceneTree

var _started := false

func _process(_dt: float) -> bool:
	if not _started:
		_started = true
		var scr: Script = load("res://scripts/garderie/tests/preview_driver.gd")
		if scr == null or not scr.can_instantiate():
			printerr("preview driver does not compile")
			quit(1)
			return false
		var drv: Node = scr.new()
		drv.name = "PreviewDriver"
		get_root().add_child(drv)
		drv.call("run")
	return false
