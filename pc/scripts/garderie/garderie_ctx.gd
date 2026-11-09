## Build context shared by the garderie builders: region kits (geometry bins), region colliders, the material
## factory, and the lists of gameplay things the builders create (lights, flickers, interactables, slides…).
extends RefCounted

const Kit := preload("res://scripts/garderie/garderie_kit.gd")
const LAYER_WORLD := 1
const LAYER_SIGHT := 16        # sight occluders (world.line_blocked casts on this layer only)

var root: Node3D
var mats                         # garderie_mats.gd instance
var kits := {}                   # region -> Kit
var cols := {}                   # region -> Kit.Col
var regions := {}                # region -> Node3D
var lights: Array = []           # [{light: Light3D, state: String, zone: String, emit: Material or null, base: float}]
var emitters: Array = []         # [{mat: StandardMaterial3D, base: float}] for flicker / power changes
var signs: Array = []            # sign lights (always on)
var interact: Array = []         # [{id, node, prompt, ...}] registered later with Game.interaction
var slides := {}                 # id -> {curve: Curve3D, top: Vector3, exit: Vector3, yaw: float, kind}
var door: Dictionary = {}        # pivot, closed, open, leaf body
var occluders: Array = []        # AABB list (OccluderInstance3D boxes)
var probes: Array = []
var notes: Array[String] = []

func region(name: String) -> Node3D:
	if not regions.has(name):
		var n := Node3D.new()
		n.name = name.capitalize().replace(" ", "")
		root.add_child(n)
		regions[name] = n
	return regions[name]

func kit(name: String):
	if not kits.has(name):
		kits[name] = Kit.new()
	return kits[name]

## Opaque colliders: block movement (WORLD) and La Gardienne's sight (SIGHT, world.line_blocked).
func col(name: String):
	if not cols.has(name):
		cols[name] = Kit.Col.new(region(name), "Colliders", LAYER_WORLD | LAYER_SIGHT)
	return cols[name]

## See-through colliders (nets, railings, posts, chairs): block movement only.
func col_see(name: String):
	var key := name + "#see"
	if not cols.has(key):
		cols[key] = Kit.Col.new(region(name), "CollidersSeeThrough", LAYER_WORLD)
	return cols[key]

const FRONT_REGIONS := ["corr", "vest", "door", "props_v"]

## Commits every kit into its region node. opts per region: {region: {no_shadow: [...], vis_end: x}}
## Then sets the render layers: corridor / door / vestibule -> 1024, everything in the hall -> 2048 (light isolation).
func commit_all(opts := {}) -> int:
	var tris := 0
	for name in kits:
		var k = kits[name]
		tris += int(k.tri_count)
		var o: Dictionary = opts.get(name, {})
		var mats_by_id := {}
		for id in (k.bins as Dictionary).keys():
			mats_by_id[id] = mats.mat(id)
		k.commit(region(name), mats_by_id, name, o)
	for name in regions:
		var layer := 1024 if name in FRONT_REGIONS else 2048
		for gi in (regions[name] as Node).find_children("*", "GeometryInstance3D", true, false):
			(gi as GeometryInstance3D).layers = layer
	return tris
