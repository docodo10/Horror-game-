// Garderie: glossy vinyl over foam padding (posts, columns, rails, decks, mats on the frame, foam blocks).
// Base colour from vertex COLOR (deep saturated primaries). The silhouette folds are real geometry (garderie_kit.fold);
// here: fine leather grain (Poly Haven leather_white, CC0) + generated wrinkles (RNM blend), a smudged clear coat
// (roughness 0.15..0.35 from hand smudges concentrated 0.6..1.3 m above the floor, measured on the Subliminal wraps),
// scuffs / tape seams via the scratch map, grime rising from the hall floor.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D grain_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grain_orm : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D wrinkle_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D scratch_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float grain_scale = 9.0;
uniform float grain_strength = 0.3;
uniform float wrinkle_scale = 0.5;
uniform float wrinkle_strength = 0.7;
uniform float rough_min = 0.15;
uniform float rough_max = 0.35;
uniform float clearcoat_amt = 0.7;
uniform float clearcoat_rough = 0.06;
uniform float floor_y = -1.05;
uniform float dirt = 0.4;
uniform float sat = 1.0;
uniform float value = 1.0;

varying vec3 wpos;

// vertex / instance colours are authored in sRGB
vec3 srgb_to_lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 blend_rnm(vec3 n1, vec3 n2) {
	vec3 t = n1 * vec3(2.0, 2.0, 2.0) + vec3(-1.0, -1.0, 0.0);
	vec3 u = n2 * vec3(-2.0, -2.0, 2.0) + vec3(1.0, 1.0, -1.0);
	vec3 r = t * dot(t, u) - u * t.z;
	return normalize(r) * 0.5 + 0.5;
}

void fragment() {
	vec3 c = srgb_to_lin(COLOR.rgb) * value;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, sat);
	vec4 nz = texture(noise_tex, wpos.xz * 0.21 + vec2(wpos.y * 0.13));
	// 25..40 cm smudge field + hand band (0.6..1.3 m above the local floor)
	vec4 nz2 = texture(noise_tex, vec2(wpos.x + wpos.z, wpos.y) * 0.33 + vec2(0.17, 0.61));
	float hy = wpos.y - floor_y;
	float hand = smoothstep(0.45, 0.7, hy) * (1.0 - smoothstep(1.2, 1.45, hy));
	vec3 sc = texture(scratch_tex, UV * 0.55).rgb;
	float smudge = clamp(nz2.r * 0.75 + hand * 0.45 * nz2.g + sc.g * 0.5 - 0.25, 0.0, 1.0);
	float d = (1.0 - smoothstep(floor_y, floor_y + 0.9, wpos.y)) * dirt;
	c *= 0.9 + nz.g * 0.2;
	c = mix(c, c * vec3(0.5, 0.46, 0.42), clamp(d * (0.35 + nz.r) + sc.g * 0.18, 0.0, 1.0));
	ALBEDO = c;
	// the folds are real geometry: the normal-mapped wrinkles / grain only add close-up detail and fade out with
	// distance (beyond a few metres they alias into a glittering clear coat)
	float vd = length(VERTEX);
	float near_k = 1.0 - smoothstep(1.5, 7.0, vd);
	vec3 gn = mix(vec3(0.5, 0.5, 1.0), texture(grain_n, UV * grain_scale).xyz, grain_strength * (0.25 + 0.75 * near_k));
	vec3 wn = mix(vec3(0.5, 0.5, 1.0), texture(wrinkle_n, UV * wrinkle_scale).xyz, wrinkle_strength * (0.3 + 0.7 * near_k));
	NORMAL_MAP = blend_rnm(wn, gn);
	float gr = texture(grain_orm, UV * grain_scale).g;
	ROUGHNESS = clamp(mix(rough_min, rough_max, smudge) * (0.8 + gr * 0.4) + sc.r * 0.15 + d * 0.3, 0.05, 1.0);
	SPECULAR = 0.5;
	CLEARCOAT = clearcoat_amt * (1.0 - smudge * 0.45) * (1.0 - d * 0.6);
	CLEARCOAT_ROUGHNESS = clearcoat_rough + smudge * 0.12 + sc.r * 0.25;
}
