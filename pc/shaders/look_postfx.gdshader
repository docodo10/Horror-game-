// La Gardienne — look module: full-screen "lens + film" pass (port of src/render/PostFX.js FRAG).
// Drawn by scripts/render/look_rig.gd on a CanvasLayer BELOW the UI (layer 10 < 20). Input = the screen after Godot's
// tonemapper (AgX), glow, depth of field and AA, i.e. display space (sRGB-encoded, 0..1): everything here works in display
// space (no double gamma). Effects: slight barrel distortion, lateral chromatic aberration growing toward the corners,
// contrast-adaptive sharpening (TAA presets), defocus + radial blur (Quality.set_blur), lens edge softness, grade
// (lift / gamma / gain, saturation, shadow toe, soft S-curve, brightness display gamma), natural vignette, fear response
// (desaturation, CA, vignette, heartbeat pulse), closet view (dark edges + soft louver shadows), flash, screen shake (UV
// offset + roll, auto zoom margin), animated luminance-aware film grain (mono + a little chroma).
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;

uniform float frame = 0.0;
uniform float zoom = 1.0;
uniform float distort = 0.03;
uniform vec3 shake = vec3(0.0);          // uv offset xy, roll (rad)
uniform float ca = 0.003;                // lateral CA (uv units at the corners)
uniform float sharpen = 0.0;             // 0..1 contrast-adaptive sharpening
uniform float vignette = 0.34;
uniform float grain = 0.028;
uniform float grain_smooth = 0.0;        // 1 = soft value-noise grain (high/ultra), 0 = per-pixel
uniform float fear = 0.0;
uniform float pulse = 0.0;
uniform float blur = 0.0;
uniform float edge_soft = 0.0;
uniform int blur_taps = 12;
uniform float hidden = 0.0;
uniform float slat_phase = 0.0;
uniform float slat_axis = 0.0;           // 0 = horizontal louvers stacked vertically, 1 = vertical slats
uniform vec4 flash = vec4(1.0, 1.0, 1.0, 0.0);
uniform float flash_mode = 1.0;          // 1 = screen (bright flash), 0 = mix toward a dark colour
uniform vec3 lift = vec3(0.010, 0.0088, 0.0072);
uniform vec3 gamma_v = vec3(1.0, 0.99, 1.0);
uniform vec3 gain = vec3(1.02, 1.0, 0.97);
uniform float sat = 0.92;
uniform float contrast = 0.1;
uniform float toe = 0.06;
uniform float bright_gamma = 1.0;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

vec3 fetch(vec2 uv) {
	return textureLod(screen_tex, uv, 0.0).rgb;
}

// PCG3D hash (integer, no precision issues)
uvec3 pcg3d(uvec3 v) {
	v = v * 1664525u + 1013904223u;
	v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
	v ^= v >> uvec3(16u);
	v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
	return v;
}

vec3 hash3(vec2 p) {
	return vec3(pcg3d(uvec3(uvec2(p + 8192.0), uint(frame)))) * (1.0 / 4294967295.0);
}

vec3 grain_noise(vec2 fc, float scale) {
	if (grain_smooth > 0.5) {
		// value noise on a lattice slightly coarser than a pixel: softer, more "filmic" than per-pixel white noise
		vec2 p = fc / scale;
		vec2 i = floor(p);
		vec2 f = fract(p);
		f = f * f * (3.0 - 2.0 * f);
		vec3 a = hash3(i);
		vec3 b = hash3(i + vec2(1.0, 0.0));
		vec3 c = hash3(i + vec2(0.0, 1.0));
		vec3 d = hash3(i + vec2(1.0, 1.0));
		vec3 n = mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
		return 0.5 + (n - 0.5) * 1.45; // restore the variance lost by interpolation
	}
	return hash3(fc);
}

// AMD FidelityFX CAS (contrast adaptive sharpening), 5 taps
vec3 cas(vec2 uv, vec2 px, vec3 c) {
	vec3 n = fetch(uv + vec2(0.0, -px.y));
	vec3 s = fetch(uv + vec2(0.0, px.y));
	vec3 e = fetch(uv + vec2(px.x, 0.0));
	vec3 w = fetch(uv + vec2(-px.x, 0.0));
	vec3 mn = min(c, min(min(n, s), min(e, w)));
	vec3 mx = max(c, max(max(n, s), max(e, w)));
	vec3 amp = sqrt(clamp(min(mn, 1.0 - mx) / max(mx, vec3(1e-4)), 0.0, 1.0));
	vec3 wt = amp * (-1.0 / mix(8.0, 5.0, sharpen));
	return clamp((c + (n + s + e + w) * wt) / (1.0 + 4.0 * wt), 0.0, 1.0);
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 res = 1.0 / px;
	float aspect = res.x / res.y;
	float inv_corner = 1.0 / (0.25 * aspect * aspect + 0.25);
	vec2 suv = SCREEN_UV;

	// ---- lens geometry: shake roll + zoom margin + barrel distortion + shake offset
	vec2 d = suv - 0.5;
	d.x *= aspect;
	float cr = cos(shake.z), sr = sin(shake.z);
	d = vec2(cr * d.x - sr * d.y, sr * d.x + cr * d.y);
	d *= zoom;
	float r2 = dot(d, d) * inv_corner;       // 0 at the centre, ~1 at the corners
	d *= 1.0 + distort * r2;
	d.x /= aspect;
	vec2 base = 0.5 + shake.xy;
	vec2 uv = base + d;

	// lateral chromatic aberration grows with the squared radius (and with fear)
	vec2 ca_off = d * (ca * r2);

	// ---- base colour (+ sharpening) + CA
	vec3 col = fetch(uv);
	if (sharpen > 0.001) col = cas(uv, px, col);
	float ca_px = length(ca_off * res);
	if (ca_px > 0.25) {
		float w = clamp(ca_px - 0.25, 0.0, 1.0);
		col.r = mix(col.r, fetch(uv + ca_off).r, w);
		col.b = mix(col.b, fetch(uv - ca_off).b, w);
	}

	// ---- blur: defocus disc + radial zoom (set_blur) + lens edge softness. Radii in uv-height units.
	float edge = edge_soft * r2 * r2;
	float blur_r = blur * 0.011 + edge * 0.0016;
	if (blur_r * res.y > 0.6) {
		vec3 acc = col;
		float wsum = 1.0;
		float zoom_k = blur * 0.06;
		// per-pixel rotation of the spiral turns discrete ghost copies into fine noise (hidden by the grain)
		float jit = hash3(FRAGCOORD.xy + 17.0).x * 6.2831853;
		for (int i = 0; i < blur_taps; i++) {
			float t = (float(i) + 0.5) / float(blur_taps);
			float a = float(i) * 2.39996323 + jit;
			vec2 o = vec2(cos(a), sin(a)) * sqrt(t) * blur_r;
			o.x /= aspect;
			vec2 tuv = base + d * (1.0 - zoom_k * t) + o;
			vec3 tc = fetch(tuv);
			if (ca_px > 0.25) {
				tc.r = mix(tc.r, fetch(tuv + ca_off).r, 0.8);
				tc.b = mix(tc.b, fetch(tuv - ca_off).b, 0.8);
			}
			acc += tc;
			wsum += 1.0;
		}
		col = acc / wsum;
	}

	// ---- grade (display space)
	float L = dot(col, LUMA);
	float s = sat * (1.0 - 0.45 * fear) * (1.0 - 0.25 * hidden);
	col = max(mix(vec3(L), col, s), 0.0);
	col = pow(max(col * gain, vec3(0.0)), gamma_v);
	col = clamp(col, 0.0, 1.0);
	// toe: x (x + 0.75 t) / (x + t), normalised — slightly deeper shadows below ~0.2, slope at black stays 0.75
	col = col * (col + 0.75 * toe) / (col + toe + 1e-5) * ((1.0 + toe) / (1.0 + 0.75 * toe));
	col = mix(col, col * col * (3.0 - 2.0 * col), contrast);
	col = pow(col, vec3(bright_gamma));

	// ---- vignette (cos^4-like falloff), fear pulse, closet view
	float vig_a = vignette + 0.22 * fear + 0.35 * pulse + 0.8 * hidden;
	float vq = 1.0 + vig_a * r2;
	col *= 1.0 / (vq * vq);
	col.r += pulse * 0.03 * r2 * (1.0 - col.r);
	if (hidden > 0.001) {
		// out-of-focus louver shadows (very close to the eye): soft cosine bands, weaker where the eye looks through
		float sl = mix(SCREEN_UV.y, SCREEN_UV.x * aspect, slat_axis) * 6.5 + slat_phase;
		float slat = 0.5 + 0.5 * cos(sl * 6.2831853);
		slat = slat * slat * mix(0.45, 1.0, smoothstep(0.0, 0.7, r2));
		col *= 1.0 - hidden * (0.32 * slat + 0.30 * smoothstep(0.15, 1.0, r2));
	}

	// ---- camera black level (after the lens vignette): warm-brown lifted shadows, never pure digital black
	col += lift * (1.0 - col);

	// ---- flash
	vec3 fc = flash.rgb;
	col = mix(col, mix(fc, col + fc * (1.0 - col), flash_mode), flash.a);

	// ---- film grain: luminance-aware (strongest in low mids, weaker in highlights), mostly mono + a bit of chroma
	float gscale = max(1.0, res.y / 1080.0 * 0.9);
	vec3 h = grain_noise(FRAGCOORD.xy, gscale);
	float g = h.x + h.y - 1.0;
	L = dot(col, LUMA);
	float gw = mix(1.0, 0.3, smoothstep(0.2, 0.9, L)) * (0.55 + 0.45 * smoothstep(0.0, 0.06, L));
	float amt = grain * (1.0 + 1.0 * fear + 0.6 * hidden);
	col += amt * gw * (vec3(g) + (h.z - 0.5) * vec3(0.30, -0.12, -0.24));

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
