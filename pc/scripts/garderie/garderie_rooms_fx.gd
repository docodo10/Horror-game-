## What lives in the garderie's side rooms (geometry: garderie_rooms.gd; positions come from ctx.room_fx):
##   dortoir    the music box starts by itself a few seconds after the player walks in (the crib mobile turns with it);
##              stopped by hand or run down, the ceiling bulb then pops and something giggles among the beds. The
##              battery night-light keeps throwing its stars on the ceiling with or without house power.
##   bureau     the phone with the cut cord rings (after her notebook was read, or after a while in the room): every
##              ring is a noise La Gardienne hears. Picking up: breathing on the line.
##   toilettes  a tap drips; the middle stall door creaks open behind the player and slams when approached.
## Three notes to read (they join the inventory like the house's notes). Everything is optional for the escape.
## API: setup(garderie, ctx), entries (interaction entries the garderie registers), reset() (after being caught).
extends Node3D

const GL := preload("res://scripts/garderie/garderie_layout.gd")
const LAYER_WORLD := 1
const LAYER_INTERACT := 2
const LAYER_SIGHT := 16
const STAR_COOKIE := "res://assets/garderie/textures/star_cookie.png"

const NOTES := {
	"dortoir": {
		"title": "Papier plié sous l’oreiller", "style": "child",
		"text": "Léa,\n\nelle compte les lits pendant la sieste.\nSept lits, sept bosses.\nJ’ai mis mes coussins sous ma couverture.\n\nFais semblant de dormir.\nNe bouge pas quand la musique s’arrête.\n\nMathis",
	},
	"bureau": {
		"title": "Cahier de la gardienne", "style": "note",
		"text": "3 novembre\nLes parents ne comprennent pas. Dehors, tout abîme les enfants. Ici, en bas, rien ne peut leur arriver.\n\n"
			+ "9 novembre\nJ’ai fermé la garderie. J’ai gardé Léa et Mathis. Ils pleurent encore. Je chante. Ça passe.\n\n"
			+ "11 novembre\nMathis a trouvé le téléphone. J’ai coupé le fil.\nIl sonne quand même, la nuit.\nJe ne réponds plus.",
	},
	"toilettes": {
		"title": "Dessin collé dans la cabine", "style": "child",
		"text": "ELLE RENTRE PAS\nDANS LE TUNNEL.\nELLE EST TROP GRANDE.\n\nSI ELLE CHANTE\nVA DANS LE TUNNEL\nEN HAUT DES MARCHES.\n\nMathis",
	},
}

var entries: Array = []

var _g: Node = null
var _ctx = null
var _mobile: Node3D = null
var _mobile_speed := 0.0
var _mobile_target := 0.0
var _proj: SpotLight3D = null
var _stars: Decal = null
var _stall: Node3D = null
var _stall_a := 0.0
var _stall_state := 0          # 0 waiting, 1 creaking open, 2 open, 3 slamming, 4 done
var _wc_t := 0.0
var _music = null
var _music_state := 0          # 0 never played, 1 playing (first time), 2 aftermath running, 3 done, 4 playing again
var _music_t := 0.0
var _dort_t := 0.0
var _phone_state := 0          # 0 silent, 1 ringing, 2 answered, 3 rang out
var _phone_arm := -1.0         # seconds before the first ring (< 0: not armed)
var _bur_t := 0.0
var _ring_t := 0.0
var _rings := 0
var _line = null
var _drip = null
var _journal_read := false

func setup(garderie: Node, ctx) -> void:
	name = "RoomsFx"
	_g = garderie
	_ctx = ctx
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var fx: Dictionary = ctx.room_fx
	# the crib mobile (its meshes never cast: a turning shadow caster would re-render the room's shadow map each frame)
	_mobile = ctx.regions.get("room_dort_mobile")
	if _mobile != null and fx.has("mobile_pos"):
		_mobile.position = fx.mobile_pos
		for m in _mobile.find_children("*", "GeometryInstance3D", true, false):
			(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the stall door, shut, with a fixed collider across its opening
	_stall = ctx.regions.get("room_wc_stall")
	if _stall != null and fx.has("stall_hinge"):
		_stall.position = fx.stall_hinge
		var w := float(fx.get("stall_w", 0.6))
		var body := StaticBody3D.new()
		body.name = "StallDoorCollider"
		body.collision_layer = LAYER_WORLD | LAYER_SIGHT
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(w, 1.4, 0.03)
		cs.shape = sh
		cs.position = (fx.stall_hinge as Vector3) + Vector3(w * 0.5, 0.85, 0.0)
		body.add_child(cs)
		add_child(body)
	# the night-light: stars on the ceiling of the dortoir (battery: it stays on when the house power is cut).
	# An emissive decal, not a light projector: a projector only works on a shadowed light (its matrix is the shadow
	# matrix), and a shadowed light that turns would re-render its shadow map every frame. A soft unshadowed spot adds
	# the bluish wash the dome would throw on the ceiling and the top of the walls.
	if fx.has("projector_pos"):
		var pp: Vector3 = fx.projector_pos
		_proj = SpotLight3D.new()
		_proj.name = "NightLightWash"
		_proj.position = pp
		_proj.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		_proj.spot_range = 5.5
		_proj.spot_angle = 70.0
		_proj.spot_angle_attenuation = 0.5
		_proj.spot_attenuation = 0.6
		_proj.light_color = Color(0.5, 0.66, 1.0)
		_proj.light_energy = 0.55
		_proj.light_specular = 0.1
		_proj.shadow_enabled = false
		_proj.light_cull_mask = 1 | 4096
		add_child(_proj)
		if ResourceLoader.exists(STAR_COOKIE):
			var D: Dictionary = GL.DORT
			_stars = Decal.new()
			_stars.name = "NightLightStars"
			_stars.texture_emission = load(STAR_COOKIE) as Texture2D
			_stars.emission_energy = 2.6
			_stars.modulate = Color(0.72, 0.84, 1.0)
			_stars.albedo_mix = 0.0
			_stars.size = Vector3(5.4, 0.3, 5.4)
			_stars.upper_fade = 0.0001
			_stars.lower_fade = 0.0001
			_stars.cull_mask = 4096
			_stars.distance_fade_enabled = true
			_stars.distance_fade_begin = 12.0
			_stars.distance_fade_length = 3.0
			_stars.position = Vector3(clampf(pp.x, float(D.x0) + 2.7, float(D.x1) - 2.7), float(D.ceil) - 0.05, (float(D.z0) + float(D.z1)) * 0.5)
			_stars.rotation = Vector3(PI, 0.0, 0.0)
			add_child(_stars)
	# things to use and to read
	if fx.has("music_box"):
		var mb := _spot("MusicBox", fx.music_box, Vector3(0.2, 0.16, 0.16))
		entries.append({"id": "garderie.dortoir.musicbox", "node": mb, "max_distance": 1.9,
			"prompt": func() -> String: return "Arrêter la boîte à musique" if _music_playing() else "Remonter la boîte à musique",
			"on_interact": _use_music_box})
	if fx.has("dort_note"):
		var dn := _spot("DortoirNote", (fx.dort_note as Vector3) + Vector3(0, 0.04, 0), Vector3(0.2, 0.1, 0.16))
		entries.append({"id": "garderie.dortoir.note", "node": dn, "max_distance": 1.9, "prompt": "Lire le papier",
			"on_interact": func() -> void: await _read("gd_note_dortoir", NOTES.dortoir, dn)})
	if fx.has("journal"):
		var jn := _spot("Journal", fx.journal, Vector3(0.2, 0.08, 0.26))
		entries.append({"id": "garderie.bureau.journal", "node": jn, "max_distance": 1.9, "prompt": "Lire le cahier",
			"on_interact": func() -> void:
				await _read("gd_note_bureau", NOTES.bureau, jn)
				if not _journal_read:
					_journal_read = true
					if _phone_state == 0: _phone_arm = 2.5})
	if fx.has("phone"):
		var pn := _spot("Phone", fx.phone, Vector3(0.26, 0.16, 0.26))
		entries.append({"id": "garderie.bureau.phone", "node": pn, "max_distance": 1.9,
			"prompt": func() -> String: return "Décrocher" if _phone_state == 1 else "Décrocher le téléphone",
			"on_interact": _use_phone})
	if fx.has("wc_note"):
		var wn := _spot("StallDrawing", fx.wc_note, Vector3(0.08, 0.34, 0.34))
		entries.append({"id": "garderie.toilettes.note", "node": wn, "max_distance": 1.9, "prompt": "Regarder le dessin",
			"on_interact": func() -> void: await _read("gd_note_toilettes", NOTES.toilettes, wn)})

func _spot(node_name: String, pos: Vector3, size: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = pos
	add_child(n)
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_INTERACT
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	n.add_child(body)
	return n

# ====================================================================== helpers

func _player_pos() -> Variant:
	var p = Game.player
	if p == null or not is_instance_valid(p) or not (p is Node3D):
		return null
	return (p as Node3D).global_position

func _wait(s: float) -> void:
	await get_tree().create_timer(s, false).timeout

func _say(text: String, seconds := 3.0) -> void:
	var ui = Game.ui
	if ui != null and is_instance_valid(ui) and ui.has_method("subtitle"):
		ui.call("subtitle", text, seconds, {})

func _read(id: String, note: Dictionary, node: Node3D) -> void:
	var pz = Game.puzzles
	if pz != null and is_instance_valid(pz) and pz.has_method("_read_note"):
		await pz.call("_read_note", id, note, node, Callable())
		return
	var ui = Game.ui
	if ui != null and is_instance_valid(ui) and ui.has_method("show_note"):
		var shown := {"id": id, "title": str(note.title), "text": str(note.text), "style": str(note.style)}
		await Game.modal(func() -> void: await ui.show_note(shown))

func _stop(h: Variant, fade := 0.3) -> void:
	if h is Object and is_instance_valid(h) and (h as Object).has_method("stop"):
		h.stop(fade)

func _chased() -> bool:
	var ent = Game.entity
	return ent != null and is_instance_valid(ent) and String(ent.get("state")) in ["chasing", "jumpscare"]

# ====================================================================== le dortoir

func _music_playing() -> bool:
	return _music_state == 1 or _music_state == 4

func _start_music(first: bool) -> void:
	var fx: Dictionary = _ctx.room_fx
	_music = _g.call("_play", "music_box", fx.music_box, -1.0, 1.0)
	_music_state = 1 if first else 4
	_music_t = 23.0
	_mobile_target = 1.5
	Events.noise.emit(fx.music_box, 0.22, "music_box")

func _use_music_box() -> void:
	if _music_playing():
		var first := _music_state == 1
		_stop(_music, 0.25)
		_music = null
		_mobile_target = 0.0
		if first:
			_aftermath()
		else:
			_music_state = 3
	elif _music_state != 2:
		_start_music(_music_state == 0)

## The silence after the music: the bulb pops (when it was lit), then a giggle among the beds.
func _aftermath() -> void:
	_music_state = 2
	_mobile_target = 0.0
	await _wait(1.3)
	var fx: Dictionary = _ctx.room_fx
	var l = fx.get("dort_light")
	if l is Light3D and (l as Light3D).visible:
		for e in _ctx.lights:
			if e.light == l or e.light == fx.get("dort_fill"):
				e["killed"] = true
				e["state"] = "dead"
				if e.emit is StandardMaterial3D:
					(e.emit as StandardMaterial3D).emission_energy_multiplier = 0.0
				(e.light as Light3D).visible = false
		_g.call("_play", "fluo_pop", (l as Light3D).global_position, -3.0, 1.1)
		var rp = fx.get("dort_probe")
		if rp is ReflectionProbe:
			(rp as ReflectionProbe).update_mode = ReflectionProbe.UPDATE_ONCE     # the room's reflections follow: dark now
	await _wait(1.6)
	_g.call("_play", "giggle", Vector3(float(GL.DORT.x0) + 1.6, 0.4, float(GL.DORT.z0) + 0.7), -6.0, 0.92)
	_music_state = 3

# ====================================================================== le bureau

func _ring() -> void:
	var fx: Dictionary = _ctx.room_fx
	_g.call("_play", "phone_ring", fx.phone, 1.0, 1.0)
	Events.noise.emit(fx.phone, 0.4, "phone")
	_rings += 1
	_ring_t = 3.4

func _use_phone() -> void:
	if _phone_state != 1:
		_say("Pas de tonalité. Le fil est coupé.", 3.0)
		return
	_phone_state = 2
	_answer()

func _answer() -> void:
	var fx: Dictionary = _ctx.room_fx
	_g.call("_play", "phone_pickup", fx.phone, 0.0, 1.0)
	await _wait(0.5)
	_line = _g.call("_play", "phone_line", (fx.phone as Vector3) + Vector3(0, 0.5, 0), 2.0, 1.0)
	await _wait(2.2)
	_say("(Une respiration, au bout du fil…)", 3.2)
	await _wait(4.3)
	_say("« …fais semblant de dormir… »", 3.0)
	await _wait(2.0)
	_line = null

# ====================================================================== les toilettes

func _stall_tick(dt: float, pp: Vector3, in_wc: bool) -> void:
	if _stall == null:
		return
	var fx: Dictionary = _ctx.room_fx
	var hinge: Vector3 = fx.stall_hinge
	match _stall_state:
		0:
			if in_wc:
				_wc_t += dt
			# it waits until the player stands at the basins, their back to the stalls
			if _wc_t > 4.0 and in_wc and pp.z < hinge.z - 1.0 and pp.x < float(GL.WC.x0) + 2.0 and not _chased():
				_stall_state = 1
				_g.call("_play", "stall_creak", hinge + Vector3(0.3, 1.0, 0.0), 0.0, 1.0)
		1:
			_stall_a = move_toward(_stall_a, 0.5, dt * 0.21)
			_stall.rotation.y = _stall_a
			if _stall_a >= 0.5:
				_stall_state = 2
		2:
			var d := Vector2(pp.x - (hinge.x + 0.3), pp.z - hinge.z).length()
			if d < 1.15 or not in_wc:
				_stall_state = 3
				_g.call("_play", "door_close", hinge + Vector3(0.3, 1.0, 0.0), 3.0, 1.25)
				Events.noise.emit(hinge, 0.45, "stall")
		3:
			_stall_a = move_toward(_stall_a, 0.0, dt * 7.0)
			_stall.rotation.y = _stall_a
			if _stall_a <= 0.0:
				_stall_state = 4
				_after_slam()

func _after_slam() -> void:
	await _wait(1.1)
	var fx: Dictionary = _ctx.room_fx
	_g.call("_play", "giggle", (fx.stall_hinge as Vector3) + Vector3(0.3, 0.5, 0.7), -9.0, 1.05)

# ====================================================================== tick

func _process(dt: float) -> void:
	if _ctx == null:
		return
	var pv = _player_pos()
	if pv == null:
		return
	var pp: Vector3 = pv
	var playing: bool = Game.state == "playing"
	var near_dort := pp.x < -3.7 and pp.x > -12.0 and pp.z < 3.2
	if _mobile != null and near_dort:
		_mobile_speed = move_toward(_mobile_speed, _mobile_target, dt * 0.7)
		if _mobile_speed > 0.001:
			_mobile.rotation.y += _mobile_speed * dt
	if _stars != null and near_dort:
		_stars.rotation.y += dt * 0.03
	if not playing:
		return
	var in_dort := GL.in_room(GL.DORT, pp)
	var in_bur := GL.in_room(GL.BUR, pp)
	var in_wc := GL.in_room(GL.WC, pp)
	# dortoir: the music box starts by itself, runs down by itself
	if _music_state == 0 and in_dort and not _chased():
		_dort_t += dt
		if _dort_t > 4.5:
			_start_music(true)
	if _music_playing():
		_music_t -= dt
		if _music_t <= 0.0:
			var first := _music_state == 1
			_music = null
			_mobile_target = 0.0
			if first:
				_aftermath()
			else:
				_music_state = 3
	# bureau: the phone
	if _phone_state == 0:
		if in_bur:
			_bur_t += dt
		if _phone_arm < 0.0 and _bur_t > 24.0:
			_phone_arm = 0.5
		if _phone_arm >= 0.0 and not _chased():
			_phone_arm -= dt
			if _phone_arm < 0.0:
				_phone_state = 1
				_rings = 0
				_ring()
	elif _phone_state == 1:
		_ring_t -= dt
		if _ring_t <= 0.0:
			if _rings >= 7:
				_phone_state = 3
			else:
				_ring()
	# toilettes: the drip while the player is near, the stall door
	var near_wc := pp.x < -10.9 and pp.x > -17.2 and pp.z > 2.6
	if near_wc and _drip == null and _ctx.room_fx.has("drip_pos"):
		_drip = _g.call("_loop", "water_drip", _ctx.room_fx.drip_pos, -2.0)
	elif not near_wc and _drip != null:
		_stop(_drip, 0.6)
		_drip = null
	_stall_tick(dt, pp, in_wc)

## After being caught (the player is put back in the house): silence, nothing left half-done.
func reset() -> void:
	_stop(_music, 0.1)
	_music = null
	if _music_playing():
		_music_state = 3
	_mobile_target = 0.0
	_stop(_line, 0.1)
	_line = null
	if _phone_state == 1:
		_phone_state = 3
	_stop(_drip, 0.2)
	_drip = null
	if _stall_state in [1, 2, 3]:
		_stall_state = 4
		_stall_a = 0.0
		if _stall != null:
			_stall.rotation.y = 0.0

func _exit_tree() -> void:
	_stop(_music, 0.0)
	_stop(_line, 0.0)
	_stop(_drip, 0.0)
