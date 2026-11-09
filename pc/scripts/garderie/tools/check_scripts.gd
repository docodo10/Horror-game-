## Compiles every garderie script (parse / type errors) without running anything:
##   godot --headless --path pc -s res://scripts/garderie/tools/check_scripts.gd
extends SceneTree

func _initialize() -> void:
	var dirs := ["res://scripts/garderie", "res://scripts/garderie/tests", "res://scripts/garderie/tools"]
	var bad := 0
	for d in dirs:
		for f in DirAccess.get_files_at(d):
			if not f.ends_with(".gd") or f == "check_scripts.gd":
				continue
			var path: String = d + "/" + f
			var s := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Script
			if s == null or not s.can_instantiate():
				bad += 1
				printerr("BAD ", path)
			else:
				print("ok  ", path)
	for f in DirAccess.get_files_at("res://shaders"):
		if f.begins_with("garderie_") and f.ends_with(".gdshader"):
			var sh := load("res://shaders/" + f) as Shader
			print("ok  ", f) if sh != null and sh.code != "" else printerr("BAD ", f)
	print("SCRIPTS %s" % ("OK" if bad == 0 else "FAILED"))
	quit(0 if bad == 0 else 1)
