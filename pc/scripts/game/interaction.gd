## Interaction (gameplay module) — port of src/game/Interaction.js: camera-centre ray, prompt + hold ring, busy lock.
## Public API (keep): register(entry: Dictionary) -> Callable (calling it unregisters), unregister(id: String),
##   current (Dictionary or null), busy: bool, activate(id, force := false) -> bool (await)
##   entry = {id, node: Node3D (anything under it with a CollisionObject3D on LAYER_INTERACT is a target), prompt: String or Callable,
##            enabled: Callable (optional), on_interact: Callable (may be a coroutine), hold: float seconds or Callable (optional),
##            max_distance := 2.1}
## Additions (optional entry keys, same as the web version):
##   hold_prompt: String or Callable (text while holding), on_hold_start / on_hold_cancel: Callable (feedback: sound, noise),
##   when_hidden: bool (the only targets while the player hides; no ray), aliases: Array[String] (other `interact_id` tags that
##   resolve to this entry), auto_proxy := true (build an invisible LAYER_INTERACT box from the node's meshes when nothing
##   under the node can be hit — keeps the game playable whatever the world provides).
## Additions (members): reset() (cancel hold/lock, clear prompt — after being caught / on win), using_gamepad: bool (last input
##   device; the prompt key hint becomes "A"), target_body (last body the ray resolved, debug), flush_proxies().
## Ray: from Game.camera along -Z, mask LAYER_WORLD | LAYER_INTERACT, areas included. First hit wins: a body resolves to an entry
##   by walking up its ancestors to a registered node (most specific first, like the web `_entryFor`), else through its metadata
##   `interact_id` (tagged here at registration, or by the world). Bodies that are hidden or carry no enabled entry are transparent
##   when they are INTERACT-only or Area3D. A WORLD body blocks what lies behind it, but interact bodies CONTAINED in the first one
##   the ray enters stay reachable (furniture colliders are AABBs: the horse on the shelves, note 3 in the open cabinet, the key in
##   the box), plus OCCLUDER_SLACK for bodies flush with a surface. An entry nested under the first hit one (an item inside an open
##   drawer) wins when the ray reaches it within NEST_WINDOW.
extends Node

const DEFAULT_DISTANCE := 2.1
const RAY_INTERVAL := 1.0 / 30.0   # raycast at most 30x per second (+ immediately on a press)
const LOCK_TIMEOUT := 12.0         # safety: a never-settling on_interact releases the lock after this (s, no modal open)
const OCCLUDER_SLACK := 0.12       # m an interact body may sit behind the surface of a blocking WORLD collider
const MAX_CONTAINED_DEPTH := 0.5   # m: past this depth inside a furniture collider nothing counts as contained
const NEST_WINDOW := 0.45          # m to look past the first entry for a more specific (nested) one
const MAX_RAY_STEPS := 10
const LAYER_WORLD := 1
const LAYER_INTERACT := 2
const META_ID := &"interact_id"

var entries := {}                  # id -> entry Dictionary
var current = null                 # targeted entry (Dictionary) or null
var busy := false                  # true while an on_interact coroutine runs
var using_gamepad := false
var target_body: Object = null

var _by_node := {}                 # node instance id -> Array[entry] (registration order)
var _alias := {}                   # tag -> Array[entry id]
var _far := DEFAULT_DISTANCE
var _ray_t := 0.0
var _holding = null
var _hold_t := 0.0
var _lock_token := 0
var _lock_age := 0.0
var _need_release := false         # the interact button must be released before it can trigger again
var _shown_text := ""
var _shown_hold := -1.0
var _shown_key := ""
var _query := PhysicsRayQueryParameters3D.new()
var _exclude: Array[RID] = []
var _tag_index := {}               # world-provided tag -> Array[CollisionObject3D]
var _tag_index_built := false
var _proxy_queue: Array = []       # entry ids waiting for an auto proxy
var _proxy_flush_pending := false
var _unreachable: Array[String] = []
var _unreachable_logged := false
var _shape_boxes := {}             # Shape3D instance id -> local AABB (ray exit tests)
var _tagged := {}                  # body instance id -> instance id of the registered node whose id it carries

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_query.collide_with_areas = true
	_query.collide_with_bodies = true
	_query.collision_mask = LAYER_WORLD | LAYER_INTERACT
	Events.game_state.connect(_on_game_state)

# ------------------------------------------------------------------ registration

func register(e: Dictionary) -> Callable:
	var id := str(e.get("id", ""))
	if id == "":
		push_warning("[interaction] register: missing id")
		return func() -> void: pass
	var node = e.get("node")
	if node == null or not is_instance_valid(node) or not (node is Node3D):
		push_warning("[interaction] register: missing node for " + id)
		return func() -> void: pass
	if entries.has(id): unregister(id)
	var entry := {"id": id, "enabled": null, "hold": 0.0, "max_distance": DEFAULT_DISTANCE, "when_hidden": false, "auto_proxy": true}
	entry.merge(e, true)
	entry["id"] = id
	entries[id] = entry
	var key: int = (node as Node).get_instance_id()
	if not _by_node.has(key): _by_node[key] = []
	_by_node[key].append(entry)
	for a in entry.get("aliases", []):
		var s := str(a)
		if not _alias.has(s): _alias[s] = []
		_alias[s].append(id)
	_prepare_targets(entry)
	_recompute_far()
	return func() -> void: unregister(id)

func unregister(id: String) -> void:
	if not entries.has(id): return
	var entry: Dictionary = entries[id]
	entries.erase(id)
	var node = entry.get("node")
	if node != null and is_instance_valid(node):
		var key: int = (node as Node).get_instance_id()
		var list: Array = _by_node.get(key, [])
		for i in list.size():
			if is_same(list[i], entry):
				list.remove_at(i)
				break
		if list.is_empty(): _by_node.erase(key)
	for a in entry.get("aliases", []):
		var ids: Array = _alias.get(str(a), [])
		ids.erase(id)
		if ids.is_empty(): _alias.erase(str(a))
	_proxy_queue.erase(id)
	if is_same(_holding, entry): _cancel_hold()
	if is_same(current, entry): _set_current(null)
	_recompute_far()

func _recompute_far() -> void:
	var far := DEFAULT_DISTANCE
	for e in entries.values():
		far = maxf(far, float(e.get("max_distance", DEFAULT_DISTANCE)))
	_far = far

## Tags the bodies under the entry's node with `interact_id` and queues an auto proxy when nothing there can be hit.
func _prepare_targets(entry: Dictionary) -> void:
	if entry.get("when_hidden", false): return
	var node: Node3D = entry["node"]
	var bodies: Array = []
	_collect_bodies(node, bodies)
	for b in bodies:
		_tag(b as Node, node, entry["id"])
	if not bodies.is_empty() or _has_tagged_body(entry): return
	if entry.get("auto_proxy", true):
		_proxy_queue.append(entry["id"])
		if not _proxy_flush_pending:
			_proxy_flush_pending = true
			flush_proxies.call_deferred()
	else:
		_note_unreachable(entry["id"])

## Sets `interact_id` on a body: never over a tag the world set, and the deepest registered node wins whatever the
## registration order (a drawer registered before the item inside it does not keep the item's body).
func _tag(body: Node, owner_node: Node, id: String) -> void:
	var key := body.get_instance_id()
	if body.has_meta(META_ID) and not _tagged.has(key): return   # tagged by the world
	if _tagged.has(key):
		var prev = instance_from_id(_tagged[key])
		if prev != null and not (prev as Node).is_ancestor_of(owner_node): return
	body.set_meta(META_ID, id)
	_tagged[key] = owner_node.get_instance_id()

func _collect_bodies(n: Node, out: Array) -> void:
	if n is CollisionObject3D and ((n as CollisionObject3D).collision_layer & (LAYER_WORLD | LAYER_INTERACT)) != 0:
		out.append(n)
	for c in n.get_children():
		_collect_bodies(c, out)

func _has_tagged_body(entry: Dictionary) -> bool:
	if not _tag_index_built: _build_tag_index()
	if _tag_index.has(entry["id"]): return true
	for a in entry.get("aliases", []):
		if _tag_index.has(str(a)): return true
	return false

## One scan of the world for bodies the world tagged itself (metadata interact_id) outside the registered nodes.
func _build_tag_index() -> void:
	_tag_index_built = true
	var w := Game.world
	if w == null or not is_instance_valid(w): return
	var stack: Array[Node] = [w]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CollisionObject3D and n.has_meta(META_ID):
			var tags = n.get_meta(META_ID)
			for t in (tags if tags is Array or tags is PackedStringArray else [tags]):
				var s := str(t)
				if not _tag_index.has(s): _tag_index[s] = []
				_tag_index[s].append(n)
		for c in n.get_children(): stack.append(c)

## Builds the queued auto proxies (deferred so every entry is registered first: meshes of other registered nodes nested under a
## node — items inside a drawer — are left out of its box). Puzzles calls it right after registering everything.
func flush_proxies() -> void:
	_proxy_flush_pending = false
	var queue := _proxy_queue.duplicate()
	_proxy_queue.clear()
	for id in queue:
		if not entries.has(id): continue
		var entry: Dictionary = entries[id]
		var node = entry.get("node")
		if node == null or not is_instance_valid(node): continue
		if _make_proxy(node as Node3D, str(id)) == null: _note_unreachable(str(id))
	if not _unreachable.is_empty() and not _unreachable_logged:
		_unreachable_logged = true
		print("[interaction] nothing to aim at (no body, no mesh) for: ", ", ".join(_unreachable))

func _note_unreachable(id: String) -> void:
	if not _unreachable.has(id): _unreachable.append(id)

## Invisible box (LAYER_INTERACT only) fitted to the visible meshes under `node`, child of it so it follows drawers and lids.
## Built in the node's orthonormalised frame so the body never carries a (non-uniform) scale.
func _make_proxy(node: Node3D, id: String) -> StaticBody3D:
	if not node.is_inside_tree(): return null
	var frame := Transform3D(node.global_basis.orthonormalized(), node.global_position)
	var inv := frame.affine_inverse()
	var skip := {}
	for k in _by_node:
		if k != node.get_instance_id(): skip[k] = true
	var acc := {"has": false, "box": AABB()}
	_accumulate_aabb(node, inv, skip, acc, true)
	if not acc["has"]: return null
	var box: AABB = acc["box"]
	box = box.grow(0.01)
	var size := Vector3(maxf(box.size.x, 0.04), maxf(box.size.y, 0.04), maxf(box.size.z, 0.04))
	var body := StaticBody3D.new()
	body.name = "InteractProxy_" + id.replace(".", "_")
	body.collision_layer = LAYER_INTERACT
	body.collision_mask = 0
	body.set_meta(META_ID, id)
	body.set_meta(&"interact_proxy", true)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	node.add_child(body)
	body.global_transform = Transform3D(frame.basis, frame * box.get_center())
	return body

func _accumulate_aabb(n: Node, inv: Transform3D, skip: Dictionary, acc: Dictionary, root: bool) -> void:
	if not root and skip.has(n.get_instance_id()): return
	if n is Node3D and not (n as Node3D).visible: return
	if n is MeshInstance3D or n is CSGShape3D or n is MultiMeshInstance3D or n is SpriteBase3D or n is Label3D:
		var vi := n as VisualInstance3D
		var a := vi.get_aabb()
		if a.size != Vector3.ZERO:
			var t := inv * vi.global_transform
			for i in 8:
				var p: Vector3 = t * a.get_endpoint(i)
				if acc["has"]:
					var b: AABB = acc["box"]
					acc["box"] = b.expand(p)
				else:
					acc["box"] = AABB(p, Vector3.ZERO)
					acc["has"] = true
	for c in n.get_children():
		_accumulate_aabb(c, inv, skip, acc, false)

# ------------------------------------------------------------------ helpers

func _is_enabled(e: Dictionary) -> bool:
	var en = e.get("enabled")
	if en is Callable and (en as Callable).is_valid():
		if not (en as Callable).call(): return false
	return _text(e.get("prompt")) != ""

func _text(p) -> String:
	if p is Callable:
		p = (p as Callable).call() if (p as Callable).is_valid() else null
	if p == null: return ""
	return str(p)

func _hold_time(e: Dictionary) -> float:
	var h = e.get("hold", 0.0)
	if h is Callable: h = (h as Callable).call() if (h as Callable).is_valid() else 0.0
	if h is float or h is int: return maxf(0.0, float(h))
	return 0.0

func _call_opt(e: Dictionary, key: String) -> void:
	var f = e.get(key)
	if f is Callable and (f as Callable).is_valid(): (f as Callable).call()

func _modal_open() -> bool:
	var ui := Game.ui
	return ui != null and is_instance_valid(ui) and ui.has_method("is_modal_open") and ui.call("is_modal_open") == true

func _player_hidden() -> bool:
	var p := Game.player
	return p != null and is_instance_valid(p) and p.get(&"hidden") == true

## First enabled entry attached to `body` or one of its ancestors (most specific first), else through its interact_id tag.
func _entry_for(body: Object):
	var n := body as Node
	while n != null:
		var list = _by_node.get(n.get_instance_id())
		if list != null:
			for e in list:
				if not e.get("when_hidden", false) and _is_enabled(e): return e
		n = n.get_parent()
	if body.has_meta(META_ID):
		var tags = body.get_meta(META_ID)
		for t in (tags if tags is Array or tags is PackedStringArray else [tags]):
			var s := str(t)
			var ids: Array = [s]
			ids.append_array(_alias.get(s, []))
			for id in ids:
				var e = entries.get(id)
				if e != null and not e.get("when_hidden", false) and _is_enabled(e): return e
	return null

# ------------------------------------------------------------------ per-frame

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		if not using_gamepad: using_gamepad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		if using_gamepad: using_gamepad = false

func _process(delta: float) -> void:
	if busy:
		_lock_age += delta
		if _lock_age > LOCK_TIMEOUT and not _modal_open():
			push_warning("[interaction] lock timeout")
			_release(_lock_token)

	var player := Game.player
	var ent := Game.entity
	var cinematic: bool = (ent != null and is_instance_valid(ent) and ent.get(&"state") == "jumpscare") \
		or (player != null and is_instance_valid(player) and player.get(&"camera_override") == true and player.get(&"hidden") != true)
	var active: bool = Game.state == "playing" and not _modal_open() and not cinematic and not busy
	if not active:
		_cancel_hold()
		_set_current(null)
		_show_prompt("")
		return

	var down := Input.is_action_pressed("interact")
	if _need_release and not down: _need_release = false
	var pressed: bool = not _need_release and Input.is_action_just_pressed("interact")
	var held: bool = not _need_release and down

	_ray_t -= delta
	if pressed or _ray_t <= 0.0 or (current != null and not _is_enabled(current)):
		_ray_t = RAY_INTERVAL
		_set_current(_pick())

	var cur = current
	if cur == null:
		_cancel_hold()
		_show_prompt("")
		return

	var hold_time := _hold_time(cur)
	if _holding != null and (not is_same(_holding, cur) or hold_time <= 0.0): _cancel_hold()

	if hold_time > 0.0:
		if _holding == null and pressed:
			_holding = cur
			_hold_t = 0.0
			_call_opt(cur, "on_hold_start")
		if _holding != null:
			if not held:
				_cancel_hold()
			else:
				_hold_t += delta
				var k := minf(1.0, _hold_t / hold_time)
				var hp := _text(cur.get("hold_prompt"))
				_show_prompt(hp if hp != "" else _text(cur.get("prompt")), k)
				if k >= 1.0:
					_holding = null
					_hold_t = 0.0
					_run(cur)
				return
		_show_prompt(_text(cur.get("prompt")), 0.0)
		return

	_show_prompt(_text(cur.get("prompt")))
	if pressed: _run(cur)

func _pick():
	if _player_hidden():
		for e in entries.values():
			if e.get("when_hidden", false) and _is_enabled(e): return e
		return null
	var cam := Game.camera
	if cam == null or not is_instance_valid(cam) or not cam.is_inside_tree():
		cam = get_viewport().get_camera_3d() if get_viewport() else null
		if cam == null: return null
	var space := cam.get_world_3d().direct_space_state
	if space == null: return null
	var from := cam.global_position
	var dir := -cam.global_basis.z.normalized()
	_query.from = from
	_query.to = from + dir * _far
	_exclude.clear()
	_query.exclude = _exclude
	target_body = null
	var first = null                 # first entry the ray reached
	var first_d := 0.0
	var first_body: Object = null
	var best = null                  # most specific entry nested under `first` (or `first` itself)
	var best_d := 0.0
	var best_body: Object = null
	var limit := INF
	for step in MAX_RAY_STEPS:
		var hit := space.intersect_ray(_query)
		if hit.is_empty(): break
		var col: Object = hit.get("collider")
		var d := from.distance_to(hit.get("position", from))
		if d > limit: break
		_exclude.append(hit.get("rid"))
		_query.exclude = _exclude
		if col == null: continue
		if col is Node3D and not (col as Node3D).is_visible_in_tree(): continue
		var e = _entry_for(col)
		if e != null:
			if first == null:
				first = e; first_d = d; first_body = col
				best = e; best_d = d; best_body = col
				limit = minf(limit, d + NEST_WINDOW)
			elif _is_nested(e, best):
				best = e; best_d = d; best_body = col
			continue
		# CSG / GridMap colliders are not CollisionObject3D: read their layer generically. Areas never block.
		var layer = col.get(&"collision_layer")
		var solid: bool = not (col is Area3D) and layer != null and (int(layer) & LAYER_WORLD) != 0
		if not solid: continue                     # INTERACT-only body without an enabled entry: transparent
		if first == null and limit == INF:
			# first solid blocker: what it contains stays reachable (AABB furniture colliders), what lies behind it does not
			var exit_d := minf(_exit_distance(col, from, dir, d), d + MAX_CONTAINED_DEPTH)
			limit = maxf(d + OCCLUDER_SLACK, exit_d + 0.02)
	if best != null and best_d <= float(best.get("max_distance", DEFAULT_DISTANCE)):
		target_body = best_body
		return best
	if first != null and first_d <= float(first.get("max_distance", DEFAULT_DISTANCE)):
		target_body = first_body
		return first
	return null

## Distance along the (unit) ray at which it leaves `col`'s collision shapes (>= enter_d; enter_d when unknown).
func _exit_distance(col: Object, from: Vector3, dir: Vector3, enter_d: float) -> float:
	var out := enter_d
	if col is CollisionObject3D:
		for c in (col as Node).get_children():
			if c is CollisionShape3D and not (c as CollisionShape3D).disabled and (c as CollisionShape3D).shape != null:
				var box := _shape_aabb((c as CollisionShape3D).shape)
				if box.size != Vector3.ZERO: out = maxf(out, _ray_box_exit((c as Node3D).global_transform, box, from, dir))
	elif col is VisualInstance3D:   # CSG with collision
		out = maxf(out, _ray_box_exit((col as Node3D).global_transform, (col as VisualInstance3D).get_aabb(), from, dir))
	return out

func _shape_aabb(shape: Shape3D) -> AABB:
	var key := shape.get_instance_id()
	if _shape_boxes.has(key): return _shape_boxes[key]
	var box := AABB()
	if shape is BoxShape3D:
		var s: Vector3 = (shape as BoxShape3D).size
		box = AABB(-s * 0.5, s)
	else:
		var m := shape.get_debug_mesh()
		if m != null: box = m.get_aabb()
	_shape_boxes[key] = box
	return box

## Slab test in the box's local frame (affine map keeps the ray parameter = world distance). -1 when missed.
func _ray_box_exit(xf: Transform3D, box: AABB, from: Vector3, dir: Vector3) -> float:
	var inv := xf.affine_inverse()
	var o := inv * from
	var dv := inv.basis * dir
	var t_min := -INF
	var t_max := INF
	for axis in 3:
		var lo: float = box.position[axis]
		var hi: float = lo + box.size[axis]
		if absf(dv[axis]) < 1e-9:
			if o[axis] < lo or o[axis] > hi: return -1.0
			continue
		var t1 := (lo - o[axis]) / dv[axis]
		var t2 := (hi - o[axis]) / dv[axis]
		t_min = maxf(t_min, minf(t1, t2))
		t_max = minf(t_max, maxf(t1, t2))
	if t_max < t_min or t_max < 0.0: return -1.0
	return t_max

func _is_nested(inner: Dictionary, outer: Dictionary) -> bool:
	var a = inner.get("node")
	var b = outer.get("node")
	return a != null and b != null and is_instance_valid(a) and is_instance_valid(b) and (b as Node).is_ancestor_of(a as Node)

func _set_current(e) -> void:
	if is_same(current, e): return
	current = e

func _show_prompt(text: String, hold := -1.0) -> void:
	var hv := -1.0 if hold < 0.0 else roundf(hold * 50.0) / 50.0
	var key := "A" if using_gamepad else "E"
	if text == _shown_text and hv == _shown_hold and (text == "" or key == _shown_key): return
	_shown_text = text
	_shown_hold = hv
	_shown_key = key
	var ui := Game.ui
	if ui == null or not is_instance_valid(ui) or not ui.has_method("set_prompt"): return
	if text == "":
		ui.call("set_prompt", "", {})
		return
	var opts := {"key": key}
	if hv >= 0.0: opts["hold"] = hv
	ui.call("set_prompt", text, opts)

func _cancel_hold() -> void:
	if _holding == null: return
	var e: Dictionary = _holding
	_holding = null
	_hold_t = 0.0
	_call_opt(e, "on_hold_cancel")

func _on_game_state(s: String, _prev: String) -> void:
	if s != "playing":
		_cancel_hold()
		_set_current(null)
		_show_prompt("")

# ------------------------------------------------------------------ running entries

func _run(entry: Dictionary) -> void:
	if busy: return
	_lock_token += 1
	var token := _lock_token
	busy = true
	_lock_age = 0.0
	_set_current(null)
	_show_prompt("")
	var fn = entry.get("on_interact")
	if fn is Callable and (fn as Callable).is_valid():
		await (fn as Callable).call()
	_release(token)

func _release(token: int) -> void:
	if token != _lock_token: return
	busy = false
	_lock_age = 0.0
	_ray_t = 0.0
	_need_release = Input.is_action_pressed("interact")

## Run an entry by id (tests / QA / scripted). force = true ignores enabled(). Returns false if unknown, disabled or busy.
func activate(id: String, force := false) -> bool:
	var e = entries.get(id)
	if e == null: return false
	if not force and not _is_enabled(e): return false
	if busy: return false
	await _run(e)
	return true

func reset() -> void:
	_cancel_hold()
	_lock_token += 1
	busy = false
	_lock_age = 0.0
	_set_current(null)
	_show_prompt("")
