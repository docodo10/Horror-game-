## L'étage (chapter 2): every coordinate of the level, in world space. The level stands far east of the house
## (x 52..68) so that nothing of the basement or the garderie is near it; the player gets there through a fade.
##
##   west                                                                         east
##   ┌──────────┬───────────────────────────────────┐
##   │ chambre  │        salon des draps            │        -z = north
##   │          │   (windows north, mantel east)    │
##   └───D──────┴──────────D D──────────────────────┘
##   B  couloir (16 m of old floorboards, runner rug, clock, sconces)        F   B = basement door (start)
##   └─────────────D(closet)──────────W(window)─────┘                            F = front door (exit)
extends RefCounted

const WALL := 0.2
const L_ET := 32768                  # render layer of the level (its lights are masked to it + characters)

## interior boxes
const HALL := {"x0": 52.0, "x1": 68.0, "z0": -0.8, "z1": 0.8, "ceil": 2.6}
const SALON := {"x0": 56.5, "x1": 65.5, "z0": -7.8, "z1": -1.0, "ceil": 2.8}
const CHAMBRE := {"x0": 52.2, "x1": 56.3, "z0": -5.4, "z1": -1.0, "ceil": 2.6}
const CLOSET := {"x0": 56.9, "x1": 57.9, "z0": 1.0, "z1": 1.9, "ceil": 2.2}

## door openings (along x) in the hallway's north / south walls
const DOOR_CHAMBRE := {"x0": 54.6, "x1": 55.48, "h": 2.03}
const DOOR_SALON := {"x0": 60.0, "x1": 61.4, "h": 2.15}
const DOOR_CLOSET := {"x0": 57.0, "x1": 57.8, "h": 2.0}
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

static func in_box(B: Dictionary, p: Vector3, pad := 0.0) -> bool:
	return p.x >= float(B.x0) - pad and p.x <= float(B.x1) + pad and p.z >= float(B.z0) - pad and p.z <= float(B.z1) + pad

static func contains(p: Vector3) -> bool:
	return p.x > 51.0 and p.x < 69.5 and p.z > -8.5 and p.z < 2.5 and p.y < 4.0

## "hall" | "salon" | "chambre" | "closet"
static func room_of(p: Vector3) -> String:
	if p.z > float(HALL.z0) - 0.1:
		return "closet" if p.z > float(HALL.z1) + 0.1 else "hall"
	return "salon" if p.x > float(SALON.x0) - 0.1 else "chambre"

## The runner rug muffles steps; everything else is floorboards.
static func surface_at(p: Vector3) -> String:
	if p.z > -0.42 and p.z < 0.42 and p.x > 53.6 and p.x < 66.6 and p.z > float(HALL.z0):
		return "carpet"
	return "wood"
