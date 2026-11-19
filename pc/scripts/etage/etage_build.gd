## Geometry of l'étage (etage_layout.gd): the hallway, the salon under its dust sheets, her bedroom, the closet, the
## doors and windows, the standing figures (the kitchen, the pantry, the bathroom and the stairwell are in
## etage_rooms.gd). Built with the garderie's kit / build context (regions, colliders, shared material factory).
## What moves at runtime gets a region of its own, authored around its pivot (door leaves around their hinge, figures
## around their feet, the pillow around its middle): etage.gd places and drives those nodes. Things etage.gd needs
## are left in c.room_fx (lights, positions).
extends RefCounted

const L := preload("res://scripts/etage/etage_layout.gd")
const Kit := preload("res://scripts/garderie/garderie_kit.gd")
const Shell := preload("res://scripts/garderie/garderie_shell.gd")

const DARK_WOOD := Color.WHITE                 # the "panel" material is already stained
const TRIM := Color(0.2, 0.13, 0.08)
const IVORY := Color(0.66, 0.62, 0.52)
const MOON := Color(0.52, 0.66, 1.0)
const MASK := 1 | L.L_ET

static func build(c) -> void:
	c.room_fx["moon"] = []
	c.room_fx["sconces"] = []
	_hall(c)
	_salon(c)
	_chambre(c)
	_closet(c)
	_figures(c)
	_finish(c)

# ====================================================================== helpers

static func _xf(pos: Vector3, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), pos)

static func _doc(i: int) -> Rect2:
	return Rect2(0.5 * float(i % 2), 0.5 * float(i / 2), 0.5, 0.5)

## Casing around an opening x0..x1 in a wall running along x (centre zc, thickness t).
static func _casing_x(k, x0: float, x1: float, zc: float, t: float, h: float) -> void:
	var cw := 0.09
	var za := zc - t * 0.5 - 0.02
	var zb := zc + t * 0.5 + 0.02
	k.box("panel", Vector3(x0 - cw, 0.0, za), Vector3(x0 + 0.015, h, zb), DARK_WOOD)
	k.box("panel", Vector3(x1 - 0.015, 0.0, za), Vector3(x1 + cw, h, zb), DARK_WOOD)
	k.box("panel", Vector3(x0 - cw - 0.02, h - 0.015, za - 0.01), Vector3(x1 + cw + 0.02, h + cw + 0.02, zb + 0.01), DARK_WOOD)

## Same for an opening z0..z1 in a wall running along z (centre xc).
static func _casing_z(k, z0: float, z1: float, xc: float, t: float, h: float) -> void:
	var cw := 0.09
	var xa := xc - t * 0.5 - 0.02
	var xb := xc + t * 0.5 + 0.02
	k.box("panel", Vector3(xa, 0.0, z0 - cw), Vector3(xb, h, z0 + 0.015), DARK_WOOD)
	k.box("panel", Vector3(xa, 0.0, z1 - 0.015), Vector3(xb, h, z1 + cw), DARK_WOOD)
	k.box("panel", Vector3(xa - 0.01, h - 0.015, z0 - cw - 0.02), Vector3(xb + 0.01, h + cw + 0.02, z1 + cw + 0.02), DARK_WOOD)

## A four-panel door leaf of width w, authored around its hinge: it runs along local +x, y from 0, thickness on z
## (xf places a fixed leaf in the world).
static func _leaf(k, w: float, h: float, col: Color, xf := Transform3D.IDENTITY) -> void:
	var knob := Color.WHITE
	k.box("panel", Vector3(0.0, 0.012, -0.02), Vector3(w, h - 0.02, 0.02), col, 1.0, Kit.ALL, xf)
	for pz in [-0.025, 0.02]:
		for py in [[0.14, 0.86], [0.98, h - 0.16]]:
			for px in [[0.09, w * 0.5 - 0.035], [w * 0.5 + 0.035, w - 0.09]]:
				k.box("panel", Vector3(px[0], py[0], pz), Vector3(px[1], py[1], pz + 0.005), col.darkened(0.25), 1.0, Kit.ALL, xf)
	for kz in [-0.06, 0.06]:
		k.sphere("brass", xf * Vector3(w - 0.07, 1.0, kz), 0.03, 10, 6, knob)
	k.box("brass", Vector3(w - 0.1, 0.9, -0.024), Vector3(w - 0.04, 1.1, 0.024), knob.darkened(0.2), 1.0, Kit.ALL, xf)

## Wainscot (dark panelling, 1 m, with a cap rail) on the face z = zf of a wall running along x, between xa and xb,
## standing out toward `side` (+1 = +z).
static func _wainscot(k, xa: float, xb: float, zf: float, side: float) -> void:
	if xb - xa < 0.05:
		return
	var z0 := minf(zf, zf + side * 0.018)
	var z1 := maxf(zf, zf + side * 0.018)
	k.box("panel", Vector3(xa, 0.0, z0), Vector3(xb, 1.0, z1), DARK_WOOD)
	var r0 := minf(zf, zf + side * 0.04)
	var r1 := maxf(zf, zf + side * 0.04)
	k.box("panel", Vector3(xa, 1.0, r0), Vector3(xb, 1.045, r1), Color(0.8, 0.8, 0.8))
	k.box("panel", Vector3(xa, 0.0, r0), Vector3(xb, 0.11, r1), Color(0.8, 0.8, 0.8))
	var n := int((xb - xa) / 0.55)
	for i in range(1, n):
		var x := xa + (xb - xa) * float(i) / float(n)
		k.box("panel", Vector3(x - 0.012, 0.11, minf(zf, zf + side * 0.026)), Vector3(x + 0.012, 1.0, maxf(zf, zf + side * 0.026)), Color(0.8, 0.8, 0.8))

## A framed photograph hung on a wall facing nrm.
static func _portrait(k, ctr: Vector3, nrm: Vector3, w: float, h: float, cell: int) -> void:
	Shell.board(k, "panel", ctr, nrm, w + 0.1, h + 0.1, 0.03, Color(0.7, 0.7, 0.7))
	Shell.sign_quad(k, "tex_portraits_atlas.jpg", ctr + nrm * 0.004, nrm, w, h, _doc(cell))

## Window in a wall running along x (the wall face toward the room is at z = z_in, the outside lies toward `out` =
## -1 (north) or +1 (south)): frame, mullions, sill, the night behind the panes, and the moon shining through it.
static func _window(c, k, x0: float, x1: float, zc: float, out: float, target: Vector3, energy: float, shaft := 1.25) -> void:
	var y0: float = L.WIN_Y0
	var y1: float = L.WIN_Y1
	var t: float = L.WALL
	var za := zc - t * 0.5
	var zb := zc + t * 0.5
	var fw := 0.05
	k.box("paintwood", Vector3(x0, y0, za), Vector3(x0 + fw, y1, zb), IVORY)
	k.box("paintwood", Vector3(x1 - fw, y0, za), Vector3(x1, y1, zb), IVORY)
	k.box("paintwood", Vector3(x0, y1 - fw, za), Vector3(x1, y1, zb), IVORY)
	k.box("paintwood", Vector3(x0, y0, za), Vector3(x1, y0 + fw, zb), IVORY)
	var xm := (x0 + x1) * 0.5
	k.box("paintwood", Vector3(xm - 0.018, y0, zc - 0.02), Vector3(xm + 0.018, y1, zc + 0.02), IVORY)
	for my in [y0 + (y1 - y0) / 3.0, y0 + (y1 - y0) * 2.0 / 3.0]:
		k.box("paintwood", Vector3(x0, my - 0.016, zc - 0.02), Vector3(x1, my + 0.016, zc + 0.02), IVORY)
	var zs := zc - out * (t * 0.5 + 0.07)
	k.box("paintwood", Vector3(x0 - 0.06, y0 - 0.04, minf(zs, zc)), Vector3(x1 + 0.06, y0, maxf(zs, zc)), IVORY)
	# the night outside (never in a shadow pass: the moon shines through it)
	var sk = c.kit("et_sky")
	# (close behind the panes and wider than the opening: a glance along the wall must not slip past its edge into
	# the lit haze outside)
	var zo := zc + out * (t * 0.5 + 0.07)
	Shell.sign_quad(sk, "night_sky", Vector3(xm, (y0 + y1) * 0.5, zo), Vector3(0, 0, -out), (x1 - x0) + 1.0, (y1 - y0) + 0.8)
	var moon := SpotLight3D.new()
	moon.name = "Moon"
	moon.position = Vector3(xm + 1.5, 5.2, zc + out * 3.6)
	moon.light_color = MOON
	moon.light_energy = energy
	moon.spot_range = 14.0
	moon.spot_angle = 17.0
	moon.spot_angle_attenuation = 0.4
	moon.spot_attenuation = 0.2
	moon.light_specular = 0.4
	moon.shadow_enabled = true
	moon.shadow_bias = 0.05
	moon.shadow_normal_bias = 1.5
	moon.shadow_blur = 1.2
	moon.light_cull_mask = MASK
	moon.light_volumetric_fog_energy = shaft
	moon.basis = Basis.looking_at(target - moon.position, Vector3.UP)
	c.region("et_lights").add_child(moon)
	c.room_fx["moon"].append(moon)
	# what the moonlit boards send back into the room (these presets render no indirect light)
	var bounce := OmniLight3D.new()
	bounce.name = "MoonBounce"
	bounce.position = target + Vector3(0, 0.35, 0)
	bounce.light_color = MOON.lerp(Color(0.5, 0.42, 0.34), 0.35)
	bounce.light_energy = energy * 0.028
	bounce.omni_range = 4.2
	bounce.omni_attenuation = 1.1
	bounce.light_specular = 0.0
	bounce.shadow_enabled = false
	bounce.light_cull_mask = MASK
	c.region("et_lights").add_child(bounce)
	_motes(c, (moon.position + target) * 0.5 + (target - moon.position).normalized() * 2.2, Vector3(0.7, 1.0, 0.9))

## Dust hanging in a beam of light.
static func _motes(c, at: Vector3, extents: Vector3) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.006, 0.006)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.86, 0.9, 1.0, 0.75)
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	quad.material = m
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.02
	pm.gravity = Vector3(0, -0.002, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.7
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.5
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_noise_speed = Vector3(0.02, 0.01, 0.02)
	pm.turbulence_influence_min = 0.02
	pm.turbulence_influence_max = 0.06
	var e := GPUParticles3D.new()
	e.name = "DustMotes"
	e.amount = 110
	e.lifetime = 14.0
	e.preprocess = 10.0
	e.randomness = 0.6
	e.process_material = pm
	e.draw_pass_1 = quad
	e.position = at
	e.visibility_aabb = AABB(-extents - Vector3(0.6, 0.6, 0.6), extents * 2.0 + Vector3(1.2, 1.2, 1.2))
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	c.region("et_lights").add_child(e)

## Cobweb in a ceiling corner: a quad hanging from `corner` along the horizontal direction `along`.
static func _cobweb(c, corner: Vector3, along: Vector3, size: float) -> void:
	var k = c.kit("et_webs")
	var a := Vector3(along.x, 0.0, along.z).normalized()
	var tl := corner
	var tr := corner + a * size
	var br := tr + Vector3.DOWN * size
	var bl := corner + Vector3.DOWN * size
	k.quad("cobweb", bl, br, tr, tl, a.cross(Vector3.UP), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))

## The last layer: reflections, haze, stains, cobwebs, mouldings.
static func _finish(c) -> void:
	var H: Dictionary = L.HALL
	var S: Dictionary = L.SALON
	var R: Dictionary = L.CHAMBRE
	var m: int = L.L_ET
	# reflection probes (floorboards, brass, glass, the bedroom mirror)
	c.room_fx["probes"] = [
		Shell.probe(c, "et_lights", "ProbeHall", Vector3(float(H.x0), 0.0, float(H.z0)), Vector3(float(H.x1), float(H.ceil), float(H.z1)), Vector3(60.4, 1.4, 0.0), 0.85),
		Shell.probe(c, "et_lights", "ProbeSalon", Vector3(float(S.x0), 0.0, float(S.z0)), Vector3(float(S.x1), float(S.ceil), float(S.z1)), Vector3(61.0, 1.45, -4.2), 0.85),
		Shell.probe(c, "et_lights", "ProbeChambre", Vector3(float(R.x0), 0.0, float(R.z0)), Vector3(float(R.x1), float(R.ceil), float(R.z1)), Vector3(54.4, 1.4, -2.6), 0.85),
	]
	# old-house haze in the salon, where the moon comes in
	for fv in [[Vector3(61.0, 1.4, -4.4), Vector3(9.0, 2.8, 6.8), 0.018]]:
		var fog := FogVolume.new()
		fog.name = "Haze"
		fog.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
		fog.size = fv[1]
		fog.position = fv[0]
		var fm := FogMaterial.new()
		fm.density = float(fv[2])
		fm.albedo = Color(0.74, 0.78, 0.86)
		fm.edge_fade = 0.5
		fog.material = fm
		c.region("et_lights").add_child(fog)
	# stains: water coming down the walls and spreading on the ceilings, grime where the floor meets the wall
	var hz0: float = H.z0
	var hz1: float = H.z1
	var brown := Color(0.2, 0.15, 0.09, 0.75)
	for d in [[Vector3(55.9, 1.9, hz0 + 0.01), Vector3.BACK, 1.3, 1.4], [Vector3(62.3, 2.0, hz0 + 0.01), Vector3.BACK, 1.1, 1.2], [Vector3(58.6, 1.95, hz1 - 0.01), Vector3.FORWARD, 1.2, 1.3],
			[Vector3(66.2, 1.9, hz1 - 0.01), Vector3.FORWARD, 1.2, 1.4], [Vector3(60.2, 2.0, float(S.z0) + 0.01), Vector3.BACK, 1.6, 1.6], [Vector3(float(S.x0) + 0.01, 1.9, -3.0), Vector3.RIGHT, 1.5, 1.7],
			[Vector3(64.2, 2.0, float(S.z1) - 0.01), Vector3.FORWARD, 1.4, 1.6], [Vector3(float(R.x0) + 0.01, 1.8, -4.6), Vector3.RIGHT, 1.3, 1.5], [Vector3(55.4, 1.9, float(R.z0) + 0.01), Vector3.BACK, 1.2, 1.4]]:
		Shell.decal(c, "et_decals", "decal_water.png", d[0], d[1], Vector2(float(d[2]), float(d[3])), m, brown)
	for d in [[Vector3(57.2, float(H.ceil), 0.1), 1.7], [Vector3(64.6, float(H.ceil), -0.2), 1.4], [Vector3(59.4, float(S.ceil), -3.2), 2.2], [Vector3(63.2, float(S.ceil), -6.2), 1.9], [Vector3(53.6, float(R.ceil), -2.4), 1.6]]:
		Shell.decal(c, "et_decals", "decal_spill.png", d[0], Vector3.DOWN, Vector2(float(d[1]), float(d[1])), m, Color(0.3, 0.22, 0.12, 0.6), float(d[1]) * 2.0)
	var dirt := Color(0.07, 0.06, 0.05, 0.75)
	for d in [[Vector3(54.4, 0.0, hz0 + 0.3), 2.2, 0.0], [Vector3(59.0, 0.0, hz1 - 0.3), 2.4, 0.0], [Vector3(65.6, 0.0, hz0 + 0.3), 2.2, 0.0], [Vector3(67.5, 0.0, 0.0), 1.5, 1.57],
			[Vector3(57.3, 0.0, -1.5), 1.6, 0.0], [Vector3(64.9, 0.0, -1.5), 1.4, 0.0], [Vector3(57.0, 0.0, -7.3), 1.5, 0.6], [Vector3(53.0, 0.0, -1.5), 1.4, 0.0]]:
		Shell.decal(c, "et_decals", "decal_grime.png", d[0], Vector3.UP, Vector2(float(d[1]), 0.7), m, dirt, float(d[2]))
	for d in [[Vector3(60.7, 0.0, -1.0), 1.2, 0.0], [Vector3(55.04, 0.0, -0.9), 1.0, 0.0], [Vector3(66.9, 0.0, 0.0), 1.2, 1.57], [Vector3(62.8, 0.0, -3.0), 1.4, 0.8]]:
		Shell.decal(c, "et_decals", "decal_scuffs.png", d[0], Vector3.UP, Vector2(float(d[1]), float(d[1]) * 1.2), m, Color(0.06, 0.05, 0.04, 0.6), float(d[2]))
	# footprints in the dust of the salon: from one of the sheets to the doorway, and back
	Shell.decal(c, "et_decals", "decal_footprints.png", Vector3(62.3, 0.0, -2.7), Vector3.UP, Vector2(0.55, 1.0), m, Color(0.5, 0.48, 0.44, 0.34), -1.25)
	Shell.decal(c, "et_decals", "decal_footprints.png", Vector3(61.2, 0.0, -1.9), Vector3.UP, Vector2(0.55, 1.0), m, Color(0.5, 0.48, 0.44, 0.28), -0.6)
	# cobwebs in the ceiling corners, on the clock, on the chandelier
	var hc: float = H.ceil
	var sc: float = S.ceil
	for w in [[Vector3(float(H.x0) + 0.01, hc - 0.01, hz0 + 0.02), Vector3(1, 0, 0.35), 0.7], [Vector3(float(H.x1) - 0.01, hc - 0.01, hz1 - 0.02), Vector3(-1, 0, -0.3), 0.8],
			[Vector3(float(H.x1) - 0.01, hc - 0.01, hz0 + 0.02), Vector3(-1, 0, 0.4), 0.6], [Vector3(57.9, hc - 0.01, hz1 - 0.02), Vector3(-1, 0, -0.15), 0.55],
			[Vector3(63.48, hc - 0.01, hz0 + 0.02), Vector3(1, 0, 0.2), 0.6], [Vector3(60.0, 2.15, hz0 - 0.02), Vector3(1, 0, 0), 0.5],
			[Vector3(float(S.x0) + 0.02, sc - 0.01, float(S.z0) + 0.02), Vector3(1, 0, 1), 1.0], [Vector3(float(S.x1) - 0.02, sc - 0.01, float(S.z0) + 0.02), Vector3(-1, 0, 1), 0.9],
			[Vector3(float(S.x0) + 0.02, sc - 0.01, float(S.z1) - 0.02), Vector3(1, 0, -1), 0.8], [Vector3(float(S.x1) - 0.38, sc - 0.01, -3.57), Vector3(-1, 0, 0.5), 0.7],
			[Vector3(60.72, sc - 0.02, -4.4), Vector3(1, 0, 0.1), 0.6], [Vector3(61.28, sc - 0.02, -4.4), Vector3(-1, 0, -0.2), 0.55],
			[Vector3(float(R.x0) + 0.02, float(R.ceil) - 0.01, float(R.z0) + 0.02), Vector3(1, 0, 1), 0.8], [Vector3(float(R.x1) - 0.02, float(R.ceil) - 0.01, float(R.z1) - 0.02), Vector3(-1, 0, -1), 0.6]]:
		_cobweb(c, w[0], w[1], float(w[2]))
	# crown mouldings and a picture rail in the hallway and the salon
	var tk = c.kit("et_trim")
	var cream := Color(0.5, 0.47, 0.4)
	for z in [[hz0, 1.0], [hz1, -1.0]]:
		var zf: float = z[0]
		var sd: float = z[1]
		tk.box("paintwood", Vector3(float(H.x0), hc - 0.07, minf(zf, zf + sd * 0.05)), Vector3(float(H.x1), hc, maxf(zf, zf + sd * 0.05)), cream)
		tk.box("paintwood", Vector3(float(H.x0), hc - 0.11, minf(zf, zf + sd * 0.025)), Vector3(float(H.x1), hc - 0.07, maxf(zf, zf + sd * 0.025)), cream)
	for e in [[Vector3(float(S.x0), sc - 0.09, float(S.z0)), Vector3(float(S.x1), sc, float(S.z0) + 0.06)], [Vector3(float(S.x0), sc - 0.09, float(S.z1) - 0.06), Vector3(float(S.x1), sc, float(S.z1))],
			[Vector3(float(S.x0), sc - 0.09, float(S.z0)), Vector3(float(S.x0) + 0.06, sc, float(S.z1))], [Vector3(float(S.x1) - 0.06, sc - 0.09, float(S.z0)), Vector3(float(S.x1), sc, float(S.z1))]]:
		tk.box("paintwood", e[0], e[1], cream)
	tk.box("panel", Vector3(float(S.x0), 2.05, float(S.z0)), Vector3(float(S.x1), 2.09, float(S.z0) + 0.02), DARK_WOOD)
	tk.box("panel", Vector3(float(S.x0), 2.05, float(S.z0)), Vector3(float(S.x0) + 0.02, 2.09, float(S.z1)), DARK_WOOD)

## A sconce on a wall (nrm = away from the wall): backplate, arm, a frosted shade lit from inside; shadowed omni.
static func _sconce(c, k, at: Vector3, nrm: Vector3, i: int) -> void:
	var r := nrm.cross(Vector3.UP).normalized()
	var pa := at - r * 0.05 - Vector3(0, 0.09, 0)
	var pb := at + r * 0.05 + Vector3(0, 0.09, 0) + nrm * 0.012
	k.box("brass", pa.min(pb), pa.max(pb), Color.WHITE)
	k.tube("brass", PackedVector3Array([at + nrm * 0.01, at + nrm * 0.1 - Vector3(0, 0.03, 0), at + nrm * 0.11 + Vector3(0, 0.03, 0)]), 0.008, 6, Color.WHITE)
	var em: StandardMaterial3D = c.mats.emissive_instance("night_glow")
	em.emission_energy_multiplier = 3.0
	var gk = Kit.new()
	gk.sphere("glow", at + nrm * 0.11 + Vector3(0, 0.1, 0), 0.07, 12, 8, Color.WHITE, Vector3(1.0, 1.25, 1.0))
	gk.commit(c.region("et_props"), {"glow": em}, "et_sconce_%d" % i, {"no_shadow": ["glow"]})
	var o := OmniLight3D.new()
	o.name = "Sconce%d" % i
	o.position = at + nrm * 0.2 + Vector3(0, 0.1, 0)
	o.light_color = Color(1.0, 0.68, 0.36)
	o.light_energy = 0.55
	o.omni_range = 4.2
	o.omni_attenuation = 1.3
	o.shadow_enabled = true
	o.shadow_bias = 0.05
	o.shadow_normal_bias = 1.2
	o.light_cull_mask = MASK
	c.region("et_lights").add_child(o)
	c.room_fx["sconces"].append({"light": o, "emit": em, "base": 0.55, "alive": true})

## Something tall, narrow and human under a dust sheet, authored around its feet (y = 0), facing local +z: a head
## with the cloth clinging to a face (two hollows, a ridge), a tent of cloth down to the shoulders, then long folds
## falling and pooling on the floor. Fold valleys are darkened in the vertex colours so the shape reads in any light.
static func sheet_figure(k, h: float, seed_: int, tint := Color.WHITE) -> void:
	var prof := [[0.0, 0.02, 0.02], [0.022, 0.078, 0.084], [0.055, 0.106, 0.115], [0.095, 0.104, 0.112], [0.13, 0.102, 0.104], [0.165, 0.165, 0.112],
		[0.195, 0.228, 0.124], [0.25, 0.24, 0.136], [0.42, 0.244, 0.16], [0.62, 0.262, 0.195], [0.82, 0.305, 0.245], [0.95, 0.34, 0.29], [0.985, 0.38, 0.33], [1.0, 0.45, 0.4]]
	var rows := 40
	var cols := 49
	var P := PackedVector3Array()
	var U := PackedVector2Array()
	var C := PackedColorArray()
	var ph := float(seed_) * 1.7
	for r in rows:
		var t := float(r) / float(rows - 1)
		t = t * t * 0.35 + t * 0.65                    # a little denser at the head
		var rx := 0.0
		var rz := 0.0
		for i in prof.size() - 1:
			if t >= float(prof[i][0]) and t <= float(prof[i + 1][0]):
				var u := (t - float(prof[i][0])) / maxf(float(prof[i + 1][0]) - float(prof[i][0]), 1e-5)
				u = u * u * (3.0 - 2.0 * u)
				rx = lerpf(float(prof[i][1]), float(prof[i + 1][1]), u)
				rz = lerpf(float(prof[i][2]), float(prof[i + 1][2]), u)
				break
		var fold := clampf((t - 0.17) / 0.5, 0.0, 1.0)
		var y := h * (1.0 - t) if t < 0.985 else h * 0.015 * (1.0 - (t - 0.985) / 0.015) + 0.004
		for cc in cols:
			var a := TAU * float(cc % (cols - 1)) / float(cols - 1)
			# long folds: a few deep ones and a finer set, drifting sideways a little on the way down
			var w := 0.55 * sin(6.0 * a + ph + t * 1.3) + 0.3 * sin(13.0 * a - ph * 1.3 + t * 2.6) + 0.15 * sin(3.0 * a + ph * 0.6)
			var f := 1.0 + fold * 0.13 * w
			# the head leans a little forward; the arms hang slightly in front
			var lean := 0.04 * clampf(1.0 - t / 0.16, 0.0, 1.0)
			var arms := 0.035 * exp(-pow((t - 0.5) / 0.14, 2.0)) * maxf(0.0, sin(a))
			# the face under the cloth: two hollows where the eyes are, the ridge of a nose, a mouth left open
			var front := a - PI * 0.5
			var eyes := exp(-pow((t - 0.066) / 0.011, 2.0)) * (exp(-pow((front - 0.36) / 0.17, 2.0)) + exp(-pow((front + 0.36) / 0.17, 2.0)))
			var nose := exp(-pow((t - 0.082) / 0.014, 2.0)) * exp(-pow(front / 0.12, 2.0))
			var mouth := exp(-pow((t - 0.108) / 0.009, 2.0)) * exp(-pow(front / 0.3, 2.0))
			var face := 1.0 - 0.15 * eyes + 0.07 * nose - 0.07 * mouth
			P.append(Vector3(cos(a) * rx * f * face, y, sin(a) * rz * f * face + lean + arms))
			U.append(Vector2(float(cc) / float(cols - 1) * 1.6, t * h))
			var shade := clampf(0.74 + 0.26 * w * fold + 0.12 * (1.0 - fold), 0.42, 1.0) * (1.0 - 0.36 * eyes - 0.22 * mouth) * lerpf(1.0, 0.8, clampf((t - 0.8) / 0.2, 0.0, 1.0))
			C.append(Color(tint.r * shade, tint.g * shade, tint.b * shade))
	k.grid("sheet", P, rows, cols, U, tint, true, true, C)

## A piece of furniture under a sheet: a rounded block of cloth, hanging folds down its sides, the hem spread on the
## floor.
static func _draped(k, cl, mn: Vector3, mx: Vector3, tint := Color.WHITE) -> void:
	k.rbox("sheet", mn - Vector3(0.05, 0.0, 0.05), mx + Vector3(0.05, 0.03, 0.05), 0.09, 3, tint)
	k.rbox("sheet", Vector3(mn.x - 0.16, 0.0, mn.z - 0.16), Vector3(mx.x + 0.16, 0.035, mx.z + 0.16), 0.03, 2, tint.darkened(0.12))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(mn.x * 131.0 + mn.z * 17.0)
	var per := 2.0 * ((mx.x - mn.x) + (mx.z - mn.z))
	var n := int(per / 0.34)
	var top := mx.y - 0.1
	for i in n:
		var s := (float(i) + rng.randf_range(0.2, 0.8)) / float(n) * per
		var q := Vector3.ZERO
		var out := Vector3.ZERO
		var lx := mx.x - mn.x
		var lz := mx.z - mn.z
		if s < lx:
			q = Vector3(mn.x + s, 0.0, mn.z - 0.05)
			out = Vector3(0, 0, -1)
		elif s < lx + lz:
			q = Vector3(mx.x + 0.05, 0.0, mn.z + (s - lx))
			out = Vector3(1, 0, 0)
		elif s < 2.0 * lx + lz:
			q = Vector3(mx.x - (s - lx - lz), 0.0, mx.z + 0.05)
			out = Vector3(0, 0, 1)
		else:
			q = Vector3(mn.x - 0.05, 0.0, mx.z - (s - 2.0 * lx - lz))
			out = Vector3(-1, 0, 0)
		var r := rng.randf_range(0.03, 0.065)
		var lean := rng.randf_range(0.02, 0.09)
		k.tube("sheet", PackedVector3Array([q + out * (lean + 0.03) + Vector3(0, 0.02, 0), q + out * lean * 0.5 + Vector3(0, top * 0.5, 0), q - out * 0.02 + Vector3(0, top, 0)]),
			r, 7, tint.darkened(rng.randf_range(0.0, 0.14)))
	cl.box(mn, mx)

# ====================================================================== le couloir

static func _hall(c) -> void:
	var k = c.kit("et_shell")
	var tk = c.kit("et_trim")
	var pk = c.kit("et_props")
	var cl = c.col("et_shell")
	var H: Dictionary = L.HALL
	var x0: float = H.x0
	var x1: float = H.x1
	var z0: float = H.z0
	var z1: float = H.z1
	var ch: float = H.ceil
	var top := ch + 0.2
	k.box("floorboards", Vector3(x0 - 0.2, -0.2, z0 - 0.2), Vector3(x1 + 0.2, 0.0, z1 + 0.2), Color.WHITE, 1.0, Kit.FACE_PY)
	cl.box(Vector3(x0 - 0.3, -0.3, -8.4), Vector3(x1 + 0.3, 0.0, 5.6))                  # one slab under the whole level
	k.box("plaster", Vector3(x0, ch, z0), Vector3(x1, top, z1), Color.WHITE, 1.0, Kit.FACE_NY | Kit.FACE_PY)
	cl.box(Vector3(x0, ch, z0), Vector3(x1, top, z1))
	# the runner: u across its width, v along the hallway
	var ry := 0.008
	var ra := 53.6
	var rb := 66.6
	k.quad("rug", Vector3(ra, ry, 0.42), Vector3(rb, ry, 0.42), Vector3(rb, ry, -0.42), Vector3(ra, ry, -0.42), Vector3.UP,
		Vector2(0.0, ra / 1.6), Vector2(0.0, rb / 1.6), Vector2(1.0, rb / 1.6), Vector2(1.0, ra / 1.6))
	var dc: Dictionary = L.DOOR_CHAMBRE
	var ds: Dictionary = L.DOOR_SALON
	var dk: Dictionary = L.DOOR_CLOSET
	var dbn: Dictionary = L.DOOR_BAIN
	var dcu: Dictionary = L.DOOR_CUISINE
	var des: Dictionary = L.DOOR_ESCALIER
	var wx0 := x0 - 0.2
	var wx1 := x1 + 0.2
	# north wall (bedroom door, the salon's wide doorway, the stairwell's door), south wall (bathroom door, closet
	# door, the kitchen's doorway, window)
	Shell.wall(c, "et_shell", "wallpaper_house", Vector2(wx0, z0 - 0.1), Vector2(wx1, z0 - 0.1), 0.2, 0.0, top,
		[[float(dc.x0) - wx0, float(dc.x1) - wx0, 0.0, float(dc.h)], [float(ds.x0) - wx0, float(ds.x1) - wx0, 0.0, float(ds.h)],
		[float(des.x0) - wx0, float(des.x1) - wx0, 0.0, float(des.h)]])
	Shell.wall(c, "et_shell", "wallpaper_house", Vector2(wx0, z1 + 0.1), Vector2(wx1, z1 + 0.1), 0.2, 0.0, top,
		[[float(dbn.x0) - wx0, float(dbn.x1) - wx0, 0.0, float(dbn.h)], [float(dk.x0) - wx0, float(dk.x1) - wx0, 0.0, float(dk.h)],
		[float(dcu.x0) - wx0, float(dcu.x1) - wx0, 0.0, float(dcu.h)],
		[float(L.WIN_HALL[0]) - wx0, float(L.WIN_HALL[1]) - wx0, float(L.WIN_Y0), float(L.WIN_Y1)]])
	# end walls: the basement door behind the player (west), the front door (east)
	var db: Dictionary = L.DOOR_BASEMENT
	var df: Dictionary = L.DOOR_FRONT
	Shell.wall(c, "et_shell", "wallpaper_house", Vector2(x0 - 0.1, z0 - 0.2), Vector2(x0 - 0.1, z1 + 0.2), 0.2, 0.0, top,
		[[float(db.z0) - (z0 - 0.2), float(db.z1) - (z0 - 0.2), 0.0, float(db.h)]])
	Shell.wall(c, "et_shell", "wallpaper_house", Vector2(x1 + 0.1, z0 - 0.2), Vector2(x1 + 0.1, z1 + 0.2), 0.2, 0.0, top,
		[[float(df.z0) - (z0 - 0.2), float(df.z1) - (z0 - 0.2), 0.0, float(df.h)]])
	_casing_x(tk, float(dc.x0), float(dc.x1), z0 - 0.1, 0.2, float(dc.h))
	_casing_x(tk, float(ds.x0), float(ds.x1), z0 - 0.1, 0.2, float(ds.h))
	_casing_x(tk, float(dk.x0), float(dk.x1), z1 + 0.1, 0.2, float(dk.h))
	_casing_x(tk, float(des.x0), float(des.x1), z0 - 0.1, 0.2, float(des.h))
	_casing_x(tk, float(dbn.x0), float(dbn.x1), z1 + 0.1, 0.2, float(dbn.h))
	_casing_x(tk, float(dcu.x0), float(dcu.x1), z1 + 0.1, 0.2, float(dcu.h))
	_casing_z(tk, float(db.z0), float(db.z1), x0 - 0.1, 0.2, float(db.h))
	_casing_z(tk, float(df.z0), float(df.z1), x1 + 0.1, 0.2, float(df.h))
	# wainscot between the openings
	var spans_n := [[x0, float(dc.x0) - 0.09], [float(dc.x1) + 0.09, float(ds.x0) - 0.09], [float(ds.x1) + 0.09, float(des.x0) - 0.09],
		[float(des.x1) + 0.09, x1]]
	for sp in spans_n:
		_wainscot(tk, float(sp[0]), float(sp[1]), z0, 1.0)
	for sp in [[x0, float(dbn.x0) - 0.09], [float(dbn.x1) + 0.09, float(dk.x0) - 0.09], [float(dk.x1) + 0.09, float(dcu.x0) - 0.09], [float(dcu.x1) + 0.09, x1]]:
		_wainscot(tk, float(sp[0]), float(sp[1]), z1, -1.0)
	# the basement door, shut for good, and the wall behind both end doors
	_leaf(tk, float(db.z1) - float(db.z0) - 0.04, float(db.h), Color(0.75, 0.75, 0.75), Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(x0 - 0.08, 0.0, float(db.z0) + 0.02)))
	cl.box(Vector3(x0 - 0.2, 0.0, float(db.z0)), Vector3(x0, float(db.h), float(db.z1)))
	# the front door: its leaf turns around its hinge (etage.gd), a transom of old glass above it
	var fk = c.kit("et_door_front")
	_leaf(fk, float(df.z1) - float(df.z0) - 0.04, float(df.h), Color(0.42, 0.5, 0.42))
	c.room_fx["front_hinge"] = Vector3(x1 + 0.08, 0.0, float(df.z1) - 0.02)
	c.room_fx["front_w"] = float(df.z1) - float(df.z0) - 0.04
	# chain and bolts on the front door frame (decoration), the mat, the umbrella stand
	tk.box("brass", Vector3(x1 - 0.012, 1.42, float(df.z0) + 0.06), Vector3(x1, 1.5, float(df.z0) + 0.2), Color.WHITE)
	tk.box("brass", Vector3(x1 - 0.012, 1.15, float(df.z0) + 0.06), Vector3(x1, 1.22, float(df.z0) + 0.16), Color.WHITE)
	pk.box("fabric", Vector3(x1 - 1.1, 0.0, -0.4), Vector3(x1 - 0.25, 0.014, 0.4), Color(0.16, 0.13, 0.1))
	pk.tube("brass", PackedVector3Array([Vector3(x1 - 0.3, 0.0, 0.62), Vector3(x1 - 0.3, 0.55, 0.62)]), 0.1, 12, Color.WHITE, 1.0, true)
	pk.tube("fabric", PackedVector3Array([Vector3(x1 - 0.3, 0.1, 0.62), Vector3(x1 - 0.26, 0.98, 0.66)]), 0.02, 6, Color(0.05, 0.05, 0.05))
	cl.box(Vector3(x1 - 0.42, 0.0, 0.5), Vector3(x1 - 0.18, 0.6, 0.74))
	# window in the south wall: the moon lays its panes across the runner
	# (a weak shaft here: down the hallway the eye looks along the beam, and a strong one whites the panes out)
	_window(c, tk, float(L.WIN_HALL[0]), float(L.WIN_HALL[1]), z1 + 0.1, 1.0, Vector3(63.6, 0.0, -0.3), 7.0, 0.3)
	# the tall clock against the north wall
	var ck: Vector3 = L.CLOCK
	pk.box("panel", ck + Vector3(-0.26, 0.0, -0.16), ck + Vector3(0.26, 0.42, 0.14), DARK_WOOD)
	pk.box("panel", ck + Vector3(-0.18, 0.42, -0.16), ck + Vector3(0.18, 1.62, 0.1), DARK_WOOD)
	pk.box("panel", ck + Vector3(-0.25, 1.62, -0.16), ck + Vector3(0.25, 2.1, 0.14), DARK_WOOD)
	pk.box("panel", ck + Vector3(-0.28, 2.1, -0.16), ck + Vector3(0.28, 2.16, 0.16), Color(0.8, 0.8, 0.8))
	pk.disc("enamel", ck + Vector3(0.0, 1.86, 0.142), Vector3.BACK, Vector3.RIGHT, 0.17, 24, Color(0.82, 0.78, 0.66))
	pk.box("dark", ck + Vector3(-0.006, 1.86, 0.143), ck + Vector3(0.006, 1.99, 0.146), Color.WHITE)
	pk.box("dark", Vector3(-0.005, 0.0, 0.0), Vector3(0.005, 0.09, 0.003), Color.WHITE, 1.0, Kit.ALL, Transform3D(Basis(Vector3.BACK, -2.2), ck + Vector3(0.0, 1.86, 0.143)))
	pk.box("dark", ck + Vector3(-0.12, 0.55, 0.1), ck + Vector3(0.12, 1.5, 0.104), Color.WHITE)
	pk.tube("brass", PackedVector3Array([ck + Vector3(0.03, 1.5, 0.11), ck + Vector3(0.03, 0.85, 0.11)]), 0.006, 6, Color.WHITE)
	pk.disc("brass", ck + Vector3(0.03, 0.8, 0.112), Vector3.BACK, Vector3.RIGHT, 0.06, 14, Color.WHITE)
	cl.box(ck + Vector3(-0.28, 0.0, -0.18), ck + Vector3(0.28, 2.16, 0.16))
	# a console table on the south wall: a framed photograph standing on it, a letter
	var ct := Vector3(61.7, 0.0, z1 - 0.19)
	pk.box("panel", ct + Vector3(-0.5, 0.74, -0.17), ct + Vector3(0.5, 0.78, 0.17), DARK_WOOD)
	for sx in [-0.45, 0.45]:
		for sz in [-0.13, 0.13]:
			pk.box("panel", ct + Vector3(sx - 0.022, 0.0, sz - 0.022), ct + Vector3(sx + 0.022, 0.74, sz + 0.022), DARK_WOOD)
	pk.box("panel", ct + Vector3(-0.47, 0.6, -0.15), ct + Vector3(0.47, 0.74, 0.15), Color(0.85, 0.85, 0.85))
	cl.box(ct + Vector3(-0.5, 0.0, -0.17), ct + Vector3(0.5, 0.78, 0.17))
	var fxf := Transform3D(Basis(Vector3.UP, PI + 0.25) * Basis(Vector3.RIGHT, -0.16), ct + Vector3(0.28, 0.78, 0.04))
	pk.box("panel", Vector3(-0.09, 0.0, -0.008), Vector3(0.09, 0.24, 0.008), Color(0.7, 0.7, 0.7), 1.0, Kit.ALL, fxf)
	pk.quad("tex_portraits_atlas.jpg", fxf * Vector3(-0.075, 0.02, 0.009), fxf * Vector3(0.075, 0.02, 0.009), fxf * Vector3(0.075, 0.22, 0.009), fxf * Vector3(-0.075, 0.22, 0.009),
		fxf.basis * Vector3.BACK, Vector2(0.5, 0.5), Vector2(1.0, 0.5), Vector2(1.0, 0.0), Vector2(0.5, 0.0))
	var letter := ct + Vector3(-0.2, 0.782, 0.0)
	var lb := Basis(Vector3.UP, 0.3)
	pk.quad("debris_paper", letter + lb * Vector3(-0.1, 0, 0.07), letter + lb * Vector3(0.1, 0, 0.07), letter + lb * Vector3(0.1, 0, -0.07), letter + lb * Vector3(-0.1, 0, -0.07),
		Vector3.UP, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Color(0.84, 0.8, 0.68))
	c.room_fx["letter"] = letter
	# photographs along the walls
	_portrait(tk, Vector3(57.6, 1.62, z0 + 0.006), Vector3.BACK, 0.36, 0.44, 0)
	_portrait(tk, Vector3(58.9, 1.58, z0 + 0.006), Vector3.BACK, 0.3, 0.3, 2)
	_portrait(tk, Vector3(54.0, 1.6, z1 - 0.006), Vector3.FORWARD, 0.42, 0.34, 1)
	_portrait(tk, Vector3(66.9, 1.62, z1 - 0.006), Vector3.FORWARD, 0.34, 0.42, 3)
	# three sconces
	var sc: Array = L.SCONCES
	for i in sc.size():
		var sp: Vector3 = sc[i]
		_sconce(c, tk, sp, Vector3.BACK if sp.z < 0.0 else Vector3.FORWARD, i)

# ====================================================================== le salon des draps

static func _salon(c) -> void:
	var k = c.kit("et_shell")
	var tk = c.kit("et_trim")
	var pk = c.kit("et_props")
	var sk = c.kit("et_sheets")
	var cl = c.col("et_shell")
	var S: Dictionary = L.SALON
	var x0: float = S.x0
	var x1: float = S.x1
	var z0: float = S.z0
	var z1: float = S.z1
	var ch: float = S.ceil
	var top := ch + 0.2
	k.box("floorboards", Vector3(x0 - 0.2, -0.2, z0 - 0.2), Vector3(x1 + 0.2, 0.0, z1), Color.WHITE, 1.0, Kit.FACE_PY)
	k.box("plaster", Vector3(x0, ch, z0), Vector3(x1, top, z1), Color.WHITE, 1.0, Kit.FACE_NY | Kit.FACE_PY)
	cl.box(Vector3(x0, ch, z0), Vector3(x1, top, z1))
	# the wall above the hallway's north wall, up to this higher ceiling
	k.box("wallpaper_house", Vector3(x0, float(L.HALL.ceil) + 0.2, z1), Vector3(x1, top, z1 + 0.2), Color.WHITE)
	# west wall (shared with the bedroom), north wall (two windows), east wall (the chimney breast)
	Shell.wall(c, "et_shell", "wallpaper_house", Vector2(x0 - 0.1, z0 - 0.2), Vector2(x0 - 0.1, z1 + 0.1), 0.2, 0.0, top)
	var ws: Array = L.WIN_SALON
	var wx0 := x0 - 0.2
	Shell.wall(c, "et_shell", "wallpaper_house", Vector2(wx0, z0 - 0.1), Vector2(x1 + 0.2, z0 - 0.1), 0.2, 0.0, top,
		[[float(ws[0][0]) - wx0, float(ws[0][1]) - wx0, float(L.WIN_Y0), float(L.WIN_Y1)], [float(ws[1][0]) - wx0, float(ws[1][1]) - wx0, float(L.WIN_Y0), float(L.WIN_Y1)]])
	Shell.wall(c, "et_shell", "wallpaper_house", Vector2(x1 + 0.1, z0 - 0.2), Vector2(x1 + 0.1, z1 + 0.1), 0.2, 0.0, top)
	for bb in [[Vector3(x0, 0.0, z0), Vector3(x0 + 0.014, 0.14, z1)], [Vector3(x1 - 0.014, 0.0, z0), Vector3(x1, 0.14, z1)], [Vector3(x0, 0.0, z0), Vector3(x1, 0.14, z0 + 0.014)]]:
		tk.box("panel", bb[0], bb[1], Color(0.8, 0.8, 0.8))
	_window(c, tk, float(ws[0][0]), float(ws[0][1]), z0 - 0.1, -1.0, Vector3(58.2, 0.0, -4.3), 9.0)
	_window(c, tk, float(ws[1][0]), float(ws[1][1]), z0 - 0.1, -1.0, Vector3(62.6, 0.0, -4.0), 9.0)
	# heavy curtains drawn back on each side of the windows
	for w in ws:
		for side in [[float(w[0]) - 0.42, float(w[0]) - 0.04], [float(w[1]) + 0.04, float(w[1]) + 0.42]]:
			for f in 4:
				var fx := lerpf(float(side[0]), float(side[1]), (float(f) + 0.5) / 4.0)
				pk.rbox("fabric", Vector3(fx - 0.055, 0.03, z0 + 0.02), Vector3(fx + 0.055, 2.5, z0 + 0.12 + 0.02 * (f % 2)), 0.04, 2, Color(0.2, 0.05, 0.05))
		pk.tube("brass", PackedVector3Array([Vector3(float(w[0]) - 0.5, 2.52, z0 + 0.08), Vector3(float(w[1]) + 0.5, 2.52, z0 + 0.08)]), 0.014, 8, Color.WHITE)
	# chimney breast, firebox, mantel; her portrait above it; the key (its own region: it is taken) lies in the box
	# that stands on the mantel (etage_rooms.gd)
	var mz: float = L.MANTEL.z
	k.box("wallpaper_house", Vector3(x1 - 0.36, 0.0, mz - 0.85), Vector3(x1, top, mz + 0.85), Color.WHITE)
	cl.box(Vector3(x1 - 0.36, 0.0, mz - 0.85), Vector3(x1, top, mz + 0.85))
	pk.box("dark", Vector3(x1 - 0.37, 0.0, mz - 0.42), Vector3(x1 - 0.355, 0.82, mz + 0.42), Color.WHITE)
	pk.box("enamel", Vector3(x1 - 0.39, 0.0, mz - 0.58), Vector3(x1 - 0.36, 0.98, mz - 0.42), Color(0.5, 0.48, 0.44))
	pk.box("enamel", Vector3(x1 - 0.39, 0.0, mz + 0.42), Vector3(x1 - 0.36, 0.98, mz + 0.58), Color(0.5, 0.48, 0.44))
	pk.box("enamel", Vector3(x1 - 0.39, 0.82, mz - 0.58), Vector3(x1 - 0.36, 0.98, mz + 0.58), Color(0.5, 0.48, 0.44))
	pk.box("panel", Vector3(x1 - 0.52, 1.1, mz - 0.75), Vector3(x1 - 0.34, 1.15, mz + 0.75), DARK_WOOD)
	cl.box(Vector3(x1 - 0.52, 0.0, mz - 0.75), Vector3(x1 - 0.34, 1.15, mz + 0.75))
	pk.box("enamel", Vector3(x1 - 0.62, 0.0, mz - 0.6), Vector3(x1 - 0.36, 0.03, mz + 0.6), Color(0.3, 0.29, 0.27))
	_portrait(pk, Vector3(x1 - 0.366, 1.95, mz), Vector3.LEFT, 0.62, 0.78, 0)
	for cz in [-0.55, 0.55]:
		pk.tube("brass", PackedVector3Array([Vector3(x1 - 0.44, 1.15, mz + cz), Vector3(x1 - 0.44, 1.32, mz + cz)]), 0.012, 8, Color.WHITE, 1.0, true)
		pk.tube("enamel", PackedVector3Array([Vector3(x1 - 0.44, 1.32, mz + cz), Vector3(x1 - 0.44, 1.5, mz + cz)]), 0.01, 8, Color(0.8, 0.76, 0.64), 1.0, true)
	pk.box("panel", Vector3(x1 - 0.5, 1.15, mz + 0.18), Vector3(x1 - 0.38, 1.36, mz + 0.4), Color(0.6, 0.6, 0.6))
	pk.disc("enamel", Vector3(x1 - 0.501, 1.27, mz + 0.29), Vector3.LEFT, Vector3.UP, 0.07, 16, Color(0.8, 0.76, 0.64))
	var kk = c.kit("et_key")
	var ring := PackedVector3Array()
	for j in 13:
		var a := TAU * float(j) / 12.0
		ring.append(Vector3(cos(a) * 0.016, 0.0, sin(a) * 0.016 - 0.045))
	kk.tube("brass", ring, 0.004, 6, Color(1.0, 0.95, 0.8))
	kk.box("brass", Vector3(-0.004, -0.004, -0.03), Vector3(0.004, 0.004, 0.05), Color(1.0, 0.95, 0.8))
	kk.box("brass", Vector3(0.0, -0.003, 0.03), Vector3(0.018, 0.003, 0.05), Color(1.0, 0.95, 0.8))
	c.room_fx["key_pos"] = Vector3(x1 - 0.44, 1.156, mz - 0.12)
	# an old rug under the sheets
	pk.box("carpet", Vector3(58.6, 0.0, -6.4), Vector3(64.0, 0.012, -2.6), Color(0.7, 0.42, 0.36), 1.0, Kit.FACE_PY)
	# the furniture under its dust sheets
	var fl: Array = L.FURNITURE
	for i in fl.size():
		var f: Array = fl[i]
		var tint := Color(1.0, 1.0, 1.0).darkened(0.04 * float(i % 3))
		_draped(sk, cl, Vector3(float(f[0]), 0.0, float(f[1])), Vector3(float(f[2]), float(f[4]), float(f[3])), tint)
	# shapes that tell what is under some of them: the piano's keyboard shelf, the sofa's back, a lamp on the table
	sk.rbox("sheet", Vector3(57.15, 0.0, -6.25), Vector3(57.5, 0.78, -4.95), 0.08, 3, Color.WHITE)
	sk.rbox("sheet", Vector3(58.4, 0.0, -4.76), Vector3(60.4, 1.1, -4.42), 0.1, 3, Color.WHITE)
	sk.rbox("sheet", Vector3(63.3, 0.0, -5.38), Vector3(64.1, 1.25, -5.1), 0.1, 3, Color.WHITE)
	# the chandelier, bagged in muslin, hanging dead from the ceiling rose
	pk.tube("brass", PackedVector3Array([Vector3(61.0, ch, -4.4), Vector3(61.0, ch - 0.45, -4.4)]), 0.012, 6, Color.WHITE)
	sk.sphere("sheet", Vector3(61.0, ch - 0.8, -4.4), 0.34, 16, 10, Color(0.8, 0.8, 0.8), Vector3(1.0, 0.85, 1.0))
	sk.sphere("sheet", Vector3(61.0, ch - 1.12, -4.4), 0.15, 12, 8, Color(0.72, 0.72, 0.72), Vector3(1.0, 1.3, 1.0))
	pk.disc("plaster", Vector3(61.0, ch - 0.002, -4.4), Vector3.DOWN, Vector3.RIGHT, 0.32, 20, Color.WHITE)

# ====================================================================== sa chambre

static func _chambre(c) -> void:
	var k = c.kit("et_shell")
	var tk = c.kit("et_trim")
	var pk = c.kit("et_props")
	var cl = c.col("et_shell")
	var R: Dictionary = L.CHAMBRE
	var x0: float = R.x0
	var x1: float = R.x1
	var z0: float = R.z0
	var z1: float = R.z1
	var ch: float = R.ceil
	var top := ch + 0.2
	k.box("floorboards", Vector3(x0 - 0.2, -0.2, z0 - 0.2), Vector3(x1 + 0.2, 0.0, z1), Color.WHITE, 1.0, Kit.FACE_PY)
	k.box("plaster", Vector3(x0, ch, z0), Vector3(x1, top, z1), Color.WHITE, 1.0, Kit.FACE_NY | Kit.FACE_PY)
	cl.box(Vector3(x0, ch, z0), Vector3(x1, top, z1))
	Shell.wall(c, "et_shell", "wallpaper_house", Vector2(x0 - 0.1, z0 - 0.2), Vector2(x0 - 0.1, z1 + 0.1), 0.2, 0.0, top)
	Shell.wall(c, "et_shell", "wallpaper_house", Vector2(x0 - 0.2, z0 - 0.1), Vector2(x1 + 0.1, z0 - 0.1), 0.2, 0.0, top)
	pk.box("carpet", Vector3(53.0, 0.0, -4.2), Vector3(55.6, 0.012, -2.0), Color(0.5, 0.36, 0.52), 1.0, Kit.FACE_PY)
	# the bedroom door: its leaf turns around its hinge (etage.gd)
	var dc: Dictionary = L.DOOR_CHAMBRE
	var dk = c.kit("et_door_chambre")
	_leaf(dk, float(dc.x1) - float(dc.x0) - 0.04, float(dc.h), Color(0.8, 0.8, 0.8))
	c.room_fx["chambre_hinge"] = Vector3(float(dc.x0) + 0.02, 0.0, z1 - 0.02)
	c.room_fx["chambre_w"] = float(dc.x1) - float(dc.x0) - 0.04
	# iron bed against the north wall, the covers thrown back
	var bx := 54.3
	var bz := z0 + 1.05
	for sx in [-0.5, 0.5]:
		pk.tube("steel_up", PackedVector3Array([Vector3(bx + sx, 0.0, z0 + 0.06), Vector3(bx + sx, 1.15, z0 + 0.06)]), 0.018, 8, Color(0.08, 0.08, 0.08))
		pk.tube("steel_up", PackedVector3Array([Vector3(bx + sx, 0.0, z0 + 2.04), Vector3(bx + sx, 0.78, z0 + 2.04)]), 0.018, 8, Color(0.08, 0.08, 0.08))
	for hy in [0.55, 1.12]:
		pk.tube("steel_up", PackedVector3Array([Vector3(bx - 0.5, hy, z0 + 0.06), Vector3(bx + 0.5, hy, z0 + 0.06)]), 0.014, 8, Color(0.08, 0.08, 0.08))
	pk.tube("steel_up", PackedVector3Array([Vector3(bx - 0.5, 0.75, z0 + 2.04), Vector3(bx + 0.5, 0.75, z0 + 2.04)]), 0.014, 8, Color(0.08, 0.08, 0.08))
	for i in 5:
		var sx := -0.4 + i * 0.2
		pk.tube("steel_up", PackedVector3Array([Vector3(bx + sx, 0.55, z0 + 0.06), Vector3(bx + sx, 1.12, z0 + 0.06)]), 0.007, 6, Color(0.08, 0.08, 0.08))
	pk.box("steel_up", Vector3(bx - 0.5, 0.3, z0 + 0.06), Vector3(bx + 0.5, 0.36, z0 + 2.04), Color(0.08, 0.08, 0.08))
	pk.rbox("fabric", Vector3(bx - 0.48, 0.36, z0 + 0.1), Vector3(bx + 0.48, 0.52, z0 + 2.0), 0.05, 2, Color(0.7, 0.68, 0.6))
	# the pillow is lifted (own region, around its middle); under it, a slip of paper with one digit on it
	var plk = c.kit("et_pillow")
	plk.rbox("fabric", Vector3(-0.36, -0.05, -0.195), Vector3(0.36, 0.05, 0.195), 0.045, 3, Color(0.76, 0.74, 0.68))
	var pil := Vector3(bx, 0.55, z0 + 0.355)
	c.room_fx["pillow_pos"] = pil
	var slip := Vector3(bx - 0.05, 0.522, z0 + 0.36)
	var sb := Basis(Vector3.UP, 0.2)
	pk.quad("debris_paper", slip + sb * Vector3(-0.07, 0, 0.09), slip + sb * Vector3(0.07, 0, 0.09), slip + sb * Vector3(0.07, 0, -0.09), slip + sb * Vector3(-0.07, 0, -0.09),
		Vector3.UP, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Color(0.86, 0.82, 0.7))
	sb = Basis(Vector3.UP, 0.6)                    # (the digit reads from the side of the bed one comes to)
	c.kit("et_slip_digit").quad("digit_ink", slip + sb * Vector3(-0.06, 0.002, 0.06), slip + sb * Vector3(0.06, 0.002, 0.06), slip + sb * Vector3(0.06, 0.002, -0.06), slip + sb * Vector3(-0.06, 0.002, -0.06),
		Vector3.UP, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
	pk.rbox("fabric", Vector3(bx - 0.5, 0.5, bz + 0.25), Vector3(bx + 0.5, 0.62, z0 + 2.02), 0.05, 3, Color(0.3, 0.12, 0.14))
	pk.rbox("fabric", Vector3(bx + 0.46, 0.06, bz + 0.3), Vector3(bx + 0.54, 0.58, z0 + 1.9), 0.03, 2, Color(0.3, 0.12, 0.14))
	cl.box(Vector3(bx - 0.52, 0.0, z0), Vector3(bx + 0.54, 0.62, z0 + 2.06))
	# bedside table: a lamp left on, a pill bottle, a second letter
	var nt := Vector3(bx + 0.95, 0.0, z0 + 0.3)
	pk.box("panel", nt + Vector3(-0.22, 0.0, -0.2), nt + Vector3(0.22, 0.56, 0.2), DARK_WOOD)
	pk.box("panel", nt + Vector3(-0.24, 0.56, -0.22), nt + Vector3(0.24, 0.59, 0.22), Color(0.85, 0.85, 0.85))
	cl.box(nt + Vector3(-0.24, 0.0, -0.22), nt + Vector3(0.24, 0.59, 0.22))
	pk.tube("brass", PackedVector3Array([nt + Vector3(0.05, 0.59, -0.05), nt + Vector3(0.05, 0.82, -0.05)]), 0.012, 8, Color.WHITE, 1.0, true)
	pk.tube("brass", PackedVector3Array([nt + Vector3(0.05, 0.59, -0.05), nt + Vector3(0.05, 0.605, -0.05)]), 0.06, 12, Color.WHITE, 1.0, true)
	var em: StandardMaterial3D = c.mats.emissive_instance("night_glow")
	em.emission_energy_multiplier = 2.4
	var gk = Kit.new()
	gk.sphere("glow", nt + Vector3(0.05, 0.92, -0.05), 0.11, 14, 8, Color.WHITE, Vector3(1.0, 0.95, 1.0))
	gk.commit(c.region("et_props"), {"glow": em}, "et_bed_lamp", {"no_shadow": ["glow"]})
	var o := OmniLight3D.new()
	o.name = "BedLamp"
	o.position = nt + Vector3(0.05, 1.08, 0.02)
	o.light_color = Color(1.0, 0.62, 0.3)
	o.light_energy = 0.7
	o.omni_range = 5.0
	o.omni_attenuation = 1.2
	o.shadow_enabled = true
	o.shadow_bias = 0.05
	o.shadow_normal_bias = 1.2
	o.light_cull_mask = MASK
	c.region("et_lights").add_child(o)
	c.room_fx["bed_lamp"] = {"light": o, "emit": em}
	var note := nt + Vector3(-0.08, 0.592, 0.08)
	pk.quad("debris_paper", note + Vector3(-0.07, 0, 0.09), note + Vector3(0.07, 0, 0.09), note + Vector3(0.07, 0, -0.09), note + Vector3(-0.07, 0, -0.09),
		Vector3.UP, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Color(0.84, 0.8, 0.68))
	c.room_fx["bed_note"] = note
	# a dresser with its mirror on the west wall, slippers by the bed
	pk.box("panel", Vector3(x0, 0.0, -3.9), Vector3(x0 + 0.48, 0.9, -2.7), DARK_WOOD)
	for i in 3:
		pk.box("panel", Vector3(x0 + 0.48, 0.08 + i * 0.27, -3.84), Vector3(x0 + 0.492, 0.32 + i * 0.27, -2.76), Color(0.82, 0.82, 0.82))
		for kz in [-3.55, -3.05]:
			pk.sphere("brass", Vector3(x0 + 0.5, 0.2 + i * 0.27, kz), 0.016, 8, 6, Color.WHITE)
	cl.box(Vector3(x0, 0.0, -3.9), Vector3(x0 + 0.48, 0.9, -2.7))
	Shell.board(pk, "mirror", Vector3(x0 + 0.02, 1.5, -3.3), Vector3.RIGHT, 0.6, 0.85, 0.02)
	Shell.board(pk, "panel", Vector3(x0 + 0.012, 1.5, -3.3), Vector3.RIGHT, 0.72, 0.97, 0.02, Color(0.7, 0.7, 0.7))
	for sx in [-0.1, 0.06]:
		pk.rbox("fabric", Vector3(bx + 0.62 + sx, 0.0, bz + 0.5), Vector3(bx + 0.7 + sx, 0.06, bz + 0.74), 0.025, 2, Color(0.36, 0.2, 0.22))
	# her rocking chair, turned to the door (it rocks: its own region, authored around the floor point under the seat)
	var rk = c.kit("et_rocker")
	for lx in [-0.24, 0.24]:
		rk.box("panel", Vector3(lx - 0.02, 0.0, -0.4), Vector3(lx + 0.02, 0.04, 0.42), DARK_WOOD)
		rk.box("panel", Vector3(lx - 0.02, 0.04, -0.3), Vector3(lx + 0.02, 0.67, -0.26), DARK_WOOD)
		rk.box("panel", Vector3(lx - 0.02, 0.04, 0.24), Vector3(lx + 0.02, 0.45, 0.28), DARK_WOOD)
		rk.box("panel", Vector3(lx - 0.025, 0.65, -0.3), Vector3(lx + 0.025, 0.68, 0.3), DARK_WOOD)
	rk.box("panel", Vector3(-0.24, 0.43, -0.3), Vector3(0.24, 0.46, 0.28), DARK_WOOD)
	var back := Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3(0, 0.45, 0.26))
	for i in 5:
		var sx := -0.2 + i * 0.1
		rk.box("panel", Vector3(sx - 0.02, 0.0, -0.012), Vector3(sx + 0.02, 0.72, 0.012), DARK_WOOD, 1.0, Kit.ALL, back)
	rk.box("panel", Vector3(-0.25, 0.7, -0.018), Vector3(0.25, 0.78, 0.018), DARK_WOOD, 1.0, Kit.ALL, back)
	rk.rbox("fabric", Vector3(-0.2, 0.45, -0.24), Vector3(0.2, 0.5, 0.2), 0.02, 2, Color(0.3, 0.12, 0.14))
	rk.rbox("fabric", Vector3(-0.22, 0.5, 0.0), Vector3(0.22, 0.56, 0.24), 0.025, 2, Color(0.5, 0.48, 0.42))      # a shawl left on it
	c.room_fx["rocker_pos"] = Vector3(x0 + 0.75, 0.0, z1 - 0.9)
	c.room_fx["rocker_yaw"] = PI * 0.62
	cl.box(Vector3(x0 + 0.4, 0.0, z1 - 1.3), Vector3(x0 + 1.1, 0.9, z1 - 0.5))
	_portrait(tk, Vector3(53.2, 1.6, z0 + 0.006), Vector3.BACK, 0.34, 0.42, 3)
	_portrait(tk, Vector3(x1 - 0.006, 1.55, -3.0), Vector3.LEFT, 0.5, 0.4, 1)

# ====================================================================== the closet off the hallway

static func _closet(c) -> void:
	var k = c.kit("et_shell")
	var pk = c.kit("et_props")
	var K: Dictionary = L.CLOSET
	var x0: float = K.x0
	var x1: float = K.x1
	var z0: float = K.z0
	var z1: float = K.z1
	var ch: float = K.ceil
	k.box("floorboards", Vector3(x0 - 0.1, -0.2, z0), Vector3(x1 + 0.1, 0.0, z1 + 0.1), Color.WHITE, 1.0, Kit.FACE_PY)
	k.box("plaster", Vector3(x0, ch, z0), Vector3(x1, ch + 0.2, z1), Color.WHITE, 1.0, Kit.FACE_NY | Kit.FACE_PY)
	Shell.wall(c, "et_shell", "plaster", Vector2(x0 - 0.05, z0), Vector2(x0 - 0.05, z1 + 0.1), 0.1, 0.0, ch + 0.2)
	Shell.wall(c, "et_shell", "plaster", Vector2(x1 + 0.05, z0), Vector2(x1 + 0.05, z1 + 0.1), 0.1, 0.0, ch + 0.2)
	Shell.wall(c, "et_shell", "plaster", Vector2(x0 - 0.1, z1 + 0.05), Vector2(x1 + 0.1, z1 + 0.05), 0.1, 0.0, ch + 0.2)
	pk.tube("panel", PackedVector3Array([Vector3(x0, 1.8, z0 + 0.5), Vector3(x1, 1.8, z0 + 0.5)]), 0.015, 8, DARK_WOOD)
	for hx in [x0 + 0.14, x1 - 0.12]:
		pk.rbox("fabric", Vector3(hx - 0.04, 0.75, z0 + 0.36), Vector3(hx + 0.04, 1.78, z0 + 0.64), 0.03, 2, Color(0.08, 0.07, 0.07))
	var dk: Dictionary = L.DOOR_CLOSET
	var lk = c.kit("et_door_closet")
	_leaf(lk, float(dk.x1) - float(dk.x0) - 0.04, float(dk.h), Color(0.8, 0.8, 0.8))
	c.room_fx["closet_hinge"] = Vector3(float(dk.x1) - 0.02, 0.0, float(L.HALL.z1) + 0.02)
	c.room_fx["closet_w"] = float(dk.x1) - float(dk.x0) - 0.04

# ====================================================================== the figures

static func _figures(c) -> void:
	var fl: Array = L.FIGURES
	for i in fl.size():
		sheet_figure(c.kit("et_fig_%d" % i), float(fl[i][1]), 11 + i * 7, Color(1, 1, 1).darkened(0.03 * float(i % 3)))
	sheet_figure(c.kit("et_walker"), float(L.WALKER[1]), 97, Color(0.96, 0.95, 0.93))
	sheet_figure(c.kit("et_closetfig"), float(L.CLOSET_FIGURE[1]), 53, Color(0.9, 0.9, 0.9))
