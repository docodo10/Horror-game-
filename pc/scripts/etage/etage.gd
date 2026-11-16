## L'étage — chapter 2 (geometry: etage_build.gd, coordinates: etage_layout.gd). Started from the TV menu (Game.mode
## "etage"): the house and the garderie are hidden, the player stands at the top of the basement stairs, in the
## hallway of the old house, at night. The way out is the front door at the far end; its key lies on the mantel of
## the salon, where everything stands under dust sheets.
##
## The dread is not a chase. One of the shapes under the sheets walks — only while nobody looks at it:
##   * every figure is a statue while any part of it is on screen and in line of sight; unseen, the walker comes
##     straight for the player (slower than a walk, faster when far), and each of its steps creaks at ITS position,
##     so the ears say how close it is behind;
##   * the other figures never walk, but they turn to face the player while unseen, and after the key is taken they
##     are found standing closer to the way out;
##   * the front door needs the key held in the lock for three seconds, back turned.
## Before the key: floorboards that complain under a standing step (crouching spares them) silence the humming
## behind the bedroom door, as if she listened. A few plain frights mark the way (a door slammed from inside, the
## clock, the piano); everything else is sound placed in the room: wood, hinges, cloth, breath.
##
## API: build() (await), begin() (start of the chapter), active, fear (0..1 for Game: heartbeat, breath),
## in_area(pos), surface_at(pos), reset_after_caught(), prewarm(on) (loading rehearsal), stage, stats.
extends Node3D

const L := preload("res://scripts/etage/etage_layout.gd")
const Build := preload("res://scripts/etage/etage_build.gd")
const Ctx := preload("res://scripts/garderie/garderie_ctx.gd")
const Mats := preload("res://scripts/garderie/garderie_mats.gd")

const LAYER_WORLD := 1
const LAYER_INTERACT := 2
const LAYER_SIGHT := 16
const WALK_SPEED := 1.32            # m/s unseen (the player walks at 1.9, crouches at 0.9)
const CATCH_DIST := 0.8

const NOTES := {
	"letter": {
		"title": "Lettre jamais envoyée", "style": "note",
		"text": "Chère Thérèse,\n\nj’ai couvert les meubles du salon pour l’hiver. Je compte les draps chaque soir avant de monter. Six.\n\n"
			+ "Hier soir il y en avait sept.\n\nElle ne bouge jamais quand je la regarde. Alors je la regarde. Je recule jusqu’à ma chambre sans la quitter des yeux, et je ferme à clé.\n\n"
			+ "Ne viens pas à Noël.",
	},
	"bed": {
		"title": "Page arrachée", "style": "note",
		"text": "Je garde la lampe allumée.\n\nQuand je chante, je l’entends moins marcher. Les petits croient que je chante pour eux.\n\n"
			+ "Si le plancher craque et que ce n’est pas moi, je m’arrête de chanter. J’écoute où elle est.\n\nLa clé de la porte d’entrée est sur la cheminée. Je n’ose plus traverser le salon.",
	},
}

var ctx = null
var built := false
var active := false
var stage := 0                    # 0 find the way out, 1 the front door is locked, 2 the key is taken (it walks), 3 out
var fear := 0.0
var stats := {}

var _entries: Array = []
var _registered_with: Node = null
var _t := 0.0
var _figs: Array = []             # the ones that only turn: {node, body, home, alt, h, at_alt, unseen, check}
var _walkers: Array = []          # {node, body, pos, home, h, awake, unseen, moved, revealed, stuck, rustle}
var _doors := {}                  # id -> {node, body, closed, open, a, goal, speed}
var _rocker: Node3D = null
var _rock := 0.0
var _rock_on := false
var _key: Node3D = null
var _obstacles: Array = []        # Rect2 (x, z) the walkers go around
var _boards_in: Array = []
var _creaks: Array = []           # times of the last loud creaks
var _rage := 0.0
var _hum = null
var _hum_pause := 0.0
var _theme = null
var _layer = null
var _tick = null
var _winds: Array = []
var _creak_t := 6.0
var _door_tried := false
var _chambre_done := false
var _piano_done := false
var _chime_done := false
var _knock_done := false
var _tap_done := false
var _closet_t := -1.0
var _steps_done := false
var _catching := false
var _busy := false
var _hint_done := false
var _seq := 0                     # bumped at every reset: coroutines of the previous life stop

# ====================================================================== build

func build() -> void:
	var t0 := Time.get_ticks_usec()
	name = "Etage"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	ctx = Ctx.new()
	ctx.root = self
	ctx.mats = Mats.new()
	Build.build(ctx)
	var tris: int = ctx.commit_all({"et_sky": {"no_shadow": ["night_sky"]}, "et_key": {"no_shadow": ["brass"]}, "et_webs": {"no_shadow": ["cobweb"]}})
	for g in find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).layers = L.L_ET
	_setup_nodes()
	_setup_entries()
	_register_or_wait()
	visible = false
	built = true
	stats = {"build_ms": (Time.get_ticks_usec() - t0) / 1000.0, "triangles": tris, "figures": _figs.size() + _walkers.size(),
		"lights": find_children("*", "Light3D", true, false).size(), "mesh_instances": find_children("*", "MeshInstance3D", true, false).size(),
		"missing_textures": ctx.mats.missing}

func _body(parent: Node3D, shape: Shape3D, at: Vector3, layer: int) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = layer
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = at
	b.add_child(cs)
	parent.add_child(b)
	return b

func _figure_body(node: Node3D, h: float) -> StaticBody3D:
	var sh := CylinderShape3D.new()
	sh.radius = 0.27
	sh.height = h
	return _body(node, sh, Vector3(0, h * 0.5, 0), LAYER_WORLD | LAYER_SIGHT)

func _setup_nodes() -> void:
	var fx: Dictionary = ctx.room_fx
	var fl: Array = L.FIGURES
	for i in fl.size():
		var n: Node3D = ctx.regions.get("et_fig_%d" % i)
		if n == null:
			continue
		var home: Vector3 = fl[i][0]
		n.position = home
		_figs.append({"node": n, "body": _figure_body(n, float(fl[i][1])), "home": home, "alt": fl[i][2], "h": float(fl[i][1]),
			"at_alt": false, "unseen": 0.0, "yaw0": float(i) * 1.9})
	for w in [["et_walker", L.WALKER], ["et_closetfig", L.CLOSET_FIGURE]]:
		var n: Node3D = ctx.regions.get(String(w[0]))
		if n == null:
			continue
		var home: Vector3 = w[1][0]
		n.position = home
		_walkers.append({"node": n, "body": _figure_body(n, float(w[1][1])), "pos": home, "home": home, "h": float(w[1][1]), "awake": false,
			"unseen": 0.0, "moved": 0.0, "revealed": false, "stuck": 0.0, "rustle": 0.0, "slow": 1.0 if _walkers.is_empty() else 0.78})
	# doors: leaves around their hinges (yaw closed / open), a collider across each opening
	_door("front", "et_door_front", fx.front_hinge, PI * 0.5, 0.2, Vector3(float(L.HALL.x1) + 0.1, 1.0, 0.0), Vector3(0.2, 2.1, 0.96))
	_door("chambre", "et_door_chambre", fx.chambre_hinge, 0.0, 1.45, Vector3((float(L.DOOR_CHAMBRE.x0) + float(L.DOOR_CHAMBRE.x1)) * 0.5, 1.0, float(L.HALL.z0) - 0.1), Vector3(0.9, 2.1, 0.2))
	_door("closet", "et_door_closet", fx.closet_hinge, PI, PI - 0.85, Vector3((float(L.DOOR_CLOSET.x0) + float(L.DOOR_CLOSET.x1)) * 0.5, 1.0, float(L.HALL.z1) + 0.1), Vector3(0.82, 2.1, 0.2))
	_rocker = ctx.regions.get("et_rocker")
	if _rocker != null:
		_rocker.position = fx.rocker_pos
		_rocker.rotation.y = float(fx.rocker_yaw)
	_key = ctx.regions.get("et_key")
	if _key != null:
		_key.position = fx.key_pos
		_key.rotation.y = 0.7
	for f in L.FURNITURE:
		_obstacles.append(Rect2(float(f[0]) - 0.34, float(f[1]) - 0.34, float(f[2]) - float(f[0]) + 0.68, float(f[3]) - float(f[1]) + 0.68))
	# chimney breast, clock, console table, bed, dresser, bedside table, rocking chair
	for r in [[65.14, -5.25, 65.5, -3.55], [62.92, -0.8, 63.48, -0.46], [61.2, 0.44, 62.2, 0.8], [53.78, -5.4, 54.84, -3.34], [52.2, -3.9, 52.68, -2.7],
			[55.0, -5.4, 55.5, -4.9], [52.6, -2.3, 53.3, -1.5]]:
		_obstacles.append(Rect2(float(r[0]) - 0.3, float(r[1]) - 0.3, float(r[2]) - float(r[0]) + 0.6, float(r[3]) - float(r[1]) + 0.6))
	_boards_in.resize(L.CREAKY.size())
	_boards_in.fill(false)

func _door(id: String, region: String, hinge: Vector3, closed: float, open: float, col_at: Vector3, col_size: Vector3) -> void:
	var n: Node3D = ctx.regions.get(region)
	if n == null:
		return
	n.position = hinge
	n.rotation.y = closed
	var sh := BoxShape3D.new()
	sh.size = col_size
	_doors[id] = {"node": n, "body": _body(self, sh, col_at, LAYER_WORLD | LAYER_SIGHT), "closed": closed, "open": open, "a": 0.0, "goal": 0.0, "speed": 1.0}

func _spot(node_name: String, pos: Vector3, size: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = pos
	add_child(n)
	var sh := BoxShape3D.new()
	sh.size = size
	_body(n, sh, Vector3.ZERO, LAYER_INTERACT)
	return n

func _setup_entries() -> void:
	var fx: Dictionary = ctx.room_fx
	var live := func() -> bool: return active and not _catching
	var fd := _spot("FrontDoor", Vector3(float(L.HALL.x1) - 0.02, 1.05, 0.0), Vector3(0.16, 2.0, 0.9))
	_entries.append({"id": "etage.front", "node": fd, "max_distance": 1.8,
		"prompt": func() -> String: return "Déverrouiller la porte" if stage == 2 else "Ouvrir la porte",
		"hold": func() -> float: return 2.8 if stage == 2 else 0.0,
		"hold_prompt": "La clé accroche…",
		"on_hold_start": func() -> void:
			_sfx("lock_wheel", fd.global_position, 0.0)
			_knock_outside(),
		"enabled": func() -> bool: return live.call() and stage < 3,
		"on_interact": _use_front})
	var cd := _spot("ChambreDoor", Vector3((float(L.DOOR_CHAMBRE.x0) + float(L.DOOR_CHAMBRE.x1)) * 0.5, 1.05, float(L.HALL.z0) + 0.03), Vector3(0.8, 2.0, 0.14))
	_entries.append({"id": "etage.chambre", "node": cd, "max_distance": 1.8, "prompt": "Ouvrir la porte",
		"enabled": func() -> bool: return live.call() and stage < 2 and not _busy,
		"on_interact": _use_chambre})
	var kn := _spot("Key", (fx.key_pos as Vector3) + Vector3(0, 0.03, 0), Vector3(0.16, 0.12, 0.2))
	_entries.append({"id": "etage.key", "node": kn, "max_distance": 1.9, "prompt": "Prendre la clé",
		"enabled": func() -> bool: return live.call() and stage < 2,
		"on_interact": _take_key})
	var ln := _spot("Letter", (fx.letter as Vector3) + Vector3(0, 0.03, 0), Vector3(0.24, 0.1, 0.2))
	_entries.append({"id": "etage.letter", "node": ln, "max_distance": 1.9, "prompt": "Lire la lettre", "enabled": live,
		"on_interact": func() -> void: await _read("et_note_letter", NOTES.letter, ln)})
	var bn := _spot("BedNote", (fx.bed_note as Vector3) + Vector3(0, 0.03, 0), Vector3(0.2, 0.1, 0.24))
	_entries.append({"id": "etage.bed_note", "node": bn, "max_distance": 1.9, "prompt": "Lire la page", "enabled": live,
		"on_interact": func() -> void: await _read("et_note_bed", NOTES.bed, bn)})

func _register_or_wait() -> void:
	if _try_register():
		return
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

func interaction_entries() -> Array:
	return _entries

# ====================================================================== small helpers

func in_area(pos: Vector3) -> bool:
	return active and L.contains(pos)

func surface_at(pos: Vector3) -> String:
	return L.surface_at(pos)

func _audio() -> Node:
	return get_node_or_null("/root/Audio")

func _sfx(sound: String, pos: Vector3, db := 0.0, pitch := 1.0, extra := {}) -> Variant:
	var a := _audio()
	if a == null or not a.has_method("play") or (a.has_method("has_sound") and not a.call("has_sound", sound)):
		return null
	var o := {"position": pos, "volume_db": db, "pitch": pitch}
	o.merge(extra, true)
	return a.call("play", sound, o)

func _loop(sound: String, opts: Dictionary) -> Variant:
	var a := _audio()
	if a == null or not a.has_method("loop") or (a.has_method("has_sound") and not a.call("has_sound", sound)):
		return null
	return a.call("loop", sound, opts)

func _stop(h: Variant, fade := 0.3) -> void:
	if h is Object and is_instance_valid(h) and (h as Object).has_method("stop"):
		h.stop(fade)

func _vol(h: Variant, db: float) -> void:
	if h is Object and is_instance_valid(h) and (h as Object).has_method("set_volume_db"):
		h.set_volume_db(db)

func _say(text: String, seconds := 3.0) -> void:
	var ui = Game.ui
	if ui != null and is_instance_valid(ui) and ui.has_method("subtitle"):
		ui.call("subtitle", text, seconds, {})

func _objective(text: String) -> void:
	var ui = Game.ui
	if ui != null and is_instance_valid(ui) and ui.has_method("set_objective"):
		ui.call("set_objective", text)

func _kick(v: float) -> void:
	var d = (Game.main as Node).get_node_or_null("FearDirector") if Game.main != null and is_instance_valid(Game.main) else null
	if d != null and is_instance_valid(d) and d.has_method("kick"):
		d.call("kick", v)
	fear = maxf(fear, clampf(v, 0.0, 1.0))

func _wait(s: float) -> bool:
	var q := _seq
	await get_tree().create_timer(s, false).timeout
	return q == _seq and active          # false: the level was reset meanwhile, the caller stops

func _read(id: String, note: Dictionary, node: Node3D) -> void:
	var pz = Game.puzzles
	if pz != null and is_instance_valid(pz) and pz.has_method("_read_note"):
		await pz.call("_read_note", id, note, node, Callable())
		return
	var ui = Game.ui
	if ui != null and is_instance_valid(ui) and ui.has_method("show_note"):
		var shown := {"id": id, "title": str(note.title), "text": str(note.text), "style": str(note.style)}
		await Game.modal(func() -> void: await ui.show_note(shown))

func _player() -> Node3D:
	var p = Game.player
	return p as Node3D if p != null and is_instance_valid(p) and p is Node3D else null

# ====================================================================== start / reset

## The loading rehearsal shows the level to the renderer (and hides it again).
func prewarm(on: bool) -> void:
	if not active:
		visible = on

func begin() -> void:
	if not built:
		return
	active = true
	visible = true
	for n in [Game.world, Game.garderie]:
		if n is Node3D and is_instance_valid(n):
			(n as Node3D).visible = false
	_door_tried = false
	_reset_level()
	var p := _player()
	if p != null:
		p.call("teleport", L.START, L.START_YAW, 0.0)
		if p.has_method("give_flashlight"):
			p.call("give_flashlight")
	_objective("Trouve la sortie.")
	_recapture(0.3)
	_intro()

## The reflection probes hold a capture of the rooms as they were lit: taken again when the lights change.
func _recapture(delay: float) -> void:
	if not is_inside_tree():
		return
	await get_tree().create_timer(delay, false).timeout
	for rp in ctx.room_fx.get("probes", []):
		if rp is ReflectionProbe:
			(rp as ReflectionProbe).update_mode = ReflectionProbe.UPDATE_ONCE

func _intro() -> void:
	if not await _wait(1.4):
		return
	_sfx("door_close", Vector3(float(L.HALL.x0), 1.0, 0.0), 2.0, 0.85)
	_kick(0.35)
	if not await _wait(1.8):
		return
	_say("Le rez-de-chaussée… La porte d’entrée est au bout du couloir.", 4.0)

func _reset_level() -> void:
	_seq += 1
	stage = 1 if _door_tried else 0
	fear = 0.0
	_t = 0.0
	_rage = 0.0
	_catching = false
	_busy = false
	_chambre_done = false
	_chime_done = false
	_knock_done = false
	_tap_done = false
	_closet_t = -1.0
	_creaks.clear()
	_creak_t = 5.0
	_hum_pause = 0.0
	for f in _figs:
		f.at_alt = false
		f.unseen = 0.0
		(f.node as Node3D).position = f.home
		(f.node as Node3D).rotation.y = float(f.yaw0)
	for w in _walkers:
		w.awake = false
		w.revealed = false
		w.unseen = 0.0
		w.pos = w.home
		(w.node as Node3D).position = w.home
		(w.node as Node3D).rotation.y = 0.4
	for id in _doors:
		var d: Dictionary = _doors[id]
		d.a = 0.0
		d.goal = 0.0
		(d.node as Node3D).rotation.y = float(d.closed)
		_door_solid(id, true)
	if _key != null:
		_key.visible = true
	for s in ctx.room_fx.get("sconces", []):
		s.alive = true
		(s.light as Light3D).visible = true
		(s.light as Light3D).light_energy = float(s.base)
		(s.emit as StandardMaterial3D).emission_energy_multiplier = 3.0
	_rock_on = false
	_recapture(0.3)
	_stop_sounds()
	_start_ambience()
	_objective("Trouve la clé de la porte d’entrée." if _door_tried else "Trouve la sortie.")

func _start_ambience() -> void:
	_theme = _loop("etage_theme", {"volume_db": -4.0})
	if _theme == null:
		_theme = _loop("ambience_drone", {"volume_db": -6.0})
	_tick = _loop("clock_tick", {"position": (L.CLOCK as Vector3) + Vector3(0, 1.8, 0.1), "volume_db": 6.0})
	for w in [Vector3(58.85, 1.6, -7.7), Vector3(63.15, 1.6, -7.7), Vector3(64.5, 1.6, 0.75)]:
		_winds.append(_loop("wind_outside", {"position": w, "volume_db": -2.0}))
	_hum_start()

func _hum_start() -> void:
	if stage >= 2 or _hum != null:
		return
	_hum = _loop("lullaby_hum", {"position": L.HUM, "volume_db": -7.0, "filter_hz": 1100.0})

func _hum_stop(pause: float) -> void:
	_stop(_hum, 0.12)
	_hum = null
	_hum_pause = maxf(_hum_pause, pause)

func _stop_sounds() -> void:
	for h in [_theme, _layer, _tick, _hum]:
		_stop(h, 0.3)
	for h in _winds:
		_stop(h, 0.3)
	_theme = null
	_layer = null
	_tick = null
	_hum = null
	_winds.clear()

## After being caught (Game calls it after the player's own reset): back at the top of the stairs, everything as
## it was — the key on the mantel, the figures under their sheets, the humming behind the door.
func reset_after_caught() -> void:
	if not active:
		return
	_reset_level()
	var p := _player()
	if p != null:
		p.call("teleport", L.START, L.START_YAW, 0.0)

func _exit_tree() -> void:
	_stop_sounds()

# ====================================================================== what the player does

func _use_front() -> void:
	var at := Vector3(float(L.HALL.x1), 1.0, 0.0)
	if stage < 2:
		_sfx("door_locked", at, 0.0)
		if not _door_tried:
			_door_tried = true
			stage = 1
			_objective("Trouve la clé de la porte d’entrée.")
			_say("Verrouillée. Il faut la clé.", 3.0)
		return
	if stage != 2:
		return
	stage = 3
	for w in _walkers:
		w.awake = false
	_sfx("unlock", at, 2.0)
	_door_solid("front", false)
	_doors.front.goal = 1.0
	_doors.front.speed = 1.1
	_sfx("win_door", at, 0.0)
	_stop(_layer, 1.2)
	_layer = null
	fear = 0.0
	_say("Dehors.", 2.5)
	if not await _wait(1.6):
		return
	_stop_sounds()
	active = false
	Game.on_win()

## The first time the key turns in the lock, something knocks on the other side of the front door.
func _knock_outside() -> void:
	if _knock_done or stage != 2:
		return
	_knock_done = true
	if await _wait(1.1) and stage == 2:
		_sfx("knock_wall", Vector3(float(L.HALL.x1) + 0.3, 1.3, 0.0), 5.0, 0.9)
		_kick(0.9)

## Before the key: the door gives a hand's width, then is pulled shut from inside.
func _use_chambre() -> void:
	var at := Vector3((float(L.DOOR_CHAMBRE.x0) + float(L.DOOR_CHAMBRE.x1)) * 0.5, 1.0, float(L.HALL.z0) - 0.1)
	if _chambre_done:
		_sfx("door_locked", at, 0.0)
		_say("Fermée de l’intérieur.", 2.5)
		return
	_busy = true
	_chambre_done = true
	_sfx("door_creak_open", at, 0.0, 0.9)
	_doors.chambre.goal = 0.17
	_doors.chambre.speed = 0.35
	_rock_on = true
	_sfx("rocking_chair", ctx.room_fx.rocker_pos, -2.0)
	if not await _wait(1.5):
		return
	_doors.chambre.goal = 0.0
	_doors.chambre.speed = 9.0
	_sfx("door_close", at, 5.0, 0.9)
	_hum_stop(11.0)
	_rock_on = false
	_kick(0.9)
	var p := _player()
	if p != null and p.has_method("flinch"):
		p.call("flinch", 0.9)
	Events.noise.emit(at, 0.5, "door")
	if not await _wait(1.6):
		return
	_say("(Quelqu’un tient la porte.)", 3.0)
	_busy = false

func _take_key() -> void:
	if stage >= 2:
		return
	stage = 2
	if _key != null:
		_key.visible = false
	_sfx("key_pickup", ctx.room_fx.key_pos, 0.0)
	_objective("Sors par la porte d’entrée.")
	_awaken()

## What the house does once the key has left the mantel.
func _awaken() -> void:
	_hum_stop(100000.0)
	if not await _wait(0.7):
		return
	_stop(_tick, 0.0)                      # the clock stops
	_tick = null
	if not await _wait(0.9):
		return
	var sc: Array = ctx.room_fx.get("sconces", [])
	for i in range(sc.size() - 1, -1, -1):
		var s: Dictionary = sc[i]
		s.alive = false
		(s.light as Light3D).visible = false
		(s.emit as StandardMaterial3D).emission_energy_multiplier = 0.0
		_sfx("light_pop", (s.light as Node3D).global_position, -4.0, 1.0 + 0.08 * i)
		if not await _wait(0.42):
			return
	# her door stands open now (nobody saw it move), the bed is empty
	_doors.chambre.a = 1.0
	_doors.chambre.goal = 1.0
	(_doors.chambre.node as Node3D).rotation.y = float(_doors.chambre.open)
	_door_solid("chambre", false)
	_recapture(0.2)
	_layer = _loop("dread_layer", {"volume_db": -40.0})
	if not await _wait(1.0):
		return
	# the walker: two metres behind the player's back, wherever that is free
	var w: Dictionary = _walkers[0]
	var cam := Game.camera
	var p := _player()
	if cam != null and p != null:
		var back := cam.global_transform.basis.z
		back = Vector3(back.x, 0.0, back.z).normalized()
		for d in [2.3, 1.9, 2.8, 3.4]:
			var q: Vector3 = p.global_position + back * float(d)
			q.y = 0.0
			if L.room_of(q) == L.room_of(p.global_position) and L.in_box(L.SALON if L.room_of(q) == "salon" else L.HALL, q, -0.45) and not _blocked(q, w):
				w.pos = q
				break
	(w.node as Node3D).position = w.pos
	_face(w, p.global_position if p != null else w.pos + Vector3.BACK)
	w.awake = true
	w.unseen = 0.0
	_closet_t = 5.0

# ====================================================================== seeing

func _ray_clear(a: Vector3, b: Vector3, exclude: Array) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, LAYER_WORLD | LAYER_SIGHT, exclude)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

## True while any part of the figure standing at `at` (height h) is on screen and not hidden by something.
func _seen(at: Vector3, h: float, body: StaticBody3D) -> bool:
	var cam := Game.camera
	if cam == null or not is_instance_valid(cam) or not cam.is_inside_tree():
		return false
	var cp := cam.global_position
	if cp.distance_to(at) > 28.0:
		return false
	var right := cam.global_transform.basis.x * 0.22
	var ex := [body.get_rid()]
	for s in [Vector3(0, h - 0.12, 0), Vector3(0, h * 0.55, 0), Vector3(0, 0.22, 0), right + Vector3(0, h * 0.72, 0), -right + Vector3(0, h * 0.72, 0)]:
		var q: Vector3 = at + s
		if cam.is_position_in_frustum(q) and _ray_clear(cp, q, ex):
			return true
	return false

# ====================================================================== the figures

func _face(f: Dictionary, target: Vector3) -> void:
	var n: Node3D = f.node
	var d := target - n.position
	if Vector2(d.x, d.z).length() > 0.05:
		n.rotation.y = atan2(d.x, d.z)

func _blocked(p: Vector3, me: Dictionary) -> bool:
	var v := Vector2(p.x, p.z)
	for r in _obstacles:
		if (r as Rect2).has_point(v):
			return true
	for f in _figs:
		if Vector2(f.node.position.x - p.x, f.node.position.z - p.z).length() < 0.62:
			return true
	for w in _walkers:
		if not is_same(w, me) and Vector2(w.pos.x - p.x, w.pos.z - p.z).length() < 0.62:
			return true
	return false

const DOORWAYS := {"salon": [60.7, -1.5, -0.35], "chambre": [55.04, -1.5, -0.35], "closet": [57.4, 1.35, 0.35]}

## Next point to walk to, from one room to another through the doorways (rooms are convex: inside one, straight).
func _route(from: Vector3, to: Vector3) -> Vector3:
	var ra := L.room_of(from)
	var rb := L.room_of(to)
	if ra == rb:
		return to
	if ra != "hall":
		var d: Array = DOORWAYS[ra]
		var inside := Vector3(float(d[0]), 0.0, float(d[1]))
		var lined := absf(from.x - float(d[0])) < 0.22
		return Vector3(float(d[0]), 0.0, float(d[2])) if lined and from.distance_to(inside) < 0.9 or lined and signf(from.z - float(d[1])) == signf(float(d[2]) - float(d[1])) else inside
	var e: Array = DOORWAYS[rb]
	if absf(from.x - float(e[0])) < 0.22:
		return Vector3(float(e[0]), 0.0, float(e[1]))
	return Vector3(float(e[0]), 0.0, float(e[2]))

func _tick_walker(w: Dictionary, dt: float, pp: Vector3) -> void:
	if not w.awake or _catching:
		return
	var n: Node3D = w.node
	if _seen(w.pos, float(w.h), w.body):
		w.unseen = 0.0
		if not w.revealed:
			w.revealed = true
			_sfx("stinger", w.pos + Vector3(0, 1.5, 0), -7.0)
			_kick(1.0)
			var p := _player()
			if p != null and p.has_method("flashlight_stutter"):
				p.call("flashlight_stutter", 0.6)
			_teach()
		return
	w.unseen += dt
	if w.unseen < 0.22:
		return                                         # a glance away is not enough
	var flat := Vector3(pp.x - w.pos.x, 0.0, pp.z - w.pos.z)
	var dist := flat.length()
	if dist < CATCH_DIST and L.room_of(pp) == L.room_of(w.pos):
		_catch(w)
		return
	var speed := (WALK_SPEED + 0.8 * clampf((dist - 6.0) / 6.0, 0.0, 1.0) + _rage) * float(w.slow)
	var goal := _route(w.pos, pp)
	var dir := Vector3(goal.x - w.pos.x, 0.0, goal.z - w.pos.z)
	if dir.length() < 0.02:
		return
	var step := dir.normalized() * minf(speed * dt, dir.length())
	var np: Vector3 = w.pos + step
	if _blocked(np, w):
		var ax: Vector3 = w.pos + Vector3(step.x, 0, 0)
		var az: Vector3 = w.pos + Vector3(0, 0, step.z)
		if absf(step.x) > 1e-5 and not _blocked(ax, w):
			np = w.pos + Vector3(signf(step.x) * step.length(), 0, 0)
		elif absf(step.z) > 1e-5 and not _blocked(az, w):
			np = w.pos + Vector3(0, 0, signf(step.z) * step.length())
		else:
			# wedged: sidestep around the obstacle
			w.stuck += dt
			var side := Vector3(-dir.z, 0, dir.x).normalized() * (1.0 if int(w.stuck * 0.7) % 2 == 0 else -1.0)
			np = w.pos + side * step.length()
			if _blocked(np, w):
				return
	w.moved += (np - w.pos).length()
	w.rustle += (np - w.pos).length()
	w.pos = np
	n.position = np
	_face(w, pp)
	if w.moved > 0.72:
		w.moved = 0.0
		var close := clampf(1.0 - dist / 9.0, 0.0, 1.0)
		_sfx(["stair_creak", "house_creak", "floor_creak_long"][randi() % 3], np + Vector3(0, 0.05, 0), lerpf(-5.0, 4.0, close), randf_range(0.82, 1.0))
	if w.rustle > 2.4:
		w.rustle = 0.0
		_sfx("cloth_move", np + Vector3(0, 1.0, 0), -3.0, 0.85)
		if dist < 3.2:
			_sfx("entity_breath", np + Vector3(0, float(w.h) - 0.2, 0), -2.0, 0.9)

func _teach() -> void:
	if _hint_done:
		return
	_hint_done = true
	if await _wait(2.2):
		_say("(Elle ne bouge pas tant que je la regarde.)", 4.5)

## The ones that never walk: unseen, they turn to face the player; after the key, each is found once closer.
## They only do it while the player is in the salon or at its doorway, and not more than once every second and a
## half each: every turn of a shadow caster makes the moonlight re-render its shadow map.
func _tick_figures(dt: float, pp: Vector3) -> void:
	var near: bool = L.room_of(pp) == "salon" or (absf(pp.x - 60.7) < 1.6 and pp.z < 0.3)
	for f in _figs:
		var n: Node3D = f.node
		f.cool = maxf(float(f.get("cool", 0.0)) - dt, 0.0)
		if not near and not (stage == 2 and not f.at_alt):
			continue
		if _seen(n.position, float(f.h), f.body):
			f.unseen = 0.0
			continue
		f.unseen += dt
		if f.unseen < 0.8 or float(f.cool) > 0.0:
			continue
		var moved := false
		if stage == 2 and not f.at_alt and f.unseen > 1.6:
			f.at_alt = true
			n.position = f.alt
			moved = true
			_sfx("house_creak", (f.alt as Vector3) + Vector3(0, 0.05, 0), -9.0, 0.9)
		var d := pp - n.position
		var want := atan2(d.x, d.z)
		if near and absf(angle_difference(n.rotation.y, want)) > 0.45:
			n.rotation.y = want
			moved = true
		if moved:
			f.cool = 1.5

func _catch(w: Dictionary) -> void:
	if _catching:
		return
	_catching = true
	var p := _player()
	var cam := Game.camera
	if p != null:
		p.set("enabled", false)
	if cam != null:
		var f := -cam.global_transform.basis.z
		f = Vector3(f.x, 0.0, f.z).normalized()
		var at := cam.global_position + f * 0.5
		at.y = cam.global_position.y - float(w.h) + 0.12
		w.pos = at
		(w.node as Node3D).position = at
		(w.node as Node3D).rotation.y = atan2(-f.x, -f.z)
	_sfx("jumpscare", w.pos + Vector3(0, 1.6, 0), 0.0)
	_sfx("entity_croak", w.pos + Vector3(0, 1.6, 0), 2.0, 0.8)
	_kick(1.0)
	if p != null and p.has_method("flinch"):
		p.call("flinch", 1.2)
	var q := _seq
	await get_tree().create_timer(0.85, false).timeout
	if p != null and is_instance_valid(p):
		p.set("enabled", true)
	if q != _seq:
		return
	_stop(_layer, 0.2)
	_layer = null
	Game.on_caught()

# ====================================================================== doors, boards, events

func _door_solid(id: String, on: bool) -> void:
	var d: Dictionary = _doors.get(id, {})
	if d.is_empty():
		return
	for c in (d.body as Node).get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).set_deferred("disabled", not on)

func _tick_doors(dt: float) -> void:
	for id in _doors:
		var d: Dictionary = _doors[id]
		if is_equal_approx(float(d.a), float(d.goal)):
			continue
		d.a = move_toward(float(d.a), float(d.goal), dt * float(d.speed))
		(d.node as Node3D).rotation.y = lerpf(float(d.closed), float(d.open), float(d.a))
	if _rocker != null:
		if _rock_on:
			_rock += dt * 2.4
			_rocker.rotation.x = sin(_rock) * 0.09
		elif absf(_rocker.rotation.x) > 0.001:
			_rocker.rotation.x = move_toward(_rocker.rotation.x, 0.0, dt * 0.2)

func _tick_boards(pp: Vector3) -> void:
	var p := _player()
	var quiet: bool = p == null or p.get("crouched") == true or p.get("moving") != true
	var cz: Array = L.CREAKY
	for i in cz.size():
		var z: Array = cz[i]
		var inside := pp.x >= float(z[0]) and pp.x <= float(z[2]) and pp.z >= float(z[1]) and pp.z <= float(z[3])
		if inside and not _boards_in[i] and not quiet:
			_board_creak(pp)
		_boards_in[i] = inside

func _board_creak(pp: Vector3) -> void:
	_sfx(["stair_creak", "floor_creak_long"][randi() % 2], pp + Vector3(0, 0.05, 0), 5.0, randf_range(0.8, 0.95))
	Events.noise.emit(pp, 0.4, "floorboard")
	_kick(0.3)
	_creaks.append(_t)
	while not _creaks.is_empty() and _t - float(_creaks[0]) > 25.0:
		_creaks.pop_front()
	if stage < 2:
		# she stops humming and listens
		_hum_stop(randf_range(6.0, 9.0))
		if _creaks.size() >= 3 and not _chambre_done:
			_creaks.clear()
			_knob()
	else:
		_rage = 0.7                                    # it heard where the player is

func _knob() -> void:
	if not await _wait(1.4):
		return
	var at := Vector3((float(L.DOOR_CHAMBRE.x0) + float(L.DOOR_CHAMBRE.x1)) * 0.5, 1.0, float(L.HALL.z0) - 0.1)
	_sfx("door_locked", at, 3.0, 0.9)
	_hum_stop(14.0)
	_kick(0.6)

func _tick_events(dt: float, pp: Vector3) -> void:
	# the humming comes back when the house has been quiet long enough
	if _hum_pause > 0.0:
		_hum_pause -= dt
		if _hum_pause <= 0.0:
			_hum_start()
	# wood settling somewhere around, sometimes overhead
	_creak_t -= dt
	if _creak_t <= 0.0:
		_creak_t = randf_range(5.0, 12.0) if stage < 2 else randf_range(3.0, 7.0)
		var a := randf() * TAU
		var r := randf_range(4.0, 8.0)
		var q := Vector3(clampf(pp.x + cos(a) * r, 52.0, 68.0), [0.1, 1.4, 3.1][randi() % 3], clampf(pp.z + sin(a) * r, -7.8, 1.9))
		_sfx("house_creak", q, randf_range(-5.0, 0.0), randf_range(0.85, 1.1))
	# footsteps cross the ceiling once, while the key is being looked for
	if stage == 1 and not _steps_done and L.room_of(pp) == "salon":
		_steps_done = true
		_sfx("ceiling_steps", Vector3(pp.x + 2.0, 3.2, pp.z - 1.0), 2.0)
		_hum_stop(9.0)
	# the piano, once, when the player walks past it
	if not _piano_done and Vector2(pp.x - L.PIANO.x, pp.z - L.PIANO.z).length() < 1.5:
		_piano_done = true
		_sfx("piano_sting", (L.PIANO as Vector3) + Vector3(0.3, 0.9, 0.0), 3.0)
		_kick(0.7)
		_hum_stop(8.0)
	if stage == 2:
		# the clock, stopped since the key was taken, strikes once as the player passes it
		if not _chime_done and L.room_of(pp) == "hall" and absf(pp.x - L.CLOCK.x) < 1.1:
			_chime_done = true
			_sfx("clock_chime", (L.CLOCK as Vector3) + Vector3(0, 1.8, 0.1), 5.0)
			_kick(0.8)
		# fingers on the hallway window as the player goes by it
		if not _tap_done and L.room_of(pp) == "hall" and pp.x > float(L.WIN_HALL[0]) - 0.2 and pp.x < float(L.WIN_HALL[1]) + 0.4:
			_tap_done = true
			_sfx("window_tap", Vector3((float(L.WIN_HALL[0]) + float(L.WIN_HALL[1])) * 0.5, 1.5, float(L.HALL.z1) + 0.1), 6.0)
			_kick(0.6)
		# the closet door opens by itself behind the player; what stands in it starts walking a little later
		if _closet_t > 0.0 and L.room_of(pp) == "hall":
			_closet_t -= dt
			if _closet_t <= 0.0:
				_closet_t = -1.0
				_closet_opens()
	_rage = move_toward(_rage, 0.0, dt * 0.28)

func _closet_opens() -> void:
	var at := Vector3((float(L.DOOR_CLOSET.x0) + float(L.DOOR_CLOSET.x1)) * 0.5, 1.0, float(L.HALL.z1))
	_sfx("door_creak_open", at, 3.0, 0.8)
	_doors.closet.goal = 1.0
	_doors.closet.speed = 0.4
	_door_solid("closet", false)
	if not await _wait(4.0):
		return
	if _walkers.size() > 1 and stage == 2:
		_walkers[1].awake = true
		_walkers[1].revealed = true

func _tick_fear(dt: float, pp: Vector3) -> void:
	var near := 99.0
	for w in _walkers:
		if w.awake:
			near = minf(near, Vector2(w.pos.x - pp.x, w.pos.z - pp.z).length())
	var target := 0.12 if stage < 2 else clampf(1.15 - near / 7.5, 0.3, 1.0)
	fear = move_toward(fear, target, dt * (0.5 if target > fear else 0.12))
	if stage == 2:
		var k := clampf(1.0 - (near - 1.2) / 9.0, 0.0, 1.0)
		_vol(_layer, lerpf(-30.0, 2.0, pow(k, 0.7)))
	var p := _player()
	if p != null:
		p.set("stress_bias", fear * 0.85)

func _process(dt: float) -> void:
	if not active or not built or Game.state != "playing":
		return
	var p := _player()
	if p == null:
		return
	_t += dt
	var pp := p.global_position
	_tick_doors(dt)
	_tick_boards(pp)
	_tick_events(dt, pp)
	_tick_figures(dt, pp)
	for w in _walkers:
		_tick_walker(w, dt, pp)
	_tick_fear(dt, pp)
