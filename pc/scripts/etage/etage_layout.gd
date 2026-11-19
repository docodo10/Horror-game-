## L'étage (chapter 2): every coordinate of the level, in world space. The level stands far east of the house
## (x 52..68.2, z -8..5.4) so that nothing of the basement or the garderie is near it; the player gets there through
## a fade.
##
##   west                                                                              east        -z = north
##   ┌───────────┬────────────────────────────────────┬─────────┐
##   │           │         salon des draps            │ W(moon) │   B = basement door (start)
##   │  chambre  │  (windows north, mantel east: the  │ landing │   F = front door (exit)
##   │ (pillow:  │   locked box, the key inside it)   │ ▲ ▲ ▲ ▲ │   D = door / doorway, W = window
##   │  digit 3) │                                    │ stairs, │
##   │           │                                    │ boarded │   cage d'escalier: the fuse board on its
##   └────D──────┴───────────D D──────────────────────┴───D─────┘   west wall, the boarded stairs east
##   B  couloir (16 m of old floorboards, runner rug, clock, sconces)                F
##   ┌────D──────┬─D(closet)─┬────D─────────────────────┬──W────────┘
##   │ salle de  ├───────────┤   cuisine                │   (yard: the moon comes in through the hallway
##   │ bain      │  garde-   │   (calendar west: digit  │    window)
##   │ (mirror:  │  manger   D    2; table and chairs,  │
##   │  digit 1) │ (fuses)   │    fridge NE, sink south)│
##   └───────────┤           │                          │
##               └───────────┴──────────────────────────┘
##
## The way out: the front door's key is in a box with three wheels on the salon's mantel. Digit 1 appears in the
## steam on the bathroom mirror (hot water needs the fuse of the water heater: a spare one is in the pantry, behind
## the dresser pushed across its door; it goes in the board of the stairwell). Digit 2 is the day circled on the
## kitchen calendar. Digit 3 is under the pillow in her bedroom, whose spare key is in the fridge's butter dish.
extends RefCounted

const WALL := 0.2
const L_ET := 32768                  # render layer of the level (its lights are masked to it + characters)

## interior boxes
const HALL := {"x0": 52.0, "x1": 68.0, "z0": -0.8, "z1": 0.8, "ceil": 2.6}
const SALON := {"x0": 56.5, "x1": 65.5, "z0": -7.8, "z1": -1.0, "ceil": 2.8}
const CHAMBRE := {"x0": 52.2, "x1": 56.3, "z0": -5.4, "z1": -1.0, "ceil": 2.6}
const CLOSET := {"x0": 56.9, "x1": 57.9, "z0": 1.0, "z1": 1.9, "ceil": 2.2}
const BAIN := {"x0": 52.4, "x1": 55.9, "z0": 1.0, "z1": 4.2, "ceil": 2.5}
const CUISINE := {"x0": 58.3, "x1": 63.3, "z0": 1.0, "z1": 5.2, "ceil": 2.6}
const CELLIER := {"x0": 56.1, "x1": 58.1, "z0": 2.2, "z1": 5.2, "ceil": 2.3}
const ESCALIER := {"x0": 65.7, "x1": 68.0, "z0": -6.2, "z1": -1.0, "ceil": 2.6}
const ROOMS := {"hall": HALL, "salon": SALON, "chambre": CHAMBRE, "closet": CLOSET, "bain": BAIN, "cuisine": CUISINE, "cellier": CELLIER,
	"escalier": ESCALIER}

## door openings (along x) in the hallway's north / south walls
const DOOR_CHAMBRE := {"x0": 54.6, "x1": 55.48, "h": 2.03}
const DOOR_SALON := {"x0": 60.0, "x1": 61.4, "h": 2.15}
const DOOR_CLOSET := {"x0": 57.0, "x1": 57.8, "h": 2.0}
const DOOR_BAIN := {"x0": 54.62, "x1": 55.44, "h": 2.03}
const DOOR_CUISINE := {"x0": 59.9, "x1": 60.8, "h": 2.1}          # an open doorway, no leaf
const DOOR_ESCALIER := {"x0": 66.72, "x1": 67.54, "h": 2.03}
## the pantry's door (along z), in the kitchen's west wall
const DOOR_CELLIER := {"z0": 3.3, "z1": 4.1, "h": 1.95}
## end doors (along z), in the west and east walls of the hallway
const DOOR_BASEMENT := {"z0": -0.42, "z1": 0.42, "h": 2.03}
const DOOR_FRONT := {"z0": -0.46, "z1": 0.46, "h": 2.08}

## windows: [x0, x1] in a wall running along x (y from 0.8 to 2.3)
const WIN_SALON := [[58.3, 59.4], [62.6, 63.7]]      # north wall of the salon
const WIN_HALL := [64.0, 65.0]                       # south wall of the hallway
const WIN_Y0 := 0.8
const WIN_Y1 := 2.3

const START := Vector3(53.3, 0.0, 0.0)
const START_YAW := -PI * 0.5                         # facing east, down the hallway
const CLOCK := Vector3(63.2, 0.0, -0.62)
const MANTEL := Vector3(65.3, 1.18, -4.4)            # where the key lies
const PIANO := Vector3(56.86, 0.0, -5.6)
const HUM := Vector3(54.2, 1.2, -3.2)                # her humming, behind the bedroom door
const SCONCES := [Vector3(56.2, 1.75, -0.74), Vector3(59.2, 1.75, 0.74), Vector3(66.4, 1.75, -0.74)]

## Figures standing under dust sheets in the salon: [home position, height, alt position (where it stands once the
## key is taken: closer to the way out, a gap of a metre always left)]
const FIGURES := [
	[Vector3(58.2, 0.0, -2.6), 1.72, Vector3(59.3, 0.0, -2.3)],
	[Vector3(59.6, 0.0, -5.9), 1.66, Vector3(60.9, 0.0, -5.0)],
	[Vector3(61.9, 0.0, -6.6), 1.80, Vector3(62.0, 0.0, -5.3)],
	[Vector3(63.9, 0.0, -2.2), 1.70, Vector3(63.0, 0.0, -1.6)],
	[Vector3(64.6, 0.0, -6.5), 1.63, Vector3(64.7, 0.0, -5.8)],
	[Vector3(57.4, 0.0, -7.1), 1.76, Vector3(58.1, 0.0, -6.4)],
]
## the one that walks: where it waits, under its sheet like the others
const WALKER := [Vector3(62.9, 0.0, -3.2), 1.86]
## the one found in the closet once its door has opened by itself
const CLOSET_FIGURE := [Vector3(57.4, 0.0, 1.5), 1.74]

## Floorboards that complain (x0, z0, x1, z1): stepping on one while standing makes a loud creak.
const CREAKY := [
	[54.7, -0.8, 55.5, 0.8], [57.6, -0.2, 58.4, 0.8], [59.4, -0.8, 60.1, 0.1], [62.1, -0.8, 62.9, 0.8], [65.6, -0.5, 66.3, 0.8],
	[60.3, -2.4, 61.2, -1.6], [59.0, -4.6, 60.0, -3.8], [62.6, -5.0, 63.6, -4.2], [64.0, -3.6, 65.0, -2.9],
	[66.6, -2.0, 67.7, -1.35], [65.8, -3.9, 66.95, -3.3],                # the stairwell: at its door, before the fuse board
]
## Draped furniture of the salon (x0, z0, x1, z1, height): colliders and things the walker goes around.
const FURNITURE := [
	[56.56, -6.4, 57.2, -4.8, 1.3],        # the upright piano against the west wall
	[58.4, -4.7, 60.4, -3.8, 0.85],        # sofa
	[61.4, -4.6, 62.3, -3.8, 0.75],        # round table
	[63.3, -5.3, 64.1, -4.5, 0.95],        # armchair
	[60.6, -7.7, 61.4, -7.2, 1.9],         # tall mirror against the north wall
	[64.9, -7.6, 65.4, -6.9, 1.1],         # a cabinet in the corner
]

## ---------------------------------------------------------------- the rooms added south and east of the hallway

## la cuisine
const TABLE := Vector3(60.6, 0.0, 3.0)               # centre of the kitchen table (1.3 along x, 0.8 along z)
## chairs around it: [seat centre, yaw of someone seated on it (facing the table)]
const CHAIRS := [
	[Vector3(60.6, 0.0, 3.72), PI],                  # south, facing north: the doorway
	[Vector3(59.62, 0.0, 3.0), PI * 0.5],            # west, facing east: the fridge
	[Vector3(60.6, 0.0, 2.28), 0.0],                 # north, its back to the doorway
	[Vector3(61.58, 0.0, 3.0), -PI * 0.5],           # east
]
const FRIDGE := {"x0": 62.62, "x1": 63.3, "z0": 1.15, "z1": 1.85, "h": 1.56}
const COUNTER := {"x0": 59.0, "x1": 62.3, "z0": 4.6, "z1": 5.2, "h": 0.9}
const DRAWERS := [59.28, 59.74, 61.72]               # x of the three drawers under the worktop (0.44 wide)
const WIN_CUISINE := [60.45, 61.35, 1.15, 1.95]      # x0, x1, y0, y1 in the south wall, over the sink
const STOVE := {"x0": 62.66, "x1": 63.3, "z0": 3.0, "z1": 3.9, "h": 0.88}
## the dresser pushed across the pantry door: its box before / after it is pushed (x0, z0, x1, z1), its height
const BUFFET := [58.3, 3.14, 58.76, 4.22]
const BUFFET_PUSH := 1.04                            # metres it slides south
const BUFFET_H := 0.96
## the calendar on the west wall: centre, size; and its day grid in uv (see tools/gen_etage2_textures.py)
const CALENDAR := Vector3(58.3, 1.52, 2.15)
const CAL_SIZE := Vector2(0.36, 0.54)
const CAL_GRID := [40.0 / 512.0, 392.0 / 768.0, (432.0 / 7.0) / 512.0, 68.0 / 768.0]      # u0, v0, cell u, cell v

## le garde-manger
const FUSE_TIN := Vector3(56.34, 1.3, 3.7)           # on the shelf facing the door

## la salle de bain
const TUB := {"x0": 52.5, "x1": 54.15, "z0": 3.44, "z1": 4.14, "h": 0.58}
const CURTAIN := {"x0": 52.44, "x1": 54.24, "z": 3.36, "y0": 0.22, "y1": 1.93}
const BASIN := Vector3(52.4, 0.84, 2.1)              # on the west wall: the point of the wall behind the taps
const MIRROR := Vector3(52.4, 1.52, 2.1)             # centre of the glass, 0.56 wide (z), 0.76 high
const MIRROR_SIZE := Vector2(0.56, 0.76)
const HEATER := Vector3(53.05, 1.72, 1.24)           # the water heater, on the north wall
const BATH_FIGURE := [Vector3(53.3, 0.1, 3.8), 1.72, Vector3(55.0, 0.0, 1.7)]      # in the tub; later, at the door

## la cage d'escalier
const STAIR := {"x0": 67.0, "x1": 68.0, "z_foot": -2.4, "run": 0.26, "rise": 0.19, "steps": 12}
const LANDING_Y := 2.28
const VOID_TOP := 5.0
const WIN_ESCALIER := [67.08, 67.92, 3.15, 4.5]      # x0, x1, y0, y1 in the north wall, above the landing
const FUSE_BOARD := Vector3(65.7, 1.46, -4.3)        # centre of the board, on the west wall
const STAIR_FIGURE := [Vector3(67.5, 2.28, -5.84), 1.78]

## Doorways as the walkers use them: room -> [the room it opens from, a point before the door, a point past it,
## half the free width of the doorway]. Every room hangs from the hallway (the pantry from the kitchen).
const PORTALS := {
	"salon": ["hall", Vector3(60.7, 0.0, -0.35), Vector3(60.7, 0.0, -1.5), 0.5],
	"chambre": ["hall", Vector3(55.04, 0.0, -0.35), Vector3(55.04, 0.0, -1.5), 0.2],
	"closet": ["hall", Vector3(57.4, 0.0, 0.35), Vector3(57.4, 0.0, 1.35), 0.2],
	"bain": ["hall", Vector3(55.03, 0.0, 0.35), Vector3(55.03, 0.0, 1.5), 0.2],
	"cuisine": ["hall", Vector3(60.35, 0.0, 0.35), Vector3(60.35, 0.0, 1.5), 0.22],
	"escalier": ["hall", Vector3(67.13, 0.0, -0.35), Vector3(67.13, 0.0, -1.5), 0.2],
	"cellier": ["cuisine", Vector3(58.86, 0.0, 3.7), Vector3(57.6, 0.0, 3.7), 0.2],
}

static func in_box(B: Dictionary, p: Vector3, pad := 0.0) -> bool:
	return p.x >= float(B.x0) - pad and p.x <= float(B.x1) + pad and p.z >= float(B.z0) - pad and p.z <= float(B.z1) + pad

static func contains(p: Vector3) -> bool:
	return p.x > 51.0 and p.x < 69.5 and p.z > -8.5 and p.z < 6.0 and p.y < 6.0

## "hall" | "salon" | "chambre" | "closet" | "bain" | "cuisine" | "cellier" | "escalier": the rooms meet in the
## middle of the walls between them.
static func room_of(p: Vector3) -> String:
	for id in ROOMS:
		if id != "hall" and in_box(ROOMS[id], p, 0.1):
			return id
	return "hall"

## The chain of rooms from the hallway down to `room` (["hall"], ["hall", "cuisine", "cellier"]...).
static func room_chain(room: String) -> Array:
	var out := [room]
	while PORTALS.has(out[0]):
		out.push_front(PORTALS[out[0]][0])
	return out

## The runner rug muffles steps; the bathroom and the pantry are tiled; everything else is floorboards (the
## kitchen's linoleum lies on them).
static func surface_at(p: Vector3) -> String:
	if p.z > -0.42 and p.z < 0.42 and p.x > 53.6 and p.x < 66.6 and p.z > float(HALL.z0):
		return "carpet"
	var r := room_of(p)
	return "concrete" if r == "bain" or r == "cellier" else "wood"
