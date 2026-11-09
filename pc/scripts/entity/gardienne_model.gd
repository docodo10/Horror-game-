## La Gardienne — the body. Runtime side of src/entity/GardienneModel.js on top of the exporter's baked
## res://assets/generated/gardienne.glb (93-bone skeleton, 5 skinned meshes + eyes/glints, 9 clips at 30 fps, hair chains,
## skirt spring and jaw baked in). Owned by the entity module; driven by gardienne.gd.
##
## Animation = an AnimationTree (manual process, advanced by update()) that reproduces the web pose blending:
##   gait clips (walk, chase, walk_stairs, walk_stairs_down, duck_walk) are NOT free-running: each is seeked every frame from
##   one shared gait phase that advances like the web model's (cycles/s = speed / (2 x step length), step length 0.6 m walk,
##   1.0 m chase, x0.62 on stairs), so every clip is speed-matched (no foot sliding) and they blend in phase (the clip phase
##   offsets come from the meta's heel-strike times). Footsteps fire at the same phase crossings as the web (L 0.25, R 0.75).
##     chaseB  = Blend2(walk, chase, chase weight)                  walk <-> predatory chase gait
##     stairsB = Blend3(stairs_down, chaseB, stairs_up, stairs)     on the treads
##     duckB   = Blend2(stairsB, duck_walk, duck) upper body only   folded under the stairwell bulkhead (legs keep the treads)
##     moveB   = Blend2(idle, duckB, move weight)                   standing <-> moving (web moveW = speed / 0.45)
##     searchB = Blend2(moveB, search, search weight)               listening: jerky scans + head tilts
##     reachB  = Blend2(searchB, reach, reach weight)               door / closet reach
##     jumpB   = Blend2(reachB, jumpscare (seeked to jump_t), 1)    lunge, arms, jaw drop, hair parting
##   On top: gardienne_pose.gd (SkeletonModifier3D): look-at + glitch head snaps / spasms; glitch freezes hold the pose.
## Materials (Godot StandardMaterial3D, Forward+): skin + face with screen-space subsurface scattering (skin mode) and
## transmittance (thin fingers / ears glow red against a light), a thin clear coat (wet look); teeth / eyes clear coat;
## gown with a fabric sheen (rim) + backlight (thin cotton), hair and gown tears alpha-tested with alpha-to-coverage under
## MSAA (alpha hash under TAA), eye glints emissive (eyeshine), and set_exposure() for the point-blank jumpscare.
## Fallback (no glb): a tall dark silhouette with the same attach points.
extends Node3D

const GLB := "res://assets/generated/gardienne.glb"
const META := "res://assets/generated/gardienne_meta.json"
const PoseLayer := preload("res://scripts/entity/gardienne_pose.gd")

## Heel strike: side "L" | "R", world position of the foot bone.
signal footstep(side: String, pos: Vector3)

# ---------------------------------------------------------------- inputs (web ctx), written by the entity before update()
var mode := "idle"                 # idle | walk | search | chase | reach | jumpscare
var speed := 0.0                   # measured horizontal speed (m/s)
var stairs := 0                    # -1 down, 0 flat, +1 up
var duck := 0.0                    # 0..1 under the stairwell bulkhead
var look_on := false
var look_target := Vector3.ZERO    # world (player's eyes)
var jump_t := -1.0                 # seconds since the jumpscare started, -1 = none
var aggression := 0
var eyeshine_target := 0.1         # 0.08..1 (her pupils catch the flashlight beam)

# ---------------------------------------------------------------- state
var ok := false                    # the glb loaded (false = fallback silhouette)
var skeleton: Skeleton3D = null
var tree: AnimationTree = null
var head_attach: Node3D = null     # BoneAttachment3D "head" (eyes + glints live under it) / fallback head node
var pose_layer: PoseLayer = null
var time := 0.0
var clips := {}                    # name -> {len, cycle, cycles, phi0, speed}
var debug_freeze := false          # debug: pose held exactly (no glitches, no damping)

var _speed := 0.0
var _move_w := 0.0
var _chase_w := 0.0
var _search_w := 0.0
var _reach_w := 0.0
var _stairs := 0.0
var _duck := 0.0
var _phase := 0.0                  # gait cycles in [0, _wrap)
var _wrap := 12.0
var _eyeshine := 0.15
var _look_w := 0.0
var _glitch_t := 4.0
var _freeze := 0.0
var _snap_t := 0.0
var _snap_yaw := 0.0
var _snap_roll := 0.0
var _spasm_t := 0.0
var _expo := 1.0
var _quality := "high"
var _jump_len := 1.8

var _bone_head := -1
var _bone_foot := {"L": -1, "R": -1}
var _mats: Array[BaseMaterial3D] = []
var _base := {}                    # material -> [albedo Color, specular, clearcoat, rim]
var _glints: Array[BaseMaterial3D] = []
var _alpha_mats: Array[BaseMaterial3D] = []
var _meshes: Array[MeshInstance3D] = []

const P_CHASE := &"parameters/chaseB/blend_amount"
const P_STAIRS := &"parameters/stairsB/blend_amount"
const P_DUCK := &"parameters/duckB/blend_amount"
const P_MOVE := &"parameters/moveB/blend_amount"
const P_SEARCH := &"parameters/searchB/blend_amount"
const P_REACH := &"parameters/reachB/blend_amount"
const P_JUMP := &"parameters/jumpB/blend_amount"
const GAIT := ["walk", "chase", "walk_stairs", "walk_stairs_down", "duck_walk"]
const SEEK := {"walk": &"parameters/walk_seek/seek_request", "chase": &"parameters/chase_seek/seek_request",
	"walk_stairs": &"parameters/up_seek/seek_request", "walk_stairs_down": &"parameters/down_seek/seek_request",
	"duck_walk": &"parameters/duck_seek/seek_request", "jumpscare": &"parameters/jump_seek/seek_request"}
const LOWER_BODY := ["root", "hips", "skirt", "thighL", "shinL", "footL", "toeL", "thighR", "shinR", "footR", "toeR"]

# ====================================================================== build

## Loads the glb on a worker thread (keeps the loading screen alive), sets materials, tree and pose layer.
func build(quality := "high") -> void:
	_quality = quality
	var ps: PackedScene = null
	if ResourceLoader.exists(GLB):
		if ResourceLoader.load_threaded_request(GLB, "PackedScene") == OK:
			while ResourceLoader.load_threaded_get_status(GLB) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				await get_tree().process_frame
			ps = ResourceLoader.load_threaded_get(GLB) as PackedScene
		if ps == null:
			ps = load(GLB) as PackedScene
	var inst: Node3D = ps.instantiate() as Node3D if ps != null else null
	if inst == null:
		push_warning("[gardienne] %s missing or broken: fallback silhouette" % GLB)
		_build_fallback()
		return
	inst.name = "Body"
	add_child(inst)
	skeleton = inst.find_child("Skeleton3D", true, false) as Skeleton3D
	var ap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if skeleton == null or ap == null:
		push_warning("[gardienne] glb without skeleton/animations: fallback silhouette")
		inst.queue_free()
		_build_fallback()
		return
	for n in inst.find_children("*", "BoneAttachment3D", true, false):
		if (n as BoneAttachment3D).bone_name == "head": head_attach = n
	_bone_head = skeleton.find_bone("head")
	_bone_foot.L = skeleton.find_bone("footL")
	_bone_foot.R = skeleton.find_bone("footR")
	_read_meta(ap)
	_setup_materials(inst)
	_build_tree(inst, ap)
	pose_layer = PoseLayer.new()
	pose_layer.name = "PoseLayer"
	skeleton.add_child(pose_layer)
	pose_layer.setup(skeleton)
	ok = true
	refresh_aa()
	update(0.0)

func _read_meta(ap: AnimationPlayer) -> void:
	var meta := {}
	var f := FileAccess.open(META, FileAccess.READ)
	if f != null:
		var j = JSON.parse_string(f.get_as_text())
		if j is Dictionary: meta = j
	var mclips: Dictionary = meta.get("clips", {})
	var cyc_lcm := 1
	for name in GAIT + ["idle", "search", "reach", "jumpscare"]:
		if not ap.has_animation(name): continue
		var a := ap.get_animation(name)
		var mc: Dictionary = mclips.get(name, {})
		var cycle := float(mc.get("cycle", 0.0) if mc.get("cycle") != null else 0.0)
		var c := {"len": a.length, "cycle": cycle, "cycles": 0, "phi0": 0.0, "speed": float(mc.get("speed", 0.0))}
		if cycle > 0.0:
			c.cycles = maxi(1, roundi(a.length / cycle))
			# phase of clip time 0 in the web gait cycle: heel strikes are L at 0.25, R at 0.75 (circular mean)
			var sx := 0.0
			var sy := 0.0
			for fs in mc.get("footsteps", []):
				var ph := (0.25 if String(fs.side) == "L" else 0.75) - float(fs.t) / cycle
				sx += cos(TAU * ph)
				sy += sin(TAU * ph)
			if sx != 0.0 or sy != 0.0: c.phi0 = fposmod(atan2(sy, sx) / TAU, 1.0)
			cyc_lcm = _lcm(cyc_lcm, int(c.cycles))
		clips[name] = c
	_wrap = float(maxi(cyc_lcm, 1))
	if clips.has("jumpscare"): _jump_len = float(clips.jumpscare.len)
	# a gait clip missing from the glb falls back to walk (keeps the tree valid)
	for g in GAIT:
		if not clips.has(g) and clips.has("walk"): clips[g] = (clips.walk as Dictionary).duplicate()

func _lcm(a: int, b: int) -> int:
	var x := a
	var y := b
	while y != 0:
		var t := y
		y = x % y
		x = t
	return a / x * b if x != 0 else a

# ---------------------------------------------------------------- AnimationTree

func _build_tree(inst: Node3D, ap: AnimationPlayer) -> void:
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	inst.add_child(tree)                     # sibling of the AnimationPlayer: same root node, same track paths
	tree.anim_player = tree.get_path_to(ap)
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var bt := AnimationNodeBlendTree.new()
	var anim := func(node_name: String, clip: String, pos: Vector2) -> void:
		var a := AnimationNodeAnimation.new()
		a.animation = StringName(clip if ap.has_animation(clip) else "walk")
		bt.add_node(node_name, a, pos)
	var seek := func(node_name: String, clip: String, pos: Vector2) -> void:
		anim.call(node_name, clip, pos)
		bt.add_node(node_name + "_seek", AnimationNodeTimeSeek.new(), pos + Vector2(160, 0))
		bt.connect_node(node_name + "_seek", 0, node_name)
	seek.call("walk", "walk", Vector2(0, 0))
	seek.call("chase", "chase", Vector2(0, 120))
	seek.call("down", "walk_stairs_down", Vector2(0, 240))
	seek.call("up", "walk_stairs", Vector2(0, 360))
	seek.call("duck", "duck_walk", Vector2(0, 480))
	seek.call("jump", "jumpscare", Vector2(0, 960))
	anim.call("idle", "idle", Vector2(0, 600))
	anim.call("search", "search", Vector2(0, 720))
	anim.call("reach", "reach", Vector2(0, 840))
	bt.add_node("chaseB", AnimationNodeBlend2.new(), Vector2(400, 60))
	bt.connect_node("chaseB", 0, "walk_seek")
	bt.connect_node("chaseB", 1, "chase_seek")
	bt.add_node("stairsB", AnimationNodeBlend3.new(), Vector2(600, 200))
	bt.connect_node("stairsB", 0, "down_seek")
	bt.connect_node("stairsB", 1, "chaseB")
	bt.connect_node("stairsB", 2, "up_seek")
	var duckb := AnimationNodeBlend2.new()
	duckb.filter_enabled = true
	var prefix := String(inst.get_path_to(skeleton)) + ":"
	for i in skeleton.get_bone_count():
		var bn := skeleton.get_bone_name(i)
		if not LOWER_BODY.has(bn): duckb.set_filter_path(NodePath(prefix + bn), true)
	bt.add_node("duckB", duckb, Vector2(800, 300))
	bt.connect_node("duckB", 0, "stairsB")
	bt.connect_node("duckB", 1, "duck_seek")
	bt.add_node("moveB", AnimationNodeBlend2.new(), Vector2(1000, 450))
	bt.connect_node("moveB", 0, "idle")
	bt.connect_node("moveB", 1, "duckB")
	bt.add_node("searchB", AnimationNodeBlend2.new(), Vector2(1200, 600))
	bt.connect_node("searchB", 0, "moveB")
	bt.connect_node("searchB", 1, "search")
	bt.add_node("reachB", AnimationNodeBlend2.new(), Vector2(1400, 750))
	bt.connect_node("reachB", 0, "searchB")
	bt.connect_node("reachB", 1, "reach")
	bt.add_node("jumpB", AnimationNodeBlend2.new(), Vector2(1600, 900))
	bt.connect_node("jumpB", 0, "reachB")
	bt.connect_node("jumpB", 1, "jump_seek")
	bt.connect_node("output", 0, "jumpB")
	tree.tree_root = bt
	tree.active = true

# ---------------------------------------------------------------- materials

func _setup_materials(inst: Node3D) -> void:
	var shared := {}   # imported material -> our copy (eyes / glints share one)
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		_meshes.append(mi)
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED   # moving character: receives GI, never baked into SDFGI
		var nm := String(mi.name)
		var kind := "skin"
		if nm.begins_with("glint"): kind = "glint"
		elif nm.begins_with("eye"): kind = "eye"
		elif nm.ends_with("head"): kind = "face"
		elif nm.ends_with("teeth"): kind = "teeth"
		elif nm.ends_with("gown"): kind = "gown"
		elif nm.ends_with("hair"): kind = "hair"
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind in ["glint", "eye", "teeth"] \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s)
			if not (src is BaseMaterial3D): continue
			var m: BaseMaterial3D = shared.get(src)
			if m == null:
				m = (src as BaseMaterial3D).duplicate() as BaseMaterial3D
				_configure(m, kind)
				shared[src] = m
				_mats.append(m)
				_base[m] = [m.albedo_color, m.metallic_specular, m.clearcoat, m.rim]
			mi.set_surface_override_material(s, m)

func _configure(m: BaseMaterial3D, kind: String) -> void:
	m.resource_local_to_scene = false
	match kind:
		"skin", "face":
			# web: MeshPhysicalMaterial roughness 0.58 / 0.5, specularIntensity 0.7, clearcoat 0.12 (0.45). Subsurface
			# scattering stays low on the body (dead, waxy skin: a strong blur would flatten her bones in a frontal beam)
			# and a little higher on the face (the jumpscare close-up); transmittance reddens thin fingers against a light.
			m.roughness = 0.5 if kind == "face" else 0.55
			m.metallic_specular = 0.35
			m.normal_scale = 0.9 if kind == "face" else 0.85
			m.clearcoat_enabled = true
			m.clearcoat = 0.12
			m.clearcoat_roughness = 0.45
			m.subsurf_scatter_enabled = true
			m.subsurf_scatter_skin_mode = true
			m.subsurf_scatter_strength = 0.22 if kind == "face" else 0.1
			m.subsurf_scatter_transmittance_enabled = true
			m.subsurf_scatter_transmittance_color = Color(0.5, 0.13, 0.09)
			m.subsurf_scatter_transmittance_depth = 0.06
			m.subsurf_scatter_transmittance_boost = 0.0
		"teeth":
			m.roughness = 0.32
			m.clearcoat_enabled = true
			m.clearcoat = 0.7
			m.clearcoat_roughness = 0.15
			m.subsurf_scatter_enabled = true
			m.subsurf_scatter_strength = 0.15
		"eye":
			m.roughness = 0.12
			m.clearcoat_enabled = true
			m.clearcoat = 1.0
			m.clearcoat_roughness = 0.04
			m.rim_enabled = true      # web sheen 0.5, sheen colour grey-green
			m.rim = 0.5
			m.rim_tint = 0.2
		"glint":
			m.emission_enabled = true
			m.emission = Color("fff2dc")
			m.emission_energy_multiplier = 0.25 + 0.1 * 7.0
			_glints.append(m)
		"gown":
			# web: fabric032 woven cotton, sheen 0.7 (colour 0.8/0.78/0.7, roughness 0.75), tear alpha test 0.5
			m.rim_enabled = true
			m.rim = 0.55
			m.rim_tint = 0.65
			m.backlight_enabled = true
			m.backlight = Color(0.16, 0.14, 0.11)
			m.metallic_specular = 0.4
			m.alpha_scissor_threshold = 0.5
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			_alpha_mats.append(m)
		"hair":
			# web: alpha-tested fibre ribbons (0.42), double-sided, roughness 0.6, specularIntensity 0.08. Its albedo is
			# ~0.003 linear: under a lamp the curtain read as a flat black hole, so the wet clumps get a soft sheen
			# (Godot's GGX at roughness 0.45) and a hair more albedo — still black, but with form.
			m.albedo_color = Color(1.8, 1.75, 1.7)
			m.roughness = 0.45
			m.metallic_specular = 0.3
			m.alpha_scissor_threshold = 0.42
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			_alpha_mats.append(m)

## Quality preset (low | medium | high | ultra): "low" drops the subsurface scattering / transmittance / clear coat
## (cheapest shading); then refresh_aa(). Call after the look module applied the preset to the viewport.
func apply_quality(q: String) -> void:
	_quality = q
	var rich := q != "low"
	for m in _mats:
		if m.subsurf_scatter_strength > 0.0: m.subsurf_scatter_enabled = rich
		if m.subsurf_scatter_transmittance_depth > 0.0 and m.subsurf_scatter_skin_mode: m.subsurf_scatter_transmittance_enabled = rich
		if m.clearcoat > 0.0 or float(_base[m][2]) > 0.0: m.clearcoat_enabled = rich
	refresh_aa()

## Hair / gown alpha: alpha-to-coverage when the viewport uses MSAA, alpha hash when it uses TAA, plain scissor otherwise.
## Call again after a quality change (the look module applies it to the viewport).
func refresh_aa() -> void:
	var vp := get_viewport()
	var msaa := vp != null and vp.msaa_3d != Viewport.MSAA_DISABLED
	# FSR 2 does its own temporal accumulation (use_taa is off while it runs): treat it like TAA
	var taa := vp != null and (vp.use_taa or vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR2)
	for m in _alpha_mats:
		if msaa:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
			m.alpha_antialiasing_edge = 0.3
		elif taa:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
			m.alpha_hash_scale = 1.0
			m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_OFF
		else:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_OFF

## Scales the albedo + specular terms of every material (1 = normal). The jumpscare uses it as a camera-style exposure:
## her face 0.3 m from the flashlight would otherwise burn to white.
func set_exposure(k: float) -> void:
	if absf(k - _expo) < 0.01: return
	_expo = k
	for m in _mats:
		var b: Array = _base[m]
		var c: Color = b[0]
		m.albedo_color = Color(c.r * k, c.g * k, c.b * k, c.a)
		m.metallic_specular = float(b[1]) * k
		m.clearcoat = float(b[2]) * k
		m.rim = float(b[3]) * k

# ---------------------------------------------------------------- fallback silhouette

func _build_fallback() -> void:
	ok = false
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.07, 0.065, 0.06)
	mat.roughness = 0.9
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.17
	cap.height = 1.72
	body.mesh = cap
	body.position = Vector3(0, 0.9, 0)
	body.rotation.x = 0.12
	body.material_override = mat
	add_child(body)
	head_attach = Node3D.new()
	head_attach.name = "head"
	head_attach.position = Vector3(0, 1.74, 0.08)
	head_attach.rotation.x = 0.35
	add_child(head_attach)
	var head := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.1
	sp.height = 0.26
	head.mesh = sp
	head.position = Vector3(0, 0.07, 0)
	head.material_override = mat
	head_attach.add_child(head)

# ====================================================================== per frame

## Advances the pose by dt from the inputs above (web GardienneModel.update(dt, ctx)).
func update(dt: float) -> void:
	dt = minf(dt, 0.05)
	time += dt
	if not ok: return
	var jumping := jump_t >= 0.0 or mode == "jumpscare"
	var chase := mode == "chase"
	if debug_freeze: dt = 0.0
	_speed = _damp(_speed, speed, 8.0, dt)
	_move_w = _damp(_move_w, clampf(speed / 0.45, 0.0, 1.0), 6.0, dt)
	_chase_w = _damp(_chase_w, 1.0 if chase else 0.0, 5.0 if chase else 2.0, dt)
	_search_w = _damp(_search_w, 1.0 if mode == "search" else 0.0, 3.0, dt)
	_reach_w = _damp(_reach_w, 1.0 if mode == "reach" else 0.0, 5.0, dt)
	_stairs = _damp(_stairs, float(stairs), 5.0, dt)
	_duck = _damp(_duck, duck, 5.0, dt)

	# ---- gait phase + footsteps (web: phase += dt * PI * speed / stepLen, heel strikes at PI/2 (L) and 3PI/2 (R))
	var step_len := lerpf(0.6, 1.0, _chase_w) * (0.62 if absf(_stairs) > 0.3 else 1.0)
	var prev := _phase
	if _speed > 0.03 and not jumping:
		_phase = fposmod(_phase + dt * _speed / (2.0 * step_len), _wrap)
	if _speed > 0.15 and not jumping and dt > 0.0:
		if _crossed(prev, _phase, 0.25): _step("L")
		if _crossed(prev, _phase, 0.75): _step("R")

	# ---- glitches (web: freeze 38 %, head snap 40 %, arm spasm 22 %)
	if not debug_freeze:
		_glitch_t -= dt
		if _glitch_t <= 0.0 and not jumping:
			_glitch_t = (1.8 if chase else 4.0) + randf() * (3.0 if chase else 8.0) - aggression * 0.6
			var k := randf()
			if k < 0.38:
				_freeze = 0.07 + randf() * 0.16
			elif k < 0.78:
				_snap_t = 0.1 + randf() * 0.22
				_snap_yaw = (randf() - 0.5) * 1.3
				_snap_roll = (-1.0 if randf() < 0.5 else 1.0) * (0.4 + randf() * 0.5)
			else:
				_spasm_t = 0.18 + randf() * 0.2
	if jumping: _eyeshine = 0.3
	elif debug_freeze: _eyeshine = eyeshine_target
	else: _eyeshine = _damp(_eyeshine, eyeshine_target, 6.0, dt)
	var ge := 0.25 + _eyeshine * 7.0
	for g in _glints:
		if absf(g.emission_energy_multiplier - ge) > 0.01: g.emission_energy_multiplier = ge
	if _freeze > 0.0 and not jumping:
		_freeze -= dt
		return   # "frame skip": the pose is held (tree not advanced, pose layer unchanged) while she keeps moving

	# ---- look-at weight (web look rates: 16 searching, 10 chasing, 4 otherwise)
	var look_rate := 16.0 if _search_w > 0.5 else (10.0 if _chase_w > 0.5 else 4.0)
	if jumping: _look_w = 0.0
	elif debug_freeze: _look_w = 1.0 if look_on else 0.0
	else: _look_w = _damp(_look_w, 1.0 if look_on else 0.0, look_rate, dt)

	# ---- tree inputs
	for g in GAIT:
		var c: Dictionary = clips[g]
		tree.set(SEEK[g], fposmod((_phase - float(c.phi0)) * float(c.cycle), float(c.len)) if float(c.cycle) > 0.0 else 0.0)
	tree.set(P_CHASE, _chase_w)
	tree.set(P_STAIRS, clampf(_stairs, -1.0, 1.0))
	tree.set(P_DUCK, _duck)
	tree.set(P_MOVE, _move_w)
	tree.set(P_SEARCH, _search_w)
	tree.set(P_REACH, _reach_w)
	tree.set(P_JUMP, 1.0 if jumping else 0.0)
	if jumping: tree.set(SEEK.jumpscare, clampf(jump_t, 0.0, _jump_len - 0.001))
	tree.advance(dt)

	# ---- procedural layer
	if look_on: pose_layer.look_target = look_target
	pose_layer.look_w = _look_w
	if _snap_t > 0.0 and not jumping:
		_snap_t -= dt
		pose_layer.snap_yaw = _snap_yaw
		pose_layer.snap_roll = _snap_roll
	else:
		pose_layer.snap_yaw = 0.0
		pose_layer.snap_roll = 0.0
	if _spasm_t > 0.0 and not jumping:
		_spasm_t -= dt
		pose_layer.spasm = sin(time * 61.0) * 0.35
		pose_layer.spasm_chest = sin(time * 47.0) * 0.08
	else:
		pose_layer.spasm = 0.0
		pose_layer.spasm_chest = 0.0

## Debug / screenshots: snap every blend weight to `m` and the clip time to `t` (no damping, no glitch).
func debug_pose(m: String, t: float, spd := -1.0) -> void:
	mode = m
	debug_freeze = true
	var walking := m in ["walk", "duck_walk", "stairs_up", "stairs_down", "stairs_duck"]
	var sp := spd if spd >= 0.0 else (2.9 if m == "chase" else (0.95 if walking else 0.0))
	speed = sp
	_speed = sp
	_move_w = clampf(sp / 0.45, 0.0, 1.0)
	_chase_w = 1.0 if m == "chase" else 0.0
	_search_w = 1.0 if m == "search" else 0.0
	_reach_w = 1.0 if m == "reach" else 0.0
	stairs = 1 if m == "stairs_up" else (-1 if m in ["stairs_down", "stairs_duck"] else 0)
	_stairs = float(stairs)
	duck = 1.0 if m in ["duck_walk", "stairs_duck"] else 0.0
	_duck = duck
	_freeze = 0.0
	_snap_t = 0.0
	_spasm_t = 0.0
	_look_w = 0.0
	jump_t = t if m == "jumpscare" else -1.0
	var gc := "chase" if m == "chase" else ("walk_stairs" if m == "stairs_up" else ("walk_stairs_down" if m in ["stairs_down", "stairs_duck"] else "walk"))
	if clips.has(gc) and float(clips[gc].cycle) > 0.0:
		_phase = fposmod(t / float(clips[gc].cycle) + float(clips[gc].phi0), _wrap)
	if not ok: return
	# free-running clips (idle / search / reach): restart them and advance to t
	tree.set(P_CHASE, _chase_w)
	tree.set(P_STAIRS, _stairs)
	tree.set(P_DUCK, _duck)
	tree.set(P_MOVE, _move_w)
	tree.set(P_SEARCH, _search_w)
	tree.set(P_REACH, _reach_w)
	tree.set(P_JUMP, 1.0 if m == "jumpscare" else 0.0)
	for g in GAIT:
		var c: Dictionary = clips[g]
		tree.set(SEEK[g], fposmod((_phase - float(c.phi0)) * float(c.cycle), float(c.len)))
	if m == "jumpscare": tree.set(SEEK.jumpscare, clampf(t, 0.0, _jump_len - 0.001))
	tree.advance(0.0)
	if m in ["idle", "search", "reach"] and t > 0.0: tree.advance(t)

## Instantly forget the smoothed look / glitch state (after teleports). The hair is baked, nothing else to reset.
func reset_simulation() -> void:
	_look_w = 0.0
	_freeze = 0.0
	_snap_t = 0.0
	_spasm_t = 0.0

func _step(side: String) -> void:
	footstep.emit(side, get_foot_world(side))

func _crossed(a: float, b: float, x: float) -> bool:
	if b < a: b += _wrap
	var n := floorf(a - x) + 1.0
	return x + n <= b

func _damp(cur: float, target: float, rate: float, dt: float) -> float:
	return cur + (target - cur) * (1.0 - exp(-rate * dt))

# ====================================================================== attach points (web getFaceWorld / getEyeWorld / getHeadWorld)

func head_transform() -> Transform3D:
	if ok and _bone_head >= 0:
		return skeleton.global_transform * skeleton.get_bone_global_pose(_bone_head)
	if head_attach != null: return head_attach.global_transform
	return global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 1.8, 0))

func get_face_world() -> Vector3: return head_transform() * Vector3(0.0, 0.06, 0.1)
func get_eye_world() -> Vector3: return head_transform() * Vector3(0.0, 0.09, 0.07)
func get_head_world() -> Vector3: return head_transform() * Vector3(0.0, 0.07, 0.0)

func get_foot_world(side: String) -> Vector3:
	var i: int = _bone_foot.get(side, -1)
	if ok and i >= 0: return skeleton.global_transform * skeleton.get_bone_global_pose(i).origin
	return global_position + global_basis * Vector3(0.085 if side == "L" else -0.085, 0.05, 0.0)
