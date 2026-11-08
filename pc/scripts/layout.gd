# AUTO-GENERATED from src/config/layout.js by the lead (do not edit by hand; regenerate instead).
# Same coordinate system as the web version and as Godot: meters, +Y up, -Z = north, models face +Z at rot_y = 0.
class_name Layout
extends RefCounted

const ROOM := {"minX": -3.5, "maxX": 3.5, "minZ": -2.75, "maxZ": 2.75, "floorY": 0.0, "ceilingY": 2.5, "wallThickness": 0.2}

const UPPER := {"floorY": 2.75, "ceilingY": 5.2}

const STAIRS := {"minX": -3.5, "maxX": -2.55, "bottomZ": 1.6, "risers": 14.0, "riserHeight": 0.196429, "treadDepth": 0.26, "topZ": -1.78, "ceilingOpeningMaxZ": 1.15, "sideWallX": -2.55, "sideWallThickness": 0.1}

const UPSTAIRS_DOOR := {"centerX": -3.025, "z": -2.75, "width": 0.85, "height": 2.03, "bottomY": 2.75, "thickness": 0.045, "hingeX": -3.45, "openAngle": -1.6}

const UPPER_HALL := {"minX": -3.6, "maxX": -2.45, "minZ": -4.4, "maxZ": -2.75}

const CLOSET := {"minX": -3.45, "maxX": -2.62, "minZ": -2.7, "maxZ": -0.35, "door": {"x": -2.55, "centerZ": -2.05, "width": 0.62, "height": 1.9, "hingeZ": -2.36, "openAngle": 1.5}, "hidePos": {"x": -3.05, "y": 1.35, "z": -2.05}, "hideYaw": -1.570796, "exitPos": {"x": -2.05, "z": -2.05}}

const ALCOVE := {"minX": 0.2, "maxX": 3.5, "minZ": -4.6, "maxZ": -2.75, "doorway": {"minX": 0.9, "maxX": 1.8, "height": 2.05}}

const WINDOW := {"minX": 1.95, "maxX": 2.95, "minY": 1.8, "maxY": 2.3, "z": 2.75}

const FAN := {"x": 0.25, "z": 0.35}

const PROPS := {"sofa": {"model": "sofa_03", "pos": [0.25, 0.0, 2.27], "rotY": 3.141593}, "pillows": {"model": "throw_pillows_01", "pos": [0.25, 0.47, 2.3], "rotY": 3.141593}, "coffeeTable": {"model": "small_wooden_table_01", "pos": [0.25, 0.0, 0.95], "rotY": 0.0}, "endTable": {"model": "painted_wooden_nightstand", "pos": [-1.5, 0.0, 2.42], "rotY": 3.141593}, "dresser": {"model": "GothicCommode_01", "pos": [-0.55, 0.0, -2.44], "rotY": 0.0}, "tv": {"model": "television_02", "pos": [-0.55, 1.212, -2.5], "rotY": 0.0}, "photoFrame": {"model": "standing_picture_frame_01", "pos": [-0.05, 1.212, -2.45], "rotY": -0.3}, "grandfather": {"model": "vintage_grandfather_clock_01", "pos": [2.95, 0.0, -2.52], "rotY": 0.0}, "shelves": {"model": "painted_wooden_shelves", "pos": [2.15, 0.0, -2.75], "rotY": 0.0}, "books": {"model": "book_encyclopedia_set_01", "pos": [1.93, 0.62, -2.62], "rotY": 0.0, "scale": 0.8}, "horse": {"model": "horse_statue_01", "pos": [2.15, 1.125, -2.58], "rotY": 0.5}, "console": {"model": "ClassicConsole_01", "pos": [3.18, 0.0, 0.15], "rotY": -1.570796}, "lockedBox": {"model": "CheeseBox_01", "pos": [3.12, 0.949, 0.15], "rotY": -1.570796, "scale": 1.7}, "chairA": {"model": "painted_wooden_chair_02", "pos": [3.12, 0.0, -1.05], "rotY": -1.570796}, "chairB": {"model": "painted_wooden_chair_02", "pos": [3.12, 0.0, 1.4], "rotY": -1.570796}, "roundFrame": {"model": "hanging_picture_frame_03", "pos": [3.48, 1.62, 0.15], "rotY": -1.570796}, "sofaPainting": {"model": "fancy_picture_frame_01", "pos": [0.25, 1.65, 2.74], "rotY": 3.141593}, "rockingChair": {"model": "Rockingchair_01", "pos": [2.55, -0.102, 1.95], "rotY": -2.2}, "kidTable": {"model": "side_table_01", "pos": [-2.0, 0.0, 0.2], "rotY": 0.0}, "kidChair": {"model": "painted_wooden_chair_01", "pos": [-2.0, 0.0, 0.75], "rotY": 3.141593, "scale": 0.72}, "duck": {"model": "rubber_duck_toy", "pos": [-1.35, 0.0, 0.95], "rotY": 0.8, "scale": 0.6}, "alarmClock": {"model": "alarm_clock_01", "pos": [0.55, 0.533, 0.92], "rotY": -0.4}, "fan": {"model": "ceiling_fan", "pos": [0.25, 2.5, 0.35], "rotY": 0.0}, "alcoveCabinet": {"model": "painted_wooden_cabinet", "pos": [1.0, 0.0, -4.28], "rotY": 0.0}, "powerBox": {"model": "power_box_01", "pos": [2.6, 1.45, -4.553], "rotY": 0.0}, "alcoveShelf": {"model": "Shelf_01", "pos": [3.5, 0.0, -3.7], "rotY": -1.570796}, "boxA": {"model": "cardboard_box_01", "pos": [2.0, 0.0, -4.3], "rotY": 0.2}, "boxB": {"model": "cardboard_box_01", "pos": [2.05, 0.335, -4.28], "rotY": -0.3, "scale": 0.85}, "boxC": {"model": "cardboard_box_01", "pos": [-3.05, 0.0, -1.0], "rotY": 1.2}, "bulb": {"model": "lightbulb_01", "pos": [1.8, 2.28, -3.6], "rotY": 0.0}, "cassette": {"model": "portable_cassette_player", "pos": [-1.95, 0.551, 0.12], "rotY": 0.3}}

const EXTRA_PROPS := {"boombox": {"model": "boombox", "pos": [-2.35, 0.0, -0.5], "rotY": 1.570796}, "gamepad": {"model": "gamepad", "pos": [-0.3, 0.0, -1.95], "rotY": 0.5, "noCollider": true}, "bat": {"model": "baseball_bat", "pos": [-3.4, 0.254, 2.63], "rotY": 0.0, "rotX": 0.1, "rotZ": 0.1}, "football": {"model": "football", "pos": [-2.35, 0.0, 1.15], "rotY": 0.7, "hideNodes": ["football_inflated"], "zeroNodeX": "football_deflated"}, "mirror": {"model": "ornate_mirror_01", "pos": [0.47, 1.62, -2.749], "rotY": 0.0, "noCollider": true}, "stairPhotoA": {"model": "hanging_picture_frame_02", "pos": [-3.498, 2.55, 0.3], "rotY": 1.570796, "noCollider": true}, "stairPhotoB": {"model": "hanging_picture_frame_02", "pos": [-3.498, 3.5, -0.75], "rotY": 1.570796, "noCollider": true}, "oldTv": {"model": "Television_01", "pos": [2.55, 0.0, -4.33], "rotY": 0.0}, "socket": {"model": "pull_chain_light_socket", "pos": [1.8, 2.5, -3.6], "rotY": 0.0, "noCollider": true}, "toolbox": {"model": "metal_toolbox", "pos": [3.2, 0.0, -4.38], "rotY": -1.570796}, "laundry": {"model": "plastic_crate_02", "pos": [0.58, 0.0, -3.22], "rotY": 0.15}, "stool": {"model": "painted_wooden_stool", "pos": [0.62, 0.0, -3.72], "rotY": 0.0}, "broom": {"model": "wooden_broom", "pos": [0.29, 0.122, -3.72], "rotY": 1.570796, "rotZ": 0.12, "noCollider": true}, "bleach": {"model": "bleach_bottle", "pos": [0.85, 1.182, -4.3], "rotY": -0.3, "noCollider": true}, "jug": {"model": "plastic_bottle_gallon", "pos": [0.6, 1.182, -4.36], "rotY": 0.5, "noCollider": true}, "paintCan": {"model": "can_rusted", "pos": [3.36, 0.66, -3.95], "rotY": 1.0, "noCollider": true}, "gnome": {"model": "garden_gnome", "pos": [3.25, 0.0, -3.1], "rotY": -1.47}, "mousetrap": {"model": "mousetrap", "pos": [1.68, 0.0, -4.5], "rotY": 0.3, "noCollider": true}, "suitcase": {"model": "vintage_suitcase", "pos": [-3.31, 0.0, -1.2], "rotY": 1.570796, "hidePrefix": "vintage_suitcase_02"}, "suitcaseHall": {"model": "vintage_suitcase", "pos": [-3.47, 2.75, -4.356], "rotY": 1.570796, "hidePrefix": "vintage_suitcase_01", "noCollider": true}}

const ITEMS := {"note1": {"pos": [0.05, 0.536, 1.0], "rotY": 0.25}, "flashlight": {"inside": "dresser.drawerTop"}, "battery1": {"inside": "endTable.drawer"}, "battery2": {"inside": "alcoveCabinet.drawer_01"}, "key": {"inside": "lockedBox"}, "note2": {"pos": [-2.05, 0.552, 0.3], "rotY": -0.2}, "note3": {"inside": "alcoveCabinet.door_01"}}

const SPAWN := {"x": 0.25, "z": 1.5, "yaw": 0.0}

const NAV_NODES := {"hall": {"x": -3.0, "z": -3.6, "upper": true}, "landing": {"x": -3.0, "z": -2.3, "upper": true}, "stairsTop": {"x": -3.0, "z": -1.6}, "stairsMid": {"x": -3.0, "z": -0.1}, "stairsBottom": {"x": -3.0, "z": 2.05}, "swCorner": {"x": -2.2, "z": 2.1}, "kidCorner": {"x": -1.0, "z": 0.0}, "closetFront": {"x": -2.0, "z": -1.9}, "tvFront": {"x": -0.6, "z": -1.55}, "center": {"x": 0.9, "z": -0.45}, "sofaFront": {"x": -0.6, "z": 1.35}, "sofaEast": {"x": 1.55, "z": 1.25}, "alcoveDoor": {"x": 1.35, "z": -2.35}, "alcoveIn": {"x": 1.35, "z": -3.5}, "alcoveEast": {"x": 2.7, "z": -3.6}, "clockFront": {"x": 2.6, "z": -1.75}, "consoleFront": {"x": 2.35, "z": 0.15}, "rocking": {"x": 1.95, "z": 1.0}}

const NAV_LINKS := [["hall", "landing"], ["landing", "stairsTop"], ["stairsTop", "stairsMid"], ["stairsMid", "stairsBottom"], ["stairsBottom", "swCorner"], ["swCorner", "sofaFront"], ["swCorner", "kidCorner"], ["kidCorner", "closetFront"], ["kidCorner", "tvFront"], ["kidCorner", "sofaFront"], ["kidCorner", "center"], ["closetFront", "tvFront"], ["tvFront", "center"], ["tvFront", "alcoveDoor"], ["center", "alcoveDoor"], ["center", "clockFront"], ["center", "consoleFront"], ["center", "sofaEast"], ["center", "rocking"], ["alcoveDoor", "alcoveIn"], ["alcoveIn", "alcoveEast"], ["clockFront", "consoleFront"], ["consoleFront", "rocking"], ["rocking", "sofaEast"]]

## Height of the stair surface at (x, z) — floor of each tread. Returns NAN when not over the stairs footprint.
static func stair_height_at(x: float, z: float) -> float:
	if x < STAIRS.minX or x > STAIRS.maxX: return NAN
	if z > STAIRS.bottomZ: return NAN
	if z <= STAIRS.topZ: return UPPER.floorY
	var k := ceili((STAIRS.bottomZ - z) / STAIRS.treadDepth)
	return min(k, int(STAIRS.risers)) * STAIRS.riserHeight

## Walkable floor height. prev_y (optional, NAN = unknown) disambiguates the closet under the stairs.
static func ground_height_at(x: float, z: float, prev_y: float = NAN) -> float:
	var has_prev := not is_nan(prev_y)
	if x >= UPPER_HALL.minX and x <= UPPER_HALL.maxX and z < ROOM.minZ and z >= UPPER_HALL.minZ and (not has_prev or prev_y > 1.5):
		return UPPER.floorY
	if has_prev and prev_y < 1.0 and x >= CLOSET.minX and x <= CLOSET.maxX and z >= CLOSET.minZ and z <= CLOSET.maxZ:
		return 0.0
	var s := stair_height_at(x, z)
	if not is_nan(s): return s
	return 0.0
