## Dehors (chapter 3): her. Out here she sees nothing; she listens. She crosses the yard on a round, a storm lantern
## in her right hand (the light is for whoever looks for her, not for her), humming. A noise she hears stops the
## humming: she comes to where it was, faster the surer she is, stands there and sweeps the air around her, then goes
## back to her round. She touches whoever she walks into.
##
##   hearing   a noise of loudness l (Events.noise) carries HEAR_K * l metres (x 1.25 once the bolt cutters are
##             out of the cellar, x 0.35 from underground)
##   speeds    WALK on her round, SEEK_SLOW..SEEK_FAST toward a noise as `alert` (0..1) rises
##   touch     CATCH while she walks, SWEEP while she stands listening
##
## The body is La Gardienne's model (scripts/entity/gardienne_model.gd), a second instance driven from here; nothing
## of it casts a shadow (it moves). dehors.gd owns this node: build(), spawn(), despawn(), hear(), tick(), prewarm.
extends Node3D

const L := preload("res://scripts/dehors/dehors_layout.gd")
const Kit := preload("res://scripts/garderie/garderie_kit.gd")
const Props := preload("res://scripts/dehors/dehors_props.gd")
const Model := preload("res://scripts/entity/gardienne_model.gd")

const HEAR_K := 60.0               # metres a noise of loudness 1 carries
const WALK := 0.95                 # m/s on her round (the player walks at 1.9, crouches at 0.9, runs at 3.3)
const WALK_LATE := 1.2
const SEEK_SLOW := 1.5
const SEEK_FAST := 2.6
const CATCH := 0.85                # m: she walks into the player
const SWEEP := 1.25                # m: her arms, while she stands listening
const CELL := 0.5
const LANTERN_ENERGY := 1.5

signal noticed(pos: Vector3)       # she has just heard something (she was on her round or standing)
signal arrived(pos: Vector3)       # she has reached the place of a noise and listens there
signal touched()                   # she has the player

var state := "away"                # away | enter | patrol | seek | listen | grab
var alert := 0.0
var pos := Vector3.ZERO
var yaw := 0.0
var late := false
var lantern_on := true
var target := Vector3.ZERO
var model: Model = null
var built := false

var _astar := AStarGrid2D.new()
var _origin := Vector2.ZERO
var _size := Vector2i.ZERO
var _path: PackedVector3Array = []
var _path_i := 0
var _repath := 0.0
var _interest := 0.0
var _listen_t := 0.0
var _wp := 0
var _wp_dir := 1
var _holder: Node3D = null         # the lantern: follows her right hand, stays upright
var _hand: BoneAttachment3D = null
var _light: OmniLight3D = null
var _flame: StandardMaterial3D = null
var _flare: MeshInstance3D = null
var _flare_mat: StandardMaterial3D = null
var _sway := 0.0
var _flick := 0.0
var _hum = null
var _hum_wait := 0.0
var _squeak = null
var _breath_t := 0.0
var _speed := 0.0
var _stuck := 0.0
var _from_seek := false
var _no_pull := 0.0
var _grab_t := 0.0
var _enter: Array = []
var _rng := RandomNumberGenerator.new()

# ====================================================================== build

func build(solids: Array) -> void:
	name = "Her"
	_rng.seed = 61
	visible = false
	model = Model.new()
	model.name = "Body"
	add_child(model)
	await model.build(str(Settings.get_value("quality", "high")))
	for n in model.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.footstep.connect(_on_step)
	_build_lantern()
	_build_grid(solids)
	built = true

func _build_lantern() -> void:
	_holder = Node3D.new()
	_holder.name = "Lantern"
	add_child(_holder)
	if model.skeleton != null and model.skeleton.find_bone("handR") >= 0:
		_hand = BoneAttachment3D.new()
		_hand.name = "HandR"
		_hand.bone_name = "handR"
		model.skeleton.add_child(_hand)
	var k = Kit.new()
	Props.lantern(k)
	var mats = load("res://scripts/dehors/dehors_mats.gd").new()
	_flame = mats.mat("dh_flame").duplicate() as StandardMaterial3D
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(1.0, 0.8, 0.5, 0.22)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.55, 0.2)
	glass.emission_energy_multiplier = 0.8
	var parts := k.commit(_holder, {"dh_iron": mats.mat("dh_iron"), "dh_rust": mats.mat("dh_rust"), "lantern_glass": glass, "flame": _flame}, "lantern")
	for mi in parts:
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(mi as MeshInstance3D).layers = L.L_DH
	_light = OmniLight3D.new()
	_light.name = "LanternLight"
	_light.position = Vector3(0, -0.2, 0)
	_light.light_color = Color(1.0, 0.6, 0.26)
	_light.light_energy = LANTERN_ENERGY
	_light.omni_range = 7.5
	_light.omni_attenuation = 1.25
	_light.shadow_enabled = false                   # it moves: a shadow map would be drawn again every frame
	_light.light_specular = 0.6
	_light.light_cull_mask = 1 | L.L_DH
	_light.light_volumetric_fog_energy = 5.0
	_holder.add_child(_light)
	# a soft halo that the fog does not swallow: what the player watches from the other end of the yard
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.12, 0.4, 1.0])
	grad.colors = PackedColorArray([Color(1.0, 0.82, 0.55, 1.0), Color(1.0, 0.62, 0.3, 0.55), Color(1.0, 0.5, 0.2, 0.12), Color(1.0, 0.4, 0.1, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	_flare_mat = StandardMaterial3D.new()
	_flare_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flare_mat.albedo_texture = gt
	_flare_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.5)
	_flare_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flare_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flare_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_flare_mat.disable_fog = true
	_flare_mat.disable_receive_shadows = true
	var q := QuadMesh.new()
	q.size = Vector2(1.1, 1.1)
	q.material = _flare_mat
	_flare = MeshInstance3D.new()
	_flare.name = "Halo"
	_flare.mesh = q
	_flare.position = Vector3(0, -0.2, 0)
	_flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flare.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_flare.layers = L.L_DH
	_holder.add_child(_flare)

func _build_grid(solids: Array) -> void:
	var Y: Dictionary = L.YARD
	_origin = Vector2(float(Y.x0), float(Y.z0))
	_size = Vector2i(int((float(Y.x1) - float(Y.x0)) / CELL), int((float(Y.z1) - float(Y.z0)) / CELL))
	_astar.region = Rect2i(Vector2i.ZERO, _size)
	_astar.cell_size = Vector2(CELL, CELL)
	_astar.offset = _origin + Vector2(CELL, CELL) * 0.5
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	for r in solids:
		set_blocked((r as Rect2).grow(0.3), true)

## Marks the cells whose centre lies in the rectangle (world x, z) as walls for her, or frees them.
func set_blocked(r: Rect2, on: bool) -> void:
	var a := _cell_of(Vector3(r.position.x, 0.0, r.position.y))
	var b := _cell_of(Vector3(r.end.x, 0.0, r.end.y))
	for j in range(a.y, b.y + 1):
		for i in range(a.x, b.x + 1):
			var c := _origin + (Vector2(i, j) + Vector2(0.5, 0.5)) * CELL
			if r.has_point(c):
				_astar.set_point_solid(Vector2i(i, j), on)
	_repath = 0.0

func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int(floor((p.x - _origin.x) / CELL)), 0, _size.x - 1), clampi(int(floor((p.z - _origin.y) / CELL)), 0, _size.y - 1))

## The free cell nearest to the point p (its own cell when that one is free).
func _free_cell_near(p: Vector3) -> Vector2i:
	var c := _cell_of(p)
	if not _astar.is_point_solid(c):
		return c
	var best := c
	var bd := 1e9
	var found_r := -1
	for r in range(1, 14):
		if found_r >= 0 and r > found_r + 1:
			break                                   # one ring further than the first hit: the nearest in metres is among these
		for j in range(-r, r + 1):
			for i in range(-r, r + 1):
				if maxi(absi(i), absi(j)) != r:
					continue
				var q := c + Vector2i(i, j)
				if q.x < 0 or q.y < 0 or q.x >= _size.x or q.y >= _size.y or _astar.is_point_solid(q):
					continue
				var w := _origin + (Vector2(q) + Vector2(0.5, 0.5)) * CELL
				var d := Vector2(w.x - p.x, w.y - p.z).length_squared()
				if d < bd:
					bd = d
					best = q
					if found_r < 0:
						found_r = r
	return best

func _free_cell(c: Vector2i) -> Vector2i:
	var w := _origin + (Vector2(c) + Vector2(0.5, 0.5)) * CELL
	return _free_cell_near(Vector3(w.x, 0.0, w.y))

## The nearest point she can stand on.
func reachable(p: Vector3) -> Vector3:
	var c := _free_cell_near(p)
	if c == _cell_of(p):
		return Vector3(p.x, 0.0, p.z)
	var w := _origin + (Vector2(c) + Vector2(0.5, 0.5)) * CELL
	return Vector3(w.x, 0.0, w.y)

func _clear_line(a: Vector3, b: Vector3) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var n := int(ceil(d.length() / 0.1))
	if n == 0:
		return true
	var side := Vector3(-d.y, 0.0, d.x).normalized() * 0.12      # a little room on both sides
	for i in range(1, n + 1):
		var q := a.lerp(b, float(i) / float(n))
		if _astar.is_point_solid(_cell_of(q)) or _astar.is_point_solid(_cell_of(q + side)) or _astar.is_point_solid(_cell_of(q - side)):
			return false
	return true

func _make_path() -> void:
	var from := _free_cell(_cell_of(pos))
	var to := _free_cell(_cell_of(target))
	var raw := _astar.get_point_path(from, to)
	_path = PackedVector3Array()
	for p in raw:
		_path.append(Vector3(p.x, 0.0, p.y))
	if not _path.is_empty():
		var goal := reachable(target)
		if _path[_path.size() - 1].distance_to(goal) < CELL:
			_path[_path.size() - 1] = goal
	_path_i = 0
	_repath = 0.6

# ====================================================================== in and out of the yard

func spawn(at: Vector3, facing := PI * 0.5) -> void:
	pos = reachable(at)
	position = pos
	yaw = facing
	rotation.y = yaw
	state = "patrol"
	alert = 0.0
	_interest = 0.0
	_wp = 0
	_wp_dir = 1
	_path = PackedVector3Array()
	target = _waypoint()
	_repath = 0.0
	visible = true
	set_lantern(true)
	if model != null:
		model.jump_t = -1.0
		model.reset_simulation()
		model.mode = "walk"
	_start_sounds()

## She walks in from `from` to `to` (feet, y included) in `seconds`, hearing nothing yet: out of the front door, across
## the porch, down the steps. Then her round begins.
func enter(from: Vector3, to: Vector3, seconds: float) -> void:
	spawn(to)
	state = "enter"
	_enter = [from, to, maxf(seconds, 0.1), 0.0]
	pos = from
	position = from
	yaw = atan2(to.x - from.x, to.z - from.z)
	rotation.y = yaw

## She has the player: in front of the camera, the lunge of her model.
func grab(feet: Vector3, facing: float) -> void:
	state = "grab"
	_grab_t = 0.0
	pos = feet
	position = pos
	yaw = facing
	rotation.y = yaw
	_hum_on(false)
	if model != null:
		model.reset_simulation()

func despawn() -> void:
	state = "away"
	if model != null:
		model.jump_t = -1.0
	visible = false
	alert = 0.0
	_stop_sounds()

func set_lantern(on: bool) -> void:
	lantern_on = on
	if _light != null:
		_light.visible = on
		_flare.visible = on
		_flame.emission_energy_multiplier = 7.0 if on else 0.0

func apply_quality(q: String) -> void:
	if model != null and model.ok:
		model.apply_quality(q)
		for n in model.find_children("*", "GeometryInstance3D", true, false):
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Loading rehearsal: shown standing at `at`, lantern lit (dehors.gd puts her in front of the tour camera).
func prewarm_at(at: Vector3, facing: float) -> void:
	visible = true
	position = at
	rotation.y = facing
	set_lantern(true)
	if model != null:
		model.mode = "walk"
		model.speed = 0.9
		model.update(0.05)
	_place_lantern(0.05)

func prewarm_end() -> void:
	if state == "away":
		visible = false

# ====================================================================== sounds

func _audio() -> Node:
	return get_node_or_null("/root/Audio")

func _sfx(sound: String, at: Vector3, db := 0.0, pitch := 1.0) -> void:
	var a := _audio()
	if a != null and a.has_method("has_sound") and a.call("has_sound", sound):
		a.call("play", sound, {"position": at, "volume_db": db, "pitch": pitch})

func _start_sounds() -> void:
	var a := _audio()
	if a == null or not a.has_method("loop"):
		return
	if _squeak == null and a.call("has_sound", "dh_lantern"):
		_squeak = a.call("loop", "dh_lantern", {"attach": _holder, "volume_db": 0.0})
	_hum_wait = 1.5

func _stop_sounds() -> void:
	for h in [_hum, _squeak]:
		if h is Object and is_instance_valid(h) and (h as Object).has_method("stop"):
			h.stop(0.3)
	_hum = null
	_squeak = null

func _hum_on(on: bool) -> void:
	if on and _hum == null:
		var a := _audio()
		if a != null and a.has_method("loop") and a.call("has_sound", "lullaby_hum"):
			_hum = a.call("loop", "lullaby_hum", {"attach": self, "attach_offset": Vector3(0, 1.6, 0), "volume_db": -3.0, "fade_in": 1.5})
	elif not on and _hum != null:
		if _hum is Object and is_instance_valid(_hum):
			_hum.stop(0.12)
		_hum = null

func _on_step(_side: String, at: Vector3) -> void:
	if state == "away" or not visible:
		return
	var surf := L.surface_at(pos)
	var s := "dh_her_grass"
	if surf == "gravel":
		s = "dh_her_gravel"
	elif surf == "leaves":
		s = "dh_her_leaves"
	elif surf == "wood" or surf == "concrete":
		s = "entity_step"
	_sfx(s, Vector3(at.x, 0.05, at.z), lerpf(-3.0, 3.0, clampf((_speed - WALK) / (SEEK_FAST - WALK), 0.0, 1.0)), _rng.randf_range(0.9, 1.05))

# ====================================================================== hearing

## A noise at `at` (Events.noise). Returns true when she heard it.
func hear(at: Vector3, loud: float, source := "") -> bool:
	if state in ["away", "enter", "grab"] or loud <= 0.0 or source.begins_with("her"):
		return false
	var l := loud
	if at.y < -1.0:
		l *= 0.35                                   # from under the lawn
	var reach := l * HEAR_K * (1.25 if late else 1.0)
	var d := Vector2(at.x - pos.x, at.z - pos.z).length()
	if d > reach:
		return false
	var near := 1.0 - d / maxf(reach, 0.01)
	var interest := l * (0.3 + 0.7 * near)
	# something louder holds her: a noise from elsewhere must be nearly as strong to turn her round
	var same_place := state == "seek" and Vector2(at.x - target.x, at.z - target.z).length() < 4.0
	if interest < _interest * (0.4 if same_place else 0.85):
		return false
	_interest = maxf(_interest, interest)
	alert = minf(1.0, alert + 0.16 + 0.85 * l * (0.4 + 0.6 * near))
	# the further the noise, the less exactly she knows where
	var err := clampf(d * 0.07, 0.0, 2.0)
	var a := _rng.randf() * TAU
	target = reachable(Vector3(at.x + cos(a) * err, 0.0, at.z + sin(a) * err))
	_repath = 0.0
	if state != "seek":
		state = "seek"
		_hum_on(false)
		_sfx("entity_croak", pos + Vector3(0, 1.6, 0), 0.0, _rng.randf_range(0.85, 1.0))
		noticed.emit(at)
	return true

# ====================================================================== every frame

func _waypoint() -> Vector3:
	var list: Array = L.PATROL_LATE if late else range(L.PATROL.size())
	return L.PATROL[int(list[posmod(_wp, list.size())])]

func _next_waypoint() -> void:
	var r := _rng.randf()
	if r < 0.12:
		_wp_dir = -_wp_dir
	_wp += _wp_dir * (2 if r > 0.85 else 1)
	target = reachable(_waypoint())
	_repath = 0.0

func _place_lantern(dt: float) -> void:
	_sway += dt * (2.2 + 2.0 * _speed)
	var hold := global_transform * Vector3(-0.3, 0.86, 0.1)
	if _hand != null and _hand.is_inside_tree():
		hold = _hand.global_position + Vector3(0, -0.06, 0)
	_holder.global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, 0.14 * sin(_sway) * minf(1.0, _speed + 0.2)), hold)
	if lantern_on:
		_flick += dt * (9.0 + 14.0 * alert)
		var f := 0.9 + 0.07 * sin(_flick) + 0.05 * sin(_flick * 2.7 + 1.0) + 0.04 * sin(_flick * 0.37)
		_light.light_energy = LANTERN_ENERGY * f * (1.0 + 0.35 * alert)
		_flame.emission_energy_multiplier = 7.0 * f

## One step of her. pp = the player's feet, catchable = the player can be touched (not hidden, not being caught).
func tick(dt: float, pp: Vector3, catchable: bool) -> void:
	if state == "away" or not built:
		return
	if state == "enter":
		_enter[3] = float(_enter[3]) + dt
		var u := clampf(float(_enter[3]) / float(_enter[2]), 0.0, 1.0)
		var a: Vector3 = _enter[0]
		var b: Vector3 = _enter[1]
		pos = Vector3(lerpf(a.x, b.x, u), lerpf(a.y, b.y, smoothstep(0.5, 0.92, u)), lerpf(a.z, b.z, u))
		position = pos
		_speed = a.distance_to(b) / float(_enter[2])
		if model != null:
			model.mode = "walk"
			model.speed = _speed
			model.update(dt)
		_place_lantern(dt)
		if u >= 1.0:
			pos = Vector3(b.x, 0.0, b.z)
			state = "patrol"
		return
	if state == "grab":
		_grab_t += dt
		if model != null:
			model.mode = "jumpscare"
			model.jump_t = _grab_t
			model.speed = 0.0
			model.update(dt)
		_place_lantern(dt)
		return
	_interest = maxf(0.0, _interest - dt * _interest / 2.5 - dt * 0.004)
	var want := 0.0
	match state:
		"patrol":
			alert = maxf(0.0, alert - dt * 0.06)
			want = WALK_LATE if late else WALK
			if _hum == null:
				_hum_wait -= dt
				if _hum_wait <= 0.0:
					_hum_on(true)
		"seek":
			alert = maxf(0.0, alert - dt * 0.02)
			want = lerpf(SEEK_SLOW, SEEK_FAST, smoothstep(0.35, 0.9, alert))
		"listen":
			alert = maxf(0.0, alert - dt * 0.03)
			_listen_t -= dt
			if _listen_t <= 0.0:
				state = "patrol"
				_hum_wait = 2.5
				if _from_seek:
					_from_seek = false
					_nearest_waypoint()
	# walk
	var moved := 0.0
	if want > 0.0:
		_repath -= dt
		if _repath <= 0.0 or _path.is_empty():
			_make_path()
		# aim at the furthest point of the path she can walk to in a straight line (after brushing a wall: from one
		# point of the path to the next for a while, which never cuts a corner)
		_no_pull = maxf(0.0, _no_pull - dt)
		if _no_pull <= 0.0:
			while _path_i < _path.size() - 1 and _clear_line(pos, _path[_path_i + 1]):
				_path_i += 1
		elif _path_i < _path.size() - 1 and Vector2(_path[_path_i].x - pos.x, _path[_path_i].z - pos.z).length() < 0.1:
			_path_i += 1
		var goal: Vector3 = _path[_path_i] if _path_i < _path.size() else target
		var to := Vector3(goal.x - pos.x, 0.0, goal.z - pos.z)
		var dist := to.length()
		var end := Vector2(target.x - pos.x, target.z - pos.z).length()
		if end < 0.45 or (_path_i >= _path.size() - 1 and dist < 0.3):
			_arrive()
		elif dist > 0.01:
			var step := minf(want * dt, dist)
			var np := pos + to / dist * step
			if _astar.is_point_solid(_cell_of(np)) and not _astar.is_point_solid(_cell_of(pos)):
				_repath = 0.0                           # a corner, or a door shut in her face: find the way again
				_no_pull = 2.0
				_stuck += dt
				if _stuck > 3.0:
					_stuck = 0.0
					_arrive()
			else:
				_stuck = 0.0
				pos = np
				moved = step
				yaw = lerp_angle(yaw, atan2(to.x, to.z), clampf(dt * 5.0, 0.0, 1.0))
	_speed = lerpf(_speed, moved / maxf(dt, 1e-4), clampf(dt * 6.0, 0.0, 1.0))
	position = pos
	rotation.y = yaw
	if model != null:
		model.mode = "search" if state == "listen" else ("chase" if state == "seek" and alert > 0.75 else "walk")
		model.speed = _speed
		model.look_on = false
		model.update(dt)
	_place_lantern(dt)
	if state == "seek" and alert > 0.6:
		_breath_t -= dt
		if _breath_t <= 0.0:
			_breath_t = 1.7
			_sfx("entity_breath", pos + Vector3(0, 1.55, 0), 2.0, 0.9)
	# touch
	if catchable and absf(pp.y - pos.y) < 1.3:
		var d := Vector2(pp.x - pos.x, pp.z - pos.z).length()
		if d < (SWEEP if state == "listen" else CATCH):
			touched.emit()

func _arrive() -> void:
	if state == "seek":
		state = "listen"
		_from_seek = true
		_listen_t = 4.0 + 3.5 * alert + (2.0 if late else 0.0)
		arrived.emit(pos)
	elif state == "patrol":
		if _rng.randf() < 0.3:
			state = "listen"
			_listen_t = _rng.randf_range(2.0, 3.5)
			_hum_on(false)
		_next_waypoint()

func _nearest_waypoint() -> void:
	var list: Array = L.PATROL_LATE if late else range(L.PATROL.size())
	var best := 0
	var bd := 1e9
	for i in list.size():
		var d: float = (L.PATROL[int(list[i])] as Vector3).distance_to(pos)
		if d < bd:
			bd = d
			best = i
	_wp = best
	target = reachable(_waypoint())
	_repath = 0.0

## Where she will be in `t` seconds if nothing disturbs her (the level places scripted sounds with it).
func head_position() -> Vector3:
	return global_position + Vector3(0, 1.6, 0)

func _exit_tree() -> void:
	_stop_sounds()
