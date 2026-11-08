## Audio module tool — regenerates res://default_bus_layout.tres from scripts/audio/buses.gd.
##   godot --headless --path pc -s res://scripts/audio/tools/make_bus_layout.gd
extends SceneTree

const Buses := preload("res://scripts/audio/buses.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame # let the autoloads enter the tree (clean exit)
	Buses.build()
	var layout := AudioServer.generate_bus_layout()
	var err := ResourceSaver.save(layout, Buses.LAYOUT_PATH)
	print("[audio] bus layout -> %s (%d buses, valid=%s) err=%d" % [Buses.LAYOUT_PATH, AudioServer.bus_count, Buses.is_valid(), err])
	# the Audio autoload is loading the sound library in threads: let it finish before quitting (clean exit)
	var audio := root.get_node_or_null("Audio")
	var guard := 0
	while audio != null and not audio.call("is_loaded") and guard < 600:
		await process_frame
		guard += 1
	quit(0 if err == OK else 1)
