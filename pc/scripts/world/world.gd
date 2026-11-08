## World module (ARCHITECTURE_PC.md §4 World) — the basement level. Port of src/world/{World,Architecture,Props,ExtraProps}.js
## on top of the exporter's outputs: level.glb (every procedural mesh of the web build) + the ORIGINAL
## res://assets/models/*.glb instances placed with their exact web matrices (level_loader.gd), real physics
## (props_physics.gd), the 14 handles bound to the real moving nodes (props_handles.gd), items / clues / TV / hide spot,
## nav graph, power, clue digits, living props (fan, clocks, rocking chair, pull chain, smoke LED: props_anim.gd), dresser TV
## static (props_tv.gd), old CRT beat (props_crt.gd), nook fluorescent batten (props_nook.gd), reflection probes + live
## planar mirror (props_reflections.gd), material fixes (props_materials.gd). Placeholder lights + a fallback Environment
## only while scripts/world/lighting.gd (look module) provides none (props_fallback_lighting.gd).
##
## Public API (keep):
##   build(progress: Callable) -> void (await)        progress.call(0..1, text)
##   set_power(on: bool)   power: bool
##   handles: Dictionary[String, Handle]   (Handle = scripts/world/handle.gd: open()/close()/toggle() awaitable, is_open, locked, node, world_position())
##   items: Dictionary[String, Node3D]     clues: Dictionary[String, Node3D]   tv (Node with is_on, set_on(on), set_digit(d), screen_position)
##   hide_spots: Array[Dictionary]  ({id, door: Handle, hide_pos: Vector3, hide_yaw: float, exit_pos: Vector3})
##   nav: AStar3D over Layout.NAV_NODES/NAV_LINKS; nav_path(from, to) -> PackedVector3Array; nearest_nav_id(pos) -> int; random_nav_near(pos, r) -> Vector3
##   line_blocked(from: Vector3, to: Vector3) -> bool   (physics ray on the sight occluders, like the web lineBlocked)
##   ground_height_at(x, z, prev_y := NAN) -> float
##   lighting (Node: scripts/world/lighting.gd)  set_clue_digits(d: Dictionary)
##   reset_after_caught()
## Additions:
##   LAYER_SIGHT (16): sight-only occluder boxes (walls, ceiling slab, landing, doors, sofa / dresser / clock… sight boxes).
##     line_blocked() casts on it; LAYER_WORLD bodies are the movement AABBs (the stair railing and chairs do not block sight).
##   rock_chair(seconds := 6.0) (await: returns when the chair is still), props: {web name: Node3D} (instances by web name:
##   photoFrame, alarmClock, cassette, rockingChair, extra_gnome, extra_mirror, extra_oldTv… + level nodes such as codeNote),
##   meta (level_meta.json), ctx (level_nodes / instances), level_root, colliders [{body, shape, tag, enabled, min, max}],
##   occluders [StaticBody3D], floors {floor, nook_floor, ramp, landing, hall_floor}, nav_nodes {id: Vector3},
##   ground_probe(x, z, from_y := 6.0) -> float (physics ray down on LAYER_WORLD, NAN if nothing), tv.screen (MeshInstance3D),
##   crt (old CRT: flicker(delay)), nook_tube (level, set_level, level_changed, auto), reflections (probes, mirror_active,
##   refresh()), anim (fan_speed, rocking, clock_hours, kick_chain), upper_hall (Node3D, visible while the door is open),
##   code_note (Node3D on the box lid), built (bool)
## Debug args (after --): --world-open=id1,id2 (open handles instantly; "all"), --world-tv[=digit], --world-crt, --world-rock,
##   --world-hold (TV digit at full strength, CRT frozen in its snow: screenshots), --world-fallback (Layout level),
##   --world-log (build summary)
extends Node3D

const LevelLoader := preload("res://scripts/world/level_loader.gd")
const PhysicsBuilder := preload("res://scripts/world/props_physics.gd")
const HandleBuilder := preload("res://scripts/world/props_handles.gd")
const TVController := preload("res://scripts/world/props_tv.gd")
const OldCRT := preload("res://scripts/world/props_crt.gd")
const PropsAnim := preload("res://scripts/world/props_anim.gd")
const NookTube := preload("res://scripts/world/props_nook.gd")
const Reflections := preload("res://scripts/world/props_reflections.gd")
const Materials := preload("res://scripts/world/props_materials.gd")
const FallbackLighting := preload("res://scripts/world/props_fallback_lighting.gd")
const LightingScript := preload("res://scripts/world/lighting.gd")

const LAYER_WORLD := 1      # walls, floors, furniture (blocks movement + sight)
const LAYER_INTERACT := 2   # interactable trigger bodies (interaction ray only)
const LAYER_PLAYER := 4
const LAYER_ENTITY := 8
const LAYER_SIGHT := 16     # sight-only occluders (line_blocked)

const ITEM_IDS := ["flashlight", "battery1", "battery2", "key", "note1", "note2", "note3"]
const CLUE_IDS := ["duck", "horse", "clock", "tv"]

var power := true
var handles := {}
var items := {}
var clues := {}
var tv: Node = null
var hide_spots: Array = []
var nav := AStar3D.new()
var nav_ids := {}
var lighting: Node = null

var props := {}
var meta := {}
var ctx := {}
var level_root: Node3D = null
var colliders: Array = []
var occluders: Array = []
var floors := {}
var nav_nodes := {}
var anim: Node = null
var crt: Node = null
var nook_tube: Node3D = null
var reflections: Node3D = null
var upper_hall: Node3D = null
var code_note: Node3D = null
var built := false

var _physics_root: Node3D = null
var _sight_query := PhysicsRayQueryParameters3D.new()
var _ground_query := PhysicsRayQueryParameters3D.new()
var _nav_points: Array[Vector3] = []
var _nav_point_ids: Array[int] = []
var _clock_loop = null
var _started := false
var _args := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_sight_query.collision_mask = LAYER_SIGHT
	_sight_query.collide_with_areas = false
	_ground_query.collision_mask = LAYER_WORLD
	_ground_query.collide_with_areas = false

# =================================================================== build

func build(progress: Callable) -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var t0 := Time.get_ticks_msec()
	progress.call(0.0, "Chargement du sous-sol…")
	_set_fallback_environment()
	level_root = Node3D.new()
	level_root.name = "Level"
	add_child(level_root)
	var loader := LevelLoader.new()
	ctx = await loader.load_level(self, level_root, func(p: float, t: String) -> void: progress.call(p * 0.78, t))
	meta = ctx.get("meta", {})
	progress.call(0.8, "Physique du sous-sol…")
	await get_tree().process_frame
	_build_physics()
	progress.call(0.85, "Mécanismes…")
	handles = HandleBuilder.build(self, ctx)
	HandleBuilder.ensure_contract(self, handles)
	_bind_doors()
	_build_items_and_clues()
	_build_runtime_props()
	_build_interaction_bodies()
	_build_props_index()
	Materials.apply(ctx, handles)
	progress.call(0.92, "Lumières…")
	await get_tree().process_frame
	await _build_lighting()
	reflections = Reflections.new()
	add_child(reflections)
	reflections.setup(self, ctx)
	_build_nav()
	Events.game_state.connect(_on_game_state)
	Events.settings_changed.connect(_on_settings_changed)
	built = true
	_apply_debug_args()
	if _args.has("world-log") or Game.debug:
		print("[world] built in %d ms: %d instances, %d colliders, %d occluders, %d handles, %d items, %d clues, lighting=%s, generated=%s" % [
			Time.get_ticks_msec() - t0, ctx.get("instances", {}).size(), colliders.size(), occluders.size(), handles.size(),
			items.size(), clues.size(), lighting.name if lighting else "none", str(ctx.get("generated", false))])
	progress.call(1.0, "Prêt")

func _build_physics() -> void:
	_physics_root = Node3D.new()
	_physics_root.name = "Physics"
	add_child(_physics_root)
	colliders = PhysicsBuilder.build_colliders(_physics_root, meta)
	floors = PhysicsBuilder.build_floors(_physics_root)
	var sight := Node3D.new()
	sight.name = "Sight"
	_physics_root.add_child(sight)
	var door_pivots: Array = []
	for n in ["door_upstairs", "door_closet"]:
		var p = ctx.get("level_nodes", {}).get(n)
		if p is Node3D: door_pivots.append(p)
	occluders = PhysicsBuilder.build_occluders(sight, ctx, door_pivots)

## Door colliders (web): the upstairs door's box blocks while it is closed; the closet's swung-open leaf blocks while open.
func _bind_doors() -> void:
	var door_cols := {}
	for c in colliders:
		if c.tag != "door": continue
		var centre: Vector3 = (c.min + c.max) * 0.5
		var best := ""
		var bd := INF
		for id in ["door.upstairs", "door.closet"]:
			var h: Handle = handles.get(id)
			if h == null: continue
			var d := centre.distance_to(h.world_position())
			if d < bd:
				bd = d
				best = id
		if best == "": continue
		if not door_cols.has(best): door_cols[best] = {"closed": null, "open": null}
		door_cols[best]["closed" if c.enabled else "open"] = c.shape
	for id in door_cols:
		var h: Handle = handles[id]
		var closed_cs: CollisionShape3D = door_cols[id]["closed"]
		var open_cs: CollisionShape3D = door_cols[id]["open"]
		h.on_start = func(opening: bool) -> void:
			if opening and closed_cs != null: closed_cs.set_deferred("disabled", true)
			if not opening and open_cs != null: open_cs.set_deferred("disabled", true)
		h.on_settled = func(is_open_now: bool) -> void:
			if closed_cs != null: closed_cs.set_deferred("disabled", is_open_now)
			if open_cs != null: open_cs.set_deferred("disabled", not is_open_now)
	# upper hallway: visible only while the upstairs door is (even slightly) open
	upper_hall = ctx.get("level_nodes", {}).get("upperHall") as Node3D
	var door: Handle = handles.get("door.upstairs")
	if door != null and upper_hall != null:
		door.on_change = func(t: float) -> void: upper_hall.visible = t > 0.002

func _build_items_and_clues() -> void:
	for id in meta.get("items", {}):
		var n := LevelLoader.find(ctx, meta.items[id].get("ref"))
		if n != null: items[id] = n
	for k in meta.get("clues", {}):
		var n := LevelLoader.find(ctx, meta.clues[k])
		if n != null: clues[k] = n
	for id in ITEM_IDS:
		if not items.has(id):
			push_warning("[world] missing item %s: empty stand-in" % id)
			var o := Node3D.new()
			o.name = id
			level_root.add_child(o)
			items[id] = o
	for k in CLUE_IDS:
		if not clues.has(k):
			var o := Node3D.new()
			o.name = "clue_" + k
			level_root.add_child(o)
			clues[k] = o
	for hs in meta.get("hideSpots", []):
		var hp: Dictionary = hs.get("hidePos", {})
		var ep: Dictionary = hs.get("exitPos", {})
		var spot := {
			"id": String(hs.get("id", "closet")), "door": handles.get(String(hs.get("door", "door.closet"))),
			"hide_pos": Vector3(hp.get("x", -3.05), hp.get("y", 1.35), hp.get("z", -2.05)), "hide_yaw": float(hs.get("hideYaw", -PI / 2.0)),
			"exit_pos": Vector3(ep.get("x", -2.05), 0.0, ep.get("z", -2.05)),
			"minX": hs.get("minX"), "maxX": hs.get("maxX"), "minZ": hs.get("minZ"), "maxZ": hs.get("maxZ"), "doorSpec": hs.get("doorSpec"),
		}
		hide_spots.append(spot)
	if hide_spots.is_empty():
		var C: Dictionary = Layout.CLOSET
		hide_spots.append({"id": "closet", "door": handles.get("door.closet"),
			"hide_pos": Vector3(C.hidePos.x, C.hidePos.y, C.hidePos.z), "hide_yaw": float(C.hideYaw),
			"exit_pos": Vector3(C.exitPos.x, 0.0, C.exitPos.z), "minX": C.minX, "maxX": C.maxX, "minZ": C.minZ, "maxZ": C.maxZ})
	code_note = ctx.get("level_nodes", {}).get("codeNote") as Node3D

func _build_runtime_props() -> void:
	var anim_meta: Dictionary = meta.get("anim", {})
	# dresser TV
	var tv_meta: Dictionary = meta.get("tv", {}) if meta.get("tv") is Dictionary else {}
	var tvc := TVController.new()
	add_child(tvc)
	var tv_node := LevelLoader.find(ctx, tv_meta.get("object"))
	if tv_node == null: tv_node = clues.get("tv")
	tvc.setup(self, tv_node, LevelLoader.find(ctx, tv_meta.get("screen")) as MeshInstance3D, tv_meta)
	tv = tvc
	# living props
	anim = PropsAnim.new()
	add_child(anim)
	anim.setup(self, ctx)
	# old CRT in the nook
	var cm: Dictionary = anim_meta.get("oldCrt", {})
	crt = OldCRT.new()
	add_child(crt)
	crt.setup(self, LevelLoader.find(ctx, cm.get("tv")), LevelLoader.find(ctx, cm.get("screen")) as MeshInstance3D, cm)
	crt.on_kick = func() -> void: anim.kick_chain(0.09)
	# fluorescent batten
	nook_tube = NookTube.new()
	level_root.add_child(nook_tube)
	nook_tube.setup(self)

## LAYER_INTERACT bodies under every handle node, item, clue and the TV (ARCHITECTURE_PC.md §6), tagged interact_id.
func _build_interaction_bodies() -> void:
	var item_nodes: Array = items.values()
	var skip: Array = item_nodes.duplicate()
	for id in handles:
		var h: Handle = handles[id]
		if h.contents != null: skip.append(h.contents)
	# web hit proxies (lid, padlock, lever, batteries, key)
	var done := {}
	for p in meta.get("proxies", []):
		var owner = p.get("owner")
		if p.get("occluder", false) or p.get("interact", false) or not (owner is Dictionary): continue
		var parent := LevelLoader.find(ctx, p.get("parent"))
		var id := ""
		for iid in items:
			if items[iid] == parent: id = iid
		if id == "": id = String(owner.get("handle", owner.get("item", "")))
		if id == "" or done.has(id): continue
		if PhysicsBuilder.meta_proxy_box(ctx, p, id) != null: done[id] = true
	for id in handles:
		if done.has(id): continue
		var h: Handle = handles[id]
		if h.node == null or not h.node.is_inside_tree(): continue
		var grow := 0.03 if h.kind == "door" else 0.01
		if PhysicsBuilder.interact_box(h.node, id, skip, grow) != null: done[id] = true
	for id in items:
		if done.has(id): continue
		var it: Node3D = items[id]
		if it.is_inside_tree(): PhysicsBuilder.interact_box(it, id, [], 0.012, 0.035)
	for k in clues:
		var c: Node3D = clues[k]
		if c.is_inside_tree(): PhysicsBuilder.interact_box(c, k, [], 0.01, 0.04)

func _build_props_index() -> void:
	var inst: Dictionary = ctx.get("instances", {})
	for k in inst: props[k] = inst[k]
	var ln: Dictionary = ctx.get("level_nodes", {})
	for k in ["codeNote", "kidsRug", "note1", "note2", "remote", "vhsTapes", "smokeDetector", "thermostat", "lightSwitch",
			"toyBlocks", "crayons", "ball", "toyCar", "floorDrawing", "wallScribbles", "stairPhotos", "upperHall",
			"extra_mirror_glass", "extra_crt_screen", "fanBowl", "doorStrip", "door_upstairs", "door_closet"]:
		if ln.get(k) is Node3D: props[k] = ln[k]
	if nook_tube != null: props["nookTube"] = nook_tube

func _build_lighting() -> void:
	var before := find_children("*", "Light3D", true, false).size()
	var l := LightingScript.new()
	l.name = "Lighting"
	add_child(l)
	lighting = l
	if l.has_method("build"): await l.build(self)
	if find_children("*", "Light3D", true, false).size() <= before:
		# the look module's lighting.gd is still the stub: placeholder lights so the level is playable / readable
		var fb := FallbackLighting.new()
		fb.name = "FallbackLighting"
		add_child(fb)
		fb.build(self)
		lighting = fb

## Fallback Environment on the World3D (used only while no WorldEnvironment / camera environment exists).
func _set_fallback_environment() -> void:
	var w := get_world_3d()
	if w == null: return
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.52, 0.48, 0.44)
	e.ambient_light_energy = 0.16
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.0
	e.ssao_enabled = true
	e.ssao_radius = 0.8
	e.ssao_intensity = 1.6
	e.glow_enabled = true
	e.glow_intensity = 0.5
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 1.2
	w.fallback_environment = e

# =================================================================== runtime API

func set_power(on: bool) -> void:
	var was := power
	power = on
	if lighting != null and is_instance_valid(lighting) and lighting.has_method("set_power"): lighting.call("set_power", on)
	if anim != null: anim.set_power(on)
	if not on and tv != null and tv.get(&"is_on") == true: tv.call("set_on", false)
	var lever = handles.get("powerBox.lever")
	if lever != null and lever.has_method("follow_power"): lever.call("follow_power", on)
	if crt != null:
		if on and not was: crt.flicker(0.55)
		elif not on: crt.stop()
	if nook_tube != null: nook_tube.set_power(on)
	if reflections != null: reflections.set_power(on)
	Events.power_changed.emit(on)

func set_clue_digits(d: Dictionary) -> void:
	if d == null: return
	if anim != null: anim.set_clue_digits(d)
	if d.get("tv") != null and tv != null: tv.call("set_digit", d["tv"])

## Rocks the rocking chair by itself for `seconds` (scare beat); returns when it is still again.
func rock_chair(seconds := 6.0) -> void:
	if anim != null: await anim.rock(seconds)

func ground_height_at(x: float, z: float, prev_y := NAN) -> float:
	return Layout.ground_height_at(x, z, prev_y)

## Physics probe: height of the first LAYER_WORLD surface under (x, from_y, z), NAN when nothing is hit.
func ground_probe(x: float, z: float, from_y := 6.0) -> float:
	if not is_inside_tree(): return NAN
	_ground_query.from = Vector3(x, from_y, z)
	_ground_query.to = Vector3(x, -2.0, z)
	var hit := get_world_3d().direct_space_state.intersect_ray(_ground_query)
	return (hit.position as Vector3).y if not hit.is_empty() else NAN

## Line of sight against the sight occluders (web lineBlocked: stops 5 cm short of `to`).
func line_blocked(from: Vector3, to: Vector3) -> bool:
	var dir := to - from
	var dist := dir.length()
	if dist <= 0.05 or not is_inside_tree(): return false
	_sight_query.from = from
	_sight_query.to = from + dir * ((dist - 0.05) / dist)
	return not get_world_3d().direct_space_state.intersect_ray(_sight_query).is_empty()

## Nearest nav node (prefers the same floor: horizontal distance + 3 × height difference, like the web).
func nearest_nav_id(pos: Vector3) -> int:
	var best := -1
	var bd := INF
	for i in _nav_points.size():
		var p := _nav_points[i]
		var d := Vector2(p.x - pos.x, p.z - pos.z).length() + absf(p.y - pos.y) * 3.0
		if d < bd:
			bd = d
			best = _nav_point_ids[i]
	return best

## A* path between two world positions: nav node positions, then `to`.
func nav_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var a := nearest_nav_id(from)
	var b := nearest_nav_id(to)
	var p := PackedVector3Array()
	if a >= 0 and b >= 0: p = nav.get_point_path(a, b)
	p.append(to)
	return p

## Random nav node position within `r` of pos (lower floor only by default; any lower node when none is close).
func random_nav_near(pos: Vector3, r := 3.0, lower_only := true) -> Vector3:
	var c: Array[Vector3] = []
	for p in _nav_points:
		if (not lower_only or p.y < 1.0) and Vector2(p.x - pos.x, p.z - pos.z).length() <= r: c.append(p)
	if c.is_empty():
		for p in _nav_points:
			if p.y < 1.0: c.append(p)
	return c.pick_random() if not c.is_empty() else pos

func reset_after_caught() -> void:
	for id in ["door.upstairs", "door.closet"]:
		var h: Handle = handles.get(id)
		if h != null: h.set_state(false)      # snaps shut, keeps the upstairs door's `locked` flag
	if anim != null: anim.stop_rocking()
	if crt != null: crt.stop()
	if lighting != null and is_instance_valid(lighting) and lighting.has_method("reset_after_caught"): lighting.call("reset_after_caught")

# =================================================================== internals

func _build_nav() -> void:
	nav.clear()
	nav_ids.clear()
	nav_nodes.clear()
	_nav_points.clear()
	_nav_point_ids.clear()
	for id in Layout.NAV_NODES:
		var n: Dictionary = Layout.NAV_NODES[id]
		var y := float(Layout.UPPER.floorY) if n.get("upper", false) else Layout.ground_height_at(n.x, n.z)
		var i := nav_ids.size()
		var p := Vector3(n.x, y, n.z)
		nav_ids[id] = i
		nav_nodes[id] = p
		nav.add_point(i, p)
		_nav_points.append(p)
		_nav_point_ids.append(i)
	for link in Layout.NAV_LINKS:
		if nav_ids.has(link[0]) and nav_ids.has(link[1]): nav.connect_points(nav_ids[link[0]], nav_ids[link[1]])

func _on_game_state(s: String, _prev: String) -> void:
	if s != "playing" or _started: return
	_started = true
	var ac = props.get("alarmClock")
	if ac is Node3D and (ac as Node3D).is_inside_tree():
		_clock_loop = Audio.loop("clock_tick", {"position": (ac as Node3D).global_position, "volume_db": linear_to_db(0.45)})
	if reflections != null: reflections.refresh(1.0)

func _on_settings_changed(key: String, value: Variant) -> void:
	if key == "quality" and reflections != null: reflections.set_quality(str(value))

func _apply_debug_args() -> void:
	if _args.has("world-open"):
		var ids: Array = handles.keys() if _args["world-open"] == "all" else Array(String(_args["world-open"]).split(","))
		for id in ids:
			var h: Handle = handles.get(id)
			if h != null and id != "powerBox.lever": h.set_state(true)
	var hold := _args.has("world-hold")
	if _args.has("world-tv"):
		if _args["world-tv"] != "1": tv.call("set_digit", _args["world-tv"])
		tv.set(&"hold_digit", hold)
		tv.call("set_on", true)
	if _args.has("world-crt") and crt != null:
		crt.set(&"hold", hold)
		crt.flicker(0.3)
	if _args.has("world-rock"): rock_chair(30.0)
