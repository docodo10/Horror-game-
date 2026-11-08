## STUB — core module replaces it (ARCHITECTURE_PC.md §World). Builds a placeholder room so other modules can run.
## Public API (keep):
##   build(progress: Callable) -> void (await)        progress.call(0..1, text)
##   set_power(on: bool)   power: bool
##   handles: Dictionary[String, Handle]   (Handle = scripts/world/handle.gd: open()/close()/toggle() awaitable, is_open, locked, node, world_position())
##   items: Dictionary[String, Node3D]     clues: Dictionary[String, Node3D]   tv (Node with is_on, set_on(on), set_digit(d), screen_position)
##   hide_spots: Array[Dictionary]  ({id, door: Handle, hide_pos: Vector3, hide_yaw: float, exit_pos: Vector3})
##   nav: AStar3D over Layout.NAV_NODES/NAV_LINKS; nav_path(from, to) -> PackedVector3Array; nearest_nav_id(pos) -> int; random_nav_near(pos, r) -> Vector3
##   line_blocked(from: Vector3, to: Vector3) -> bool   (physics ray on LAYER_WORLD)
##   ground_height_at(x, z, prev_y := NAN) -> float
##   lighting (Node: scripts/world/lighting.gd)  set_clue_digits(d: Dictionary)
##   reset_after_caught()
extends Node3D

const LAYER_WORLD := 1      # walls, floors, furniture (blocks movement + sight)
const LAYER_INTERACT := 2   # interactable trigger bodies (interaction ray only)
const LAYER_PLAYER := 4
const LAYER_ENTITY := 8

var power := true
var handles := {}
var items := {}
var clues := {}
var tv: Node = null
var hide_spots: Array = []
var nav := AStar3D.new()
var nav_ids := {}
var lighting: Node = null

func build(progress: Callable) -> void:
	progress.call(0.5, "Construction du sous-sol…")
	var R := Layout.ROOM
	_box(Vector3((R.minX + R.maxX) / 2, -0.05, (R.minZ + R.maxZ) / 2), Vector3(R.maxX - R.minX, 0.1, R.maxZ - R.minZ))
	for w in [[0, R.minZ - 0.1, 7.4, 0.2], [0, R.maxZ + 0.1, 7.4, 0.2], [R.minX - 0.1, 0, 0.2, 5.9], [R.maxX + 0.1, 0, 0.2, 5.9]]:
		_box(Vector3(w[0], R.ceilingY / 2, w[1]), Vector3(w[2], R.ceilingY, w[3]))
	var l := OmniLight3D.new(); l.position = Vector3(Layout.FAN.x, 2.0, Layout.FAN.z); l.light_energy = 2.0; l.shadow_enabled = true; l.omni_range = 10; add_child(l)
	var env := WorldEnvironment.new(); var e := Environment.new(); e.background_mode = Environment.BG_COLOR; e.background_color = Color.BLACK; e.ambient_light_color = Color(0.2, 0.2, 0.25); e.ambient_light_energy = 0.3; env.environment = e; add_child(env)
	for id in Layout.NAV_NODES:
		var n: Dictionary = Layout.NAV_NODES[id]
		var y := Layout.UPPER.floorY if n.get("upper", false) else Layout.ground_height_at(n.x, n.z)
		var i := nav_ids.size(); nav_ids[id] = i; nav.add_point(i, Vector3(n.x, y, n.z))
	for link in Layout.NAV_LINKS: nav.connect_points(nav_ids[link[0]], nav_ids[link[1]])
	progress.call(1.0, "Prêt")

func _box(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new(); body.collision_layer = LAYER_WORLD; body.position = pos
	var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = size; cs.shape = sh; body.add_child(cs)
	var mi := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = size; mi.mesh = bm; body.add_child(mi)
	add_child(body)

func set_power(on: bool) -> void:
	power = on
	Events.power_changed.emit(on)

func set_clue_digits(_d: Dictionary) -> void: pass

func ground_height_at(x: float, z: float, prev_y := NAN) -> float: return Layout.ground_height_at(x, z, prev_y)

func line_blocked(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func nearest_nav_id(pos: Vector3) -> int: return nav.get_closest_point(pos)

func nav_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var p := nav.get_point_path(nearest_nav_id(from), nearest_nav_id(to))
	p.append(to)
	return p

func random_nav_near(pos: Vector3, r := 3.0) -> Vector3:
	var c := []
	for id in nav.get_point_ids():
		var p := nav.get_point_position(id)
		if p.y < 1.0 and Vector2(p.x - pos.x, p.z - pos.z).length() <= r: c.append(p)
	return c.pick_random() if not c.is_empty() else pos

func reset_after_caught() -> void: pass
