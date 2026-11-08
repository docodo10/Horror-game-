## UI module — the diegetic main menu ON the dresser TV (port of the web UI "TV menu (3D)" section).
## A curved glass mesh fitted over the television_02 screen shows the P100 teletext pages (SubViewport) through the CRT
## shader (shaders/ui_crt_tv.gdshader). The menu camera frames the TV (web updateMenuCamera): a dedicated Camera3D made
## current while the menu is up — it copies the game camera's attributes / environment / compositor so it renders like
## it, and the player blends from its framing when the game starts (player.gd reads the current camera). Picking: camera ray →
## curved glass (analytic) → page UV → teletext line. "Nouvelle partie": static burst + power-off collapse (1.2 s, wall
## clock), fade to black, then the UI emits Events.ui_start.
## TV lookup: Game.world.tv (Node3D or object with `node`) → a MeshInstance3D with the television_02 bounds
## (0.40 × 0.41 × 0.35 m) → its frame; else any such mesh under Game.world; else Layout.PROPS.tv.
extends Node3D

const Style := preload("res://scripts/ui/ui_style.gd")
const TT := preload("res://scripts/ui/teletext.gd")
const CRT_SHADER := preload("res://shaders/ui_crt_tv.gdshader")

const MENU_FOV := 30.0
const GLASS_FRAC := 0.42          # glass height / screen height (web: 13 rows × 22 css px, clamped 0.34..0.74)
# television_02 glass (model space, measured from the GLB): centre 0.256 m above the model base, ~0.30 × 0.225 m,
# spherical bulge peaking at z ≈ 0.121 m.
const G_Y := 0.256
const G_HW := 0.148
const G_HH := 0.111
const G_ZC := 0.1228
const G_K := 0.8
const BRIGHT := 1.55

var ui: Node = null
var screen: TT = null
var mesh: MeshInstance3D = null
var mat: ShaderMaterial = null
var on := false
var found_model := false
var center := Vector3.ZERO
var nrm := Vector3.BACK
var up_v := Vector3.UP
var right_v := Vector3.RIGHT
var glass_w := G_HW * 2.0
var glass_h := G_HH * 2.0
var trans := {}                   # power-off transition {t, dur, faded, done, on_done: Callable}

var cam: Camera3D = null
var _cam_t := 0.0
var _cam_frame := -1
var _time := 0.0
var _light_mode := ""
var _hum: Variant = null
var _built := false

func setup(ui_: Node) -> void:
	ui = ui_
	name = "TvMenu"
	process_mode = Node.PROCESS_MODE_ALWAYS
	screen = TT.create(self, 32, 13, 14, 26, 16, 11, ui_, "TvTeletext")
	screen.home = "main"
	cam = Camera3D.new()
	cam.name = "MenuCamera"
	cam.near = 0.04
	cam.far = 120.0
	cam.fov = MENU_FOV
	add_child(cam)

## Builds the glass mesh in front of the TV (once, when the world exists).
func ensure() -> bool:
	if _built:
		return true
	if not is_inside_tree():
		return false
	_built = true
	var fr := _tv_frame()
	found_model = fr.found
	var xf: Transform3D = fr.xf
	var local := Transform3D(Basis(), Vector3(fr.ox, fr.oy + G_Y, G_ZC))
	mesh = MeshInstance3D.new()
	mesh.name = "TvMenuGlass"
	mesh.mesh = _glass_mesh()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mesh.extra_cull_margin = 0.5
	mat = ShaderMaterial.new()
	mat.shader = CRT_SHADER
	mat.render_priority = Material.RENDER_PRIORITY_MAX
	mat.set_shader_parameter("page", screen.get_texture())
	mat.set_shader_parameter("tex_size", Vector2(screen.W, screen.H))
	mat.set_shader_parameter("u_bright", BRIGHT)
	mesh.material_override = mat
	mesh.visible = false
	add_child(mesh)
	mesh.global_transform = xf * local
	var gx := mesh.global_transform
	center = gx.origin
	nrm = gx.basis.z.normalized()
	up_v = gx.basis.y.normalized()
	right_v = up_v.cross(nrm).normalized()
	glass_w = G_HW * 2.0 * gx.basis.x.length()
	glass_h = G_HH * 2.0 * gx.basis.y.length()
	return true

func _glass_mesh() -> ArrayMesh:
	var nx := 24
	var ny := 18
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in ny + 1:
		for i in nx + 1:
			var u := float(i) / nx
			var v := float(j) / ny
			var x := (u * 2.0 - 1.0) * G_HW
			var y := (1.0 - v * 2.0) * G_HH
			verts.append(Vector3(x, y, -G_K * (x * x + y * y)))
			uvs.append(Vector2(u, v))
			norms.append(Vector3(2.0 * G_K * x, 2.0 * G_K * y, 1.0).normalized())
	for j in ny:
		for i in nx:
			var a := j * (nx + 1) + i
			var b := a + 1
			var c := a + nx + 1
			var d := c + 1
			idx.append_array([a, b, c, b, d, c])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

## Locates the TV model frame: {xf: Transform3D, ox, oy, found}.
func _tv_frame() -> Dictionary:
	var world: Node = Game.world
	var roots: Array[Node] = []
	var screen_pos: Variant = null
	if world != null and is_instance_valid(world):
		var tv: Variant = world.get("tv")
		var n: Node = null
		if tv is Node3D:
			n = tv
		elif tv is Object and is_instance_valid(tv):
			var nn: Variant = (tv as Object).get("node")
			if nn is Node3D: n = nn
		if tv is Object and is_instance_valid(tv):
			screen_pos = (tv as Object).get("screen_position")
		if n != null:
			roots.append(n)
		roots.append(world)
	for r in roots:
		var mi := _find_tv_mesh(r)
		if mi != null:
			var bb := mi.get_aabb()
			return {"xf": mi.global_transform, "ox": bb.position.x + bb.size.x * 0.5, "oy": bb.position.y, "found": true}
	var p: Dictionary = Layout.PROPS.get("tv", {})
	if not p.is_empty():
		var pos: Array = p.pos
		var b := Basis(Vector3.UP, float(p.get("rotY", 0.0))).scaled(Vector3.ONE * float(p.get("scale", 1.0)))
		return {"xf": Transform3D(b, Vector3(pos[0], pos[1], pos[2])), "ox": -0.002, "oy": 0.0, "found": false}
	var sp: Vector3 = screen_pos if screen_pos is Vector3 else Vector3(-0.55, 1.468, -2.377)
	return {"xf": Transform3D(Basis(), sp - Vector3(0.0, G_Y, G_ZC)), "ox": 0.0, "oy": 0.0, "found": false}

func _find_tv_mesh(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D and _is_tv_mesh(root):
		return root
	for c in root.find_children("*", "MeshInstance3D", true, false):
		if _is_tv_mesh(c):
			return c
	return null

func _is_tv_mesh(mi: MeshInstance3D) -> bool:
	if mi.mesh == null or not mi.is_inside_tree():
		return false
	var s := mi.get_aabb().size
	return absf(s.x - 0.4) < 0.03 and absf(s.y - 0.411) < 0.03 and absf(s.z - 0.35) < 0.03

# ================================================================ on / off

func activate() -> void:
	if not ensure():
		return
	if on:
		return
	on = true
	mesh.visible = true
	mat.set_shader_parameter("u_collapse", 0.0)
	mat.set_shader_parameter("u_static", 0.05)
	screen.set_active(true)
	screen.fresh()
	_light_mode = ""
	var world: Node = Game.world
	if world != null and is_instance_valid(world):
		var L: Variant = world.get("lighting")
		var tv: Variant = world.get("tv")
		if L is Object and is_instance_valid(L) and (L as Object).has_method("set_tv_light"):
			L.set_tv_light(true, 1.0)
			_light_mode = "light"
		elif tv is Object and is_instance_valid(tv) and (tv as Object).has_method("set_on") and not bool((tv as Object).get("is_on")):
			tv.set_on(true)
			_light_mode = "tv"
		if L is Object and is_instance_valid(L) and (L as Object).has_method("set_menu_mode"):
			L.set_menu_mode(true)              # ceiling bulb on a faint dimmer, the CRT as the key light
	if _hum == null:
		_hum = Audio.loop("tv_static", {"position": center, "volume_db": linear_to_db(0.045)})

func deactivate() -> void:
	var was := on
	on = false
	trans = {}
	if screen:
		screen.locked = false
		screen.set_active(false)
	if mesh:
		mesh.visible = false
	if not was:
		return
	var world: Node = Game.world
	if world != null and is_instance_valid(world):
		var L: Variant = world.get("lighting")
		var tv: Variant = world.get("tv")
		var tv_on := tv is Object and is_instance_valid(tv) and bool((tv as Object).get("is_on"))
		if _light_mode == "light" and L is Object and is_instance_valid(L) and not tv_on:
			L.set_tv_light(false, 0.0)
		elif _light_mode == "tv" and tv is Object and is_instance_valid(tv) and (tv as Object).has_method("set_on"):
			tv.set_on(false)
		if L is Object and is_instance_valid(L) and (L as Object).has_method("set_menu_mode"):
			L.set_menu_mode(false)
	_light_mode = ""
	_stop_hum()
	call_deferred("_release_camera")

func _stop_hum() -> void:
	if _hum is Object and is_instance_valid(_hum) and (_hum as Object).has_method("stop"):
		_hum.stop(0.4)
	elif _hum is Dictionary and (_hum as Dictionary).get("stop") is Callable:
		(_hum.stop as Callable).call(0.4)
	_hum = null

## After the menu (deferred, so the player's game_state handler can still read the menu framing): hand the view back
## to the player camera if nothing else did.
func _release_camera() -> void:
	if on or not cam.current:
		return
	var gc: Camera3D = Game.camera
	if gc != null and is_instance_valid(gc) and gc.is_inside_tree():
		gc.make_current()
	else:
		cam.current = false

func _exit_tree() -> void:
	_stop_hum()

# ================================================================ per frame

func process_frame(dt: float) -> void:
	if not on:
		return
	_time += dt
	screen.tick(dt)
	mat.set_shader_parameter("u_time", _time)
	mat.set_shader_parameter("u_burst", screen.burst_amount())
	if not trans.is_empty():
		_trans_step()
	else:
		mat.set_shader_parameter("u_static", 0.025 + screen.flick * 0.22)
		mat.set_shader_parameter("u_jitter", 0.2 + screen.flick * 1.1)

## The menu camera renders like the game camera (exposure / DOF / environment overrides set by the look module).
func _sync_from_game_camera() -> void:
	var gc: Camera3D = Game.camera
	if gc == null or not is_instance_valid(gc) or gc == cam:
		return
	if cam.attributes != gc.attributes: cam.attributes = gc.attributes
	if cam.environment != gc.environment: cam.environment = gc.environment
	if cam.compositor != gc.compositor: cam.compositor = gc.compositor
	cam.cull_mask = gc.cull_mask

## Writes the menu camera (web updateMenuCamera). Safe to call several times per frame.
func update_camera(dt: float) -> void:
	if not _built:
		return
	_sync_from_game_camera()
	if not cam.current:
		cam.make_current()
	var frame := Engine.get_process_frames()
	if frame != _cam_frame:
		_cam_frame = frame
		_cam_t += dt
	if absf(cam.fov - MENU_FOV) > 0.001:
		cam.fov = MENU_FOV
	var vs := get_viewport().get_visible_rect().size
	var asp := vs.x / maxf(1.0, vs.y)
	var h := glass_h / GLASS_FRAC
	h = maxf(h, maxf(glass_w / (0.86 * asp), (glass_w * 1.42) / (0.98 * asp)))
	var d := h / (2.0 * tan(deg_to_rad(MENU_FOV) * 0.5))
	if not trans.is_empty():
		d *= 1.0 - 0.14 * Style.smooth(0.0, 1.0, float(trans.t) / float(trans.dur))
	var m := Style.clamp01(float(Settings.get_value("camera_motion", 1.0)))
	var t := _cam_t
	var dx := (sin(t * 0.31) * 0.6 + sin(t * 0.77 + 1.3) * 0.4) * 0.012 * m
	var dy := (sin(t * 0.23 + 0.7) * 0.6 + sin(t * 0.61) * 0.4) * 0.008 * m + sin(t * 1.15) * 0.0025 * m
	var p := center + nrm * d + right_v * (0.085 * d + dx) + up_v * (-0.06 * d + dy)
	var tg := center + right_v * (sin(t * 0.17) * 0.004 * m) + up_v * (cos(t * 0.13) * 0.003 * m - 0.004)
	var xf := Transform3D(Basis(), p).looking_at(tg, Vector3.UP)
	xf.basis = xf.basis * Basis(Vector3(0, 0, 1), sin(t * 0.29) * 0.006 * m - 0.004)
	cam.global_transform = xf

## Mouse position (viewport coordinates) → {it, side} of the teletext line under it, or {}.
func pick(pos: Vector2) -> Dictionary:
	if not on or mesh == null:
		return {}
	var c := cam if cam.current else get_viewport().get_camera_3d()
	if c == null:
		return {}
	var o := c.project_ray_origin(pos)
	var dir := c.project_ray_normal(pos)
	var inv := mesh.global_transform.affine_inverse()
	var lo := inv * o
	var ld := (inv.basis * dir)
	if absf(ld.z) < 1e-6:
		return {}
	var tp := -lo.z / ld.z
	for i in 3:
		var pt := lo + ld * tp
		var z := -G_K * (pt.x * pt.x + pt.y * pt.y)
		tp = (z - lo.z) / ld.z
	if tp < 0.0:
		return {}
	var hp := lo + ld * tp
	var x := hp.x / G_HW
	var y := hp.y / G_HH
	var f := 1.0 + 0.045 * (x * x + y * y)
	x = x * f * 0.5 + 0.5
	y = y * f * 0.5 + 0.5
	if x < 0.0 or x > 1.0 or y < 0.0 or y > 1.0:
		return {}
	return screen.hit(x, 1.0 - y)

# ================================================================ power-off transition

## Static burst + CRT collapse (1.2 s, wall clock), fade to black at 0.82 s, then on_done (ui_start / quit).
func power_off(on_done: Callable) -> void:
	if not trans.is_empty() or not on:
		return
	trans = {"t": 0.0, "dur": 1.2, "faded": false, "done": false, "last": Style.now(), "on_done": on_done}
	screen.locked = true
	if ui:
		ui.sfx("off")

func _trans_step() -> void:
	var tn := Style.now()
	trans.t = float(trans.t) + minf(0.25, tn - float(trans.last))
	trans.last = tn
	var t: float = trans.t
	var collapse := Style.clamp01((t - 0.22) / 0.78)
	mat.set_shader_parameter("u_static", (0.9 - t * 1.5) if t < 0.28 else maxf(0.0, 0.5 - t))
	mat.set_shader_parameter("u_jitter", 3.0 if t < 0.28 else 1.0)
	mat.set_shader_parameter("u_collapse", collapse)
	if _light_mode == "light":
		var world: Node = Game.world
		var L: Variant = world.get("lighting") if world != null and is_instance_valid(world) else null
		if L is Object and is_instance_valid(L) and (L as Object).has_method("set_tv_light"):
			L.set_tv_light(true, maxf(0.0, 1.0 - collapse * 1.2))
	if not trans.faded and t >= 0.82:
		trans.faded = true
		if ui:
			ui.fade_to(1.0, 0.36)
	if not trans.done and t >= float(trans.dur):
		trans.done = true
		var cb: Callable = trans.on_done
		if cb.is_valid():
			cb.call()
