## L'étage — chapter 2 (coordinates: etage_layout.gd; geometry: etage_build.gd for the hallway, the salon, her bedroom
## and the closet, etage_rooms.gd for the kitchen, the pantry, the bathroom and the stairwell). Started from the TV
## menu (Game.mode "etage"): the house and the garderie are hidden, the player stands at the top of the basement
## stairs, in the hallway of the old house, at night. The way out is the front door at the far end.
##
## Getting out. The front door's key is in a box with three wheels, on the mantel of the salon where everything
## stands under dust sheets. A card under the box gives the order of its digits:
##   1. the mirror    — a digit a finger draws in the steam on the bathroom mirror, once the hot tap has run long
##                      enough. Hot water needs the water heater, and its fuse is missing from the board in the
##                      stairwell; spare fuses are in the pantry, behind the dresser pushed across its door.
##   2. the calendar  — the day ringed in red on the kitchen calendar.
##   3. the pillow    — on a slip of paper under her pillow. Her door is held shut from inside; its spare key is in
##                      the fridge, under the cover of the butter dish.
## The digits are drawn at random when the chapter starts (`code`), a wrong try brings one of the sheets closer.
##
## The dread is not a chase. One of the shapes under the sheets walks — only while nobody looks at it:
##   * every figure is a statue while any part of it is on screen and in line of sight; unseen, the walker comes
##     straight for the player (slower than a walk, faster when far), room to room through the doorways (a shut
##     door opens for it), and each of its steps creaks at ITS position, so the ears say how close it is behind;
##   * the other figures never walk, but they turn to face the player while unseen, and after the key is taken they
##     are found standing closer to the way out; one sits at the kitchen table and is found on another chair; one
##     watches from the top of the boarded stairs until the fuse goes in; one is found in the bath once the mirror
##     has been read;
##   * the front door needs the key held in the lock for three seconds, back turned.
## Before the key: floorboards that complain under a standing step (crouching spares them) silence the humming
## behind the bedroom door, as if she listened. A few plain frights mark the way (a door slammed from inside, the
## clock, the piano, pipes that answer a running tap, a mousetrap in a drawer); everything else is sound placed in
## the room: wood, hinges, cloth, water, breath.
##
## Being caught puts the player back at the top of the stairs with the key back in its box: what was found and
## opened stays found and opened.
##
## API: build() (await), begin() (start of the chapter), active, fear (0..1 for Game: heartbeat, breath),
## in_area(pos), surface_at(pos), reset_after_caught(), reset_all() (everything as at the start: tours, tests),
## prewarm(on) (loading rehearsal: shows what only appears later), try_code(digits), stage, code, found, stats.
extends Node3D

const L := preload("res://scripts/etage/etage_layout.gd")
const Build := preload("res://scripts/etage/etage_build.gd")
const Rooms := preload("res://scripts/etage/etage_rooms.gd")
const Ctx := preload("res://scripts/garderie/garderie_ctx.gd")
const Mats := preload("res://scripts/etage/etage_mats.gd")

const LAYER_WORLD := 1
const LAYER_INTERACT := 2
const LAYER_SIGHT := 16
const WALK_SPEED := 1.32            # m/s unseen (the player walks at 1.9, crouches at 0.9)
const CATCH_DIST := 0.8
const FOG_TIME := 10.0              # seconds of hot water before the mirror is misted over
## regions that move at runtime, or only show later: never in a shadow pass
const NO_SHADOW := ["et_fridge_door", "et_drawer_0", "et_drawer_1", "et_drawer_2", "et_buffet", "et_butter_lid", "et_ckey", "et_door_cellier",
	"et_door_bain", "et_door_esc", "et_curtain", "et_pillow", "et_box_lid", "et_cal_ring", "et_fuse_item", "et_fuse_in", "et_plank_up", "et_plank_down",
	"et_mirror_fx", "et_stream_hot", "et_stream_cold", "et_slip_digit"]
## rooms whose doorway has a leaf: room -> id in _doors
const ROOM_DOOR := {"chambre": "chambre", "closet": "closet", "bain": "bain", "escalier": "esc", "cellier": "cellier"}

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
			+ "Si le plancher craque et que ce n’est pas moi, je m’arrête de chanter. J’écoute où elle est.\n\n"
			+ "La clé de la porte d’entrée est dans le coffret, sur la cheminée. Je n’ose plus traverser le salon.",
	},
	"card": {
		"title": "Carte glissée sous le coffret", "style": "note",
		"text": "Pour le jour où je n’aurai plus toute ma tête.\n\nTrois chiffres, dans cet ordre :\n\n1. ce que la buée écrit sur le miroir\n2. le jour entouré, à la cuisine\n3. ce qui dort sous mon oreiller\n\n"
			+ "Ne l’écris nulle part ailleurs. Elle sait lire.",
	},
	"table": {
		"title": "Mot laissé sur la table", "style": "note",
		"text": "Thérèse,\n\nsi tu viens quand même : ne touche pas au buffet. Je l’ai poussé devant le garde-manger le soir où j’ai compté sept draps.\n\n"
			+ "Ça a gratté toute la nuit derrière la porte. Au matin, plus rien.\n\nJe n’ai pas ouvert.\n\n"
			+ "Je mets encore la table pour les petits. Quatre bols. Il y a toujours quelqu’un d’assis.",
	},
	"list": {
		"title": "Liste de courses", "style": "note",
		"text": "Bougies\nFicelle\nBeurre\nFusibles (porcelaine, 10 A) — non : il en reste une boîte au garde-manger\n\n"
			+ "Ne plus laisser la clé de ma chambre sur la porte. Je la mets au froid, sous la cloche du beurrier.\n\nElle n’ouvre jamais le frigo. La lumière la gêne.",
	},
	"bath": {
		"title": "Papier sur la tablette", "style": "note",
		"text": "Ne plus faire couler l’eau chaude la nuit.\n\nLes tuyaux répondent. Trois coups, toujours trois.\n\n"
			+ "Et quand la glace se couvre de buée, quelqu’un écrit dedans avant moi. Toujours le même chiffre.\n\nJ’en ai fait le premier du coffret. Comme ça, je ne l’oublierai pas : il suffit de laisser couler.",
	},
	"stairs": {
		"title": "Avis cloué sur les planches", "style": "note",
		"text": "ÉTAGE CONDAMNÉ\n\nJ’ai cloué l’escalier le 12 novembre.\n\nCe n’est pas pour empêcher de monter.\n\nSi une planche tombe, ne la remets pas. Va-t’en.",
	},
}

var ctx = null
var built := false
var active := false
var stage := 0                    # 0 find the way out, 1 the front door is locked, 2 the key is taken (it walks), 3 out
var fear := 0.0
var stats := {}
var code: Array = [1, 1, 1]       # the box's digits: mirror, calendar, pillow
var found: Array = [false, false, false]

var _entries: Array = []
var _registered_with: Node = null
var _t := 0.0
var _figs: Array = []             # the ones that only turn: {node, body, home, alt, h, at_alt, unseen, room, on, ...}
var _walkers: Array = []          # {node, body, pos, home, h, awake, unseen, moved, revealed, stuck, rustle}
var _doors := {}                  # id -> {node, body, closed, open, a, goal, speed}
var _movers := {}                 # id -> {a, goal, speed, fn}: drawers, the fridge door, the dresser, lids, the curtain
var _rocker: Node3D = null
var _rock := 0.0
var _rock_on := false
var _key: Node3D = null
var _obstacles: Array = []        # Rect2 (x, z) the walkers go around
var _buffet_rect := 0             # index in _obstacles of the dresser (it moves)
var _boards_in: Array = []
var _creaks: Array = []           # times of the last loud creaks
var _rage := 0.0
var _hum = null
var _hum_pause := 0.0
var _hum_at: Vector3 = L.HUM
var _theme = null
var _layer = null
var _tick = null
var _winds: Array = []
var _loops := {}                  # id -> handle: taps, the fridge, the water heater, the bathroom lamp, the drip
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

# ---- progress (kept when caught, cleared by reset_all)
var _box_seen := false
var _box_open := false
var _box_tries := 0
var _has_fuse := false
var _board_seen := false
var _power := false
var _buffet_pushed := false
var _has_ckey := false
var _chambre_open := false
var _fridge_open := false
var _fridge_once := false
var _drawer_open := [false, false, false]
var _trap_done := false
var _curtain_open := false
var _pillow_up := false
var _hot := false                 # taps running
var _cold := false
var _hot_tried := false
var _hot_t := 0.0                 # seconds of hot water since the tap was opened
var _fog := 0.0                   # 0..1 mist on the mirror
var _mirror_look := 0.0
var _cold_knock := false
var _bath_arm := false            # the mirror has been read: the bath is next
var _bath_done := false
var _bath_unseen := 0.0
var _seat := 0                    # the chair the kitchen figure sits on (-1: gone)
var _seat_want := 0
var _seat_unseen := 0.0
var _stair_gone := false
var _stair_want_gone := false
var _stair_seen := false
var _hum_hall := false            # she hums in the hallway, outside her own door
var _opened := {}                 # doors the player has opened (stay open when caught)

var _seated: Node3D = null
var _seated_body: StaticBody3D = null
var _late: Array = []             # [node, shown by default]: what prewarm(true) shows
var _fx := {}

# ====================================================================== build

func build() -> void:
	var t0 := Time.get_ticks_usec()
	name = "Etage"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	ctx = Ctx.new()
	ctx.root = self
	ctx.mats = Mats.new()
	Build.build(ctx)
	Rooms.build(ctx)
	var tris: int = ctx.commit_all({"et_sky": {"no_shadow": ["night_sky", "frost_glow"]}, "et_key": {"no_shadow": ["brass"]}, "et_webs": {"no_shadow": ["cobweb"]}})
	for g in find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).layers = L.L_ET
	for r in NO_SHADOW:
		var n: Node = ctx.regions.get(r)
		if n != null:
			for mi in n.find_children("*", "GeometryInstance3D", true, false):
				(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx = ctx.room_fx
	_setup_nodes()
	_setup_rooms()
	_setup_entries()
	_register_or_wait()
	_reset_progress()
	visible = false
	built = true
	stats = {"build_ms": (Time.get_ticks_usec() - t0) / 1000.0, "triangles": tris, "figures": _figs.size() + _walkers.size() + 1,
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

func _region(id: String) -> Node3D:
	return ctx.regions.get(id) as Node3D

func _setup_nodes() -> void:
	var fx: Dictionary = _fx
	var fl: Array = L.FIGURES
	for i in fl.size():
		var n: Node3D = ctx.regions.get("et_fig_%d" % i)
		if n == null:
			continue
		var home: Vector3 = fl[i][0]
		n.position = home
		_figs.append({"node": n, "body": _figure_body(n, float(fl[i][1])), "home": home, "alt": fl[i][2], "h": float(fl[i][1]),
			"at_alt": false, "unseen": 0.0, "yaw0": float(i) * 1.9, "room": "salon", "on": true})
	for w in [["et_walker", L.WALKER], ["et_closetfig", L.CLOSET_FIGURE]]:
		var n: Node3D = ctx.regions.get(String(w[0]))
		if n == null:
			continue
		var home: Vector3 = w[1][0]
		n.position = home
		_walkers.append({"node": n, "body": _figure_body(n, float(w[1][1])), "pos": home, "home": home, "h": float(w[1][1]), "awake": false,
			"unseen": 0.0, "moved": 0.0, "revealed": false, "stuck": 0.0, "stall": 0.0, "rustle": 0.0, "slow": 1.0 if _walkers.is_empty() else 0.78})
	# doors: leaves around their hinges (yaw closed / open), a collider across each opening
	_door("front", "et_door_front", fx.front_hinge, PI * 0.5, 0.2, Vector3(float(L.HALL.x1) + 0.1, 1.0, 0.0), Vector3(0.2, 2.1, 0.96))
	_door("chambre", "et_door_chambre", fx.chambre_hinge, 0.0, 1.45, Vector3((float(L.DOOR_CHAMBRE.x0) + float(L.DOOR_CHAMBRE.x1)) * 0.5, 1.0, float(L.HALL.z0) - 0.1), Vector3(0.9, 2.1, 0.2))
	_door("closet", "et_door_closet", fx.closet_hinge, PI, PI - 0.85, Vector3((float(L.DOOR_CLOSET.x0) + float(L.DOOR_CLOSET.x1)) * 0.5, 1.0, float(L.HALL.z1) + 0.1), Vector3(0.82, 2.1, 0.2))
	_door("bain", "et_door_bain", fx.bain_hinge, PI, PI * 1.5 - 0.12, Vector3((float(L.DOOR_BAIN.x0) + float(L.DOOR_BAIN.x1)) * 0.5, 1.0, float(L.HALL.z1) + 0.1), Vector3(0.84, 2.1, 0.2))
	_door("esc", "et_door_esc", fx.esc_hinge, PI, PI - 1.5, Vector3((float(L.DOOR_ESCALIER.x0) + float(L.DOOR_ESCALIER.x1)) * 0.5, 1.0, float(L.HALL.z0) - 0.1), Vector3(0.84, 2.1, 0.2))
	_door("cellier", "et_door_cellier", fx.cellier_hinge, PI * 0.5, PI * 0.5 + 1.5, Vector3(float(L.CUISINE.x0) - 0.1, 1.0, (float(L.DOOR_CELLIER.z0) + float(L.DOOR_CELLIER.z1)) * 0.5), Vector3(0.2, 2.0, 0.82))
	_rocker = ctx.regions.get("et_rocker")
	if _rocker != null:
		_rocker.position = fx.rocker_pos
		_rocker.rotation.y = float(fx.rocker_yaw)
	_key = ctx.regions.get("et_key")
	if _key != null:
		_key.position = fx.key_pos
		_key.rotation.y = 1.2
	for f in L.FURNITURE:
		_obstacles.append(Rect2(float(f[0]) - 0.34, float(f[1]) - 0.34, float(f[2]) - float(f[0]) + 0.68, float(f[3]) - float(f[1]) + 0.68))
	# chimney breast, clock, console table, bed, dresser, bedside table, rocking chair
	for r in [[65.14, -5.25, 65.5, -3.55], [62.92, -0.8, 63.48, -0.46], [61.2, 0.44, 62.2, 0.8], [53.78, -5.4, 54.84, -3.34], [52.2, -3.9, 52.68, -2.7],
			[55.0, -5.4, 55.5, -4.9], [52.6, -2.3, 53.3, -1.5]]:
		_obstacles.append(Rect2(float(r[0]) - 0.3, float(r[1]) - 0.3, float(r[2]) - float(r[0]) + 0.6, float(r[3]) - float(r[1]) + 0.6))
	# the rooms added later (a thinner margin: they are small). Kitchen: the table and its chairs, the worktop, the
	# fridge, the stove; bathroom: the bath and its stub wall, the lavatory, the basin, the basket; pantry: the
	# shelves, the sacks; stairwell: the stairs, the trunk
	var K: Dictionary = L.COUNTER
	var F: Dictionary = L.FRIDGE
	var S: Dictionary = L.STOVE
	var T: Vector3 = L.TABLE
	for r in [[T.x - 1.2, T.z - 0.95, T.x + 1.2, T.z + 0.95], [float(K.x0), float(K.z0), float(K.x1), float(K.z1)], [float(F.x0), float(F.z0), float(F.x1), float(F.z1)],
			[float(S.x0), float(S.z0), float(S.x1), float(S.z1)], [52.4, 3.3, 54.35, 4.2], [55.08, 3.56, 55.56, 4.2], [52.4, 1.8, 52.86, 2.4], [55.4, 3.0, 55.9, 3.4],
			[56.1, 2.2, 56.44, 5.2], [56.5, 4.9, 58.1, 5.2], [56.5, 2.2, 58.1, 2.95], [67.0, -6.2, 68.0, -2.4], [65.7, -6.2, 66.7, -5.54]]:
		_obstacles.append(Rect2(float(r[0]) - 0.24, float(r[1]) - 0.24, float(r[2]) - float(r[0]) + 0.48, float(r[3]) - float(r[1]) + 0.48))
	_buffet_rect = _obstacles.size()
	_obstacles.append(Rect2())
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

## What the rooms added later need at runtime: figures, movers, lights that come on, things shown later.
func _setup_rooms() -> void:
	var fx: Dictionary = _fx
	# the one seated at the kitchen table
	_seated = _region("et_seated")
	var sh := CylinderShape3D.new()
	sh.radius = 0.26
	sh.height = 1.3
	_seated_body = _body(_seated, sh, Vector3(0, 0.65, 0.05), LAYER_SIGHT)
	# the one at the top of the stairs, the one in the bath: they only turn, like the salon's
	var sf: Node3D = _region("et_stairfig")
	sf.position = L.STAIR_FIGURE[0]
	_figs.append({"node": sf, "body": _figure_body(sf, float(L.STAIR_FIGURE[1])), "home": L.STAIR_FIGURE[0], "alt": null, "h": float(L.STAIR_FIGURE[1]),
		"at_alt": false, "unseen": 0.0, "yaw0": PI, "room": "escalier", "on": true, "id": "stairs"})
	var bf: Node3D = _region("et_bathfig")
	bf.position = L.BATH_FIGURE[0]
	_figs.append({"node": bf, "body": _figure_body(bf, float(L.BATH_FIGURE[1])), "home": L.BATH_FIGURE[0], "alt": L.BATH_FIGURE[2], "h": float(L.BATH_FIGURE[1]),
		"at_alt": false, "unseen": 0.0, "yaw0": PI * 0.75, "room": "bain", "on": false, "id": "bath"})
	# movers
	var fd: Node3D = _region("et_fridge_door")
	fd.position = fx.fridge_hinge
	_mover("fridge", func(a: float) -> void: fd.rotation.y = -PI * 0.5 - 1.62 * smoothstep(0.0, 1.0, a), 1.4)
	for i in 3:
		var dn: Node3D = _region("et_drawer_%d" % i)
		var base: Vector3 = fx.drawers[i]
		_mover("drawer%d" % i, func(a: float) -> void: dn.position = base + Vector3(0, 0, -0.3 * smoothstep(0.0, 1.0, a)), 2.6)
	var bn: Node3D = _region("et_buffet")
	var bsz: Vector3 = fx.buffet_size
	var bsh := BoxShape3D.new()
	bsh.size = bsz
	_body(bn, bsh, bsz * 0.5, LAYER_WORLD | LAYER_SIGHT)
	var bpos: Vector3 = fx.buffet_pos
	var slide := func(a: float) -> void:
		var e := a * a * (3.0 - 2.0 * a)
		bn.position = bpos + Vector3(0.012 * sin(a * 40.0) * sin(a * PI), 0, float(L.BUFFET_PUSH) * e)
		bn.rotation.y = 0.012 * sin(a * 23.0) * sin(a * PI)
	_mover("buffet", slide, 1.0 / 2.5)
	var lid: Node3D = _region("et_butter_lid")
	var lpos: Vector3 = fx.butter
	var lift := func(a: float) -> void:
		lid.position = lpos + Vector3(0, 0.07 * sin(a * PI), 0.19 * a)
		lid.rotation.x = 0.3 * sin(a * PI)
	_mover("butter", lift, 1.6)
	(_region("et_ckey") as Node3D).position = lpos + Vector3(0.0, 0.004, -0.01)
	(_region("et_ckey") as Node3D).rotation.y = 0.5
	var cn: Node3D = _region("et_curtain")
	cn.position = fx.curtain_pos
	_mover("curtain", func(a: float) -> void: cn.scale.x = lerpf(1.0, 0.2, smoothstep(0.0, 1.0, a)), 1.3)
	var pn: Node3D = _region("et_pillow")
	var ppos: Vector3 = fx.pillow_pos
	var toss := func(a: float) -> void:
		pn.position = ppos + Vector3(0.05 * a, 0.12 * sin(a * PI) + 0.02 * a, 0.44 * a)
		pn.rotation.y = 0.5 * a
	_mover("pillow", toss, 1.5)
	var bl: Node3D = _region("et_box_lid")
	bl.position = fx.box_hinge
	_mover("box", func(a: float) -> void: bl.rotation.z = -1.9 * smoothstep(0.0, 1.0, a), 1.8)
	(_region("et_fuse_item") as Node3D).position = fx.fuse_item
	(_region("et_fuse_in") as Node3D).position = fx.fuse_socket
	# shown later: the loading rehearsal shows them once
	for id in ["et_fuse_in", "et_plank_down", "et_mirror_fx", "et_stream_hot", "et_stream_cold", "et_bathfig"]:
		_late.append([_region(id), false])
	for d in fx.bain_prints:
		if d != null:
			_late.append([d, false])
	_late.append([fx.fridge.light, false])
	_late.append([fx.fridge.fill, false])
	_late.append([fx.bain_lamp.light, false])

func _mover(id: String, fn: Callable, speed: float) -> void:
	_movers[id] = {"a": 0.0, "goal": 0.0, "speed": speed, "fn": fn}
	fn.call(0.0)

func _move(id: String, goal: float) -> void:
	_movers[id].goal = goal

func _snap(id: String, a: float) -> void:
	var m: Dictionary = _movers[id]
	m.a = a
	m.goal = a
	(m.fn as Callable).call(a)

func _spot(node_name: String, pos: Vector3, size: Vector3, parent: Node3D = null) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = pos
	(parent if parent != null else self).add_child(n)
	var sh := BoxShape3D.new()
	sh.size = size
	_body(n, sh, Vector3.ZERO, LAYER_INTERACT)
	return n

func _setup_entries() -> void:
	var fx: Dictionary = _fx
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
	_entries.append({"id": "etage.chambre", "node": cd, "max_distance": 1.8,
		"prompt": func() -> String: return "Déverrouiller la porte" if _has_ckey else "Ouvrir la porte",
		"hold": func() -> float: return 1.2 if _has_ckey else 0.0,
		"hold_prompt": "La clé tourne…",
		"on_hold_start": func() -> void: _sfx("lock_wheel", cd.global_position, -2.0),
		"enabled": func() -> bool: return live.call() and stage < 2 and not _busy and not _chambre_open,
		"on_interact": _use_chambre})
	# the box on the mantel, the key in it, the card under it
	var bx := _spot("Coffret", (fx.box_at as Vector3) + Vector3(-0.03, 0.05, 0), Vector3(0.2, 0.14, 0.28))
	_entries.append({"id": "etage.box", "node": bx, "max_distance": 1.9, "prompt": "Ouvrir le coffret",
		"enabled": func() -> bool: return live.call() and stage < 2 and not _box_open, "on_interact": _use_box})
	var kn := _spot("Key", (fx.key_pos as Vector3) + Vector3(0, 0.03, 0), Vector3(0.16, 0.12, 0.2))
	_entries.append({"id": "etage.key", "node": kn, "max_distance": 1.9, "prompt": "Prendre la clé",
		"enabled": func() -> bool: return live.call() and stage < 2 and _box_open,
		"on_interact": _take_key})
	_note_entry("etage.card", "Card", (fx.card as Vector3) + Vector3(0, 0.02, 0), Vector3(0.16, 0.08, 0.2), "Lire la carte", "et_note_card", NOTES.card, live)
	_note_entry("etage.letter", "Letter", (fx.letter as Vector3) + Vector3(0, 0.03, 0), Vector3(0.24, 0.1, 0.2), "Lire la lettre", "et_note_letter", NOTES.letter, live)
	_note_entry("etage.bed_note", "BedNote", (fx.bed_note as Vector3) + Vector3(0, 0.03, 0), Vector3(0.2, 0.1, 0.24), "Lire la page", "et_note_bed", NOTES.bed, live)
	_note_entry("etage.table_note", "TableNote", (fx.table_note as Vector3) + Vector3(0, 0.03, 0), Vector3(0.22, 0.1, 0.26), "Lire le mot", "et_note_table", NOTES.table, live)
	_note_entry("etage.bath_note", "BathNote", (fx.bain_note as Vector3) + Vector3(0, 0.03, 0), Vector3(0.14, 0.1, 0.2), "Lire le papier", "et_note_bath", NOTES.bath, live)
	_note_entry("etage.stair_note", "StairNote", fx.stair_note, Vector3(0.22, 0.26, 0.08), "Lire l’avis", "et_note_stairs", NOTES.stairs, live)
	# ---- la cuisine
	var cal := _spot("Calendar", (L.CALENDAR as Vector3) + Vector3(0.03, 0, 0), Vector3(0.08, 0.56, 0.4))
	_entries.append({"id": "etage.calendar", "node": cal, "max_distance": 2.2, "prompt": "Regarder le calendrier", "enabled": live, "on_interact": _use_calendar})
	var F: Dictionary = L.FRIDGE
	var fw := float(F.z1) - float(F.z0)
	var fr := _spot("FridgeDoor", Vector3(fw * 0.5, 0.9, 0.03), Vector3(fw, 1.3, 0.1), _region("et_fridge_door"))
	_entries.append({"id": "etage.fridge", "node": fr, "max_distance": 1.9,
		"prompt": func() -> String: return "Fermer le frigo" if _fridge_open else "Ouvrir le frigo",
		"enabled": live, "on_interact": _use_fridge})
	var bt := _spot("Butter", (fx.butter as Vector3) + Vector3(0, 0.03, 0), Vector3(0.16, 0.12, 0.22))
	_entries.append({"id": "etage.butter", "node": bt, "max_distance": 1.7, "prompt": "Soulever la cloche du beurrier",
		"enabled": func() -> bool: return live.call() and _fridge_open and not _has_ckey and not _chambre_open,
		"on_interact": _use_butter})
	for i in 3:
		var dn := _spot("Drawer%d" % i, Vector3(0, 0, -0.02), Vector3(0.44, 0.18, 0.08), _region("et_drawer_%d" % i))
		_entries.append({"id": "etage.drawer%d" % i, "node": dn, "max_distance": 1.8,
			"prompt": func() -> String: return "Fermer le tiroir" if _drawer_open[i] else "Ouvrir le tiroir",
			"enabled": live, "on_interact": _use_drawer.bind(i)})
	var ln := _spot("ListNote", Vector3(0.1, -0.04, 0.2), Vector3(0.16, 0.06, 0.22), _region("et_drawer_0"))
	_entries.append({"id": "etage.list_note", "node": ln, "max_distance": 1.8, "prompt": "Lire la liste",
		"enabled": func() -> bool: return live.call() and _drawer_open[0],
		"on_interact": func() -> void: await _read("et_note_list", NOTES.list, ln)})
	var bsz: Vector3 = fx.buffet_size
	var bf := _spot("Buffet", Vector3(bsz.x + 0.02, bsz.y * 0.5, bsz.z * 0.5), Vector3(0.12, bsz.y, bsz.z), _region("et_buffet"))
	_entries.append({"id": "etage.buffet", "node": bf, "max_distance": 1.9, "prompt": "Pousser le buffet", "hold": 2.0, "hold_prompt": "Il est lourd…",
		"enabled": func() -> bool: return live.call() and not _buffet_pushed and not _busy,
		"on_interact": _push_buffet})
	var pd := _spot("CellierDoor", Vector3(float(L.CUISINE.x0) - 0.02, 1.0, (float(L.DOOR_CELLIER.z0) + float(L.DOOR_CELLIER.z1)) * 0.5), Vector3(0.3, 1.9, 0.78))
	_entries.append({"id": "etage.cellier", "node": pd, "max_distance": 1.8, "prompt": "Ouvrir la porte",
		"enabled": func() -> bool: return live.call() and _buffet_pushed and float(_doors.cellier.goal) < 0.5 and not _busy,
		"on_interact": _use_cellier})
	var fz := _spot("FuseTin", (L.FUSE_TIN as Vector3) + Vector3(0.08, 0.0, -0.03), Vector3(0.22, 0.14, 0.34))
	_entries.append({"id": "etage.fuse", "node": fz, "max_distance": 1.9, "prompt": "Prendre un fusible",
		"enabled": func() -> bool: return live.call() and not _has_fuse and not _power,
		"on_interact": _take_fuse})
	# ---- la cage d'escalier
	var ed := _spot("EscDoor", Vector3((float(L.DOOR_ESCALIER.x0) + float(L.DOOR_ESCALIER.x1)) * 0.5, 1.05, float(L.HALL.z0) + 0.03), Vector3(0.78, 2.0, 0.14))
	_entries.append({"id": "etage.esc_door", "node": ed, "max_distance": 1.8, "prompt": "Ouvrir la porte",
		"enabled": func() -> bool: return live.call() and float(_doors.esc.goal) < 0.5, "on_interact": _open_door.bind("esc", 0.6)})
	var fb := _spot("FuseBoard", (L.FUSE_BOARD as Vector3) + Vector3(0.04, 0.0, 0.0), Vector3(0.1, 0.66, 0.62))
	_entries.append({"id": "etage.fusebox", "node": fb, "max_distance": 1.9,
		"prompt": func() -> String: return "Visser le fusible" if _has_fuse else "Regarder le tableau",
		"hold": func() -> float: return 1.5 if _has_fuse else 0.0,
		"hold_prompt": "Le fusible se visse…",
		"enabled": func() -> bool: return live.call() and not _power,
		"on_interact": _use_fusebox})
	# ---- la salle de bain
	var bd := _spot("BainDoor", Vector3((float(L.DOOR_BAIN.x0) + float(L.DOOR_BAIN.x1)) * 0.5, 1.05, float(L.HALL.z1) - 0.03), Vector3(0.78, 2.0, 0.14))
	_entries.append({"id": "etage.bain_door", "node": bd, "max_distance": 1.8, "prompt": "Ouvrir la porte",
		"enabled": func() -> bool: return live.call() and float(_doors.bain.goal) < 0.5, "on_interact": _open_door.bind("bain", 0.6)})
	var th := _spot("TapHot", (fx.tap_hot as Vector3) + Vector3(0.0, 0.02, 0.0), Vector3(0.14, 0.16, 0.14))
	_entries.append({"id": "etage.tap_hot", "node": th, "max_distance": 1.7,
		"prompt": func() -> String: return "Fermer l’eau chaude" if _hot else "Ouvrir l’eau chaude",
		"enabled": live, "on_interact": _use_tap.bind(true)})
	var tc := _spot("TapCold", (fx.tap_cold as Vector3) + Vector3(0.0, 0.02, 0.0), Vector3(0.14, 0.16, 0.14))
	_entries.append({"id": "etage.tap_cold", "node": tc, "max_distance": 1.7,
		"prompt": func() -> String: return "Fermer l’eau froide" if _cold else "Ouvrir l’eau froide",
		"enabled": live, "on_interact": _use_tap.bind(false)})
	var mi := _spot("Mirror", (L.MIRROR as Vector3) + Vector3(0.03, 0, 0), Vector3(0.06, 0.76, 0.56))
	_entries.append({"id": "etage.mirror", "node": mi, "max_distance": 2.0, "prompt": "Regarder le miroir",
		"enabled": func() -> bool: return live.call() and _fog > 0.85 and not found[0],
		"on_interact": _read_mirror})
	# the curtain: across the bath while it is drawn, gathered at the wall once pulled
	var cu: Dictionary = L.CURTAIN
	var cw := float(cu.x1) - float(cu.x0)
	var cs := _spot("Curtain", Vector3(float(cu.x0) + 0.2, 1.1, float(cu.z)), Vector3(0.4, 1.7, 0.16))
	var wide := CollisionShape3D.new()
	var wsh := BoxShape3D.new()
	wsh.size = Vector3(cw, 1.7, 0.14)
	wide.shape = wsh
	wide.position = Vector3(cw * 0.5 - 0.2, 0, 0)
	wide.name = "Wide"
	(cs.get_child(0) as Node).add_child(wide)
	_fx["curtain_wide"] = wide
	_entries.append({"id": "etage.curtain", "node": cs, "max_distance": 1.9,
		"prompt": func() -> String: return "Tirer le rideau" if _curtain_open else "Écarter le rideau",
		"enabled": func() -> bool: return live.call() and not _busy, "on_interact": _use_curtain})
	# ---- sa chambre
	var pl := _spot("Pillow", (fx.pillow_pos as Vector3) + Vector3(0, 0.03, 0), Vector3(0.72, 0.16, 0.4))
	_entries.append({"id": "etage.pillow", "node": pl, "max_distance": 1.9, "prompt": "Soulever l’oreiller",
		"enabled": func() -> bool: return live.call() and not _pillow_up, "on_interact": _lift_pillow})

func _note_entry(id: String, node_name: String, pos: Vector3, size: Vector3, prompt: String, note_id: String, note: Dictionary, live: Callable) -> void:
	var n := _spot(node_name, pos, size)
	_entries.append({"id": id, "node": n, "max_distance": 1.9, "prompt": prompt, "enabled": live,
		"on_interact": func() -> void: await _read(note_id, note, n)})

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

## A named loop of the rooms (a tap, the fridge...): started once, stopped by name.
func _loop_on(id: String, sound: String, opts: Dictionary) -> void:
	if _loops.get(id) == null:
		var o := opts.duplicate()
		o["unique"] = true                     # (never the instance another part of the game may be playing)
		_loops[id] = _loop(sound, o)

func _loop_off(id: String, fade := 0.3) -> void:
	_stop(_loops.get(id), fade)
	_loops.erase(id)

func _say(text: String, seconds := 3.0) -> void:
	var ui = Game.ui
	if ui != null and is_instance_valid(ui) and ui.has_method("subtitle"):
		ui.call("subtitle", text, seconds, {})

## A line said a little later, if the level has not been reset meanwhile (and `cond`, if given, still holds).
func _say_later(delay: float, text: String, seconds := 3.0, cond := Callable()) -> void:
	if await _wait(delay) and (not cond.is_valid() or bool(cond.call())):
		_say(text, seconds)

func _objective(text: String) -> void:
	var ui = Game.ui
	if ui != null and is_instance_valid(ui) and ui.has_method("set_objective"):
		ui.call("set_objective", text)

func _kick(v: float) -> void:
	var d = (Game.main as Node).get_node_or_null("FearDirector") if Game.main != null and is_instance_valid(Game.main) else null
	if d != null and is_instance_valid(d) and d.has_method("kick"):
		d.call("kick", v)
	fear = maxf(fear, clampf(v, 0.0, 1.0))

func _flinch(v: float) -> void:
	var p := _player()
	if p != null and p.has_method("flinch"):
		p.call("flinch", v)

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

func _found_count() -> int:
	return found.count(true)

## The objective line, from what is known so far.
func _update_objective() -> void:
	if stage >= 2:
		_objective("Sors par la porte d’entrée.")
	elif _box_open:
		_objective("Prends la clé dans le coffret.")
	elif not _box_seen:
		_objective("Trouve la clé de la porte d’entrée." if _door_tried else "Trouve la sortie.")
	elif _found_count() >= 3:
		_objective("Tu as les trois chiffres : ouvre le coffret du salon.")
	else:
		var hint := ""
		if _has_ckey and not _chambre_open:
			hint = "La petite clé ouvre sa chambre."
		elif _has_fuse:
			hint = "Le fusible va au tableau, dans la cage d’escalier." if _board_seen else "Trouve le tableau où va le fusible."
		elif _power and not found[0]:
			hint = "Le chauffe-eau marche : fais couler l’eau chaude."
		elif (_hot_tried or _board_seen) and not _power:
			hint = "Il manque un fusible pour le chauffe-eau."
		_objective("Trouve les trois chiffres du coffret (%d/3).%s" % [_found_count(), (" " + hint) if hint != "" else ""])

# ====================================================================== start / reset

## The loading rehearsal shows the level to the renderer (and hides it again): with it, everything that only
## appears later in the chapter (lights that come on, the steam on the mirror, the figure in the bath...).
func prewarm(on: bool) -> void:
	if active:
		return
	visible = on
	if on:
		for e in _late:
			(e[0] as Node3D).visible = true
		var keep := _fog
		_set_fog(0.7)
		_fog = keep
		_seated.visible = true
	else:
		_apply_progress()

func begin() -> void:
	if not built:
		return
	active = true
	visible = true
	for n in [Game.world, Game.garderie]:
		if n is Node3D and is_instance_valid(n):
			(n as Node3D).visible = false
	_door_tried = false
	_reset_progress()
	_reset_level()
	var p := _player()
	if p != null:
		p.call("teleport", L.START, L.START_YAW, 0.0)
		if p.has_method("give_flashlight"):
			p.call("give_flashlight")
	_intro()

## The reflection probes hold a capture of the rooms as they were lit: taken again when the lights change, one room
## after the other (`rooms` empty = all of them).
func _recapture(delay: float, rooms: Array = []) -> void:
	if not is_inside_tree():
		return
	var list: Array = []
	if rooms.is_empty():
		list.append_array(_fx.get("probes", []))
		list.append_array((_fx.get("probes2", {}) as Dictionary).values())
	else:
		for r in rooms:
			if (_fx.get("probes2", {}) as Dictionary).has(r):
				list.append(_fx.probes2[r])
	await get_tree().create_timer(delay, false).timeout
	for rp in list:
		if rp is ReflectionProbe and is_instance_valid(rp):
			(rp as ReflectionProbe).update_mode = ReflectionProbe.UPDATE_ONCE
			await get_tree().create_timer(0.12, false).timeout

func _intro() -> void:
	if not await _wait(1.4):
		return
	_sfx("door_close", Vector3(float(L.HALL.x0), 1.0, 0.0), 2.0, 0.85)
	_kick(0.35)
	if not await _wait(1.8):
		return
	_say("Le rez-de-chaussée… La porte d’entrée est au bout du couloir.", 4.0)

## Everything the player found, opened and switched on: back to nothing, and a new code.
func _reset_progress() -> void:
	code = [randi_range(1, 9), randi_range(1, 9), randi_range(1, 9)]
	found = [false, false, false]
	_box_seen = false
	_box_open = false
	_box_tries = 0
	_has_fuse = false
	_board_seen = false
	_power = false
	_buffet_pushed = false
	_has_ckey = false
	_chambre_open = false
	_fridge_open = false
	_fridge_once = false
	_drawer_open = [false, false, false]
	_trap_done = false
	_curtain_open = false
	_pillow_up = false
	_hot_tried = false
	_fog = 0.0
	_cold_knock = false
	_bath_arm = false
	_bath_done = false
	_seat = 0
	_seat_want = 0
	_stair_gone = false
	_stair_want_gone = false
	_stair_seen = false
	_opened.clear()
	_piano_done = false
	_steps_done = false
	_hint_done = false
	_apply_code()
	_apply_progress()

## The digits, where they are read: the ring on the calendar, the glyph in the steam, the glyph on the slip.
func _apply_code() -> void:
	var g: Array = L.CAL_GRID
	var day: int = code[1]
	var u := float(g[0]) + (float(day % 7) + 0.5) * float(g[2])
	var v := float(g[1]) + (float(day / 7) + 0.5) * float(g[3])
	var cal: Vector3 = L.CALENDAR
	var sz: Vector2 = L.CAL_SIZE
	var ring := _region("et_cal_ring")
	if ring != null:
		ring.position = Vector3(cal.x + 0.0075, cal.y + (0.5 - v) * sz.y, cal.z - (u - 0.5) * sz.x)
	for pair in [["digit_fog", code[0]], ["digit_ink", code[2]]]:
		var m := ctx.mats.mat(String(pair[0])) as StandardMaterial3D
		var d: int = pair[1]
		m.uv1_scale = Vector3(0.2, 0.5, 1.0)
		m.uv1_offset = Vector3(0.2 * float(d % 5), 0.5 * float(d / 5), 0.0)

## Puts every prop of the rooms in the state the progress flags say (after a reset, after the loading rehearsal).
func _apply_progress() -> void:
	var fx: Dictionary = _fx
	_snap("fridge", 1.0 if _fridge_open else 0.0)
	_set_fridge_light(_fridge_open)
	for i in 3:
		_snap("drawer%d" % i, 1.0 if _drawer_open[i] else 0.0)
	_snap("buffet", 1.0 if _buffet_pushed else 0.0)
	_set_buffet_rect()
	_snap("butter", 1.0 if (_has_ckey or _chambre_open) else 0.0)
	(_region("et_ckey") as Node3D).visible = not (_has_ckey or _chambre_open)
	_snap("curtain", 1.0 if _curtain_open else 0.0)
	(fx.curtain_wide as CollisionShape3D).set_deferred("disabled", _curtain_open)
	_snap("pillow", 1.0 if _pillow_up else 0.0)
	_snap("box", 1.0 if _box_open else 0.0)
	(_region("et_fuse_item") as Node3D).visible = not (_has_fuse or _power)
	(_region("et_fuse_in") as Node3D).visible = _power
	(_region("et_plank_up") as Node3D).visible = not _stair_gone
	(_region("et_plank_down") as Node3D).visible = _stair_gone
	var lamp: Dictionary = fx.bain_lamp
	(lamp.light as Light3D).visible = _power
	(lamp.light as Light3D).light_energy = float(lamp.energy)
	(lamp.emit as StandardMaterial3D).emission_energy_multiplier = 2.6 if _power else 0.0
	(fx.pilot as StandardMaterial3D).emission_energy_multiplier = 3.0 if _power else 0.0
	_set_tap(true, false)
	_set_tap(false, false)
	_set_fog(_fog)
	for d in fx.bain_prints:
		if d != null:
			(d as Node3D).visible = _bath_done
	# the figures of these rooms
	for f in _figs:
		var id := String(f.get("id", ""))
		if id == "stairs":
			f.on = not _stair_gone
		elif id == "bath":
			f.on = _bath_done
		if id != "":
			_fig_show(f, f.on)
	_seat_place(_seat if _seat >= 0 else maxi(_seat_want, 0))
	if _key != null:
		_key.visible = stage < 2

func _fig_show(f: Dictionary, on: bool) -> void:
	f.on = on
	(f.node as Node3D).visible = on
	for c in (f.body as Node).get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).set_deferred("disabled", not on)

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
	_hum_hall = false
	_hum_at = L.HUM
	_hot = false
	_cold = false
	_hot_t = 0.0
	_mirror_look = 0.0
	for f in _figs:
		f.at_alt = false
		f.unseen = 0.0
		(f.node as Node3D).position = f.home
		(f.node as Node3D).rotation.y = float(f.yaw0)
	for w in _walkers:
		w.awake = false
		w.revealed = false
		w.unseen = 0.0
		w.stall = 0.0
		w.pos = w.home
		(w.node as Node3D).position = w.home
		(w.node as Node3D).rotation.y = 0.4
	for id in _doors:
		var d: Dictionary = _doors[id]
		var open: bool = _opened.has(id)
		d.a = 1.0 if open else 0.0
		d.goal = d.a
		(d.node as Node3D).rotation.y = lerpf(float(d.closed), float(d.open), float(d.a))
		_door_solid(id, not open)
	for s in _fx.get("sconces", []):
		s.alive = true
		(s.light as Light3D).visible = true
		(s.light as Light3D).light_energy = float(s.base)
		(s.emit as StandardMaterial3D).emission_energy_multiplier = 3.0
	_rock_on = false
	_apply_progress()
	_recapture(0.3)
	_stop_sounds()
	_start_ambience()
	_update_objective()

func _start_ambience() -> void:
	_theme = _loop("etage_theme", {"volume_db": -4.0})
	if _theme == null:
		_theme = _loop("ambience_drone", {"volume_db": -6.0})
	_tick = _loop("clock_tick", {"position": (L.CLOCK as Vector3) + Vector3(0, 1.8, 0.1), "volume_db": 6.0})
	for w in [Vector3(58.85, 1.6, -7.7), Vector3(63.15, 1.6, -7.7), Vector3(64.5, 1.6, 0.75), Vector3(60.9, 1.6, 5.1), Vector3(67.5, 3.8, -6.1)]:
		_winds.append(_loop("wind_outside", {"position": w, "volume_db": -2.0}))
	_loop_on("drip", "water_drip", {"position": Vector3(float(L.TUB.x1) - 0.1, 0.7, float(L.TUB.z0) + 0.35), "volume_db": -4.0})
	# the fridge still runs: heard from the kitchen doorway, louder once its door is open
	_loop_on("fridge", "fridge_hum", {"position": _fx.fridge_at, "volume_db": -3.0 if _fridge_open else -11.0})
	if _power:
		_loop_on("heater", "furnace", {"position": L.HEATER, "volume_db": -12.0, "pitch": 1.5})
		_loop_on("lamp", "light_buzz", {"position": (L.MIRROR as Vector3) + Vector3(0.1, 0.6, 0), "volume_db": -10.0})
	if not _chambre_open:
		_hum_start()

func _hum_start() -> void:
	if stage >= 2 or _hum != null or (_chambre_open and not _hum_hall):
		return
	_hum = _loop("lullaby_hum", {"position": _hum_at, "volume_db": -7.0 if not _hum_hall else -3.0, "filter_hz": 1100.0 if not _hum_hall else 3200.0})

func _hum_stop(pause: float) -> void:
	_stop(_hum, 0.12)
	_hum = null
	_hum_pause = maxf(_hum_pause, pause)

func _stop_sounds() -> void:
	for h in [_theme, _layer, _tick, _hum]:
		_stop(h, 0.3)
	for h in _winds:
		_stop(h, 0.3)
	for id in _loops.keys():
		_loop_off(id)
	_theme = null
	_layer = null
	_tick = null
	_hum = null
	_winds.clear()

## After being caught (Game calls it after the player's own reset): back at the top of the stairs, the key back in
## its box, the figures under their sheets, the walker asleep. What was found and opened stays so.
func reset_after_caught() -> void:
	if not active:
		return
	_reset_level()
	var p := _player()
	if p != null:
		p.call("teleport", L.START, L.START_YAW, 0.0)

## Everything as when the chapter starts (a new code too): for the tours and the tests.
func reset_all() -> void:
	if not active:
		return
	_door_tried = false
	stage = 0
	_reset_progress()
	_reset_level()
	var p := _player()
	if p != null:
		p.call("teleport", L.START, L.START_YAW, 0.0)

func _exit_tree() -> void:
	_stop_sounds()

# ====================================================================== the front door, her door, the box, the key

func _use_front() -> void:
	var at := Vector3(float(L.HALL.x1), 1.0, 0.0)
	if stage < 2:
		_sfx("door_locked", at, 0.0)
		if not _door_tried:
			_door_tried = true
			stage = 1
			_update_objective()
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

## Her door. Without its key: it gives a hand's width, then is pulled shut from inside. With the key from the
## butter dish: it opens on an empty room, the chair still rocking.
func _use_chambre() -> void:
	var at := Vector3((float(L.DOOR_CHAMBRE.x0) + float(L.DOOR_CHAMBRE.x1)) * 0.5, 1.0, float(L.HALL.z0) - 0.1)
	if _has_ckey:
		_busy = true
		_has_ckey = false
		_chambre_open = true
		_opened["chambre"] = true
		_sfx("unlock", at, 0.0)
		_hum_stop(100000.0)
		if not await _wait(0.7):
			return
		_sfx("door_creak_open", at, 0.0, 0.85)
		_doors.chambre.goal = 1.0
		_doors.chambre.speed = 0.45
		_door_solid("chambre", false)
		_rock_on = true
		_sfx("rocking_chair", _fx.rocker_pos, -2.0)
		_kick(0.6)
		_update_objective()
		if not await _wait(3.2):
			return
		_rock_on = false
		_say("(Personne. Le fauteuil bouge encore.)", 3.5)
		_busy = false
		return
	if _chambre_done:
		_sfx("door_locked", at, 0.0)
		_say("Fermée à clé, de l’intérieur.", 2.5)
		return
	_busy = true
	_chambre_done = true
	_sfx("door_creak_open", at, 0.0, 0.9)
	_doors.chambre.goal = 0.17
	_doors.chambre.speed = 0.35
	_rock_on = true
	_sfx("rocking_chair", _fx.rocker_pos, -2.0)
	if not await _wait(1.5):
		return
	_doors.chambre.goal = 0.0
	_doors.chambre.speed = 9.0
	_sfx("door_close", at, 5.0, 0.9)
	_hum_stop(11.0)
	_rock_on = false
	_kick(0.9)
	_flinch(0.9)
	Events.noise.emit(at, 0.5, "door")
	if not await _wait(1.6):
		return
	_say("(Quelqu’un tient la porte. La clé tourne, de l’autre côté.)", 3.5)
	_busy = false

## The box: the padlock view with three wheels. What has been found so far is recalled in its title.
func _use_box() -> void:
	if not _box_seen:
		_box_seen = true
		_update_objective()
		_say("Un coffret à trois molettes. La clé doit être dedans.", 3.5)
	var ui = Game.ui
	if ui == null or not is_instance_valid(ui) or not ui.has_method("show_keypad"):
		return
	ui.set("clues", {})                        # (the scrap of paper with the basement's clues is not for this lock)
	var names := ["miroir", "calendrier", "oreiller"]
	var parts: Array[String] = []
	for i in 3:
		parts.append("%s %s" % [names[i], str(code[i]) if found[i] else "?"])
	var title := "Coffret du salon — " + " · ".join(parts)
	var r = await Game.modal(func(): return await ui.show_keypad(title, 3))
	var s := ""
	for ch in str(r) if r != null else "":
		if ch >= "0" and ch <= "9":
			s += ch
	if s.length() == 3:
		try_code(s)

## Tries three digits on the box (the padlock view calls it; tests too). True when it opens.
func try_code(s: String) -> bool:
	if _box_open or stage >= 2:
		return false
	var at: Vector3 = _fx.box_at
	if s == "%d%d%d" % [code[0], code[1], code[2]]:
		_box_open = true
		for i in 3:
			found[i] = true
		_sfx("lock_success", at, 0.0)
		_sfx("box_open", at, 0.0)
		_move("box", 1.0)
		_update_objective()
		return true
	_box_tries += 1
	_sfx("lock_fail", at, 2.0)
	Events.noise.emit(at, 0.4, "lock")
	_hum_stop(9.0)
	_kick(0.4)
	# a wrong try: one of the sheets is found closer (never one that is being looked at)
	for f in _figs:
		if f.room == "salon" and not f.at_alt and not _seen((f.node as Node3D).position, float(f.h), f.body):
			f.at_alt = true
			(f.node as Node3D).position = f.alt
			_face(f, at)
			_sfx("house_creak", (f.alt as Vector3) + Vector3(0, 0.05, 0), -4.0, 0.9)
			break
	_say("Ça ne s’ouvre pas." if _box_tries < 2 else "Ça ne s’ouvre pas. (Quelque chose a bougé, derrière.)", 3.0)
	return false

func _take_key() -> void:
	if stage >= 2 or not _box_open:
		return
	stage = 2
	if _key != null:
		_key.visible = false
	_sfx("key_pickup", _fx.key_pos, 0.0)
	_update_objective()
	_awaken()

## What the house does once the key has left its box.
func _awaken() -> void:
	_hum_hall = false
	_hum_stop(100000.0)
	_seat_want = -1                         # the kitchen chair is found empty
	if not await _wait(0.7):
		return
	_stop(_tick, 0.0)                      # the clock stops
	_tick = null
	if not await _wait(0.9):
		return
	var sc: Array = _fx.get("sconces", [])
	for i in range(sc.size() - 1, -1, -1):
		var s: Dictionary = sc[i]
		s.alive = false
		(s.light as Light3D).visible = false
		(s.emit as StandardMaterial3D).emission_energy_multiplier = 0.0
		_sfx("light_pop", (s.light as Node3D).global_position, -4.0, 1.0 + 0.08 * i)
		if not await _wait(0.42):
			return
	# the fridge is found open: with the lamps out, its light is all that comes from the kitchen doorway
	if not _fridge_open:
		_fridge_open = true
		_snap("fridge", 1.0)
		_set_fridge_light(true)
		_vol(_loops.get("fridge"), -3.0)
	# her door stands open now (nobody saw it move), the bed is empty
	_doors.chambre.a = 1.0
	_doors.chambre.goal = 1.0
	(_doors.chambre.node as Node3D).rotation.y = float(_doors.chambre.open)
	_door_solid("chambre", false)
	_recapture_old(0.2)
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
			if L.room_of(q) == L.room_of(p.global_position) and L.in_box(L.ROOMS[L.room_of(q)], q, -0.45) and not _blocked(q, w):
				w.pos = q
				break
	(w.node as Node3D).position = w.pos
	_face(w, p.global_position if p != null else w.pos + Vector3.BACK)
	w.awake = true
	w.unseen = 0.0
	_closet_t = 5.0

## The probes of the hallway, the salon and her bedroom (their lights just changed).
func _recapture_old(delay: float) -> void:
	if not is_inside_tree():
		return
	await get_tree().create_timer(delay, false).timeout
	for rp in _fx.get("probes", []):
		if rp is ReflectionProbe:
			(rp as ReflectionProbe).update_mode = ReflectionProbe.UPDATE_ONCE

# ====================================================================== la cuisine, le garde-manger

func _use_calendar() -> void:
	var first: bool = not found[1]
	found[1] = true
	_say("(Novembre 1994. Barré jusqu’au 11. Le %d est entouré de rouge.)" % int(code[1]), 4.5)
	_update_objective()
	if first and _seat == 0:
		_seat_want = 1

func _set_fridge_light(on: bool) -> void:
	var f: Dictionary = _fx.fridge
	(f.light as Light3D).visible = on
	(f.fill as Light3D).visible = on
	(f.emit as StandardMaterial3D).emission_energy_multiplier = 5.0 if on else 0.0

func _use_fridge() -> void:
	_fridge_open = not _fridge_open
	var at: Vector3 = _fx.fridge_at
	_move("fridge", 1.0 if _fridge_open else 0.0)
	if _fridge_open:
		_sfx("cabinet_open", at, 0.0, 0.8)
		_set_fridge_light(true)
		_vol(_loops.get("fridge"), -3.0)
		if not _fridge_once:
			_fridge_once = true
			_kick(0.35)
			if _seat == 0:
				_seat_want = 1
			_say_later(1.4, "(Il marche encore. Le beurrier a une cloche.)", 3.5, func() -> bool: return _fridge_open)
	else:
		_sfx("cabinet_close", at, 0.0, 0.8)
		_fridge_dark()

## The light goes out as the door meets the cabinet.
func _fridge_dark() -> void:
	if await _wait(0.5) and not _fridge_open:
		_set_fridge_light(false)
		_vol(_loops.get("fridge"), -11.0)

func _use_butter() -> void:
	if _has_ckey or _chambre_open:
		return
	var at: Vector3 = _fx.butter
	_move("butter", 1.0)
	_sfx("cabinet_open", at, -6.0, 1.5)
	if not await _wait(0.75):
		return
	_has_ckey = true
	(_region("et_ckey") as Node3D).visible = false
	_sfx("key_pickup", at, 0.0)
	_say("Une petite clé, sous la cloche. L’étiquette dit : « chambre ».", 4.0)
	_update_objective()

func _use_drawer(i: int) -> void:
	_drawer_open[i] = not _drawer_open[i]
	var at: Vector3 = _fx.drawers[i]
	_move("drawer%d" % i, 1.0 if _drawer_open[i] else 0.0)
	_sfx("drawer_open" if _drawer_open[i] else "drawer_close", at, 0.0)
	if not _drawer_open[i]:
		return
	if i == 1 and not _trap_done:
		_trap_done = true
		_trap(at)
	elif i == 2:
		_say_later(0.5, "(Des bougies, de la ficelle, des allumettes mouillées.)", 3.0)

## The mousetrap goes off as the drawer jolts open.
func _trap(at: Vector3) -> void:
	if not await _wait(0.3):
		return
	_sfx("lock_fail", at, 6.0, 1.6)
	_sfx("bump", at, 3.0, 1.4)
	_kick(0.7)
	_flinch(0.7)
	Events.noise.emit(at, 0.5, "trap")
	_hum_stop(9.0)
	_say_later(1.2, "(Une tapette. Elle était tendue.)", 3.0)

func _set_buffet_rect() -> void:
	var B: Array = L.BUFFET
	var dz: float = float(L.BUFFET_PUSH) if _buffet_pushed else 0.0
	_obstacles[_buffet_rect] = Rect2(float(B[0]) - 0.2, float(B[1]) + dz - 0.2, float(B[2]) - float(B[0]) + 0.4, float(B[3]) - float(B[1]) + 0.4)

func _push_buffet() -> void:
	if _buffet_pushed:
		return
	var pl := _player()
	if pl != null and pl.global_position.z > float(L.BUFFET[3]) - 0.1 and pl.global_position.x < float(L.BUFFET[2]) + 0.3:
		_say("(Pas de ce côté : c’est vers ici qu’il doit glisser.)", 3.0)       # the player stands where it is going
		return
	_busy = true
	_buffet_pushed = true
	var at: Vector3 = (_fx.buffet_pos as Vector3) + Vector3(0.3, 0.5, 0.6)
	_sfx("furniture_drag", at, 3.0)
	_move("buffet", 1.0)
	Events.noise.emit(at, 0.8, "furniture")
	_hum_stop(14.0)
	_kick(0.4)
	_set_buffet_rect()
	_buffet_event()

func _buffet_event() -> void:
	if not await _wait(2.9):
		return
	_busy = false
	# something answers from behind the door it was hiding
	var door := Vector3(float(L.CUISINE.x0) - 0.1, 1.0, (float(L.DOOR_CELLIER.z0) + float(L.DOOR_CELLIER.z1)) * 0.5)
	if not await _wait(0.9):
		return
	_sfx("knock_wall", door, 2.0, 1.1)
	_kick(0.7)
	_say_later(1.6, "(Une porte, derrière. « Ne pas ouvrir. »)", 3.5)

func _use_cellier() -> void:
	_open_door("cellier", 0.5)

## Opens a door for good (the player's hand, or the walker's).
func _open_door(id: String, speed := 0.6, quiet := false) -> void:
	var d: Dictionary = _doors.get(id, {})
	if d.is_empty() or float(d.goal) > 0.5:
		return
	d.goal = 1.0
	d.speed = speed
	_opened[id] = true
	_door_solid(id, false)
	var at: Vector3 = ((d.body as Node).get_child(0) as Node3D).global_position
	_sfx("door_creak_open", at, -8.0 if quiet else 0.0, 0.9)
	if id == "esc" and not quiet:
		_kick(0.3)

func _take_fuse() -> void:
	if _has_fuse or _power:
		return
	_has_fuse = true
	(_region("et_fuse_item") as Node3D).visible = false
	_sfx("pickup", L.FUSE_TIN, 0.0)
	_say("Un fusible de porcelaine. Dix ampères.", 3.0)
	_update_objective()
	_fuse_event()

## The pantry door shuts on the player (only if they stand well inside), and the sheet on the floor stirs.
func _fuse_event() -> void:
	var p := _player()
	if p == null or L.room_of(p.global_position) != "cellier" or p.global_position.x > float(L.CELLIER.x1) - 0.55:
		_seat_want = 2
		return
	if not await _wait(0.8):
		return
	var d: Dictionary = _doors.cellier
	d.goal = 0.0
	d.speed = 0.9
	_opened.erase("cellier")
	_door_solid("cellier", true)
	var at := Vector3(float(L.CELLIER.x1), 1.0, (float(L.DOOR_CELLIER.z0) + float(L.DOOR_CELLIER.z1)) * 0.5)
	_sfx("door_creak_open", at, -2.0, 1.2)
	if not await _wait(1.0):
		return
	_sfx("door_close", at, 3.0, 0.9)
	_kick(0.8)
	_flinch(0.6)
	_seat_want = 2
	if not await _wait(1.4):
		return
	_sfx("cloth_move", (_fx.heap as Vector3) + Vector3(0, 0.2, 0), 2.0, 0.8)
	_say_later(1.2, "(La porte. Et ce drap, par terre : il n’y a rien dessous.)", 4.0)

## The one at the kitchen table: found on another chair, never seen moving.
func _seat_place(i: int) -> void:
	if _seated == null:
		return
	var on := i >= 0
	_seated.visible = on
	for c in _seated_body.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).set_deferred("disabled", not on)
	if on:
		var ch: Array = L.CHAIRS[i]
		_seated.position = ch[0]
		_seated.rotation.y = float(ch[1])

func _tick_seated(dt: float) -> void:
	if _seated == null or _seat_want == _seat:
		return
	if _seat >= 0 and _seen(_seated.position, 1.3, _seated_body):
		_seat_unseen = 0.0
		return
	if _seat_want >= 0 and _seen(L.CHAIRS[_seat_want][0], 1.3, _seated_body):
		_seat_unseen = 0.0
		return
	_seat_unseen += dt
	if _seat_unseen < 0.7:
		return
	_seat_unseen = 0.0
	_seat = _seat_want
	_seat_place(_seat)
	if _seat >= 0:
		_sfx("house_creak", (L.CHAIRS[_seat][0] as Vector3) + Vector3(0, 0.3, 0), -4.0, 1.2)
		_sfx("cloth_move", (L.CHAIRS[_seat][0] as Vector3) + Vector3(0, 0.9, 0), -6.0, 0.8)

# ====================================================================== la cage d'escalier

func _use_fusebox() -> void:
	var at: Vector3 = L.FUSE_BOARD
	if not _has_fuse:
		_board_seen = true
		_sfx("lock_fail", at, -6.0, 0.7)
		_say("Il manque un fusible. Le 5 : « chauffe-eau », et à la main : « salle de bain ».", 4.5)
		_update_objective()
		return
	_has_fuse = false
	_board_seen = true
	_power = true
	(_region("et_fuse_in") as Node3D).visible = true
	_sfx("breaker_flip", at, 2.0)
	_sfx("power_up", at, -2.0)
	_update_objective()
	_power_on()
	_stair_event()

## The fuse is in: the water heater lights, the bathroom lamp comes on (stuttering first).
func _power_on() -> void:
	var lamp: Dictionary = _fx.bain_lamp
	var l: Light3D = lamp.light
	var em: StandardMaterial3D = lamp.emit
	(_fx.pilot as StandardMaterial3D).emission_energy_multiplier = 3.0
	_loop_on("heater", "furnace", {"position": L.HEATER, "volume_db": -12.0, "pitch": 1.5})
	l.visible = true
	for k in [0.2, 0.0, 0.5, 0.1, 0.8, 0.3, 1.0]:
		l.light_energy = float(lamp.energy) * float(k)
		em.emission_energy_multiplier = 2.6 * float(k)
		if not await _wait(0.09):
			return
	_loop_on("lamp", "light_buzz", {"position": (L.MIRROR as Vector3) + Vector3(0.1, 0.6, 0), "volume_db": -10.0})
	_recapture(0.3, ["bain"])
	# the hallway's lamps dip as the heater draws
	for s in _fx.get("sconces", []):
		if s.alive:
			(s.light as Light3D).light_energy = float(s.base) * 0.45
	if not await _wait(0.5):
		return
	for s in _fx.get("sconces", []):
		if s.alive:
			(s.light as Light3D).light_energy = float(s.base)
	if await _wait(1.4):
		_say("(Quelque chose s’est rallumé, à l’autre bout de la maison.)", 4.0)

## Behind the player's back as the fuse goes in: a board comes off the stairs, and what stood at the top is gone.
func _stair_event() -> void:
	if _stair_gone:
		return
	if not await _wait(1.3):
		return
	_stair_gone = true
	_stair_want_gone = true
	(_region("et_plank_up") as Node3D).visible = false
	(_region("et_plank_down") as Node3D).visible = true
	var at := Vector3(67.3, 0.1, float(L.STAIR.z_foot) + 0.6)
	_sfx("land_thump", at, 6.0, 1.1)
	_sfx("bump", at, 4.0, 0.8)
	_kick(0.9)
	_flinch(0.8)
	_hum_stop(12.0)
	Events.noise.emit(at, 0.6, "plank")
	if not await _wait(2.2):
		return
	_sfx("ceiling_steps", Vector3(66.2, 3.0, -3.0), 3.0)
	if await _wait(2.5):
		_say("(Une planche est tombée. Il n’y a plus personne, là-haut.)", 4.0)

# ====================================================================== la salle de bain

func _set_tap(hot: bool, on: bool) -> void:
	var n := _region("et_stream_hot" if hot else "et_stream_cold")
	if n != null:
		n.visible = on
	if hot:
		_hot = on
	else:
		_cold = on
	var id := "tap_hot" if hot else "tap_cold"
	if on:
		_loop_on(id, "tap_run", {"position": _fx.tap_hot if hot else _fx.tap_cold, "volume_db": -2.0, "pitch": 1.0 if hot else 1.08})
	else:
		_loop_off(id, 0.15)
	var steam: GPUParticles3D = _fx.steam
	if steam != null and not (_hot and _power):
		steam.emitting = false

func _use_tap(hot: bool) -> void:
	var on: bool = not (_hot if hot else _cold)
	_set_tap(hot, on)
	var at: Vector3 = _fx.tap_hot if hot else _fx.tap_cold
	_sfx("stall_creak", at, -6.0, 1.7)
	if not on:
		return
	_hum_stop(8.0)
	if hot:
		_hot_t = 0.0
		if not _power:
			var first := not _hot_tried
			_hot_tried = true
			_update_objective()
			if first:
				_say_later(2.0, "L’eau reste glacée. Le chauffe-eau est éteint : plus de courant de ce côté-là.", 4.5, func() -> bool: return _hot)
	elif not _cold_knock:
		_cold_knock = true
		_cold_answer()

## Cold water: the pipes answer, three blows, from the wall behind the bath.
func _cold_answer() -> void:
	if not await _wait(2.6) or not _cold:
		return
	_sfx("pipe_knock", Vector3(float(L.BAIN.x0), 1.0, 3.9), 4.0)
	_kick(0.6)
	_say_later(2.6, "(Les tuyaux. Trois coups.)", 3.0)

func _set_fog(v: float) -> void:
	_fog = clampf(v, 0.0, 1.0)
	var n := _region("et_mirror_fx")
	if n != null:
		n.visible = _fog > 0.01
	var fm := ctx.mats.mat("fog_mirror") as StandardMaterial3D
	fm.albedo_color.a = _fog * 0.92
	var dm := ctx.mats.mat("digit_fog") as StandardMaterial3D
	dm.albedo_color.a = smoothstep(0.55, 1.0, _fog) * 0.85

func _tick_bain(dt: float, pp: Vector3) -> void:
	var steam: GPUParticles3D = _fx.steam
	if _hot and _power:
		var before := _hot_t
		_hot_t += dt
		if steam != null and _hot_t > 2.0 and not steam.emitting:
			steam.emitting = true
		_set_fog(_fog + dt / FOG_TIME)
		# the pipes answer the running water: far first, then from the bath itself
		if before < 3.5 and _hot_t >= 3.5:
			_sfx("pipe_knock", Vector3(float(L.BAIN.x0), 1.0, 3.9), 3.0)
			_kick(0.5)
		if before < 7.5 and _hot_t >= 7.5:
			_sfx("pipe_knock", Vector3(float(L.TUB.x0) + 0.8, 0.4, float(L.TUB.z0) + 0.3), 6.0, 0.92)
			_sfx("curtain_rings", Vector3(float(L.CURTAIN.x0) + 0.9, 1.9, float(L.CURTAIN.z)), -8.0, 0.8)
			_kick(0.7)
	elif _fog > 0.0 and not _bath_arm:
		_set_fog(_fog - dt / 45.0)
	elif _fog > 0.0:
		_set_fog(_fog - dt / 120.0)
	# the digit is read by looking at the glass from close
	if _fog > 0.9 and not found[0]:
		var cam := Game.camera
		var m: Vector3 = L.MIRROR
		if cam != null and cam.global_position.distance_to(m) < 1.7 and (-cam.global_transform.basis.z).dot((m - cam.global_position).normalized()) > 0.86:
			_mirror_look += dt
			if _mirror_look > 0.8:
				_read_mirror()
		else:
			_mirror_look = 0.0
	# once it has been read: the curtain is found drawn back, and something stands in the bath
	if _bath_arm and not _bath_done:
		var c := Vector3(float(L.TUB.x0) + 0.8, 1.1, float(L.CURTAIN.z))
		var cam2 := Game.camera
		var looking: bool = cam2 != null and cam2.is_position_in_frustum(c) and L.room_of(pp) == "bain"
		_bath_unseen = 0.0 if looking else _bath_unseen + dt
		if _bath_unseen > 0.5:
			_bath_event()

func _read_mirror() -> void:
	if found[0] or _fog < 0.85:
		return
	found[0] = true
	_say("(Un chiffre, tracé du doigt dans la buée : %d.)" % int(code[0]), 4.5)
	_update_objective()
	_bath_arm = true
	_bath_unseen = 0.0

func _bath_event() -> void:
	_bath_done = true
	var at := Vector3(float(L.CURTAIN.x0) + 0.5, 1.6, float(L.CURTAIN.z))
	if not _curtain_open:
		_curtain_open = true
		_snap("curtain", 1.0)
		(_fx.curtain_wide as CollisionShape3D).set_deferred("disabled", true)
		_sfx("curtain_rings", at, 4.0)
	else:
		_sfx("cloth_move", at, 3.0, 0.8)
	for f in _figs:
		if String(f.get("id", "")) == "bath":
			(f.node as Node3D).position = f.home
			_fig_show(f, true)
			var p := _player()
			if p != null:
				_face(f, p.global_position)
	for d in _fx.bain_prints:
		if d != null:
			(d as Node3D).visible = true
	_sfx("water_drip", at + Vector3(0.4, -1.0, 0.4), 4.0)
	_kick(1.0)

func _use_curtain() -> void:
	_curtain_open = not _curtain_open
	_move("curtain", 1.0 if _curtain_open else 0.0)
	(_fx.curtain_wide as CollisionShape3D).set_deferred("disabled", _curtain_open)
	var at := Vector3(float(L.CURTAIN.x0) + 0.7, 1.6, float(L.CURTAIN.z))
	_sfx("curtain_rings", at, 0.0)
	Events.noise.emit(at, 0.3, "curtain")
	if _curtain_open and not _bath_done:
		_kick(0.4)
		_say_later(1.3, "(De l’eau noire, jusqu’au bord. Rien d’autre.)", 3.5, func() -> bool: return _curtain_open and not _bath_done)

# ====================================================================== sa chambre

func _lift_pillow() -> void:
	if _pillow_up:
		return
	_pillow_up = true
	found[2] = true
	_move("pillow", 1.0)
	_sfx("cloth_move", _fx.pillow_pos, 2.0)
	_update_objective()
	_pillow_event()

func _pillow_event() -> void:
	if not await _wait(1.2):
		return
	_say("(Un papier plié, sous l’oreiller. Un seul chiffre : %d.)" % int(code[2]), 4.5)
	if not await _wait(2.4) or stage >= 2:
		return
	# she hums again — in the hallway now, just outside her own door
	_hum_hall = true
	_hum_at = Vector3((float(L.DOOR_CHAMBRE.x0) + float(L.DOOR_CHAMBRE.x1)) * 0.5, 1.5, -0.2)
	_hum_pause = 0.0
	_stop(_hum, 0.1)
	_hum = null
	_hum_start()
	_kick(0.7)

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

## Where a walker can stand: inside a room (not against its walls) or in a doorway.
func _walkable(p: Vector3) -> bool:
	for id in L.ROOMS:
		if L.in_box(L.ROOMS[id], p, -0.22):
			return true
	for id in L.PORTALS:
		var P: Array = L.PORTALS[id]
		if id == "cellier" and not _buffet_pushed:
			continue
		var a: Vector3 = P[1]
		var b: Vector3 = P[2]
		var axis := (b - a).normalized()
		var rel := p - a
		var along := rel.dot(axis)
		if along > -0.3 and along < a.distance_to(b) + 0.3 and (rel - axis * along).length() < float(P[3]):
			return true
	return false

func _blocked(p: Vector3, me: Dictionary) -> bool:
	if not _walkable(p):
		return true
	var v := Vector2(p.x, p.z)
	for r in _obstacles:
		if (r as Rect2).has_point(v):
			return true
	for f in _figs:
		if f.on and Vector2(f.node.position.x - p.x, f.node.position.z - p.z).length() < 0.62:
			return true
	if _seat >= 0 and _seated != null and Vector2(_seated.position.x - p.x, _seated.position.z - p.z).length() < 0.6:
		return true
	for w in _walkers:
		if not is_same(w, me) and Vector2(w.pos.x - p.x, w.pos.z - p.z).length() < 0.62:
			return true
	return false

## Next point to walk to, from one room to another through the doorways (rooms are convex: inside one, straight).
## A shut door on the way opens before the walker.
func _route(from: Vector3, to: Vector3) -> Vector3:
	var ra := L.room_of(from)
	var rb := L.room_of(to)
	if ra == rb:
		return to
	var chain: Array = L.room_chain(rb)
	var i := chain.find(ra)
	var room := ""                                  # the room whose doorway is crossed
	var first := Vector3.ZERO
	var second := Vector3.ZERO
	if i >= 0:
		room = chain[i + 1]                         # down into a room that hangs from this one
		first = L.PORTALS[room][1]
		second = L.PORTALS[room][2]
	else:
		room = ra                                   # back out toward the hallway
		first = L.PORTALS[room][2]
		second = L.PORTALS[room][1]
	var axis := (second - first).normalized()
	var rel := from - first
	var along := rel.dot(axis)
	var lateral := (rel - axis * along).length()
	if lateral < 0.2 and along > -0.25:
		var id := String(ROOM_DOOR.get(room, ""))
		if id != "" and _doors.has(id) and float(_doors[id].goal) < 0.5:
			_open_door(id, 0.5, true)
		return second + axis * 0.3
	return first

func _tick_walker(w: Dictionary, dt: float, pp: Vector3) -> void:
	if not w.awake or _catching:
		return
	var n: Node3D = w.node
	if _seen(w.pos, float(w.h), w.body):
		w.unseen = 0.0
		w.stall = 0.0
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
	var same: bool = L.room_of(pp) == L.room_of(w.pos)
	if dist < CATCH_DIST and same:
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
		# slide along what is in the way, on the axis that still leads somewhere (not on one the goal is already
		# level with: it would only shuffle on the spot)
		var sl := step.length()
		if absf(step.x) > sl * 0.25 and not _blocked(ax, w):
			np = w.pos + Vector3(signf(step.x) * sl, 0, 0)
		elif absf(step.z) > sl * 0.25 and not _blocked(az, w):
			np = w.pos + Vector3(0, 0, signf(step.z) * sl)
		else:
			# wedged: sidestep around the obstacle
			w.stuck += dt
			var side := Vector3(-dir.z, 0, dir.x).normalized() * (1.0 if int(w.stuck * 0.7) % 2 == 0 else -1.0)
			np = w.pos + side * step.length()
			if _blocked(np, w):
				# nowhere to go: a player who squeezed into a corner next to it is not safe there for ever
				w.stall += dt
				if w.stall > 2.0 and same and dist < 1.7:
					_catch(w)
				return
	w.stall = 0.0
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
## They only do it while the player is in their room or at its doorway, and not more than once every second and a
## half each: every turn of a shadow caster makes the light over it re-render its shadow map.
func _tick_figures(dt: float, pp: Vector3) -> void:
	var here := L.room_of(pp)
	for f in _figs:
		if not f.on:
			continue
		var n: Node3D = f.node
		f.cool = maxf(float(f.get("cool", 0.0)) - dt, 0.0)
		var door: Vector3 = L.PORTALS[f.room][1]
		var near: bool = here == f.room or Vector2(pp.x - door.x, pp.z - door.z).length() < 1.7
		var can_alt: bool = stage == 2 and not f.at_alt and f.alt != null
		var leaving: bool = String(f.get("id", "")) == "stairs" and _stair_want_gone
		if not near and not can_alt and not leaving:
			continue
		if _seen(n.position, float(f.h), f.body):
			f.unseen = 0.0
			if String(f.get("id", "")) == "stairs" and not _stair_seen and here == "escalier":
				_stair_seen = true
				_sfx("stinger", n.position + Vector3(0, 1.0, 0), -12.0, 0.8)
				_kick(0.7)
			continue
		f.unseen += dt
		if leaving:
			if f.unseen > 0.15:
				_fig_show(f, false)
			continue
		if f.unseen < 0.8 or float(f.cool) > 0.0:
			continue
		var moved := false
		if can_alt and f.unseen > 1.6 and not _seen(f.alt, float(f.h), f.body):
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
	_flinch(1.2)
	var q := _seq
	await get_tree().create_timer(0.85, false).timeout
	if p != null and is_instance_valid(p):
		p.set("enabled", true)
	if q != _seq:
		return
	_stop(_layer, 0.2)
	_layer = null
	Game.on_caught()

# ====================================================================== doors, movers, boards, events

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
	for id in _movers:
		var m: Dictionary = _movers[id]
		if is_equal_approx(float(m.a), float(m.goal)):
			continue
		m.a = move_toward(float(m.a), float(m.goal), dt * float(m.speed))
		(m.fn as Callable).call(float(m.a))
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
		if _creaks.size() >= 3 and not _chambre_done and not _chambre_open:
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
	var here := L.room_of(pp)
	# the humming comes back when the house has been quiet long enough
	if _hum_pause > 0.0:
		_hum_pause -= dt
		if _hum_pause <= 0.0:
			_hum_start()
	# in the hallway, outside her door: it stops dead when the player comes to see
	if _hum_hall and (here == "hall" or pp.distance_to(_hum_at) < 1.6):
		_hum_hall = false
		_hum_stop(100000.0)
		_kick(0.8)
		_sfx("ceiling_steps", Vector3(pp.x + 3.0, 3.2, pp.z), 2.0)
	# wood settling somewhere around, sometimes overhead
	_creak_t -= dt
	if _creak_t <= 0.0:
		_creak_t = randf_range(5.0, 12.0) if stage < 2 else randf_range(3.0, 7.0)
		var a := randf() * TAU
		var r := randf_range(4.0, 8.0)
		var q := Vector3(clampf(pp.x + cos(a) * r, 52.0, 68.0), [0.1, 1.4, 3.1][randi() % 3], clampf(pp.z + sin(a) * r, -7.8, 5.2))
		_sfx("house_creak", q, randf_range(-5.0, 0.0), randf_range(0.85, 1.1))
	# footsteps cross the ceiling once, while the key is being looked for
	if stage == 1 and not _steps_done and here == "salon":
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
		if not _chime_done and here == "hall" and absf(pp.x - L.CLOCK.x) < 1.1:
			_chime_done = true
			_sfx("clock_chime", (L.CLOCK as Vector3) + Vector3(0, 1.8, 0.1), 5.0)
			_kick(0.8)
		# fingers on the hallway window as the player goes by it
		if not _tap_done and here == "hall" and pp.x > float(L.WIN_HALL[0]) - 0.2 and pp.x < float(L.WIN_HALL[1]) + 0.4:
			_tap_done = true
			_sfx("window_tap", Vector3((float(L.WIN_HALL[0]) + float(L.WIN_HALL[1])) * 0.5, 1.5, float(L.HALL.z1) + 0.1), 6.0)
			_kick(0.6)
		# the closet door opens by itself behind the player; what stands in it starts walking a little later
		if _closet_t > 0.0 and here == "hall":
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
	if stage < 2 and L.room_of(pp) in ["cuisine", "cellier", "bain", "escalier"]:
		target = 0.2                                   # the dark rooms weigh a little more than the lit hallway
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
	_tick_bain(dt, pp)
	_tick_seated(dt)
	_tick_figures(dt, pp)
	for w in _walkers:
		_tick_walker(w, dt, pp)
	_tick_fear(dt, pp)
