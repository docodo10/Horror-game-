## Dehors — chapter 3 (geometry: dehors_build.gd + dehors_props.gd, coordinates: dehors_layout.gd, her:
## dehors_her.gd). Started from the TV menu (Game.mode "dehors"): everything else is hidden, the player stands on
## the porch of the old house, at night, in fog. The way out is the garden gate at the far end of the driveway.
##
## The chain: the gate is chained -> bolt cutters are needed -> they are in the root cellar -> its doors are
## padlocked -> the key hangs in the tool shed -> the shed is locked -> its key lies under the blue pot in the
## greenhouse. Then back: the shed, the cellar, the gate. Four things to read tell the rest of the story.
##
## She comes out of the house once the player has gone far enough (or rattled the gate). She sees nothing out here;
## she listens (dehors_her.gd). What makes noise: running anywhere, walking upright on gravel or dead leaves, on
## the porch boards, doors, the pots lifted in the greenhouse, the chain being cut. What does not: the grass,
## crouching, standing still. What helps: the wind chimes on the porch, the horn of the dead car, the radio in the
## shed, pebbles to throw (right click / G), and three places to hide (the playhouse, the kennel, the boot of the
## car) where she cannot reach.
##
## API (same shape as chapter 2): build() (await), begin(), active, stage, fear (0..1 for Game), in_area(pos),
## surface_at(pos), reset_after_caught(), prewarm(on) + prewarm_view(cam) (loading rehearsal),
## teleport_player(pos, yaw), stats, her.
extends Node3D

const L := preload("res://scripts/dehors/dehors_layout.gd")
const Build := preload("res://scripts/dehors/dehors_build.gd")
const Ctx := preload("res://scripts/garderie/garderie_ctx.gd")
const Mats := preload("res://scripts/dehors/dehors_mats.gd")
const Her := preload("res://scripts/dehors/dehors_her.gd")
const Acoustics := preload("res://scripts/audio/acoustics.gd")
const SKY_SHADER := preload("res://shaders/dehors_sky.gdshader")

const FOG_COLOR := Color(0.1, 0.13, 0.185)        # the night fog; the sky's horizon takes it too
const FOG_DENSITY := 0.045
const LAYER_WORLD := 1
const LAYER_INTERACT := 2
const LAYER_SIGHT := 16
## How loud things are (Events.noise loudness; she hears a noise of loudness l from 60 * l metres)
const NOISE := {"door": 0.5, "trap": 0.6, "pot": 0.2, "hide": 0.12, "chimes": 0.55, "horn": 1.0, "radio": 0.6, "stone_hard": 0.75,
	"stone_soft": 0.4, "chain": 0.9, "gate": 0.8, "swing": 0.3, "glass": 0.5, "slam": 1.0, "pant": 0.06}
const MOVING := ["dh_front_door", "dh_chimes", "dh_swing_0", "dh_swing_1", "dh_trap_0", "dh_trap_1", "dh_trap_lock", "dh_gate_0", "dh_gate_1",
	"dh_chain", "dh_shed_door", "dh_pot_0", "dh_pot_1", "dh_pot_2", "dh_pot_3", "dh_key_shed", "dh_key_cave", "dh_cutters", "dh_pebble",
	"dh_hands", "dh_radio_led", "dh_battery_0", "dh_battery_1"]

const NOTES := {
	"porch": {
		"title": "Lettre laissée sur le banc", "style": "note",
		"text": "Madame,\n\nle portail est enchaîné, comme vous l’avez demandé. Personne n’entre. Personne ne sort.\n\n"
			+ "J’ai remis votre coupe-boulon à sa place, au caveau. La clé du caveau est au clou, dans la remise.\n\n"
			+ "Je ne reviendrai pas. La nuit, de ma fenêtre, je vois votre lanterne faire le tour du jardin. Tout le village sait que vous n’y voyez plus, dehors.\n\n"
			+ "Alors pour qui, la lumière ?\n\nR. Vasseur",
	},
	"cabane": {
		"title": "Dessin punaisé à la cabane", "style": "child",
		"text": "LA CABANE C’EST CHEZ NOUS.\nELLE RENTRE PAS, ELLE EST TROP GRANDE.\n\nDEHORS ELLE VOIT RIEN.\nELLE ÉCOUTE.\n\n"
			+ "ON MARCHE DANS L’HERBE.\nPAS SUR LES CAILLOUX.\nPAS SUR LES FEUILLES.\n\nQUAND LA LANTERNE VIENT\nON BOUGE PLUS.\n\nLéa",
	},
	"car": {
		"title": "Journal laissé dans la voiture", "style": "newspaper",
		"text": "LE COURRIER DU LAC — 2 décembre 1994\n\nLA GARDIENNE DES « PETITS SOLEILS » TOUJOURS INTROUVABLE\n\n"
			+ "Trois semaines après la découverte de Léa et Mathis, les gendarmes ont fouillé une dernière fois la maison et son jardin. En vain.\n\n"
			+ "« Elle vivait volets clos depuis des années. Elle disait que le jour lui brûlait les yeux », rapporte un voisin. "
			+ "Le même affirme voir, certaines nuits, une lueur se déplacer derrière la clôture.\n\nLa maison a été placée sous scellés. Le portail est enchaîné.",
	},
	"cave": {
		"title": "Page posée sur la table", "style": "note",
		"text": "14 novembre\nIls sont venus avec leurs lampes. Ils ont emmené mes petits. Je suis descendue ici. Ils ont marché au-dessus de moi tout le jour et n’ont pas soulevé les portes.\n\n"
			+ "30 novembre\nJe ne remonte que la nuit. Mes yeux ne veulent plus de dehors. Tant pis : j’entends l’herbe, j’entends le gravier, j’entends les feuilles.\n\n"
			+ "J’ai descendu sept petites chaises. Je prends la lanterne et je fais le tour.\nCe n’est pas pour moi, la lumière.\nC’est pour qu’ils me retrouvent.",
	},
}

var ctx = null
var built := false
var active := false
var stage := 0                    # 0 out of the house, 1 the gate is chained, 2 shed key, 3 cellar key, 4 cellar open, 5 bolt cutters, 6 chain cut, 7 out
var fear := 0.0
var stats := {}
var her: Her = null
var flags := {}
var pebbles := 0
var hide_spots: Array = []

var _entries: Array = []
var _registered_with: Node = null
var _t := 0.0
var _seq := 0                     # bumped at every reset: coroutines of the previous life stop
var _doors := {}                  # id -> {node, axis, closed, open, a, goal, speed}
var _bodies := {}                 # id -> StaticBody3D (gate, trap, shed door)
var _nodes := {}                  # short name -> Node3D (things shown / hidden / moved)
var _pots: Array = []             # {node, home, lifted}
var _swing := [0.0, 0.0]          # amplitude of each swing
var _swing_ph := 0.0
var _catching := false
var _her_out := false
var _emerge_t := -1.0             # seconds before she comes out (< 0: not armed)
var _emerging := false
var _taught := false
var _gravel_said := false
var _look_on := false
var _sky: Sky = null
var _chime_t := 0.0
var _chime_cd := 0.0
var _horn_t := 0.0
var _horn_left := 2
var _radio_on := false
var _radio_t := 0.0
var _radio = null
var _lure_tick := 0.0
var _swing_done := false
var _hands_done := false
var _slam_done := false
var _shut_in := false
var _lantern_out := 0.0
var _scratch_done := ""
var _throw: Dictionary = {}
var _wind = null
var _theme = null
var _layer = null
var _life_t := 12.0
var _pant_t := 0.0
var _cellar_k := 0.0
var _prewarming := false

# ====================================================================== build

func build() -> void:
	var t0 := Time.get_ticks_usec()
	name = "Dehors"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	ctx = Ctx.new()
	ctx.root = self
	ctx.mats = Mats.new()
	Build.build(ctx)
	var opts := {"dh_tufts": {"no_shadow": ["dh_tuft"]}, "dh_glass": {"no_shadow": ["dh_glass"]}, "dh_car_glass": {"no_shadow": ["dh_glass"]},
		"dh_shed_glass": {"no_shadow": ["dh_glass"]}, "dh_lit": {"no_shadow": ["dh_window_lit"]}, "dh_serre_lamp": {"no_shadow": ["dh_tube_cold"]}}
	var tris: int = ctx.commit_all(opts)
	for g in find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).layers = L.L_DH
	for r in MOVING:
		var n: Node3D = ctx.regions.get(r)
		if n != null:
			for g in n.find_children("*", "GeometryInstance3D", true, false):
				(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_setup_nodes()
	her = Her.new()
	add_child(her)
	await her.build(ctx.room_fx.solids)
	her.set_blocked(ctx.room_fx.serre_gap, false)
	her.touched.connect(_on_touched)
	her.noticed.connect(_on_noticed)
	her.arrived.connect(_on_arrived)
	_setup_entries()
	_register_or_wait()
	Events.noise.connect(_on_noise)
	Events.settings_changed.connect(_on_setting)
	_reset_flags()
	_apply_state()
	visible = false
	built = true
	stats = {"build_ms": (Time.get_ticks_usec() - t0) / 1000.0, "triangles": tris,
		"lights": find_children("*", "Light3D", true, false).size(), "mesh_instances": find_children("*", "MeshInstance3D", true, false).size(),
		"missing_textures": ctx.mats.missing, "her_model": her.model != null and her.model.ok}

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

func _box_body(mn: Vector3, mx: Vector3, layer: int) -> StaticBody3D:
	var sh := BoxShape3D.new()
	sh.size = (mx - mn).abs()
	return _body(self, sh, (mn + mx) * 0.5, layer)

func _door(id: String, region: String, hinge: Vector3, axis: String, closed: float, open: float) -> void:
	var n: Node3D = ctx.regions.get(region)
	if n == null:
		return
	n.position = hinge
	_set_rot(n, 0 if axis == "x" else 1, closed)
	_doors[id] = {"node": n, "axis": 0 if axis == "x" else 1, "closed": closed, "open": open, "a": 0.0, "goal": 0.0, "speed": 1.0}

func _set_rot(n: Node3D, axis: int, v: float) -> void:
	var r := Vector3.ZERO
	r[axis] = v
	n.rotation = r

func _place(short: String, region: String, at: Vector3, rot := Vector3.ZERO) -> Node3D:
	var n: Node3D = ctx.regions.get(region)
	if n == null:
		return null
	n.position = at
	n.rotation = rot
	_nodes[short] = n
	return n

func _setup_nodes() -> void:
	var fx: Dictionary = ctx.room_fx
	_door("front", "dh_front_door", fx.front_hinge, "y", float(fx.front_yaw), float(fx.front_yaw) - 1.25)
	_door("shed", "dh_shed_door", fx.shed_hinge, "y", 0.0, -1.75)
	var th: Array = fx.trap_hinges
	_door("trap0", "dh_trap_0", th[0], "x", 0.0, -1.85)
	_door("trap1", "dh_trap_1", th[1], "x", 0.0, 1.85)
	var gh: Array = fx.gate_hinges
	_door("gate0", "dh_gate_0", gh[0], "y", 0.0, 1.3)
	_door("gate1", "dh_gate_1", gh[1], "y", 0.0, -1.3)
	_place("chimes", "dh_chimes", fx.chimes)
	var sp: Array = fx.swing_pivots
	for i in sp.size():
		_place("swing%d" % i, "dh_swing_%d" % i, sp[i])
	_place("trap_lock", "dh_trap_lock", fx.trap_lock)
	_place("chain", "dh_chain", fx.chain_pos)
	_place("key_shed", "dh_key_shed", fx.key_shed, Vector3(0.0, 0.8, 0.0))
	var kc := _place("key_cave", "dh_key_cave", fx.key_cave)
	if kc != null:
		kc.basis = Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, PI * 0.5)       # hanging from its ring, flat against the wall
	_place("cutters", "dh_cutters", fx.cutters_pos, Vector3(0.0, float(fx.cutters_yaw), 0.0))
	_place("pebble", "dh_pebble", Vector3(118.0, 0.03, 6.0))
	_place("hands", "dh_hands", fx.hands)
	_place("battery_0", "dh_battery_0", fx.battery_0, Vector3(0.0, 0.5, 0.0))
	_place("battery_1", "dh_battery_1", fx.battery_1, Vector3(0.0, 2.1, 0.0))
	_nodes["led"] = ctx.regions.get("dh_radio_led")
	_nodes["lit"] = ctx.regions.get("dh_lit")
	var pots: Array = fx.pots
	for i in pots.size():
		var n := _place("pot%d" % i, "dh_pot_%d" % i, pots[i], Vector3(0.0, 1.3 * float(i), 0.0))
		_pots.append({"node": n, "home": pots[i], "lifted": false})
	# colliders of what opens
	var S: Dictionary = L.SHAFT
	_bodies["trap"] = _box_body(Vector3(float(S.x0), 0.08, float(S.z0)), Vector3(float(S.x1), 0.17, float(S.z1)), LAYER_WORLD | LAYER_SIGHT)
	var G: Dictionary = L.GATE
	_bodies["gate"] = _box_body(Vector3(float(G.x) - 0.06, 0.0, float(G.z0)), Vector3(float(G.x) + 0.06, float(G.h), float(G.z1)), LAYER_WORLD)
	var D: Dictionary = L.SHED_DOOR
	var sz: float = L.SHED.z1
	_bodies["shed"] = _box_body(Vector3(float(D.x0), 0.0, sz), Vector3(float(D.x1), float(D.h), sz + 0.1), LAYER_WORLD | LAYER_SIGHT)
	hide_spots = []
	for id in ["cabane", "car", "niche"]:
		var h: Dictionary = fx["hide_" + id]
		hide_spots.append({"id": "dh_" + id, "door": null, "hide_pos": h.hide_pos, "hide_yaw": float(h.hide_yaw), "exit_pos": h.exit_pos, "at": h.door})

func _solid(id: String, on: bool) -> void:
	var b: StaticBody3D = _bodies.get(id)
	if b == null:
		return
	for c in b.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).set_deferred("disabled", not on)

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
	var free := func() -> bool: return active and not _catching and not _hidden()
	# ---- things to read
	var np := _spot("NotePorch", (fx.note_porch as Vector3) + Vector3(0, 0.03, 0), Vector3(0.22, 0.1, 0.26))
	_entries.append({"id": "dehors.note_porch", "node": np, "max_distance": 2.0, "prompt": "Lire la lettre", "enabled": free,
		"on_interact": func() -> void:
			await _read("dh_note_porch", NOTES.porch, np)
			flags.know_chain = true
			flags.know_cutters = true
			flags.know_cave_key = true
			_update_objective()})
	var nc := _spot("NoteCabane", (fx.note_cabane as Vector3) + Vector3(0.03, 0, 0), Vector3(0.1, 0.3, 0.24))
	_entries.append({"id": "dehors.note_cabane", "node": nc, "max_distance": 2.0, "prompt": "Regarder le dessin", "enabled": free,
		"on_interact": func() -> void: await _read("dh_note_cabane", NOTES.cabane, nc)})
	var nv := _spot("NoteCar", fx.note_car, Vector3(0.34, 0.14, 0.26))
	_entries.append({"id": "dehors.note_car", "node": nv, "max_distance": 2.0, "prompt": "Lire le journal", "enabled": free,
		"on_interact": func() -> void: await _read("dh_note_car", NOTES.car, nv)})
	var ne := _spot("NoteCave", (fx.note_cave as Vector3) + Vector3(0, 0.03, 0), Vector3(0.22, 0.1, 0.26))
	_entries.append({"id": "dehors.note_cave", "node": ne, "max_distance": 2.0, "prompt": "Lire la page", "enabled": free,
		"on_interact": func() -> void: await _read("dh_note_cave", NOTES.cave, ne)})
	var tb := _spot("ToolBoard", (fx.toolboard as Vector3) + Vector3(0.75, -0.05, 0.03), Vector3(0.5, 0.9, 0.08))
	_entries.append({"id": "dehors.toolboard", "node": tb, "max_distance": 2.4, "prompt": "Regarder le panneau", "enabled": free,
		"on_interact": func() -> void:
			_say("(La place du coupe-boulon est vide. « Au caveau. »)", 4.0)
			flags.know_cutters = true
			_update_objective()})
	# ---- the house
	var P: Dictionary = L.PORCH
	var fd := _spot("FrontDoor", Vector3(float(L.HOUSE.x1) + 0.02, float(P.y) + 1.05, 0.0), Vector3(0.14, 2.0, 0.9))
	_entries.append({"id": "dehors.front", "node": fd, "max_distance": 1.9, "prompt": "Ouvrir la porte",
		"enabled": func() -> bool: return free.call() and not _her_out and not _emerging,
		"on_interact": func() -> void:
			_sfx("door_locked", fd.global_position, 0.0)
			_noise(fd.global_position, 0.3, "door")
			_say("Non. Pas par là.", 2.5)})
	var ch := _spot("Chimes", (fx.chimes as Vector3) + Vector3(0, -0.3, 0), Vector3(0.3, 0.6, 0.3))
	_entries.append({"id": "dehors.chimes", "node": ch, "max_distance": 2.6, "prompt": "Secouer le carillon",
		"enabled": func() -> bool: return free.call() and _chime_cd <= 0.0, "on_interact": _use_chimes})
	# ---- the gate
	var gt := _spot("Gate", fx.chain_pos, Vector3(0.3, 1.2, 1.2))
	_entries.append({"id": "dehors.gate", "node": gt, "max_distance": 2.0,
		"prompt": func() -> String: return "Pousser le portail" if flags.chain_cut else ("Couper la chaîne" if flags.cutters else "Ouvrir le portail"),
		"hold": func() -> float: return 2.0 if flags.chain_cut else (4.0 if flags.cutters else 0.0),
		"hold_prompt": func() -> String: return "Le portail racle…" if flags.chain_cut else "L’acier mord…",
		"on_hold_start": _gate_hold_start,
		"enabled": func() -> bool: return free.call() and stage < 7,
		"on_interact": _use_gate})
	# ---- the greenhouse: four pots, a key
	for i in _pots.size():
		var pi := i
		var pn := _spot("Pot%d" % i, (_pots[i].home as Vector3) + Vector3(0, 0.12, 0), Vector3(0.26, 0.26, 0.26))
		_entries.append({"id": "dehors.pot_%d" % i, "node": pn, "max_distance": 2.0, "prompt": "Soulever le pot", "hold": 0.45, "hold_prompt": "…",
			"enabled": func() -> bool: return free.call() and not _pots[pi].lifted,
			"on_interact": func() -> void: _lift_pot(pi)})
	var ks := _spot("KeyShed", (fx.key_shed as Vector3) + Vector3(0, 0.03, 0), Vector3(0.14, 0.08, 0.2))
	_entries.append({"id": "dehors.key_shed", "node": ks, "max_distance": 2.0, "prompt": "Prendre la clé",
		"enabled": func() -> bool: return free.call() and not flags.shed_key and _pots[L.POT_KEY].lifted,
		"on_interact": _take_shed_key})
	# ---- the shed
	var sd := _spot("ShedDoor", fx.shed_door_spot, Vector3(0.86, 1.9, 0.12))
	_entries.append({"id": "dehors.shed_door", "node": sd, "max_distance": 2.0,
		"prompt": func() -> String: return "Déverrouiller la remise" if flags.shed_key else "Ouvrir la remise",
		"hold": func() -> float: return 1.2 if flags.shed_key else 0.0, "hold_prompt": "La clé tourne…",
		"on_hold_start": func() -> void: _sfx("lock_wheel", sd.global_position, 0.0),
		"enabled": func() -> bool: return free.call() and not flags.shed_open,
		"on_interact": _use_shed_door})
	var kc := _spot("KeyCave", fx.key_cave, Vector3(0.12, 0.2, 0.14))
	_entries.append({"id": "dehors.key_cave", "node": kc, "max_distance": 2.0, "prompt": "Prendre la clé du caveau",
		"enabled": func() -> bool: return free.call() and not flags.cave_key and flags.shed_open,
		"on_interact": _take_cave_key})
	var rd := _spot("Radio", fx.radio, Vector3(0.34, 0.24, 0.16))
	_entries.append({"id": "dehors.radio", "node": rd, "max_distance": 2.2,
		"prompt": func() -> String: return "Éteindre la radio" if _radio_on else "Allumer la radio",
		"enabled": func() -> bool: return free.call() and flags.shed_open, "on_interact": _use_radio})
	# ---- spare batteries for the torch: one on the shed's bench, one in the greenhouse
	for i in 2:
		var bi := i
		var bn := _spot("Battery%d" % i, (fx["battery_%d" % i] as Vector3) + Vector3(0, 0.02, 0), Vector3(0.12, 0.08, 0.1))
		_entries.append({"id": "dehors.battery_%d" % i, "node": bn, "max_distance": 2.0, "prompt": "Prendre la pile",
			"enabled": func() -> bool: return free.call() and not flags.get("battery_%d" % bi, false) and (bi == 1 or flags.shed_open),
			"on_interact": func() -> void:
				flags["battery_%d" % bi] = true
				(_nodes["battery_%d" % bi] as Node3D).visible = false
				_sfx("pickup", bn.global_position, -2.0)
				var inv = Game.inventory
				if inv != null and is_instance_valid(inv) and inv.has_method("add"):
					inv.call("add", "battery")})
	# ---- the cellar
	var S: Dictionary = L.SHAFT
	var tl := _spot("Trap", Vector3(float(S.x1) - 0.9, 0.2, (float(S.z0) + float(S.z1)) * 0.5), Vector3(1.4, 0.3, 1.0))
	_entries.append({"id": "dehors.trap", "node": tl, "max_distance": 2.3,
		"prompt": func() -> String: return "Soulever les portes" if flags.cave_unlocked else ("Déverrouiller le cadenas" if flags.cave_key else "Ouvrir le caveau"),
		"hold": func() -> float: return 1.8 if flags.cave_unlocked else (1.3 if flags.cave_key else 0.0),
		"hold_prompt": func() -> String: return "Les gonds grincent…" if flags.cave_unlocked else "La clé accroche…",
		"on_hold_start": func() -> void: _sfx("lock_wheel" if not flags.cave_unlocked else "stall_creak", tl.global_position, 0.0),
		"enabled": func() -> bool: return free.call() and not flags.cave_open and not _shut_in,
		"on_interact": _use_trap})
	var ti := _spot("TrapInside", Vector3(float(S.x1) - 0.9, -0.25, (float(S.z0) + float(S.z1)) * 0.5), Vector3(1.6, 0.3, 1.0))
	_entries.append({"id": "dehors.trap_in", "node": ti, "max_distance": 2.4, "prompt": "Pousser les portes", "hold": 1.6, "hold_prompt": "Elles pèsent…",
		"enabled": func() -> bool: return free.call() and _shut_in,
		"on_interact": _push_trap})
	var cu := _spot("Cutters", (fx.cutters_pos as Vector3) + Vector3(-0.15, 0.02, 0.0), Vector3(0.7, 0.1, 0.3))
	_entries.append({"id": "dehors.cutters", "node": cu, "max_distance": 2.0, "prompt": "Prendre le coupe-boulon",
		"enabled": func() -> bool: return free.call() and not flags.cutters, "on_interact": _take_cutters})
	# ---- the car: the horn
	var hn := _spot("Horn", fx.horn, Vector3(0.3, 0.3, 0.3))
	_entries.append({"id": "dehors.horn", "node": hn, "max_distance": 2.0, "prompt": "Klaxonner",
		"enabled": func() -> bool: return free.call() and _horn_t <= 0.0, "on_interact": _use_horn})
	# ---- pebbles
	var heaps: Array = fx.pebbles
	for i in heaps.size():
		var hp := _spot("Pebbles%d" % i, (heaps[i] as Vector3) + Vector3(0, 0.08, 0), Vector3(0.5, 0.2, 0.5))
		_entries.append({"id": "dehors.pebbles_%d" % i, "node": hp, "max_distance": 2.2, "prompt": "Ramasser des cailloux",
			"enabled": func() -> bool: return free.call() and pebbles < 3,
			"on_interact": func() -> void:
				pebbles = 3
				_sfx("pickup", hp.global_position, -2.0)
				_noise(hp.global_position, 0.08, "pebbles")
				_say("(Trois cailloux. %s pour en lancer un.)" % _throw_key(), 4.0)})
	# ---- hiding places
	var names := {"dh_cabane": ["Se cacher dans la cabane", "Sortir de la cabane"], "dh_car": ["Se cacher dans le coffre", "Sortir du coffre"],
		"dh_niche": ["Se glisser dans la niche", "Sortir de la niche"]}
	for sp in hide_spots:
		var spot: Dictionary = sp
		var hn2 := _spot("Hide_" + str(spot.id), spot.at, Vector3(0.5, 0.9, 0.7))
		_entries.append({"id": "dehors.hide_%s" % str(spot.id).trim_prefix("dh_"), "node": hn2, "max_distance": 2.3, "prompt": names[spot.id][0],
			"enabled": func() -> bool: return free.call(),
			"on_interact": func() -> void: await _enter_hide(spot)})
		_entries.append({"id": "dehors.exit_%s" % str(spot.id).trim_prefix("dh_"), "node": hn2, "when_hidden": true, "prompt": names[spot.id][1],
			"enabled": func() -> bool: return live.call() and _hidden_in() == str(spot.id),
			"on_interact": func() -> void: await _exit_hide(spot)})

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
	# the cellar doors are boards only while they are shut
	if flags.get("cave_open", false) and not _shut_in and pos.y > -0.25 and L.in_box(L.SHAFT, pos, 0.1):
		return "concrete"
	return L.surface_at(pos)

## Height of the floor at (x, z) for a body near prev_y (the player's teleport asks Game.world: see teleport_player).
func ground_height_at(x: float, z: float, prev_y := NAN) -> float:
	var p := Vector3(x, 0.0, z)
	var low := not is_nan(prev_y) and prev_y < -0.3
	if low and L.in_box(L.CAVE, p, 0.35):
		return float(L.CAVE.floor)
	if low and L.in_box(L.SHAFT, p):
		var a: float = float(L.SHAFT.x0) + 0.2
		return lerpf(float(L.CAVE.floor), 0.0, clampf((x - a) / (float(L.SHAFT.x1) - a), 0.0, 1.0))
	if L.in_box(L.PORCH, p):
		return float(L.PORCH.y)
	if L.in_box(L.SHED, p, 0.1):
		return 0.05
	return 0.0

## Puts the player at pos (feet), on this level's floors (the porch deck, the cellar under the lawn).
func teleport_player(pos: Vector3, yaw: float, pitch := 0.0) -> void:
	var p := _player()
	if p == null or not p.has_method("teleport"):
		return
	var w: Node = Game.world
	Game.world = self
	p.call("teleport", Vector3(pos.x, ground_height_at(pos.x, pos.z, pos.y), pos.z), yaw, pitch)
	Game.world = w

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

func _noise(pos: Vector3, loud: float, source: String) -> void:
	Events.noise.emit(pos, loud, source)

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

func _hidden() -> bool:
	var p := _player()
	return p != null and p.get("hidden") == true

func _hidden_in() -> String:
	var p := _player()
	if p == null or p.get("hidden") != true:
		return ""
	var s: Variant = p.get("hide_spot")
	return str((s as Dictionary).get("id", "")) if s is Dictionary else ""

func _throw_key() -> String:
	var ui = Game.ui
	if ui != null and is_instance_valid(ui) and ui.get("last_input_gamepad") == true:
		return "X"
	return "Clic droit"

# ====================================================================== the look of the night

func _look_cfg() -> Dictionary:
	if _sky == null:
		var sm := ShaderMaterial.new()
		sm.shader = SKY_SHADER
		sm.set_shader_parameter("noise_tex", ctx.mats.tex("noise_rgba.png"))
		sm.set_shader_parameter("moon_dir", ctx.room_fx.get("moon_dir", Vector3(0.48, 0.62, 0.62)))
		sm.set_shader_parameter("horizon", FOG_COLOR * 1.08)
		_sky = Sky.new()
		_sky.sky_material = sm
		_sky.radiance_size = Sky.RADIANCE_SIZE_64
		_sky.process_mode = Sky.PROCESS_MODE_QUALITY
	return {
		"background_mode": Environment.BG_SKY, "sky": _sky,
		"ambient_light_source": Environment.AMBIENT_SOURCE_COLOR, "ambient_light_color": Color(0.4, 0.5, 0.74), "ambient_light_energy": 0.22,
		"reflected_light_source": Environment.REFLECTION_SOURCE_SKY,
		"fog_enabled": true, "fog_mode": Environment.FOG_MODE_EXPONENTIAL, "fog_light_color": FOG_COLOR, "fog_light_energy": 1.0,
		"fog_density": FOG_DENSITY, "fog_sky_affect": 0.0, "fog_sun_scatter": 0.0, "fog_aerial_perspective": 0.0, "fog_height": -100.0, "fog_height_density": 0.0,
		"volumetric_fog_density": 0.011, "volumetric_fog_albedo": Color(0.8, 0.86, 0.96), "volumetric_fog_length": 42.0,
		"volumetric_fog_anisotropy": 0.55, "volumetric_fog_ambient_inject": 0.0, "volumetric_fog_sky_affect": 0.35,
	}

func _set_look(on: bool) -> void:
	if on == _look_on:
		return
	var rig = Quality.rig()
	if rig == null or not rig.has_method("set_outdoor"):
		return
	_look_on = on
	var none := {}
	rig.call("set_outdoor", _look_cfg() if on else none)

func _on_setting(key: String, value: Variant) -> void:
	if key == "quality" and her != null:
		her.apply_quality.call_deferred(str(value))

# ====================================================================== loading rehearsal

## Shows the level to the renderer (and hides it again), with what only appears later: the light of the hall,
## the hand prints, the radio's lamp, the flying pebble, her.
func prewarm(on: bool) -> void:
	if active:
		return
	# (not shown yet: only while the tour camera stands in the yard, see prewarm_view — the rooms of the other
	# chapters must be rehearsed as they are played, without this level's sky, fog and moon)
	visible = false
	_prewarming = on
	for n in ["hands", "led", "pebble"]:
		if _nodes.get(n) != null:
			(_nodes[n] as Node3D).visible = on
	(ctx.room_fx.hall_light as Light3D).visible = on
	if on:
		her.apply_quality(str(Settings.get_value("quality", "high")))
	else:
		her.prewarm_end()
		_set_look(false)
		_apply_state()

## Called for every view of the rehearsal, before its first frame: the night look only where the yard is. She is not
## in this frame: her skin uses subsurface scattering, which switches the whole frame to another set of pipelines,
## and every view must be drawn once without it (measured: three draw-time compilations on the first frame of play
## otherwise) and once with it (prewarm_her).
func prewarm_view(cam: Camera3D) -> void:
	if active or not _prewarming or cam == null:
		return
	var inside := L.contains(cam.global_position)
	visible = inside
	_set_look(inside)
	her.visible = false

## Second frame of the same view: she stands in front of the camera, lantern lit.
func prewarm_her(cam: Camera3D) -> void:
	if active or not _prewarming or cam == null or not L.contains(cam.global_position):
		return
	var f := -cam.global_transform.basis.z
	f = Vector3(f.x, 0.0, f.z).normalized()
	var at := cam.global_position + f * 3.4 + Vector3(f.z, 0.0, -f.x) * 0.9
	at.y = ground_height_at(at.x, at.z, cam.global_position.y - 1.6)
	her.prewarm_at(at, atan2(-f.x, -f.z))

# ====================================================================== start / reset

func _reset_flags() -> void:
	flags = {"gate_seen": false, "know_chain": false, "know_cutters": false, "know_cave_key": false, "shed_tried": false, "know_pot": false,
		"shed_key": false, "shed_open": false, "cave_tried": false, "cave_key": false, "cave_unlocked": false, "cave_open": false,
		"cutters": false, "chain_cut": false}
	stage = 0
	pebbles = 0
	for p in _pots:
		p.lifted = false
	_swing_done = false
	_hands_done = false
	_slam_done = false
	_shut_in = false
	_taught = false
	_gravel_said = false
	_horn_left = 2

## Puts every node where the flags say it is (after a reset, after the rehearsal).
func _apply_state() -> void:
	for id in _doors:
		var d: Dictionary = _doors[id]
		var open := false
		match id:
			"shed": open = flags.shed_open
			"trap0", "trap1": open = flags.cave_open and not _shut_in
			"gate0", "gate1": open = stage >= 7
		d.a = 1.0 if open else 0.0
		d.goal = d.a
		_set_rot(d.node, int(d.axis), lerpf(float(d.closed), float(d.open), float(d.a)))
	_solid("shed", not flags.shed_open)
	_solid("trap", not (flags.cave_open and not _shut_in))
	_solid("gate", stage < 7)
	if her != null and her.built:
		her.set_blocked(ctx.room_fx.shed_gap, not flags.shed_open)
	var show := {"trap_lock": not flags.cave_unlocked, "chain": not flags.chain_cut, "key_shed": not flags.shed_key, "key_cave": not flags.cave_key,
		"cutters": not flags.cutters, "pebble": false, "battery_0": not flags.get("battery_0", false), "battery_1": not flags.get("battery_1", false), "hands": _hands_done, "led": _radio_on, "lit": not _her_out}
	for n in show:
		if _nodes.get(n) != null:
			(_nodes[n] as Node3D).visible = show[n]
	for i in _pots.size():
		var p: Dictionary = _pots[i]
		(p.node as Node3D).position = (p.home as Vector3) + (Vector3(0.14, 0.0, -0.2) if p.lifted else Vector3.ZERO)
		(p.node as Node3D).rotation.z = 1.45 if p.lifted else 0.0
	(ctx.room_fx.hall_light as Light3D).visible = false
	(ctx.room_fx.window_light as Light3D).visible = not _her_out
	(ctx.room_fx.dust as GPUParticles3D).emitting = false

func begin() -> void:
	if not built:
		return
	active = true
	visible = true
	for n in [Game.world, Game.garderie, Game.etage]:
		if n is Node3D and is_instance_valid(n):
			(n as Node3D).visible = false
	_set_look(true)
	Acoustics.far_fade = Vector2(46.0, 60.0)        # the yard is wider than any room: sounds carry across it
	_reset_flags()
	_her_out = false
	_reset_level()
	teleport_player(L.START, L.START_YAW)
	var p := _player()
	if p != null and p.has_method("give_flashlight"):
		p.call("give_flashlight")
		if p.has_method("add_battery"):
			p.call("add_battery", 100.0)              # a fresh battery for the night; two more lie in the shed and the greenhouse
	_recapture(0.4)
	_intro()

## The chapter from its beginning again, in place (tools; a later "start over").
func restart() -> void:
	if not active:
		return
	_reset_flags()
	_her_out = false
	_reset_level()
	_emerge_t = -1.0
	_t = 0.0
	teleport_player(L.START, L.START_YAW)
	_recapture(0.4)

## The reflection probes hold a capture of their rooms: taken again when the lights change.
func _recapture(delay: float) -> void:
	if not is_inside_tree():
		return
	await get_tree().create_timer(delay, false).timeout
	for rp in ctx.room_fx.get("probes", []):
		if rp is ReflectionProbe:
			(rp as ReflectionProbe).update_mode = ReflectionProbe.UPDATE_ONCE

func _intro() -> void:
	if not await _wait(1.2):
		return
	_sfx("door_close", Vector3(float(L.HOUSE.x1), 1.3, 0.0), 2.0, 0.85)
	_kick(0.3)
	if not await _wait(2.0):
		return
	_say("Dehors. Le portail est au bout de l’allée.", 4.0)

## Back to the porch: she is inside again, the lures are ready; what the player has done stays done.
func _reset_level() -> void:
	_seq += 1
	fear = 0.0
	_catching = false
	_emerging = false
	_throw = {}
	_chime_t = 0.0
	_chime_cd = 0.0
	_horn_t = 0.0
	_horn_left = maxi(_horn_left, 1)
	_radio_on = false
	_lantern_out = 0.0
	_scratch_done = ""
	_shut_in = false
	_swing = [0.0, 0.0]
	if her != null:
		her.despawn()
		her.late = flags.cutters
	# she comes out again a little after the player has left the porch
	var was_out := _her_out
	_her_out = false
	_emerge_t = 14.0 if was_out or stage >= 1 else -1.0
	_apply_state()
	_stop_sounds()
	_start_ambience()
	_update_objective()

func _start_ambience() -> void:
	_wind = _loop("dh_wind", {"volume_db": -2.0})
	_theme = _loop("dh_theme", {"volume_db": -5.0})
	_layer = _loop("dread_layer", {"volume_db": -40.0})
	_life_t = 10.0

func _stop_sounds() -> void:
	for h in [_wind, _theme, _layer, _radio]:
		_stop(h, 0.3)
	_wind = null
	_theme = null
	_layer = null
	_radio = null

## After being caught (Game calls it after the player's own reset).
func reset_after_caught() -> void:
	if not active:
		return
	_reset_level()
	teleport_player(L.START, L.START_YAW)

func _exit_tree() -> void:
	_stop_sounds()
	Acoustics.far_fade = Acoustics.FAR_FADE
	if _look_on:
		_look_on = false
		var rig = Quality.rig()
		if rig != null and is_instance_valid(rig) and rig.has_method("set_outdoor"):
			var none := {}
			rig.call("set_outdoor", none)

func _set_stage(n: int) -> void:
	stage = maxi(stage, n)
	_update_objective()

func _update_objective() -> void:
	var t := "Sors du jardin."
	if flags.chain_cut:
		t = "Pousse le portail."
	elif flags.cutters:
		t = "Coupe la chaîne du portail."
	elif flags.cave_open:
		t = "Descends au caveau. Le coupe-boulon y est."
	elif flags.cave_key:
		t = "Ouvre le caveau."
	elif flags.shed_open:
		t = "La clé du caveau est dans la remise."
	elif flags.shed_key:
		t = "Ouvre la remise."
	elif flags.know_pot:
		t = "La clé de la remise est dans la serre, sous le pot bleu."
	elif flags.know_cave_key or flags.cave_tried:
		t = "La clé du caveau est dans la remise."
	elif flags.know_cutters:
		t = "Le coupe-boulon est au caveau."
	elif flags.gate_seen or flags.know_chain:
		t = "Le portail est enchaîné. Trouve de quoi couper la chaîne."
	_objective(t)

# ====================================================================== what the player does

func _use_gate() -> void:
	var at: Vector3 = ctx.room_fx.chain_pos
	if not flags.cutters:
		_sfx("dh_chain", at, 0.0)
		_noise(at, 0.5, "gate")
		_swing_door_nudge()
		if not flags.gate_seen:
			flags.gate_seen = true
			_set_stage(1)
			_say("Une chaîne. Un cadenas. Il me faut de quoi la couper.", 4.0)
			if not _her_out and _emerge_t < 0.0:
				_emerge_t = 2.5
		return
	if not flags.chain_cut:
		flags.chain_cut = true
		(_nodes.chain as Node3D).visible = false
		_sfx("dh_cut", at, 3.0)
		_noise(at, float(NOISE.chain), "gate")
		_set_stage(6)
		_say("(La chaîne tombe.)", 2.5)
		# her lantern goes out: from here she can only be heard
		if _her_out:
			_lantern_out = 16.0
			her.set_lantern(false)
			_sfx("light_pop", her.head_position(), -6.0, 0.7)
			_kick(0.9)
		return
	if stage >= 7:
		return
	stage = 7
	_sfx("dh_gate", at, 3.0)
	_solid("gate", false)
	for id in ["gate0", "gate1"]:
		_doors[id].goal = 1.0
		_doors[id].speed = 0.55
	if her != null:
		her.despawn()
	_stop(_layer, 1.0)
	_layer = null
	fear = 0.0
	_objective("")
	if not await _wait(1.3):
		return
	_say("Dehors.", 2.5)
	if not await _wait(1.4):
		return
	_stop_sounds()
	active = false
	Game.on_win()

func _gate_hold_start() -> void:
	var at: Vector3 = ctx.room_fx.chain_pos
	if flags.chain_cut:
		_sfx("dh_gate", at, -3.0, 1.1)
		_noise(at, float(NOISE.gate), "gate")
	elif flags.cutters:
		_sfx("dh_chain", at, 2.0)
		_noise(at, 0.6, "gate")

## The gate shivers on its chain when it is tried.
func _swing_door_nudge() -> void:
	for id in ["gate0", "gate1"]:
		var d: Dictionary = _doors[id]
		d.a = 0.03
		d.goal = 0.0
		d.speed = 0.08

func _lift_pot(i: int) -> void:
	var p: Dictionary = _pots[i]
	if p.lifted:
		return
	p.lifted = true
	var n: Node3D = p.node
	_sfx("dh_pot", n.global_position, 0.0, randf_range(0.9, 1.1))
	_noise(n.global_position, float(NOISE.pot), "pot")
	var tw := create_tween()
	tw.tween_property(n, "position", (p.home as Vector3) + Vector3(0.14, 0.06, -0.2), 0.22)
	tw.parallel().tween_property(n, "rotation:z", 1.45, 0.3)
	tw.tween_property(n, "position", (p.home as Vector3) + Vector3(0.14, 0.0, -0.2), 0.1)
	if i != L.POT_KEY:
		_say(["(Rien. De la terre.)", "(Un cloporte. Rien d’autre.)", "(Rien dessous.)"][i % 3], 2.0)

func _take_shed_key() -> void:
	if flags.shed_key:
		return
	flags.shed_key = true
	flags.know_pot = true
	(_nodes.key_shed as Node3D).visible = false
	_sfx("key_pickup", ctx.room_fx.key_shed, 0.0)
	_set_stage(2)
	if not _her_out and _emerge_t < 0.0:
		_emerge_t = 1.0
	_hands()

## The scare of the greenhouse: something slaps the glass in front of the player; two hand prints stay on it.
func _hands() -> void:
	if _hands_done:
		return
	_hands_done = true
	if not await _wait(0.9):
		return
	var at: Vector3 = ctx.room_fx.hands
	(_nodes.hands as Node3D).visible = true
	_sfx("dh_glass_bang", at, 6.0)
	_noise(at, float(NOISE.glass), "glass")
	_kick(1.0)
	var p := _player()
	if p != null and p.has_method("flinch"):
		p.call("flinch", 1.0)
	if p != null and p.has_method("flashlight_stutter"):
		p.call("flashlight_stutter", 0.5)

func _use_shed_door() -> void:
	var at: Vector3 = ctx.room_fx.shed_door_spot
	if not flags.shed_key:
		_sfx("door_locked", at, 0.0)
		_noise(at, 0.3, "door")
		flags.shed_tried = true
		flags.know_pot = true
		_say("Fermée à clé. Une étiquette au cadenas : « clé — serre, sous le pot bleu ».", 5.0)
		_update_objective()
		return
	flags.shed_open = true
	_sfx("unlock", at, 0.0)
	_sfx("door_creak_open", at, 2.0, 0.9)
	_noise(at, float(NOISE.door), "door")
	_solid("shed", false)
	_doors.shed.goal = 1.0
	_doors.shed.speed = 0.8
	her.set_blocked(ctx.room_fx.shed_gap, false)
	_update_objective()
	_recapture(1.6)

func _take_cave_key() -> void:
	if flags.cave_key:
		return
	flags.cave_key = true
	(_nodes.key_cave as Node3D).visible = false
	_sfx("key_pickup", ctx.room_fx.key_cave, 0.0)
	_set_stage(3)

func _use_radio() -> void:
	var at: Vector3 = ctx.room_fx.radio
	_radio_on = not _radio_on
	_sfx("flashlight_click", at, 2.0)
	(_nodes.led as Node3D).visible = _radio_on
	if _radio_on:
		_radio_t = 45.0
		_radio = _loop("dh_radio", {"position": at, "volume_db": 2.0})
	else:
		_stop(_radio, 0.05)
		_radio = null

func _radio_off(by_her: bool) -> void:
	if not _radio_on:
		return
	_radio_on = false
	_stop(_radio, 0.02)
	_radio = null
	(_nodes.led as Node3D).visible = false
	_sfx("flashlight_click", ctx.room_fx.radio, 3.0, 0.8)
	if by_her:
		_kick(0.5)

func _use_trap() -> void:
	var at: Vector3 = ctx.room_fx.trap_lock
	if not flags.cave_key:
		_sfx("door_locked", at, 0.0, 0.8)
		_noise(at, 0.3, "trap")
		flags.cave_tried = true
		_say("Un cadenas. Il me faut sa clé.", 3.0)
		_update_objective()
		return
	if not flags.cave_unlocked:
		flags.cave_unlocked = true
		(_nodes.trap_lock as Node3D).visible = false
		_sfx("unlock", at, 0.0)
		_noise(at, 0.25, "trap")
		return
	_open_trap()
	_set_stage(4)

func _open_trap() -> void:
	var at: Vector3 = ctx.room_fx.trap_lock
	flags.cave_open = true
	_shut_in = false
	_sfx("dh_trap_open", at, 2.0)
	_noise(at, float(NOISE.trap), "trap")
	_solid("trap", false)
	for id in ["trap0", "trap1"]:
		_doors[id].goal = 1.0
		_doors[id].speed = 0.7
	_recapture(2.0)

func _push_trap() -> void:
	if not _shut_in:
		return
	_open_trap()

func _take_cutters() -> void:
	if flags.cutters:
		return
	flags.cutters = true
	(_nodes.cutters as Node3D).visible = false
	_sfx("pickup", ctx.room_fx.cutters_pos, 0.0, 0.8)
	_set_stage(5)
	if her != null:
		her.late = true
	if not _her_out and _emerge_t < 0.0:
		_emerge_t = 0.5
	_slam()

## The scare of the cellar: the doors fall shut over the steps, dust comes down from the joists, and she walks
## over the lawn above.
func _slam() -> void:
	if _slam_done or not flags.cave_open:
		return
	_slam_done = true
	if not await _wait(1.6):
		return
	var p := _player()
	if p == null or not L.in_cellar(p.global_position) or p.global_position.x > float(L.SHAFT.x0) + 1.2:
		return                                        # already on the way up: the doors stay open
	var at: Vector3 = ctx.room_fx.trap_lock
	_shut_in = true
	_solid("trap", true)
	for id in ["trap0", "trap1"]:
		_doors[id].goal = 0.0
		_doors[id].speed = 7.0
	_sfx("dh_trap_slam", at, 6.0)
	(ctx.room_fx.dust as GPUParticles3D).restart()
	(ctx.room_fx.dust as GPUParticles3D).emitting = true
	_kick(1.0)
	if p.has_method("flinch"):
		p.call("flinch", 1.0)
	if p.has_method("flashlight_stutter"):
		p.call("flashlight_stutter", 1.4)
	_noise(Vector3(at.x, 0.0, at.z), float(NOISE.slam), "trap")
	_recapture(0.5)
	if not await _wait(3.0):
		return
	(ctx.room_fx.dust as GPUParticles3D).emitting = false
	_say("(Les portes… Elle est là-haut. Attendre qu’elle s’éloigne.)", 5.0)

func _use_chimes() -> void:
	var at: Vector3 = ctx.room_fx.chimes
	_chime_t = 7.0
	_chime_cd = 22.0
	_sfx("dh_chimes", at + Vector3(0, -0.3, 0), 3.0)

func _use_horn() -> void:
	var at: Vector3 = ctx.room_fx.horn
	if _horn_left <= 0:
		_sfx("dh_horn_dead", at, 0.0)
		_noise(at, 0.25, "horn")
		_say("(Plus rien. La batterie est morte.)", 3.0)
		return
	_horn_left -= 1
	_horn_t = 3.6
	_sfx("dh_horn", at, 6.0)
	_kick(0.5)

func _enter_hide(spot: Dictionary) -> void:
	var p := _player()
	if p == null or not p.has_method("enter_hide"):
		return
	_noise(spot.exit_pos, float(NOISE.hide), "hide")
	_sfx("closet_enter", spot.at, -4.0, 0.9)
	_scratch_done = ""
	await p.enter_hide(spot)

func _exit_hide(spot: Dictionary) -> void:
	var p := _player()
	if p == null or not p.has_method("exit_hide"):
		return
	_noise(spot.exit_pos, float(NOISE.hide), "hide")
	await p.exit_hide()

# ---- pebbles

func _unhandled_input(event: InputEvent) -> void:
	if not active or Game.state != "playing" or not InputMap.has_action("throw"):
		return
	if event.is_action_pressed("throw"):
		throw_pebble()

## Throws a pebble where the camera looks. Returns where it will land (Vector3.ZERO: nothing thrown).
func throw_pebble() -> Vector3:
	if pebbles <= 0 or _catching or _hidden() or not _throw.is_empty():
		return Vector3.ZERO
	var cam := Game.camera
	if cam == null or not is_instance_valid(cam):
		return Vector3.ZERO
	pebbles -= 1
	var from := cam.global_position + cam.global_transform.basis.x * 0.2 - cam.global_transform.basis.y * 0.15
	var vel := (-cam.global_transform.basis.z + Vector3(0, 0.16, 0)).normalized() * 14.0
	var pts: Array = [from]
	var space := get_world_3d().direct_space_state
	var p := from
	var hit_n := Vector3.UP
	var ex: Array[RID] = []
	var pl := _player()
	if pl is CollisionObject3D:
		ex.append((pl as CollisionObject3D).get_rid())
	for i in 100:
		var np := p + vel * 0.03
		vel.y -= 9.8 * 0.03
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, np, LAYER_WORLD, ex))
		if not hit.is_empty():
			pts.append(hit.position)
			hit_n = hit.normal
			break
		pts.append(np)
		p = np
		if np.y < -3.0:
			break
	_throw = {"pts": pts, "t": 0.0, "n": hit_n}
	(_nodes.pebble as Node3D).visible = true
	(_nodes.pebble as Node3D).position = from
	_sfx("cloth_move", from, -6.0, 1.5)
	if pebbles == 0:
		_say("(Plus de cailloux.)", 2.0)
	return pts[pts.size() - 1]

func _tick_throw(dt: float) -> void:
	if _throw.is_empty():
		return
	var pts: Array = _throw.pts
	_throw.t = float(_throw.t) + dt
	var f := float(_throw.t) / 0.03
	var i := int(f)
	var n: Node3D = _nodes.pebble
	if i >= pts.size() - 1:
		var at: Vector3 = pts[pts.size() - 1]
		n.position = at + Vector3(0, 0.02, 0)
		var surf := L.surface_at(at)
		var hard: bool = surf in ["gravel", "wood", "concrete"] or at.y > 0.25
		_sfx("dh_stone_hard" if hard else "dh_stone_soft", at, 4.0 if hard else 2.0, randf_range(0.92, 1.08))
		_noise(at, float(NOISE.stone_hard if hard else NOISE.stone_soft), "stone")
		_throw = {}
		return
	n.position = (pts[i] as Vector3).lerp(pts[i + 1], f - float(i))

# ====================================================================== her

func _on_noise(at: Vector3, loud: float, source: String) -> void:
	if not active or not _her_out or her == null or _catching:
		return
	var p := _player()
	# the player's own steps, softer on the stone steps of the cellar
	var heard := her.hear(at, loud, source)
	if heard and source == "player" and p != null:
		if not _gravel_said and L.surface_at(p.global_position) in ["gravel", "leaves"] and p.get("crouched") != true:
			_gravel_said = true
			_say("(Elle m’a entendu. Le gravier, les feuilles : accroupi, ou pas du tout.)", 5.0)

func _on_noticed(_at: Vector3) -> void:
	if not active:
		return
	_kick(0.55)
	if not _taught:
		_taught = true
		_teach()

func _teach() -> void:
	if await _wait(2.0):
		_say("(Elle ne chante plus. Elle écoute. Elle vient où il y a eu du bruit.)", 5.0)

func _on_arrived(at: Vector3) -> void:
	if not active:
		return
	# the radio: she finds it and turns it off
	if _radio_on and at.distance_to(ctx.room_fx.radio_listen) < 2.2:
		_radio_off(true)
	# a hiding place she stands in front of: fingers along the boards, once
	var hid := _hidden_in()
	if hid != "" and _scratch_done != hid:
		for sp in hide_spots:
			if str(sp.id) == hid and at.distance_to(sp.exit_pos) < 2.6:
				_scratch_done = hid
				_scratch(sp)

func _scratch(spot: Dictionary) -> void:
	if not await _wait(1.2):
		return
	if _hidden_in() != str(spot.id):
		return
	_sfx("fear_scratch", spot.at, 4.0, 0.8)
	_kick(0.85)
	if not await _wait(1.8):
		return
	_sfx("entity_breath", (spot.at as Vector3) + Vector3(0, 0.3, 0), 0.0, 0.85)

func _on_touched() -> void:
	if active and not _catching and Game.state == "playing" and not _hidden():
		_catch()

## She comes out of the house: the front door opens on the lit hall, the window upstairs goes dark, and the lantern
## starts down the steps.
func _emerge() -> void:
	if _her_out or _emerging:
		return
	_emerging = true
	var at := Vector3(float(L.HOUSE.x1), float(L.PORCH.y) + 1.0, 0.0)
	(_nodes.lit as Node3D).visible = false
	(ctx.room_fx.window_light as Light3D).visible = false
	if not await _wait(0.8):
		return
	_sfx("door_creak_open", at, 9.0, 0.8)
	_doors.front.goal = 1.0
	_doors.front.speed = 0.45
	(ctx.room_fx.hall_light as Light3D).visible = true
	_kick(0.6)
	if not await _wait(2.6):
		return
	_her_out = true
	her.late = flags.cutters
	# through the door, across the boards, down the steps: the lantern is seen before she is
	her.enter(Vector3(float(L.HOUSE.x1) + 0.2, float(L.PORCH.y), 0.0), L.HER_HOME, 4.2)
	if _lantern_out > 0.0:
		her.set_lantern(false)
	if not await _wait(3.4):
		return
	_doors.front.goal = 0.0
	_doors.front.speed = 0.6
	if not await _wait(2.0):
		return
	(ctx.room_fx.hall_light as Light3D).visible = false
	_sfx("door_close", at, 4.0, 0.85)
	_emerging = false
	if stage < 5:
		_say("(La porte de la maison. Une lanterne. Elle sort.)", 4.5)

func _catch() -> void:
	if _catching:
		return
	_catching = true
	var p := _player()
	var cam := Game.camera
	if p != null:
		p.set("enabled", false)
	if cam != null and her != null:
		var f := -cam.global_transform.basis.z
		f = Vector3(f.x, 0.0, f.z).normalized()
		var feet := cam.global_position + f * 0.85
		feet.y = (p.global_position.y if p != null else 0.0)
		her.grab(feet, atan2(-f.x, -f.z))
	_sfx("jumpscare", her.head_position(), 0.0)
	_sfx("entity_croak", her.head_position(), 2.0, 0.8)
	_kick(1.0)
	if p != null and p.has_method("flinch"):
		p.call("flinch", 1.2)
	var q := _seq
	await get_tree().create_timer(0.95, false).timeout
	if p != null and is_instance_valid(p):
		p.set("enabled", true)
	if q != _seq:
		return
	_stop(_layer, 0.2)
	_layer = null
	Game.on_caught()

# ====================================================================== every frame

func _tick_doors(dt: float) -> void:
	for id in _doors:
		var d: Dictionary = _doors[id]
		if is_equal_approx(float(d.a), float(d.goal)):
			continue
		d.a = move_toward(float(d.a), float(d.goal), dt * float(d.speed))
		_set_rot(d.node, int(d.axis), lerpf(float(d.closed), float(d.open), float(d.a)))

func _tick_lures(dt: float) -> void:
	_chime_cd = maxf(0.0, _chime_cd - dt)
	_lure_tick -= dt
	var beat := _lure_tick <= 0.0
	if beat:
		_lure_tick = 0.5
	var ch: Node3D = _nodes.get("chimes")
	if _chime_t > 0.0:
		_chime_t -= dt
		if ch != null:
			ch.rotation.x = 0.3 * sin(_t * 9.0) * minf(1.0, _chime_t / 3.0)
			ch.rotation.z = 0.22 * sin(_t * 7.3 + 1.0) * minf(1.0, _chime_t / 3.0)
		if beat:
			_noise(ctx.room_fx.chimes, float(NOISE.chimes), "chimes")
	elif ch != null:
		ch.rotation.x = 0.03 * sin(_t * 1.3)
		ch.rotation.z = 0.02 * sin(_t * 0.9 + 2.0)
	if _horn_t > 0.0:
		_horn_t -= dt
		if beat:
			_noise(ctx.room_fx.horn, float(NOISE.horn), "horn")
	if _radio_on:
		_radio_t -= dt
		if beat:
			_noise(ctx.room_fx.radio_listen, float(NOISE.radio), "radio")
		if _radio_t <= 0.0:
			_radio_off(false)

func _tick_swings(dt: float, pp: Vector3) -> void:
	var S: Dictionary = L.SWING
	# the one with both chains starts to swing by itself as the player walks by, once
	if not _swing_done and (stage >= 1 or _her_out) and Vector2(pp.x - float(S.x), pp.z - float(S.z)).length() < 4.2:
		_swing_done = true
		_swing[0] = 0.62
		_swing_ph = 0.0
		var at := Vector3(float(S.x) + float(S.seats[0]), 1.2, float(S.z))
		_sfx("dh_swing", at, 4.0)
		_noise(at, float(NOISE.swing), "swing")
		_kick(0.7)
	_swing_ph += dt * 2.35
	_swing[0] = maxf(0.0, float(_swing[0]) - dt * 0.035)
	for i in 2:
		var n: Node3D = _nodes.get("swing%d" % i)
		if n != null:
			var idle := 0.025 * sin(_t * (0.9 + 0.3 * i) + float(i))
			n.rotation.x = idle + float(_swing[i]) * sin(_swing_ph)

func _tick_events(dt: float, pp: Vector3) -> void:
	# she comes out: armed by the gate, by the shed key, by time, or by how far the player has gone
	if not _her_out and not _emerging:
		if _emerge_t < 0.0 and (pp.x > 127.0 or _t > 110.0):
			_emerge_t = 1.5
		if _emerge_t >= 0.0 and Vector2(pp.x - L.HER_HOME.x, pp.z - L.HER_HOME.z).length() > 7.0:
			_emerge_t -= dt
			if _emerge_t <= 0.0:
				_emerge_t = -1.0
				_emerge()
	# her lantern, put out when the chain falls, comes back
	if _lantern_out > 0.0:
		_lantern_out -= dt
		if _lantern_out <= 0.0 and her != null and _her_out:
			her.set_lantern(true)
	# out of breath after a run: she hears it from close
	var p := _player()
	if p != null and p.get("exhausted") == true and _her_out:
		_pant_t -= dt
		if _pant_t <= 0.0:
			_pant_t = 1.0
			_noise(pp, float(NOISE.pant), "pant")
	# the night around: an owl far off, a branch that gives, a gust in the leaves
	_life_t -= dt
	if _life_t <= 0.0:
		_life_t = randf_range(14.0, 30.0)
		if her == null or her.alert < 0.3:
			var a := randf() * TAU
			var r := randf()
			if r < 0.4:
				_sfx("dh_owl", Vector3(pp.x + cos(a) * 26.0, 7.0, pp.z + sin(a) * 26.0), 0.0, randf_range(0.92, 1.05))
			elif r < 0.75:
				_sfx("dh_twig", Vector3(clampf(pp.x + cos(a) * 12.0, 100.0, 150.0), 0.3, signf(sin(a)) * 18.5), 0.0, randf_range(0.9, 1.1))
			else:
				_sfx("dh_gust", Vector3(float(L.OAK.x), 4.0, float(L.OAK.z)), 0.0, randf_range(0.9, 1.1))

func _tick_fear(dt: float, pp: Vector3) -> void:
	var d := 99.0
	var al := 0.0
	if _her_out and her != null and her.state != "away":
		d = Vector2(her.pos.x - pp.x, her.pos.z - pp.z).length()
		al = her.alert
	var target := 0.1 + (0.06 if stage >= 1 else 0.0)
	if d < 90.0:
		target = clampf(1.1 - d / 15.0, 0.16, 1.0) * (0.55 + 0.45 * al)
		if her.state == "seek":
			target = maxf(target, 0.45 + 0.3 * al)
	if _shut_in:
		target = maxf(target, 0.6)
	fear = move_toward(fear, target, dt * (0.6 if target > fear else 0.12))
	var k := clampf(1.0 - (d - 1.5) / 14.0, 0.0, 1.0)
	_vol(_layer, lerpf(-34.0, 1.0, pow(k, 0.7)) if d < 90.0 else -40.0)
	var p := _player()
	if p != null:
		p.set("stress_bias", fear * 0.85)
	# down in the cellar there is no fog and no night air
	_cellar_k = move_toward(_cellar_k, 1.0 if pp.y < -1.0 else 0.0, dt * 1.5)
	if _look_on:
		var rig = Quality.rig()
		if rig != null and rig.get("environment") != null:
			(rig.environment as Environment).fog_density = FOG_DENSITY * (1.0 - _cellar_k)

func _process(dt: float) -> void:
	if not active or not built or Game.state != "playing":
		return
	var p := _player()
	if p == null:
		return
	_t += dt
	var pp := p.global_position
	_tick_doors(dt)
	_tick_lures(dt)
	_tick_swings(dt, pp)
	_tick_throw(dt)
	_tick_events(dt, pp)
	if _her_out and her != null:
		her.tick(dt, pp, not _catching and not _hidden())
	_tick_fear(dt, pp)
