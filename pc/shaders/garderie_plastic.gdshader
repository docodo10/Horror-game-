// Garderie: rotomoulded glossy plastic (slides, crawl tube, sign housings, small props). Vertex COLOR = plastic colour
// (deep, saturated), COLOR.a < 1 = cavity (lane corners, lips, seams: authored by the builders) where dust and grime
// settle. "Broken" specular like the reference slides: roughness 0.12..0.35 from a 25..40 cm smudge field, long
// scratches along the sliding direction (UV v runs down the slide), fingerprints, dust on up-facing parts and in the
// cavities; optional translucency (BACKLIGHT) for the coloured tubes.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D scratch_tex : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float rough_min = 0.12;
uniform float rough_max = 0.35;
uniform float scratch_amt = 1.0;
uniform float dust = 0.6;
uniform float cavity_dust = 1.0;
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
	// long run-direction scratches (stretched ~20x along v)
	float run = texture(scratch_tex, UV * vec2(2.3, 0.07) + vec2(0.5, 0.0)).r;
	vec4 nz = texture(noise_tex, wpos.xz * 0.3 + vec2(wpos.y * 0.2));
	vec4 nzs = texture(noise_tex, vec2(wpos.x + wpos.y * 0.7, wpos.z - wpos.y * 0.4) * 0.3 + vec2(0.41, 0.13));
	float smudge = clamp(nzs.r * 1.3 - 0.25 + s.g * 0.45, 0.0, 1.0);
	float scr = max(max(s.r, s2.r * 0.8), run * 0.9) * scratch_amt;
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float up = clamp(wn.y, 0.0, 1.0);
	float cav = (1.0 - COLOR.a) * cavity_dust;
	float du = (s.b * 0.8 + nz.b * 0.6) * dust * up * up + s2.g * 0.25 * dust + cav * (0.55 + nz.r * 0.6);
	du = clamp(du, 0.0, 1.0);
	c *= 0.94 + nz.g * 0.12;
	c = mix(c, c * 0.75, cav);                      // grime in the corners
	c = mix(c, vec3(0.52, 0.5, 0.46) * (0.6 + 0.4 * l), clamp(du * 0.5 + scr * 0.1, 0.0, 1.0));
	ALBEDO = c;
	ROUGHNESS = clamp(mix(rough_min, rough_max, smudge) + scr * 0.25 + du * 0.5, 0.03, 1.0);
	SPECULAR = 0.55;
	CLEARCOAT = clearcoat_amt * (1.0 - du) * (1.0 - smudge * 0.35);
	CLEARCOAT_ROUGHNESS = 0.05 + scr * 0.35 + smudge * 0.1;
	if (backlight_amt > 0.0) {
		BACKLIGHT = c * backlight_amt;
	}
}
