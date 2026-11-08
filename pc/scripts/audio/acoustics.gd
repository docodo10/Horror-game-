## Audio module — acoustic model of the house (port of src/audio/Audio.js `_zoneOf/_occl/_doorway`), pure functions.
## Zones: where a point is (basement room, stairwell, laundry nook, upstairs hall, above the ceiling, closet under the
## stairs, inside/behind a wall, outside the window). Occlusion = (low-pass Hz, gain) between a source zone and the
## listener zone; the upstairs door is continuous (0 = closed .. 1 = open) so a door being opened opens the sound.
extends RefCounted

const Z_ROOM := 0
const Z_STAIR := 1
const Z_NOOK := 2
const Z_HALL := 3
const Z_CEIL := 4
const Z_CLOSET := 5
const Z_WALL := 6
const Z_OUT := 7
const ZONE_NAMES := ["room", "stairwell", "nook", "hall", "ceiling", "closet", "wall", "outside"]

## Reverb space per zone: 0 = small carpeted basement (ReverbRoom), 1 = darker/longer (laundry nook concrete, stairwell,
## upstairs hall: ReverbDark), and the send amount into it. Web sends per source zone: ZONE_ROOM = [1, .6, .15, .1, .35,
## .3, .4, .2], ZONE_LONG = [0, .5, 1, .75, 0, 0, 0, .15] -> one send to the dominant space, energy-summed.
const SPACE_OF_ZONE := [0, 1, 1, 1, 0, 0, 0, 0]
const SEND_OF_ZONE := [1.0, 0.78, 1.0, 0.757, 0.35, 0.3, 0.4, 0.25]

const R := Layout.ROOM
const ST := Layout.STAIRS
const AL := Layout.ALCOVE
const UH := Layout.UPPER_HALL
const CL := Layout.CLOSET

const LN2 := 0.6931471805599453


static func zone_of(p: Vector3) -> int:
	var x := p.x
	var y := p.y
	var z := p.z
	if y > float(R.ceilingY) + 0.05:
		if z < float(R.minZ) - 0.05:
			return Z_HALL if (x >= float(UH.minX) and x <= float(UH.maxX)) else Z_WALL
		if x <= float(ST.maxX) + 0.1 and z < float(ST.ceilingOpeningMaxZ):
			return Z_STAIR
		if x < float(R.minX) or x > float(R.maxX) or z > float(R.maxZ):
			return Z_WALL
		return Z_CEIL
	if z < float(R.minZ) - 0.05:
		return Z_NOOK if (x >= float(AL.minX) and x <= float(AL.maxX) and z >= float(AL.minZ)) else Z_WALL
	if z > float(R.maxZ) + 0.05:
		return Z_OUT
	if x < float(R.minX) - 0.05 or x > float(R.maxX) + 0.05:
		return Z_WALL
	if x >= float(CL.minX) and x <= float(CL.maxX) and z >= float(CL.minZ) and z <= float(CL.maxZ):
		var sh := Layout.stair_height_at(x, z)
		if is_nan(sh):
			sh = float(R.ceilingY)
		if y < sh - 0.05:
			return Z_CLOSET
	if x <= float(ST.maxX) and z < float(ST.bottomZ) and y > 1.0:
		return Z_STAIR
	return Z_ROOM


## 0..1: how much of the straight path listener -> source goes through the laundry-nook doorway (soft edges).
static func doorway(sp: Vector3, lp: Vector3) -> float:
	var dz := sp.z - lp.z
	if absf(dz) < 1e-4:
		return 0.0
	var t := (float(R.minZ) - lp.z) / dz
	if t < 0.0 or t > 1.0:
		return 1.0
	var x := lp.x + (sp.x - lp.x) * t
	var y := lp.y + (sp.y - lp.y) * t
	var d: Dictionary = AL.doorway
	var o := clampf((minf(x - float(d.minX), float(d.maxX) - x) + 0.3) / 0.6, 0.0, 1.0)
	if y > float(d.height):
		o *= clampf(1.0 - (y - float(d.height)) / 0.35, 0.0, 1.0)
	return o


static func _lerp_hz(a: float, b: float, t: float) -> float:
	return exp(lerpf(log(a), log(b), t))


## Occlusion between a source (zone sz at sp) and the listener (zone lz at lp). door_t: upstairs door openness 0..1.
## Returns Vector2(low-pass Hz, gain) — 20000 Hz / 1.0 when nothing is in the way.
static func occlusion(sz: int, lz: int, door_t: float, sp: Vector3, lp: Vector3) -> Vector2:
	var hz := 20000.0
	var g := 1.0
	var a := Z_ROOM if sz == Z_STAIR else sz
	var b := Z_ROOM if lz == Z_STAIR else lz
	if a != b:
		var nook := b == Z_NOOK
		match a:
			Z_CEIL:
				hz = 420.0 if nook else 600.0
				g = 0.4 if nook else 0.62
			Z_HALL:
				if nook:
					hz = _lerp_hz(380.0, 1600.0, door_t)
					g = lerpf(0.28, 0.5, door_t)
				else:
					hz = _lerp_hz(520.0, 5500.0, door_t)
					g = lerpf(0.42, 0.9, door_t)
			Z_WALL:
				hz = 650.0 if nook else 950.0
				g = 0.5 if nook else 0.68
			Z_OUT:
				hz = 700.0 if nook else 1500.0
				g = 0.35 if nook else 0.6
			Z_CLOSET:
				hz = 1200.0 if nook else 2600.0
				g = 0.45 if nook else 0.72
			Z_NOOK, Z_ROOM:
				if b == Z_NOOK or b == Z_ROOM:
					var o := doorway(sp, lp)
					hz = lerpf(1300.0, 9000.0, o)
					g = lerpf(0.5, 0.95, o)
				elif b == Z_CLOSET:
					hz = 1200.0 if a == Z_NOOK else 3400.0
					g = 0.45 if a == Z_NOOK else 0.82
				elif b == Z_HALL:
					hz = _lerp_hz(500.0, 5000.0, door_t)
					g = lerpf(0.4, 0.85, door_t)
	return Vector2(hz, g)


## Web Audio "inverse" distance model (PannerNode: refDistance, rolloffFactor), plus a smooth fade 20 -> 25 m.
static func distance_gain(ref: float, roll: float, d: float) -> float:
	var dd := maxf(d, ref)
	var g := ref / (ref + roll * (dd - ref))
	if d > 20.0:
		g *= 1.0 - smoothstep(20.0, 25.0, d)
	return g


## Maps a 2-pole low-pass cutoff (the web occlusion filter) to the per-voice high-shelf Godot offers
## (AudioStreamPlayer3D attenuation filter): Vector2(shelf corner Hz, high-frequency gain dB).
static func shelf_for_lowpass(hz: float) -> Vector2:
	if hz >= 15000.0:
		return Vector2(16000.0, 0.0)
	var depth := -6.3 * log(16000.0 / maxf(hz, 60.0)) / LN2
	return Vector2(clampf(hz * 1.6, 250.0, 16000.0), clampf(depth, -42.0, 0.0))
