## Animated openable (drawer, door, lid, lever...). Core owns it. Tweens `node` between closed/open local transforms.
class_name Handle
extends RefCounted

var id := ""
var node: Node3D = null              # the moving node (raycast target is its collision body child or a proxy)
var closed_xform := Transform3D()
var open_xform := Transform3D()
var is_open := false
var locked := false
var duration := 0.6
var sfx_open := ""
var sfx_close := ""
var contents: Node3D = null           # items parented here move with the drawer
var animating := false

func world_position() -> Vector3:
	return node.global_position if node else Vector3.ZERO

func open() -> void:
	if is_open or not node: return
	await _animate(open_xform, sfx_open)
	is_open = true

func close() -> void:
	if not is_open or not node: return
	await _animate(closed_xform, sfx_close)
	is_open = false

func toggle() -> void:
	if is_open: await close()
	else: await open()

func _animate(target: Transform3D, sfx: String) -> void:
	animating = true
	if sfx != "": Audio.play(sfx, {"position": world_position()})
	var tw := node.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(node, "transform", target, duration)
	await tw.finished
	animating = false
