## Procedural flashlight cookie (SpotLight3D.light_projector) — port of makeCookieTexture() in src/player/Player.js:
## hot core, smooth body, warm spill, faint reflector ring, angular reflector imperfections, lens smudges (same seeded RNG,
## same pixels as the web build). Godot extras:
##  * three.js multiplies the cookie by the spot penumbra (smoothstep between cos(angle) and cos(angle * (1 - penumbra)));
##    Godot's cone falloff has another shape, so that penumbra is baked into the texture and the light uses a flat cone
##    (high spot_angle_attenuation) => identical beam profile.
##  * Godot samples projector textures from the sRGB decal atlas: the linear cookie values are sRGB-encoded so the light
##    receives exactly the web's (linear, NoColorSpace) values.
## Usage: light.light_projector = FlashlightCookie.make(256, 0.42, 0.45)  (preload this script; no class_name on purpose)
extends RefCounted

static func _rnd(state: Array) -> float:
	# Park-Miller minimal standard generator (same sequence as the web version's rnd()). `state` is an Array so the
	# callee's write is shared with the caller (packed arrays are copy-on-write).
	var s: int = (int(state[0]) * 16807) % 2147483647
	state[0] = s
	return float(s - 1) / 2147483646.0

## size: texture size (px). angle: spot half-angle (rad). penumbra: three.js penumbra (0..1). srgb: encode for Godot's atlas.
static func make(size := 256, angle := 0.42, penumbra := 0.45, srgb := true) -> ImageTexture:
	var state := [1337]
	var blobs: Array[PackedFloat32Array] = []
	for i in 10:
		var a := _rnd(state) * TAU
		var r := sqrt(_rnd(state)) * 0.6
		blobs.append(PackedFloat32Array([cos(a) * r, sin(a) * r, 0.035 + _rnd(state) * 0.08, 0.05 + _rnd(state) * 0.08]))
	var n := size * size
	var vals := PackedFloat32Array()
	vals.resize(n)
	var h := size * 0.5
	var tan_a := tan(angle)
	var cos_outer := cos(angle)
	var cos_inner := cos(angle * (1.0 - penumbra))
	# pass 1: radial profile x angular imperfections x per-pixel grain (RNG consumed in the web's pixel order)
	for py in size:
		var y := (py + 0.5 - h) / h
		for px in size:
			var x := (px + 0.5 - h) / h
			var r := sqrt(x * x + y * y)
			if r >= 1.0:
				continue
			var hot := 0.32 * exp(-pow(r / 0.12, 2.0))
			var body := 0.7 * pow(1.0 - smoothstep(0.2, 0.62, r), 1.4)
			var spill := 0.17 * (1.0 - smoothstep(0.48, 0.97, r))
			var ring := 0.05 * exp(-pow((r - 0.34) / 0.03, 2.0)) - 0.035 * exp(-pow((r - 0.43) / 0.05, 2.0))
			var v := hot + body + spill + ring
			var th := atan2(y, x)
			var ir := smoothstep(0.18, 0.5, r)
			v *= 1.0 + ir * (0.04 * sin(3.0 * th + 0.7) + 0.025 * sin(7.0 * th + 2.1) + 0.015 * sin(13.0 * th + 0.3))
			v *= 1.0 + (_rnd(state) - 0.5) * 0.025
			# three.js spot penumbra at this pixel's angle (perspective projection: r = tan(a) / tan(angle))
			var ca := cos(atan(r * tan_a))
			v *= smoothstep(cos_outer, cos_inner, ca)
			vals[py * size + px] = v
	# pass 2: lens smudges (only inside each blob's footprint, q < 4)
	for b in blobs:
		var rad := 2.0 * b[2]
		var x0 := maxi(0, int(floor((b[0] - rad) * h + h)))
		var x1 := mini(size - 1, int(ceil((b[0] + rad) * h + h)))
		var y0 := maxi(0, int(floor((b[1] - rad) * h + h)))
		var y1 := mini(size - 1, int(ceil((b[1] + rad) * h + h)))
		var inv_r2 := 1.0 / (b[2] * b[2])
		for py in range(y0, y1 + 1):
			var y := (py + 0.5 - h) / h
			for px in range(x0, x1 + 1):
				var i := py * size + px
				if vals[i] == 0.0:
					continue
				var x := (px + 0.5 - h) / h
				var dx := x - b[0]
				var dy := y - b[1]
				var q := (dx * dx + dy * dy) * inv_r2
				if q < 4.0:
					vals[i] *= 1.0 - b[3] * exp(-q)
	# pass 3: tint (cool-white core, warmer spill) + encode
	var bytes := PackedByteArray()
	bytes.resize(n * 4)
	for py in size:
		var y := (py + 0.5 - h) / h
		for px in size:
			var x := (px + 0.5 - h) / h
			var i := py * size + px
			var v := clampf(vals[i], 0.0, 1.0)
			var w := smoothstep(0.25, 0.8, sqrt(x * x + y * y))
			var c := Color(v, v * (0.985 - 0.08 * w), v * (0.96 - 0.2 * w))
			if srgb:
				c = c.linear_to_srgb()
			var o := i * 4
			bytes[o] = int(round(clampf(c.r, 0.0, 1.0) * 255.0))
			bytes[o + 1] = int(round(clampf(c.g, 0.0, 1.0) * 255.0))
			bytes[o + 2] = int(round(clampf(c.b, 0.0, 1.0) * 255.0))
			bytes[o + 3] = 255
	var img := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, bytes)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
