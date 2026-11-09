## Garderie layout: every coordinate of the area, in the level frame (metres, +Y up, -Z north, the area lies west of
## the main room: x < -3.7). Shared by the builders, the gameplay hooks, the bake tool and the tests.
##
##   main room ─ door (west wall, z 1.72..2.48) ─ corridor (y 0) ─ vestibule "vestiaire" (y 0) ─ landing (y 0)
##   ─ 6 steps down ─ soft-play hall (y -1.05, roof 7.0): 3-level play frame, 4-lane wave slide, spiral tube slide,
##   ball pit, toddler corner, party tables, mural, emergency exit.
extends RefCounted

const UP := 0.0                      # corridor / vestibule / landing / play deck L1
const HALL := -1.05                  # hall floor (6 risers of 0.175 below the landing)
const WALL := 0.2

# ---------------------------------------------------------------- doorway in the main room's west wall
const DOOR := {"x0": -3.7, "x1": -3.5, "z0": 1.72, "z1": 2.48, "h": 2.03}
## Geometry of other modules removed inside this box (room wall, baseboard, stair skirt tip, shadow-caster box).
## y starts just above the carpet (y = 0) so the floor is never cut; x reaches 6 cm into the room for trims.
const CARVE_MIN := Vector3(-3.72, 0.004, 1.72)
const CARVE_MAX := Vector3(-3.44, 2.03, 2.48)
## Colliders / ray blockers removed inside this box (whole wall thickness, floor to header).
const CUT_MIN := Vector3(-3.76, 0.0, 1.72)
const CUT_MAX := Vector3(-3.44, 2.03, 2.48)
const LEAF := {"w": 0.70, "h": 2.0, "t": 0.042, "hinge_x": -3.66, "hinge_z": 2.455, "open": 1.62}

# ---------------------------------------------------------------- corridor (old basement corridor)
const CORR := {"x0": -11.0, "x1": -3.7, "z0": 1.45, "z1": 2.75, "ceil": 2.25}
const BULB := Vector3(-7.4, 1.98, 2.1)

# ---------------------------------------------------------------- vestibule ("vestiaire")
const VEST := {"x0": -17.0, "x1": -11.2, "z0": -0.8, "z1": 5.0, "ceil": 2.6}
const VEST_IN := {"z0": 1.6, "z1": 2.6, "h": 2.1}          # opening in its east wall (x -11.2..-11.0)
const VEST_OUT := {"z0": 1.2, "z1": 3.0, "h": 2.2}         # double doors to the hall (wall x -17.2..-17.0)
const VEST_COLUMNS := [Vector2(-14.1, 0.55), Vector2(-14.1, 3.65)]
## 2' x 4' troffers in the 2' ceiling grid: (cell i along x from VEST.x0, cell j along z from VEST.z0, state)
## state: on | shadow | flicker | dead
const VEST_LIGHTS := [[7, 1, "shadow"], [2, 6, "on"], [2, 1, "flicker"], [7, 6, "dead"]]

# ---------------------------------------------------------------- hall
const HALLB := {"x0": -39.0, "x1": -17.2, "z0": -7.0, "z1": 11.0, "roof": 7.0, "wall": 0.3}
const LANDING := {"x0": -20.6, "x1": -17.2, "z0": -2.0, "z1": 4.8}
const STEPS := {"x_top": -20.6, "n": 6, "rise": 0.175, "run": 0.30, "z0": 1.1, "z1": 3.1}
const HALL_LIGHT_Y := 5.9
## fixtures (x, z, state)
const HALL_LIGHTS := [
	[-19.8, -4.6, "on"], [-19.8, 1.4, "on"], [-19.8, 7.4, "dead"],
	[-25.4, -4.6, "shadow"], [-25.4, 1.4, "shadow"], [-25.4, 7.4, "shadow"],
	[-31.0, -4.6, "shadow"], [-31.0, 1.4, "dead"], [-31.0, 7.4, "flicker"],
	[-36.6, -4.6, "dead"], [-36.6, 1.4, "dead"], [-36.6, 7.4, "on"],
]
const HALL_COLUMNS := [Vector2(-23.0, 4.0), Vector2(-38.4, 0.8), Vector2(-17.95, 8.6)]
const EXIT_DOOR := {"x": -39.0, "z0": -2.6, "z1": -1.4, "h": 2.1}   # emergency exit, west wall (chained)

# ---------------------------------------------------------------- play frame (3 levels)
const L1 := 0.0
const L2 := 1.95
const L3 := 3.9
const DECK_T := 0.15
const RAIL_H := 1.15                 # net railing height above a deck
const TOP_Y := 5.4                   # top of the tower frame
## decks: [x0, x1, z0, z1, top_y]
const DECKS := [
	[-31.0, -23.8, -1.8, 2.6, L1],
	[-35.0, -31.0, -5.4, 2.6, L1],
	[-31.0, -27.4, -1.8, 2.6, L2],
	[-35.0, -31.0, -5.4, 2.6, L2],
	[-35.0, -31.0, -5.4, 2.6, L3],
]
## flights of padded steps (invisible ramp + visual blocks): [x_low, x_high, z0, z1, y_low, y_high, risers]
## x_low/x_high = x of the bottom / top nosing line (the stairs climb from x_low toward x_high)
const FLIGHTS := [
	[-22.3, -23.8, -1.5, -0.5, HALL, L1, 5],      # hall floor -> deck L1 (east entrance)
	[-25.3, -27.4, 1.6, 2.6, L1, L2, 7],          # L1 -> L2
	[-28.9, -31.0, -1.8, -0.8, L2, L3, 7],        # L2 -> L3
]
## crawl tube lying on the landing (the hide spot): mouth facing west over the hall, closed end at the wall
const TUBE := {"mouth_x": -19.6, "end_x": -17.38, "z": -1.2, "r": 0.62, "bell": 0.78}
const HIDE := {"id": "garderie_tunnel", "hide_pos": Vector3(-18.55, 0.62, -1.2), "hide_yaw": PI * 0.5, "exit_pos": Vector3(-20.22, 0.0, -1.2)}

# ---------------------------------------------------------------- slides
## 4-lane wave slide from deck L3 (east edge) down to the hall floor, toward +x
const WAVE := {"x_start": -31.0, "x_flat": -30.6, "x_end": -22.0, "x_out": -20.2, "z0": -5.32, "z1": -3.0, "lanes": 4,
	"y_top": L3 + 0.05, "y_end": HALL + 0.36, "y_out": HALL + 0.30, "waves": 2.0, "amp": 0.7}
## spiral tube slide from deck L3 (south edge): chute south, 1.25 turns, exits east
const SPIRAL := {"xc": -33.0, "zc": 4.5, "radius": 1.15, "turns": 1.25, "x_entry": -34.15, "z_entry": 2.6,
	"y_top": L3 + 0.05, "y_end": HALL + 0.34, "tube_r": 0.44, "x_out": -31.5}

# ---------------------------------------------------------------- ball pit, party, toddler corner
const PIT := {"x0": -29.8, "x1": -24.6, "z0": 4.6, "z1": 8.6, "wall_h": 0.55, "wall_t": 0.25, "fill": 0.42,
	"gate_z0": 6.2, "gate_z1": 7.0}
const PARTY := {"x0": -23.6, "x1": -18.4, "z0": 6.0, "z1": 10.2}
const TODDLER := {"x0": -38.6, "x1": -35.6, "z0": 3.6, "z1": 10.4}
const MURAL := {"x0": -36.5, "x1": -20.5, "y0": HALL + 0.7, "y1": HALL + 4.7, "z": -7.0}

# ---------------------------------------------------------------- navigation (ground level, La Gardienne)
## y is the floor height at the node.
const NAV_NODES := {
	"gd_door": Vector3(-4.3, UP, 2.1),
	"gd_corrMid": Vector3(-7.4, UP, 2.1),
	"gd_corrEnd": Vector3(-10.5, UP, 2.1),
	"gd_vestIn": Vector3(-12.0, UP, 2.1),
	"gd_vest": Vector3(-14.1, UP, 2.1),
	"gd_vestNorth": Vector3(-14.9, UP, 0.25),
	"gd_vestSouth": Vector3(-13.0, UP, 3.9),
	"gd_vestOut": Vector3(-16.4, UP, 2.1),
	"gd_landing": Vector3(-18.5, UP, 2.1),
	"gd_landingWest": Vector3(-20.0, UP, 0.3),
	"gd_tubeMouth": Vector3(-20.15, UP, -1.2),
	"gd_stepsTop": Vector3(-20.3, UP, 2.1),
	"gd_stepsBottom": Vector3(-22.9, HALL, 2.1),
	"gd_hallMidEast": Vector3(-22.0, HALL, 0.0),
	"gd_hallEast": Vector3(-21.3, HALL, -2.5),
	"gd_neCorner": Vector3(-19.5, HALL, -2.6),
	"gd_waveBottom": Vector3(-19.5, HALL, -4.6),
	"gd_neNorth": Vector3(-19.5, HALL, -6.3),
	"gd_northAisle": Vector3(-27.0, HALL, -6.3),
	"gd_nwCorner": Vector3(-37.4, HALL, -6.2),
	"gd_westAisle": Vector3(-37.2, HALL, 1.6),
	"gd_exitDoor": Vector3(-38.2, HALL, -2.0),
	"gd_spiralWest": Vector3(-35.05, HALL, 3.1),
	"gd_toddlerGate": Vector3(-35.05, HALL, 6.8),
	"gd_toddler": Vector3(-37.1, HALL, 6.8),
	"gd_southWest": Vector3(-30.9, HALL, 9.9),
	"gd_southAisle": Vector3(-28.0, HALL, 9.9),
	"gd_southEast": Vector3(-23.9, HALL, 9.6),
	"gd_spiralOut": Vector3(-30.6, HALL, 7.0),
	"gd_spiralEast": Vector3(-30.6, HALL, 3.6),
	"gd_southMid": Vector3(-28.0, HALL, 3.6),
	"gd_hallSE": Vector3(-24.0, HALL, 3.5),
	"gd_pitGate": Vector3(-23.9, HALL, 6.6),
	"gd_party": Vector3(-20.9, HALL, 5.4),
}
const NAV_LINKS := [
	["gd_door", "stairsBottom"], ["gd_door", "swCorner"],
	["gd_door", "gd_corrMid"], ["gd_corrMid", "gd_corrEnd"], ["gd_corrEnd", "gd_vestIn"], ["gd_vestIn", "gd_vest"],
	["gd_vest", "gd_vestNorth"], ["gd_vest", "gd_vestSouth"], ["gd_vest", "gd_vestOut"], ["gd_vestOut", "gd_landing"],
	["gd_landing", "gd_stepsTop"], ["gd_landing", "gd_landingWest"], ["gd_landingWest", "gd_tubeMouth"],
	["gd_stepsTop", "gd_stepsBottom"], ["gd_stepsBottom", "gd_hallMidEast"], ["gd_hallMidEast", "gd_hallEast"],
	["gd_hallEast", "gd_neCorner"], ["gd_neCorner", "gd_waveBottom"], ["gd_waveBottom", "gd_neNorth"],
	["gd_neNorth", "gd_northAisle"], ["gd_northAisle", "gd_nwCorner"], ["gd_nwCorner", "gd_westAisle"],
	["gd_westAisle", "gd_exitDoor"], ["gd_westAisle", "gd_spiralWest"], ["gd_spiralWest", "gd_toddlerGate"],
	["gd_toddlerGate", "gd_toddler"], ["gd_toddlerGate", "gd_southWest"], ["gd_southWest", "gd_southAisle"],
	["gd_southWest", "gd_spiralOut"], ["gd_spiralOut", "gd_spiralEast"], ["gd_spiralEast", "gd_southMid"],
	["gd_southMid", "gd_hallSE"], ["gd_hallSE", "gd_stepsBottom"], ["gd_hallSE", "gd_pitGate"],
	["gd_southAisle", "gd_southEast"], ["gd_southEast", "gd_pitGate"], ["gd_pitGate", "gd_party"],
]

# ---------------------------------------------------------------- helpers

## Floor height of the area at (x, z) (NAN outside it). prev_y disambiguates stacked play decks (default: ground level).
static func ground_height_at(x: float, z: float, prev_y: float = NAN) -> float:
	if x > -3.5:
		return NAN
	if x > -3.72:
		return UP if z >= DOOR.z0 and z <= DOOR.z1 else NAN
	if x >= CORR.x0 - 0.2 and z >= CORR.z0 and z <= CORR.z1:
		return UP
	if x >= VEST.x0 - 0.2 and x <= VEST.x1 + 0.2 and z >= VEST.z0 and z <= VEST.z1:
		return UP
	if x < HALLB.x0 or x > HALLB.x1 or z < HALLB.z0 or z > HALLB.z1:
		return NAN
	if x >= LANDING.x0 and z >= LANDING.z0 and z <= LANDING.z1:
		return UP
	if z >= STEPS.z0 and z <= STEPS.z1 and x < STEPS.x_top and x >= STEPS.x_top - STEPS.run * STEPS.n:
		# ramp through the nosings (what the colliders give)
		return maxf(HALL, UP - (STEPS.x_top - x) * STEPS.rise / STEPS.run)
	var has_prev := not is_nan(prev_y)
	if has_prev and prev_y > HALL + 0.6:
		var best := NAN
		for d in DECKS:
			if x >= d[0] and x <= d[1] and z >= d[2] and z <= d[3] and float(d[4]) <= prev_y + 0.35:
				if is_nan(best) or float(d[4]) > best:
					best = float(d[4])
		if not is_nan(best):
			return best
	return HALL

## Rough surface kind for footsteps (player request): concrete | foam | wood | vinyl.
static func surface_at(pos: Vector3) -> String:
	if pos.x > -3.72:
		return "wood"
	if pos.x >= CORR.x0 - 0.2:
		return "concrete"
	if pos.y > HALL + 0.6 and pos.x < LANDING.x0 - 0.05:
		return "vinyl"
	return "foam"

## True when (x, z) lies inside the area (corridor, vestibule, hall).
static func contains(p: Vector3) -> bool:
	return not is_nan(ground_height_at(p.x, p.z))
