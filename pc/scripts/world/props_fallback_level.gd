## Fallback level (world module): only used when res://assets/generated/ (exporter outputs) is missing or unusable.
extends RefCounted

func build(host: Node, parent: Node3D, progress: Callable) -> Dictionary:
	progress.call(1.0, "Sous-sol (secours)…")
	await host.get_tree().process_frame
	var level := Node3D.new()
	level.name = "FallbackLevel"
	parent.add_child(level)
	return {"meta": {}, "level": level, "instances": {}, "level_nodes": {}, "shadow_casters": null, "errors": [], "generated": false}
