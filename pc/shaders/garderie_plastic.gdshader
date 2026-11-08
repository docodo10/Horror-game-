// Garderie: rotomoulded glossy plastic (slides, crawl tube, signs housings). Vertex COLOR = plastic colour.
// Scratches along the sliding direction (UV v), fingerprints / smudges, dust that settles on up-facing parts,
// optional translucency (BACKLIGHT) for the coloured tube so it glows when lit from outside.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D scratch_tex : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float rough_base = 0.1;
uniform float scratch_amt = 1.0;
uniform float dust = 0.6;
uniform float backlight_amt = 0.0;
uniform float sat = 1.0;
uniform float value = 1.0;
uniform float clearcoat_amt = 0.5;

varying vec3 wpos;

// vertex / instance colours are authored in sRGB
vec3 srgb_to_lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = srgb_to_lin(COLOR.rgb) * value;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, sat);
	vec3 s = texture(scratch_tex, UV * vec2(0.9, 0.35)).rgb;
	vec3 s2 = texture(scratch_tex, UV * vec2(0.27, 0.11) + vec2(0.37, 0.11)).rgb;
	vec4 nz = texture(noise_tex, wpos.xz * 0.3 + vec2(wpos.y * 0.2));
	float scr = max(s.r, s2.r * 0.8) * scratch_amt;
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float up = clamp(wn.y, 0.0, 1.0);
	float du = (s.b * 0.8 + nz.b * 0.6) * dust * up * up + s2.g * 0.25 * dust;
	c *= 0.94 + nz.g * 0.12;
	c = mix(c, vec3(0.74, 0.72, 0.68), clamp(du * 0.45 + scr * 0.12, 0.0, 1.0));
	ALBEDO = c;
	ROUGHNESS = clamp(rough_base + scr * 0.3 + du * 0.55 + s.g * 0.18, 0.03, 1.0);
	SPECULAR = 0.55;
	CLEARCOAT = clearcoat_amt * (1.0 - du);
	CLEARCOAT_ROUGHNESS = 0.06 + scr * 0.4;
	if (backlight_amt > 0.0) {
		BACKLIGHT = c * backlight_amt;
	}
}
