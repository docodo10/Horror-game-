## Dehors (chapter 3): every coordinate of the level, in world space. The yard of the old house stands far east of
## everything else (x 100..150); the player gets there through a fade. x grows east, z grows south.
##
##          north (-z)                                                     fence + black tree line all around
##   ┌───────────────────────────────────────────────────────────────┐
##   │ caveau (trapdoor,     trees, dead leaves            remise    │
##   │ room under the lawn)                                 (shed)   │
##   │          cabane     balançoire    bac à sable                  │
##   H                                             le chêne           │
##   H perron ── path ─┐      (lawn)               (leaves)   niche   │
##   H (start, chimes) │                                              │
##   H                 └───────────── allée de gravier ─────────── PORTAIL   (east: the way out, chained)
##   │   la voiture (parking)                serre                    │
##   └───────────────────────────────────────────────────────────────┘
##          south (+z)
extends RefCounted

const L_DH := 65536                  # render layer of the level (its lights are masked to it + characters)

## the yard inside its fence
const YARD := {"x0": 104.0, "x1": 146.0, "z0": -17.0, "z1": 17.0}
const FENCE_H := 1.95

## the house: only its east front (the facade the player has just walked out of) and the porch
const HOUSE := {"x0": 97.0, "x1": 104.0, "z0": -9.0, "z1": 9.0, "eave": 5.6, "ridge": 8.2}
const PORCH := {"x0": 104.0, "x1": 106.6, "z0": -3.0, "z1": 3.0, "y": 0.36, "roof": 2.75}
const STEPS := {"x0": 106.6, "x1": 107.3, "z0": -1.0, "z1": 1.0}
const DOOR_FRONT := {"z0": -0.5, "z1": 0.5, "h": 2.08}

const START := Vector3(105.5, 0.36, 0.0)
const START_YAW := -PI * 0.5                         # facing east, toward the yard

## gravel: the driveway from the gate, the parking pad by the house, the greenhouse apron (x0, z0, x1, z1), and the
## path from the porch steps to the driveway (polyline, half width)
const GRAVEL := [[108.0, 6.5, 146.0, 10.5], [108.0, 6.5, 116.5, 13.2], [126.0, 10.5, 128.0, 12.2], [146.0, 7.0, 150.0, 10.0]]
const PATH := [Vector2(107.3, 0.0), Vector2(112.6, 0.0), Vector2(116.2, 6.6)]
const PATH_HALF := 0.8
## dead leaves under the trees: circles (x, z, radius)
const LEAVES := [[133.0, -1.5, 5.4], [140.2, -8.6, 3.1], [118.0, -15.3, 3.0], [127.5, -15.6, 2.8], [144.3, 0.6, 2.7],
	[142.2, 14.2, 3.4], [106.4, 14.6, 2.8], [121.0, 15.2, 2.4], [136.0, 14.6, 2.2], [106.2, -7.2, 2.4]]
## bare earth (no sound of its own: it only shows): under the swings, around the sandbox, by the cellar, puddles
const DIRT := [[120.5, -4.5, 2.2], [126.5, -9.5, 2.3], [112.6, -11.0, 2.2], [139.9, -10.6, 1.4], [115.9, -6.5, 1.1]]
const PUDDLES := [[121.5, 8.2, 1.3], [134.5, 9.1, 1.1], [111.2, 8.0, 0.9], [142.6, 7.7, 0.9], [128.6, 7.4, 0.7]]

## trees standing inside the yard: (x, z, trunk radius, height)
const OAK := Vector3(133.0, 0.0, -1.5)
const YARD_TREES := [[118.0, -15.6, 0.22, 8.0], [127.5, -15.9, 0.2, 7.5], [142.4, 14.6, 0.24, 8.5], [106.2, 14.8, 0.2, 7.0],
	[144.6, 0.4, 0.18, 7.0], [136.0, 15.4, 0.17, 6.5]]

## the daycare's things on the lawn
const SWING := {"x": 120.5, "z": -4.5, "half": 1.5, "h": 2.25, "seats": [-0.6, 0.6]}      # top bar along x; swings swing along z
const SANDBOX := {"x0": 125.2, "x1": 127.8, "z0": -10.8, "z1": -8.2}
const CABANE := {"x": 114.5, "z": -6.5, "half": 0.85, "h": 1.45}                            # the playhouse (a hiding place)
const NICHE := {"x": 139.5, "z": 1.5, "hx": 0.7, "hz": 0.55, "h": 0.95}                    # the kennel (a hiding place)

## the dead car on the parking pad, nose to the east
const CAR := {"x": 112.0, "z": 10.6, "len": 4.2, "w": 1.66}

## la remise (tool shed): interior box, door in the south wall
const SHED := {"x0": 138.2, "x1": 142.6, "z0": -15.6, "z1": -12.0, "eave": 2.15, "ridge": 2.95}
const SHED_DOOR := {"x0": 139.6, "x1": 140.5, "h": 1.95}
## la serre (greenhouse): interior box, door opening in the north wall
const SERRE := {"x0": 124.0, "x1": 130.0, "z0": 12.2, "z1": 16.0, "eave": 2.0, "ridge": 2.9, "base": 0.5}
const SERRE_DOOR := {"x0": 126.5, "x1": 127.5, "h": 1.95}
const POTS := [125.2, 126.4, 127.6, 128.8]           # x of the four pots on the south bench (z = 15.5)
const POT_KEY := 2                                   # the blue one: the shed key lies under it

## le caveau (root cellar): a bulkhead in the lawn, stone steps down to the west, one room under the lawn
const SHAFT := {"x0": 110.6, "x1": 114.2, "z0": -13.6, "z1": -12.6}
const CAVE := {"x0": 105.4, "x1": 110.6, "z0": -15.6, "z1": -10.6, "floor": -2.5, "ceil": -0.35}
const CAVE_DOOR_H := 2.0                             # doorway from the foot of the steps into the room

## the garden gate (east fence, at the end of the driveway)
const GATE := {"x": 146.0, "z0": 7.0, "z1": 10.0, "h": 1.9}

## where she walks when she has heard nothing (a loop); the last four are the ones she keeps to once the bolt
## cutters have left the cellar
const PATROL := [Vector3(109.0, 0.0, 0.4), Vector3(116.8, 0.0, -4.4), Vector3(121.0, 0.0, -1.8), Vector3(126.4, 0.0, -6.6),
	Vector3(112.6, 0.0, -10.4), Vector3(124.0, 0.0, -13.0), Vector3(135.0, 0.0, -9.6), Vector3(140.0, 0.0, -9.4),
	Vector3(138.0, 0.0, 3.6), Vector3(143.4, 0.0, 8.6), Vector3(132.0, 0.0, 8.4), Vector3(127.0, 0.0, 11.0),
	Vector3(120.0, 0.0, 12.6), Vector3(114.6, 0.0, 8.3)]
const PATROL_LATE := [7, 8, 9, 10, 11, 6]
const HER_HOME := Vector3(107.9, 0.0, 0.0)           # the foot of the porch steps: where she comes out

static func in_rect(r: Array, x: float, z: float, pad := 0.0) -> bool:
	return x >= float(r[0]) - pad and x <= float(r[2]) + pad and z >= float(r[1]) - pad and z <= float(r[3]) + pad

static func in_box(B: Dictionary, p: Vector3, pad := 0.0) -> bool:
	return p.x >= float(B.x0) - pad and p.x <= float(B.x1) + pad and p.z >= float(B.z0) - pad and p.z <= float(B.z1) + pad

static func contains(p: Vector3) -> bool:
	return p.x > 96.0 and p.x < 152.0 and p.z > -20.0 and p.z < 20.0 and p.y < 9.0

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * t)

static func is_gravel(x: float, z: float) -> bool:
	for r in GRAVEL:
		if in_rect(r, x, z):
			return true
	var p := Vector2(x, z)
	for i in PATH.size() - 1:
		if _seg_dist(p, PATH[i], PATH[i + 1]) < PATH_HALF:
			return true
	return false

static func is_leaves(x: float, z: float) -> bool:
	for c in LEAVES:
		var dx := x - float(c[0])
		var dz := z - float(c[1])
		if dx * dx + dz * dz < float(c[2]) * float(c[2]):
			return true
	return false

static func in_cellar(p: Vector3) -> bool:
	return p.y < -0.6 and p.x < float(SHAFT.x1) + 0.3 and p.x > float(CAVE.x0) - 0.3 and p.z < float(CAVE.z1) + 0.3 and p.z > float(CAVE.z0) - 0.3

## "grass" | "gravel" | "leaves" | "wood" | "concrete": what the player's steps sound like (and how far they carry)
static func surface_at(p: Vector3) -> String:
	if p.y < -0.25:
		return "concrete"                             # the stone steps and the floor of the cellar
	if in_box(PORCH, p) or in_box(STEPS, p) or in_box(SHED, p):
		return "wood"
	if in_box(SERRE, p):
		return "concrete"                             # paving slabs between the benches
	if in_box(SHAFT, p, 0.1):
		return "wood"                                 # the cellar doors, when they are shut
	if is_gravel(p.x, p.z):
		return "gravel"
	if is_leaves(p.x, p.z):
		return "leaves"
	return "grass"

## "perron" | "allee" | "pelouse" | "remise" | "serre" | "caveau" | "portail": the place a point belongs to
static func place_of(p: Vector3) -> String:
	if in_cellar(p):
		return "caveau"
	if in_box(SHED, p):
		return "remise"
	if in_box(SERRE, p):
		return "serre"
	if in_box(PORCH, p, 0.8):
		return "perron"
	if p.x > 142.0 and p.z > 5.5 and p.z < 11.5:
		return "portail"
	if is_gravel(p.x, p.z):
		return "allee"
	return "pelouse"
