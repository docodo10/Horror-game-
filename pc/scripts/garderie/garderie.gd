## La garderie "Les Petits Soleils": an abandoned home-daycare soft-play area under the house, reached through a new
## doorway in the main room's west wall (ARCHITECTURE_PC.md §7). Original design: old basement corridor → vestibule
## (cubbies, sign-in counter, notice boards) → landing and six steps down → a vast soft-play hall with a 3-level padded
## play frame, a 4-lane wave slide, a spiral tube slide, a ball pit, party tables and a faded mural.
##
## Public API (contract):
##   build(world) -> void (await)   builds everything, carves the doorway through the room (meshes, colliders,
##                                  occluders of whatever `world` built), adds colliders / lights / interactables.
##                                  Works with the real world, the stub world or no world (needs only a Node3D parent).
##   nav_nodes: Dictionary          id -> Vector3 (ground level) for La Gardienne's AStar3D
##   nav_links: Array               [[a, b], ...] (includes gd_door <-> stairsBottom / swCorner in the main room)
##   hide_spots: Array              [{id, door: null, hide_pos, hide_yaw, exit_pos, kind, check_pos}] (world.hide_spots shape)
## Extra API:
##   ground_height_at(x, z, prev_y := NAN) -> float   floor of the area (NAN outside) — world.ground_height_at should
##                                  delegate to it for x < -3.7 (the hall floor is 1.05 m below the house floor)
##   surface_at(pos) -> String      concrete | foam | vinyl | wood (footstep surface request for the player module)
##   door: Handle                   the old door (open()/close()/toggle() awaitable, is_open); door_node: Node3D
##   recarve() -> Dictionary        re-cuts the doorway (call after a module rebuilt the room meshes)
##   set_power(on) / power          lights follow the house power (SORTIE signs stay lit on battery)
##   set_light_scale(k)             global multiplier of the area's light energies (look module tuning)
##   ride(slide_id) -> void (await) camera ride down "wave" (lane 2) or "spiral"; ride_active: bool
##   in_area(pos) -> bool, in_ball_pit: bool, stats: Dictionary (build ms, triangles, lights, draw calls estimate)
##   reset_after_caught()           cancels a ride, resets scares
## Calls defensively (all optional): Game.interaction.register, Game.player (camera_override, teleport, enter_hide,
##   exit_hide, speed_scale), Game.entity.state, Audio.play/loop (names checked against the manifest), Events.noise.
class_name Garderie
extends Node3D

const GL := preload("res://scripts/garderie/garderie_layout.gd")
const Carve := preload("res://scripts/garderie/garderie_carve.gd")
const Ctx := preload("res://scripts/garderie/garderie_ctx.gd")
const Mats := preload("res://scripts/garderie/garderie_mats.gd")
const Shell := preload("res://scripts/garderie/garderie_shell.gd")
const Play := preload("res://scripts/garderie/garderie_play.gd")
const Props := preload("res://scripts/garderie/garderie_props.gd")
const Ride := preload("res://scripts/garderie/garderie_ride.gd")

const LAYER_WORLD := 1
const LAYER_INTERACT := 2
const LAYER_PLAYER := 4
const LAYER_ENTITY := 8
const AJAR := 0.38
const MANIFEST := "res://assets/audio/manifest.json"
## Sounds wanted by the garderie -> fallbacks from the current manifest (first existing name wins).
const SFX := {
	"slide_whoosh": ["slide_whoosh", "wind_outside"],
	"slide_squeak": ["slide_squeak", "stair_creak"],
	"slide_land": ["slide_land", "land_thump"],
	"ball_rustle": ["ballpit_rustle", "cloth_move"],
	"ball_bounce": ["ball_bounce", "bump"],
	"door_open": ["door_creak_open"],
	"door_close": ["door_close"],
	"fluo_buzz": ["fluo_buzz", "light_buzz"],
	"fluo_pop": ["light_pop"],
	"giggle": ["giggle"],
	"hum": ["lullaby_hum"],
	"whisper": ["whisper"],
	"hall_tone": ["hall_tone", "room_tone"],
}

var nav_nodes := {}
var nav_links := []
var hide_spots := []
var door = null
var door_node: Node3D = null
var power := true
var light_scale := 1.0
var built := false
var build_ms := 0.0
var carve_report := {}
var stats := {}
var ride_active := false
var in_ball_pit := false
var ctx = null

var _world: Node = null
var _entries: Array = []
var _registered_with: Node = null
var _sounds := {}
var _sfx_names := {}
var _zone := ""
var _zone_t := 0.0
var _flicker: Array = []          # [{light, emit, base, t, phase}]
var _scare_t := 35.0
var _pit_noise_t := 0.0
var _pit_area: Area3D = null
var _balls_mat: ShaderMaterial = null
var _ride: Node = null
var _buzz_handles: Array = []
var _dead_tube := -1
var _rng := RandomNumberGenerator.new()

# ====================================================================== build

func build(world = null) -> void:
	var t0 := Time.get_ticks_usec()
	if name == "" or name.begins_with("@"):
		name = "Garderie"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_world = world
	_rng.seed = 1997
	_load_sound_names()
	ctx = Ctx.new()
	ctx.root = self
	ctx.mats = Mats.new()
	carve_report = recarve()
	var tg := Time.get_ticks_usec()
	Shell.build(ctx)
	Play.build(ctx)
	Props.build(ctx)
	if not (carve_report.get("moved", []) as Array).any(func(n): return String(n).to_lower().contains("switch")):
		_switch_plate(ctx.kit("door"))
	var tris: int = ctx.commit_all({
		"trusses": {"no_shadow": ["steel"]},
		"fixtures": {"no_shadow": ["enamel", "metal", "fluo_on", "fluo_dead"]},
		"balls": {"no_shadow": ["balls"]},
		"props_v": {"vis_end": 28.0},
		"props_h": {"vis_end": 40.0},
		"play_small": {"vis_end": 45.0, "no_shadow": ["metal"]},
	})
	var tgeo := Time.get_ticks_usec()
	_env_nodes()
	_setup_door()
	_setup_nav()
	_setup_hide()
	_setup_slides()
	_setup_pit()
	_setup_flicker()
	_register_or_wait()
	set_power(_world_power())
	if Events.power_changed.is_connected(set_power) == false:
		Events.power_changed.connect(set_power)
	built = true
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	stats = {
		"build_ms": build_ms, "carve_ms": (tg - t0) / 1000.0, "geometry_ms": (tgeo - tg) / 1000.0, "triangles": tris,
		"lights": ctx.lights.size(), "shadowed_lights": ctx.lights.filter(func(l): return (l.light as Light3D).shadow_enabled).size(),
		"mesh_instances": find_children("*", "MeshInstance3D", true, false).size(),
		"multimesh_instances": find_children("*", "MultiMeshInstance3D", true, false).size(),
		"missing_textures": ctx.mats.missing,
	}
	_update_zone(true)
	_debug_args()

## Re-cuts the doorway through every mesh / collider / occluder of the room (idempotent).
func recarve() -> Dictionary:
	var search: Node = null
	if _world is Node and is_instance_valid(_world):
		search = (_world as Node).get_parent() if (_world as Node).get_parent() != null else _world
	elif get_parent() != null:
		search = get_parent()
	if search == null:
		return {}
	var mesh_box := AABB(GL.CARVE_MIN, GL.CARVE_MAX - GL.CARVE_MIN)
	var cut_box := AABB(GL.CUT_MIN, GL.CUT_MAX - GL.CUT_MIN)
	var moved := _relocate_wall_fixtures(search)
	var rep := Carve.carve(search, self, mesh_box, cut_box)
	rep["moved"] = moved
	return rep

## Small fixtures flush on the west wall where the doorway opens (the web level's light switch at the foot of the
## stairs and its hand-grime decal) slide north beside the new door casing instead of being cut in half.
func _relocate_wall_fixtures(search: Node) -> Array:
	var moved: Array = []
	var zmax := float(GL.DOOR.z0) - 0.085
	for n in search.find_children("*", "Node3D", true, false):
		var nd := n as Node3D
		if nd == null or is_ancestor_of(nd) or nd == self:
			continue
		var ab := _node_aabb(nd)
		if ab.size == Vector3.ZERO or ab.size.length() > 0.45:
			continue
		if ab.position.x < -3.53 or ab.end.x > -3.46 or ab.end.z < float(GL.DOOR.z0) or ab.position.z > float(GL.DOOR.z1) or ab.position.y > float(GL.DOOR.h):
			continue
		# move the outermost small ancestor only
		var p := nd.get_parent() as Node3D
		if p != null and p != search and _node_aabb(p).size.length() <= 0.45 and _node_aabb(p).size != Vector3.ZERO:
			continue
		var dz := zmax - ab.end.z
		nd.global_position += Vector3(0.0, 0.0, dz)
		moved.append(String(nd.name))
	return moved

## A basement door always has its switch: plate on the room side, stair side of the casing (when the level's own
## switch was not found to be moved there).
func _switch_plate(k) -> void:
	var z1 := float(GL.DOOR.z0) - 0.085
	k.box("plastic", Vector3(-3.5, 1.165, z1 - 0.07), Vector3(-3.492, 1.28, z1), Color(0.92, 0.9, 0.84))
	k.box("plastic", Vector3(-3.492, 1.205, z1 - 0.042), Vector3(-3.482, 1.24, z1 - 0.028), Color(0.95, 0.94, 0.9))

static func _node_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var list: Array = [n]
	list.append_array(n.find_children("*", "VisualInstance3D", true, false))
	for v in list:
		var vi := v as VisualInstance3D
		if vi == null:
			continue
		var ab := vi.global_transform * vi.get_aabb()
		if first:
			out = ab
			first = false
		else:
			out = out.merge(ab)
	return out

func _world_power() -> bool:
	if _world is Object and is_instance_valid(_world):
		var p: Variant = (_world as Object).get("power")
		if p is bool:
			return p
	return true

## Reflection probes (box projected), dusty fog volume, occluders, the hall's ambient tone.
func _env_nodes() -> void:
	var probes := [
		["HallProbe", AABB(Vector3(GL.HALLB.x0, GL.HALL, GL.HALLB.z0), Vector3(GL.HALLB.x1 - GL.HALLB.x0, GL.HALLB.roof - GL.HALL, GL.HALLB.z1 - GL.HALLB.z0)), Vector3(-26.0, 1.4, 1.0)],
		["VestProbe", AABB(Vector3(GL.VEST.x0, 0.0, GL.VEST.z0), Vector3(GL.VEST.x1 - GL.VEST.x0, GL.VEST.ceil, GL.VEST.z1 - GL.VEST.z0)), Vector3(-14.1, 1.5, 2.1)],
		["CorrProbe", AABB(Vector3(GL.CORR.x0, 0.0, GL.CORR.z0), Vector3(GL.CORR.x1 - GL.CORR.x0, GL.CORR.ceil, GL.CORR.z1 - GL.CORR.z0)), Vector3(-7.4, 1.4, 2.1)],
	]
	for p in probes:
		var rp := ReflectionProbe.new()
		rp.name = p[0]
		var ab: AABB = p[1]
		rp.position = p[2]
		rp.size = ab.size
		rp.origin_offset = Vector3.ZERO
		rp.position = ab.get_center()
		rp.origin_offset = (p[2] as Vector3) - ab.get_center()
		rp.box_projection = true
		rp.interior = true
		rp.enable_shadows = false
		rp.update_mode = ReflectionProbe.UPDATE_ONCE
		rp.intensity = 0.9
		rp.blend_distance = 0.6
		rp.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
		rp.mesh_lod_threshold = 4.0
		add_child(rp)
		ctx.probes.append(rp)
	var fog := FogVolume.new()
	fog.name = "HallDust"
	fog.size = Vector3(GL.HALLB.x1 - GL.HALLB.x0, GL.HALLB.roof - GL.HALL, GL.HALLB.z1 - GL.HALLB.z0)
	fog.position = Vector3((GL.HALLB.x0 + GL.HALLB.x1) * 0.5, (GL.HALL + GL.HALLB.roof) * 0.5, (GL.HALLB.z0 + GL.HALLB.z1) * 0.5)
	fog.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	var fm := FogMaterial.new()
	fm.density = 0.018
	fm.albedo = Color(0.85, 0.83, 0.78)
	fm.height_falloff = 0.08
	fm.edge_fade = 0.4
	fog.material = fm
	add_child(fog)
	var occ_root := Node3D.new()
	occ_root.name = "Occluders"
	add_child(occ_root)
	for ab in ctx.occluders:
		var oi := OccluderInstance3D.new()
		var bo := BoxOccluder3D.new()
		bo.size = (ab as AABB).size
		oi.occluder = bo
		oi.position = (ab as AABB).get_center()
		occ_root.add_child(oi)

# ====================================================================== door

func _setup_door() -> void:
	var d: Dictionary = ctx.door
	if d.is_empty():
		return
	door_node = d.pivot
	door_node.transform = Transform3D(Basis(Vector3.UP, AJAR), (d.closed as Transform3D).origin)
	door = Handle.new()
	door.id = "door.garderie"
	door.node = door_node
	door.closed_xform = d.closed
	door.open_xform = d.open
	door.duration = 1.15
	door.sfx_open = _sfx_name("door_open")
	door.sfx_close = _sfx_name("door_close")
	door.is_open = false
	_entries.append({
		"id": "garderie.door", "node": door_node, "max_distance": 2.2,
		"prompt": func() -> String: return "Fermer la porte" if door.is_open else "Ouvrir la porte",
		"enabled": func() -> bool: return not door.animating,
		"on_interact": _door_toggle,
	})

func _door_toggle() -> void:
	if door == null or door.animating:
		return
	var p := door_node.global_position + Vector3(0, 1.0, -0.35)
	_noise(p, 0.2 if not door.is_open else 0.25, "door")
	await door.toggle()

## Instantly sets the door (tests / debug).
func set_door_open(open: bool) -> void:
	if door == null:
		return
	door.is_open = open
	door_node.transform = door.open_xform if open else door.closed_xform

# ====================================================================== navigation + hide spot

func _setup_nav() -> void:
	nav_nodes = GL.NAV_NODES.duplicate()
	nav_links = GL.NAV_LINKS.duplicate(true)

func _setup_hide() -> void:
	var H: Dictionary = GL.HIDE
	var spot := {
		"id": H.id, "door": null, "hide_pos": H.hide_pos, "hide_yaw": float(H.hide_yaw), "exit_pos": H.exit_pos,
		"kind": "tunnel", "check_pos": Vector3(H.exit_pos.x - 0.4, 0.0, H.exit_pos.z),
		"minX": float(GL.TUBE.mouth_x), "maxX": float(GL.TUBE.end_x), "minZ": float(GL.TUBE.z) - 0.6, "maxZ": float(GL.TUBE.z) + 0.6,
	}
	hide_spots = [spot]
	var mouth := Node3D.new()
	mouth.name = "TunnelMouth"
	mouth.position = Vector3(float(GL.TUBE.mouth_x) - 0.15, 0.7, float(GL.TUBE.z))
	add_child(mouth)
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_INTERACT
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.3, 1.3, 1.4)
	cs.shape = sh
	body.add_child(cs)
	mouth.add_child(body)
	_entries.append({
		"id": "garderie.tunnel.hide", "node": mouth, "max_distance": 2.4,
		"prompt": "Se cacher dans le tunnel",
		"enabled": func() -> bool: return not _player_hidden() and not ride_active,
		"on_interact": _enter_tunnel,
	})
	_entries.append({
		"id": "garderie.tunnel.exit", "node": mouth, "when_hidden": true, "prompt": "Sortir du tunnel",
		"enabled": func() -> bool: return _player_hidden() and _hidden_here(),
		"on_interact": _exit_tunnel,
	})

func _player() -> Node:
	var p: Node = Game.player if is_instance_valid(Game.player) else null
	return p

func _player_hidden() -> bool:
	var p := _player()
	return p != null and p.get("hidden") == true

func _hidden_here() -> bool:
	var p := _player()
	if p == null:
		return false
	var s: Variant = p.get("hide_spot")
	return s is Dictionary and (s as Dictionary).get("id") == GL.HIDE.id

func _enter_tunnel() -> void:
	var p := _player()
	if p == null or not p.has_method("enter_hide"):
		return
	_play("ball_rustle", GL.HIDE.hide_pos, -6.0, 0.8)
	_noise(GL.HIDE.exit_pos, 0.1, "tunnel")
	await p.enter_hide(hide_spots[0])

func _exit_tunnel() -> void:
	var p := _player()
	if p == null or not p.has_method("exit_hide"):
		return
	_noise(GL.HIDE.exit_pos, 0.1, "tunnel")
	await p.exit_hide()

# ====================================================================== slides

func _setup_slides() -> void:
	_ride = Ride.new()
	_ride.name = "SlideRide"
	_ride.garderie = self
	add_child(_ride)
	for id in ctx.slides:
		var s: Dictionary = ctx.slides[id]
		var top := Node3D.new()
		top.name = "SlideTop_%s" % id
		top.position = s.top
		add_child(top)
		var body := StaticBody3D.new()
		body.collision_layer = LAYER_INTERACT
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = s.get("trigger", Vector3(1.0, 1.0, 1.0))
		cs.shape = sh
		body.add_child(cs)
		top.add_child(body)
		_entries.append({
			"id": "garderie.slide.%s" % id, "node": top, "max_distance": 2.4, "prompt": "Glisser",
			"enabled": func() -> bool: return not ride_active and not _player_hidden(),
			"on_interact": ride.bind(id),
		})

## Rides slide `id` ("wave" or "spiral"); returns when the player is back on the floor.
func ride(id: String) -> void:
	if ride_active or not ctx.slides.has(id) or _ride == null:
		return
	await _ride.run(ctx.slides[id])

# ====================================================================== ball pit

func _setup_pit() -> void:
	var P: Dictionary = GL.PIT
	_pit_area = Area3D.new()
	_pit_area.name = "BallPitArea"
	_pit_area.collision_layer = 0
	_pit_area.collision_mask = LAYER_PLAYER
	_pit_area.monitorable = false
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	var t: float = P.wall_t
	sh.size = Vector3(float(P.x1) - float(P.x0) - 2.0 * t, 1.2, float(P.z1) - float(P.z0) - 2.0 * t)
	cs.shape = sh
	_pit_area.add_child(cs)
	_pit_area.position = Vector3((float(P.x0) + float(P.x1)) * 0.5, GL.HALL + 0.6, (float(P.z0) + float(P.z1)) * 0.5)
	add_child(_pit_area)
	_pit_area.body_entered.connect(func(b: Node) -> void: if b == _player(): _set_pit(true))
	_pit_area.body_exited.connect(func(b: Node) -> void: if b == _player(): _set_pit(false))
	var mm := find_child("BallPitBalls", true, false) as MultiMeshInstance3D
	if mm != null and mm.multimesh != null and mm.multimesh.mesh != null:
		_balls_mat = mm.multimesh.mesh.surface_get_material(0) as ShaderMaterial

func _set_pit(on: bool) -> void:
	in_ball_pit = on
	var p := _player()
	if p != null and "speed_scale" in p:
		p.set("speed_scale", 0.55 if on else 1.0)
	if on:
		_play("ball_rustle", p.global_position if p else Vector3.ZERO, -2.0, 1.0)
	elif _balls_mat:
		_balls_mat.set_shader_parameter("push_pos", Vector3(0, -100, 0))

# ====================================================================== lights, zones, power

func _setup_flicker() -> void:
	for l in ctx.lights:
		if l.state == "flicker" and l.kind != "spill":
			var f := {"light": l.light, "emit": l.emit, "base": float(l.base), "t": _rng.randf_range(0.0, 3.0), "phase": 0, "extra": []}
			# the ceiling spill of a flickering troffer follows it
			for o in ctx.lights:
				if o.kind == "spill" and o.state == "flicker" and Vector2(o.pos.x, o.pos.z).distance_to(Vector2(l.pos.x, l.pos.z)) < 0.5:
					f.extra.append([o.light, float(o.base)])
			_flicker.append(f)
			var h = _loop("fluo_buzz", (l.light as Node3D).global_position, -14.0)
			if h != null:
				_buzz_handles.append(h)

func set_power(on: bool) -> void:
	power = on
	if ctx == null:
		return
	for l in ctx.lights:
		var lt: Light3D = l.light
		var dead: bool = l.state == "dead"
		lt.visible = on and not dead and not (l.get("killed", false))
		lt.light_energy = float(l.base) * light_scale
		var em = l.emit
		if em is StandardMaterial3D and l.state != "dead":
			(em as StandardMaterial3D).emission_energy_multiplier = (5.0 if l.kind == "highbay" else (9.0 if l.kind == "bulb" else 3.2)) * (1.0 if on else 0.0)
	_update_zone(true)

func set_light_scale(k: float) -> void:
	light_scale = k
	set_power(power)

## Lights of rooms the camera cannot see are hidden (shadow maps and clustered cost), zone by zone.
func _update_zone(force := false) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() and get_viewport() else null
	var p := cam.global_position if cam else Vector3(0, 1.6, 0)
	var z := "house"
	if p.x < GL.VEST.x1 + 0.1:
		z = "hall"
	elif p.x < -3.6:
		z = "corridor"
	if z == _zone and not force:
		return
	_zone = z
	for l in ctx.lights:
		var lt: Light3D = l.light
		var on: bool = power and l.state != "dead" and not l.get("killed", false)
		if l.kind == "highbay":
			on = on and z == "hall"
		lt.visible = on

func _process(dt: float) -> void:
	if not built:
		return
	_zone_t -= dt
	if _zone_t <= 0.0:
		_zone_t = 0.25
		_update_zone()
	if power:
		_tick_flicker(dt)
	if in_ball_pit:
		_tick_pit(dt)
	_tick_scares(dt)

func _tick_flicker(dt: float) -> void:
	for f in _flicker:
		var lt: Light3D = f.light
		if f.get("dead", false):
			continue
		f.t -= dt
		var on := true
		if f.t < 0.0:
			f.phase = (int(f.phase) + 1) % 12
			f.t = _rng.randf_range(0.03, 0.18) if int(f.phase) % 2 == 1 else _rng.randf_range(0.1, 2.6)
		on = int(f.phase) % 2 == 0
		var k := 1.0 if on else _rng.randf_range(0.0, 0.15)
		lt.light_energy = float(f.base) * light_scale * k
		for e in f.extra:
			(e[0] as Light3D).light_energy = float(e[1]) * light_scale * k
		var em = f.emit
		if em is StandardMaterial3D:
			(em as StandardMaterial3D).emission_energy_multiplier = 5.0 * k

func _tick_pit(dt: float) -> void:
	var p := _player()
	if p == null:
		return
	var feet: Vector3 = (p as Node3D).global_position
	if _balls_mat:
		_balls_mat.set_shader_parameter("push_pos", feet)
	var spd := float(p.get("speed")) if p.get("speed") != null else 0.0
	_pit_noise_t -= dt
	if spd > 0.3 and _pit_noise_t <= 0.0:
		_pit_noise_t = 0.75
		_noise(feet, 0.4, "ballpit")
		_play("ball_rustle", feet, -4.0, _rng.randf_range(0.9, 1.15))

# ====================================================================== ambient scares (only while the player is in the area)

func _tick_scares(dt: float) -> void:
	if Game.state != "playing":
		return
	var p := _player()
	if p == null or not in_area((p as Node3D).global_position):
		return
	var ent: Node = Game.entity if is_instance_valid(Game.entity) else null
	if ent != null and String(ent.get("state")) in ["chasing", "jumpscare"]:
		return
	_scare_t -= dt
	if _scare_t > 0.0:
		return
	_scare_t = _rng.randf_range(28.0, 60.0)
	var pp: Vector3 = (p as Node3D).global_position
	var options := ["giggle_slide", "tube_dies", "ball_roll", "hum"]
	if pp.x > GL.VEST.x0:
		options = ["hum", "giggle_slide"]
	scare(options[_rng.randi() % options.size()])

## Plays one ambient scare: giggle_slide | tube_dies | ball_roll | hum (also usable by gameplay / debug).
func scare(kind: String) -> void:
	match kind:
		"giggle_slide":
			var top: Vector3 = ctx.slides["wave"].top if ctx.slides.has("wave") else Vector3(-31, 4, -4)
			_play("slide_squeak", top, -6.0, 1.3)
			await get_tree().create_timer(0.7, false).timeout
			_play("giggle", top + Vector3(3.0, -2.0, 0.0), -8.0, 0.95)
		"tube_dies":
			_tube_dies()
		"ball_roll":
			_ball_roll()
		"hum":
			_play("hum", Vector3(-14.1, 1.4, 4.4), -16.0, 0.9)

func _tube_dies() -> void:
	var cands: Array = ctx.lights.filter(func(l): return l.kind == "highbay" and l.state == "on" and not l.get("killed", false))
	if cands.is_empty():
		return
	var l: Dictionary = cands[_rng.randi() % cands.size()]
	var lt: Light3D = l.light
	_play("fluo_buzz", lt.global_position, -8.0)
	for i in 7:
		lt.light_energy = float(l.base) * light_scale * (0.2 if i % 2 == 0 else 1.0)
		await get_tree().create_timer(_rng.randf_range(0.05, 0.22), false).timeout
	_play("fluo_pop", lt.global_position, -4.0)
	l["killed"] = true
	lt.visible = false

func _ball_roll() -> void:
	var P: Dictionary = GL.PIT
	var ball := RigidBody3D.new()
	ball.name = "RollingBall"
	ball.collision_layer = 0
	ball.collision_mask = LAYER_WORLD
	ball.mass = 0.05
	ball.linear_damp = 0.35
	ball.angular_damp = 0.4
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.037
	cs.shape = sh
	ball.add_child(cs)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.037
	sm.height = 0.074
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.12, 0.1)
	mat.roughness = 0.25
	sm.material = mat
	mi.mesh = sm
	ball.add_child(mi)
	add_child(ball)
	ball.global_position = Vector3(float(P.x1) - 0.12, GL.HALL + float(P.wall_h) + 0.06, float(P.gate_z0) + 0.4)
	var p := _player()
	var dir := Vector3(1, 0, 0)
	if p != null:
		dir = ((p as Node3D).global_position - ball.global_position)
		dir.y = 0.0
		dir = dir.normalized()
	ball.apply_central_impulse(dir * 0.09 + Vector3(0, 0.02, 0))
	_play("ball_bounce", ball.global_position, -6.0, 1.6)
	await get_tree().create_timer(14.0, false).timeout
	if is_instance_valid(ball):
		ball.queue_free()

# ====================================================================== queries

func ground_height_at(x: float, z: float, prev_y: float = NAN) -> float:
	var g := GL.ground_height_at(x, z, prev_y)
	if not is_nan(g):
		return g
	if _world is Object and is_instance_valid(_world) and (_world as Object).has_method("ground_height_at") and _world != self:
		return float(_world.ground_height_at(x, z, prev_y))
	return Layout.ground_height_at(x, z, prev_y)

func surface_at(pos: Vector3) -> String:
	return GL.surface_at(pos)

func in_area(pos: Vector3) -> bool:
	return pos.x < -3.7 and GL.contains(pos)

func reset_after_caught() -> void:
	if _ride != null and _ride.has_method("cancel"):
		_ride.cancel()
	ride_active = false
	_scare_t = 40.0
	if in_ball_pit:
		_set_pit(false)

## Teleports the player into the area with the right floor height (the house's ground_height_at knows nothing
## about the 1.05 m lower hall or the play decks): Game.world answers with this node during the call.
## pos.y = feet height hint (picks the deck level), yaw / pitch in radians.
func teleport_player(pos: Vector3, yaw: float, pitch := 0.0) -> void:
	var p := _player()
	if p == null or not p.has_method("teleport"):
		return
	var w: Node = Game.world
	Game.world = self
	p.call("teleport", Vector3(pos.x, ground_height_at(pos.x, pos.z, pos.y + 0.2), pos.z), yaw, pitch)
	Game.world = w

## Debug args (after --): --garderie-cam=x,y,z,yawDeg,pitchDeg (feet height y) teleports the player once the game
## plays; --garderie-ride=wave|spiral rides a slide right away; --garderie-scare=giggle_slide|tube_dies|ball_roll|hum.
func _debug_args() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if not (args.has("garderie-cam") or args.has("garderie-ride") or args.has("garderie-scare")):
		return
	while is_inside_tree() and Game.state != "playing":
		await get_tree().process_frame
	await get_tree().process_frame
	if args.has("garderie-cam"):
		var c: PackedStringArray = String(args["garderie-cam"]).split(",")
		if c.size() >= 3:
			teleport_player(Vector3(float(c[0]), float(c[1]), float(c[2])), deg_to_rad(float(c[3])) if c.size() > 3 else 0.0,
				deg_to_rad(float(c[4])) if c.size() > 4 else 0.0)
	if args.has("garderie-ride") and ctx.slides.has(String(args["garderie-ride"])):
		var s: Dictionary = ctx.slides[String(args["garderie-ride"])]
		teleport_player(s.top, PI if String(args["garderie-ride"]) == "spiral" else -PI * 0.5)
		await get_tree().create_timer(0.5, false).timeout
		await ride(String(args["garderie-ride"]))
	if args.has("garderie-scare"):
		scare(String(args["garderie-scare"]))

# ====================================================================== interaction registration

func _register_or_wait() -> void:
	if _try_register():
		return
	# main.gd adds the Interaction node after the world: register the moment it is ready (before the puzzles).
	if is_inside_tree() and not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)

func _on_node_added(n: Node) -> void:
	if n.name == "Interaction" or n == Game.interaction:
		n.ready.connect(func() -> void: _register_with(n), CONNECT_ONE_SHOT)

func _try_register() -> bool:
	var it: Node = Game.interaction if is_instance_valid(Game.interaction) else null
	if it == null:
		return false
	_register_with(it)
	return true

func _register_with(it: Node) -> void:
	if it == null or not it.has_method("register") or _registered_with == it:
		return
	_registered_with = it
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	for e in _entries:
		it.call("register", e)

## Entries handed to Game.interaction (tests, debug).
func interaction_entries() -> Array:
	return _entries

# ====================================================================== sound + noise helpers

func _load_sound_names() -> void:
	_sfx_names = {}
	if not FileAccess.file_exists(MANIFEST):
		return
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	var d: Variant = JSON.parse_string(f.get_as_text()) if f else null
	if d is Dictionary:
		for k in (d as Dictionary).keys():
			_sfx_names[String(k)] = true

func _sfx_name(key: String) -> String:
	for n in SFX.get(key, [key]):
		if _sfx_names.has(n):
			return n
	return ""

func _audio() -> Node:
	return get_node_or_null("/root/Audio")

func _play(key: String, pos: Vector3, vol_db := 0.0, pitch := 1.0) -> Variant:
	var n := _sfx_name(key)
	var a := _audio()
	if n == "" or a == null or not a.has_method("play"):
		return null
	return a.call("play", n, {"position": pos, "volume_db": vol_db, "pitch": pitch})

func _loop(key: String, pos: Vector3, vol_db := 0.0) -> Variant:
	var n := _sfx_name(key)
	var a := _audio()
	if n == "" or a == null or not a.has_method("loop"):
		return null
	return a.call("loop", n, {"position": pos, "volume_db": vol_db})

func _noise(pos: Vector3, loudness: float, source: String) -> void:
	Events.noise.emit(pos, loudness, source)

func _exit_tree() -> void:
	for h in _buzz_handles:
		if h is Object and is_instance_valid(h) and (h as Object).has_method("stop"):
			h.stop(0.0)
	_buzz_handles.clear()
