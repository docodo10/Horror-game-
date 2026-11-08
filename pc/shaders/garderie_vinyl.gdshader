// Garderie: glossy vinyl over foam padding (posts, columns, rails, decks, mats on the frame, foam blocks).
// Base colour from vertex COLOR. Fine leather grain (Poly Haven leather_white, CC0) + generated wrinkles (RNM blend),
// clear-coat highlights, smudges / scuffs, grime rising from the hall floor, tape seams via the scratch map.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D grain_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grain_orm : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D wrinkle_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D scratch_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float grain_scale = 9.0;
uniform float grain_strength = 0.45;
uniform float wrinkle_scale = 0.9;
uniform float wrinkle_strength = 0.85;
uniform float rough_base = 0.17;
uniform float clearcoat_amt = 0.9;
uniform float floor_y = -1.05;
uniform float dirt = 0.4;
uniform float sat = 0.92;
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
	vec3 sc = texture(scratch_tex, UV * 0.55).rgb;
	float d = (1.0 - smoothstep(floor_y, floor_y + 0.9, wpos.y)) * dirt;
	c *= 0.9 + nz.g * 0.2;
	c = mix(c, c * vec3(0.5, 0.46, 0.42), clamp(d * (0.35 + nz.r) + sc.g * 0.22, 0.0, 1.0));
	ALBEDO = c;
	vec3 gn = mix(vec3(0.5, 0.5, 1.0), texture(grain_n, UV * grain_scale).xyz, grain_strength);
	vec3 wn = mix(vec3(0.5, 0.5, 1.0), texture(wrinkle_n, UV * wrinkle_scale).xyz, wrinkle_strength);
	NORMAL_MAP = blend_rnm(wn, gn);
	float gr = texture(grain_orm, UV * grain_scale).g;
	ROUGHNESS = clamp(rough_base * (0.65 + gr * 0.7) + sc.g * 0.28 + d * 0.3, 0.05, 1.0);
	SPECULAR = 0.5;
	CLEARCOAT = clearcoat_amt * (1.0 - sc.g * 0.6) * (1.0 - d * 0.6);
	CLEARCOAT_ROUGHNESS = 0.07 + sc.r * 0.3;
}
