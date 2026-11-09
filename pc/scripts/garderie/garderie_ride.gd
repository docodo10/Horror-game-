## Slide ride: takes the player's camera (player.camera_override) down a slide's Curve3D with a simple physical speed
## model (gravity along the slope, sliding friction, extra friction from the centripetal load in curves, air drag),
## look-ahead, banking, speed shake, a plastic whoosh whose volume / pitch follow the speed, squeaks, a loud landing
## (Events.noise 0.8 at the bottom: La Gardienne hears it), then glides out on the floor with the remaining momentum,
## stands up and hands the camera back exactly where the player now stands.
## Slide dictionary (garderie_play.gd): {curve: Curve3D (surface centre line, top -> bottom), exit_dir: Vector3,
##   mu: float, mu_out: float, out_from: float (arc length where the run-out starts), eye: float, kind: "wave"|"spiral"}
extends Node

const G := 9.8
const DRAG := 0.02
const VMAX := 7.5
const STAND_EYE := 1.62

var garderie
var _cancel := false
var _shake := Vector3.ZERO

## Pure simulation (no camera): {exit_pos, duration, vmax, v_end} — used by the tests and to plan the glide-out.
static func simulate(s: Dictionary, dt := 1.0 / 60.0) -> Dictionary:
	var curve: Curve3D = s.curve
	var L := curve.get_baked_length()
	var d := 0.0
	var v := 0.9
	var t := 0.0
	var vmax := 0.0
	while d < L and t < 60.0:
		v = _step_speed(s, curve, d, v, dt)
		d += v * dt
		t += dt
		vmax = maxf(vmax, v)
	var glide := _glide_dist(v)
	var end := curve.sample_baked(L)
	var dir: Vector3 = s.get("exit_dir", Vector3.RIGHT)
	var ex := end + dir * (0.45 + glide)
	ex.y = float(s.get("floor_y", end.y))
	return {"exit_pos": ex, "duration": t, "vmax": vmax, "v_end": v, "glide": glide}

static func _glide_dist(v_end: float) -> float:
	return clampf(v_end * v_end / (2.0 * 0.6 * G), 0.0, 1.2)

static func _tangent(curve: Curve3D, d: float) -> Vector3:
	var L := curve.get_baked_length()
	var a := curve.sample_baked(clampf(d - 0.05, 0.0, L))
	var b := curve.sample_baked(clampf(d + 0.05, 0.0, L))
	var t := b - a
	return t.normalized() if t.length_squared() > 1e-10 else Vector3.FORWARD

static func _step_speed(s: Dictionary, curve: Curve3D, d: float, v: float, dt: float) -> float:
	var tan := _tangent(curve, d)
	var sin_t := -tan.y
	var cos_t := sqrt(maxf(0.0, 1.0 - sin_t * sin_t))
	var mu: float = s.get("mu", 0.2)
	if d >= float(s.get("out_from", 1e9)):
		mu = float(s.get("mu_out", 0.55))
	# centripetal load in curves (horizontal turning radius from the heading change)
	var t2 := _tangent(curve, d + 0.3)
	var h1 := Vector2(tan.x, tan.z)
	var h2 := Vector2(t2.x, t2.z)
	var curv := 0.0
	if h1.length() > 0.2 and h2.length() > 0.2:
		curv = absf(h1.normalized().angle_to(h2.normalized())) / 0.3
	var a := G * sin_t - mu * (G * cos_t + v * v * curv) - DRAG * v * v
	return clampf(v + a * dt, 0.55, VMAX)

func cancel() -> void:
	_cancel = true

func run(s: Dictionary) -> void:
	var g = garderie
	var p: Node = g._player()
	if p == null or p.get("hidden") == true or p.get("camera_override") == true:
		return
	var cam: Camera3D = p.get("camera")
	if cam == null:
		return
	g.ride_active = true
	_cancel = false
	p.set("camera_override", true)
	var curve: Curve3D = s.curve
	var L := curve.get_baked_length()
	var eye: float = s.get("eye", 0.74)
	var whoosh = g._loop("slide_whoosh", cam.global_position, -40.0)
	# 1) sit down at the top
	await _blend(cam, cam.global_transform, _pose(s, curve, 0.0, 0.0, eye), 0.6)
	g._play("slide_squeak", cam.global_position, -6.0, 1.1)
	# 2) slide
	var d := 0.0
	var v := 0.9
	var squeak_t := 0.5
	var mid_noise := false
	while d < L and not _cancel:
		await get_tree().process_frame
		if not is_inside_tree() or _cancel:
			break
		if _camera_taken():
			_cancel = true
			break
		var dt := get_process_delta_time()
		if dt <= 0.0:
			continue
		v = _step_speed(s, curve, d, v, dt)
		d = minf(d + v * dt, L)
		var xf := _pose(s, curve, d, v, eye)
		_shake = _shake.lerp(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.0045 * v, clampf(dt * 20.0, 0.0, 1.0))
		xf.basis = xf.basis * Basis.from_euler(_shake)
		cam.global_transform = xf
		if whoosh is Object and is_instance_valid(whoosh):
			if whoosh.has_method("set_volume_db"):
				whoosh.set_volume_db(lerpf(-30.0, -4.0, clampf(v / 6.0, 0.0, 1.0)))
			if whoosh.has_method("set_position"):
				whoosh.set_position(xf.origin)
		squeak_t -= dt
		if squeak_t <= 0.0:
			squeak_t = randf_range(0.35, 1.1)
			g._play("slide_squeak", xf.origin, lerpf(-14.0, -5.0, clampf(v / 6.0, 0.0, 1.0)), randf_range(0.9, 1.35))
		if not mid_noise and d > L * 0.5:
			mid_noise = true
			g._noise(xf.origin, 0.35, "slide")
	if whoosh is Object and is_instance_valid(whoosh) and whoosh.has_method("stop"):
		whoosh.stop(0.25)
	if _cancel:
		g.ride_active = false
		if not _camera_taken():
			p.set("camera_override", false)
		return
	# 3) the bottom: thump + noise, glide out with the remaining speed while standing up
	var end := curve.sample_baked(L)
	var dir: Vector3 = s.get("exit_dir", _tangent(curve, L))
	dir.y = 0.0
	dir = dir.normalized()
	g._play("slide_land", end, -2.0, randf_range(0.9, 1.05))
	g._noise(end, 0.8, "slide")
	var glide := 0.45 + _glide_dist(v)
	var floor_y: float = s.get("floor_y", end.y)
	var stand := Vector3(end.x, floor_y, end.z) + dir * glide
	var yaw := atan2(-dir.x, -dir.z)
	var from := cam.global_transform
	var to := Transform3D(Basis.from_euler(Vector3(-0.08, yaw, 0.0)), stand + Vector3(0, STAND_EYE, 0))
	await _blend(cam, from, to, clampf(0.35 + glide / maxf(v, 0.8), 0.45, 1.1), true)
	# 4) put the player there (the area's floor heights are lower than the house: ground override while teleporting)
	if p.has_method("teleport"):
		var w = Game.world
		Game.world = g
		p.teleport(stand, yaw, -0.08)
		Game.world = w
	p.set("camera_override", false)
	g.ride_active = false

func _camera_taken() -> bool:
	if Game.state != "playing" and Game.state != "paused":
		return true
	var e: Node = Game.entity if is_instance_valid(Game.entity) else null
	return e != null and String(e.get("state")) == "jumpscare"

## Camera pose on the slide: sitting eye above the surface point, looking ahead and slightly down, banked in curves.
func _pose(s: Dictionary, curve: Curve3D, d: float, v: float, eye: float) -> Transform3D:
	var L := curve.get_baked_length()
	var p := curve.sample_baked(clampf(d, 0.0, L))
	var ahead := curve.sample_baked(clampf(d + 1.6 + v * 0.25, 0.0, L))
	var fwd := ahead - p
	if fwd.length_squared() < 1e-6:
		fwd = s.get("exit_dir", Vector3.RIGHT)
	fwd = fwd.normalized()
	fwd = (fwd + Vector3(0, -0.12, 0)).normalized()
	var t1 := _tangent(curve, d)
	var t2 := _tangent(curve, d + 0.5)
	var turn := Vector2(t1.x, t1.z).angle_to(Vector2(t2.x, t2.z)) if Vector2(t1.x, t1.z).length() > 0.2 and Vector2(t2.x, t2.z).length() > 0.2 else 0.0
	var roll := clampf(-turn * v * 0.35, -0.38, 0.38)
	var b := Basis.looking_at(fwd, Vector3.UP)
	b = b * Basis(Vector3.FORWARD, roll)
	return Transform3D(b, p + Vector3(0, eye, 0))

func _blend(cam: Camera3D, from: Transform3D, to: Transform3D, dur: float, ease_out := false) -> void:
	var t := 0.0
	var qa := from.basis.orthonormalized().get_rotation_quaternion()
	var qb := to.basis.orthonormalized().get_rotation_quaternion()
	while t < dur and not _cancel:
		await get_tree().process_frame
		if not is_inside_tree() or _camera_taken():
			_cancel = true
			return
		t += get_process_delta_time()
		var k := clampf(t / dur, 0.0, 1.0)
		k = 1.0 - pow(1.0 - k, 3.0) if ease_out else k * k * (3.0 - 2.0 * k)
		cam.global_transform = Transform3D(Basis(qa.slerp(qb, k)), from.origin.lerp(to.origin, k))
