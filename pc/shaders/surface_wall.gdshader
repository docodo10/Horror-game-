// Surfaces module — painted walls (drywall, plaster, painted block, wallpaper) of the basement level.
// World-space planar projection of a hi-res PBR set + layered, non-repeating wear:
//   paint colour x high-passed texture detail, world-space macro variation (value + hue), cavity dirt,
//   rising grime / kick marks over the floor line (follows the stairs), dust under the ceiling, dirt in corners,
//   rubber scuffs at baseboard and furniture height, greasy hand smudges, water run-down streaks, rising damp,
//   efflorescence and mould (nook / closet), drywall joints, roller waviness and paint drips in the normal,
//   roughness breakup (dust = matte, grease / scuffs / damp = glossier).
// Parameters are set per material by pc/scripts/surfaces/surfaces.gd (recipes) — defaults = main room drywall.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/surface_common.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mask_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable; // R ao, G height, B rough
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;             // R/G/B fbm, A blotches
uniform sampler2D grunge_tex : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable; // R smudge, G streak, B scuff
uniform sampler2D uv_albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;   // optional print (mesh UV)

uniform float detail_level = 1.0;          // 0 = medium preset (no macro normal / drips / joints), 1 = high
uniform float tile_size = 2.0;             // metres per repeat of the hi-res set
uniform vec3 paint_color : source_color = vec3(0.84, 0.77, 0.63);
uniform float tex_color_mix = 0.0;         // 0 = paint colour x texture luminance detail, 1 = raw texture colour
uniform float tex_mean_lum = 0.5;          // mean luminance of albedo_tex (used when highpass = 0)
uniform float highpass = 0.85;             // remove the texture's own low frequencies (anti-tiling)
uniform float hp_lod = 6.0;                // blurred mip used as the low-pass reference
uniform float detail_contrast = 1.0;
uniform float uv_albedo_mix = 0.0;         // > 0: multiply in uv_albedo_tex (upper-hall wallpaper print)
uniform float vertex_color_amount = 0.85;  // the web build's baked AO / grime (vertex colours)
uniform float normal_strength = 0.8;
uniform float ao_amount = 0.6;
uniform float cavity_dirt = 0.25;
uniform float specular_level = 0.4;

uniform float macro_amount = 0.07;         // world-space value variation
uniform float macro_hue = 0.5;             // yellowed patches
uniform float wave_amp = 0.006;            // roller / board waviness (normal)
uniform float seam_amount = 0.0;           // drywall tape joints (normal ridge + sheen)
uniform float drip_amount = 0.0;           // paint drips (normal + gloss)

uniform vec3 grime_color : source_color = vec3(0.36, 0.31, 0.25);
uniform float floor_grime = 0.55;
uniform float floor_grime_height = 0.42;
uniform float ceil_grime = 0.25;
uniform float corner_grime = 0.4;
uniform float corner_radius = 0.28;
uniform float scuff_amount = 0.55;
uniform float smudge_amount = 0.35;
uniform float streak_amount = 0.25;
uniform vec3 streak_tint : source_color = vec3(0.80, 0.70, 0.52);
uniform float damp_amount = 0.0;
uniform float damp_height = 0.55;
uniform float efflorescence = 0.0;
uniform float mould_amount = 0.0;
uniform float speck_amount = 0.5;           // fly / dirt specks on the lower wall
uniform float scratch_amount = 0.4;         // thin pencil-like scratches and scrapes

uniform float rough_base = 0.82;
uniform float rough_detail = 1.0;          // x (mask.b - rough_mid)
uniform float rough_mid = 0.9;
uniform float rough_var = 0.06;
uniform float rough_grime = 0.95;
uniform float rough_smudge = 0.5;

varying vec3 v_wpos;
varying vec3 v_wnrm;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 p = v_wpos;
	vec3 N = normalize(v_wnrm);
	vec2 uvm;
	vec3 T;
	vec3 B;
	surf_project(p, N, uvm, T, B);
	vec2 uv = uvm / tile_size;
	bool wall = abs(N.y) < 0.6;

	// ---------------------------------------------------------------- samples
	vec3 a = texture(albedo_tex, uv).rgb;
	vec3 a_lo = textureLod(albedo_tex, uv, hp_lod).rgb;
	vec4 m = texture(mask_tex, uv);
	vec4 nt = texture(normal_tex, uv);
	float n_big = texture(noise_tex, uvm / 3.7).r;
	float n_mid = texture(noise_tex, uvm / 1.3 + vec2(0.37, 0.11)).g;
	float n_fine = texture(noise_tex, uvm / 0.45 + vec2(0.19, 0.53)).b;
	float blot = texture(noise_tex, uvm / 2.3 + vec2(0.61, 0.27)).a;
	float n_big2 = texture(noise_tex, uvm / 5.3 + vec2(0.71, 0.43)).r;
	float g_smudge = texture(grunge_tex, uvm / 1.7).r;
	float g_streak = texture(grunge_tex, vec2(uvm.x / 2.3, uvm.y / 3.1) + vec2(0.29, 0.0)).g;
	float g_scuff = texture(grunge_tex, vec2(uvm.x / 1.25, uvm.y / 0.6) + vec2(0.13, 0.41)).b;

	// ---------------------------------------------------------------- geometry-driven masks
	float fy = surf_floor_y(p);
	float h = max(p.y - fy, 0.0);
	float hc = max(surf_ceil_y(p) - p.y, 0.0);
	float dc = wall ? surf_corner_dist(p, N) : 99.0;

	float fb = 1.0 - smoothstep(0.0, floor_grime_height * (0.7 + 0.6 * n_mid), h);
	fb = fb * fb * (0.6 + 0.4 * g_smudge);
	float dust_line = exp(-h / 0.035);
	float cb = exp(-hc / 0.14) * (0.55 + 0.45 * n_fine);
	float cg = exp(-dc / corner_radius) * (0.45 + 0.55 * n_mid) * (0.55 + 0.45 * max(1.0 - smoothstep(0.0, 0.8, h), exp(-hc / 0.5)));
	float kick = smoothstep(0.04, 0.1, h) * (1.0 - smoothstep(0.3, 0.55, h));
	float fur = smoothstep(0.5, 0.62, h) * (1.0 - smoothstep(0.82, 1.02, h));
	float scuff = smoothstep(0.3, 0.8, g_scuff) * (kick * smoothstep(0.4, 0.7, n_mid) + fur * 0.7 * smoothstep(0.55, 0.8, blot + n_fine * 0.3));
	float hands = smoothstep(0.75, 1.0, h) * (1.0 - smoothstep(1.5, 1.8, h));
	float smudge = smoothstep(0.55, 0.95, g_smudge) * (0.06 + hands * 0.8 * smoothstep(0.55, 0.85, n_mid + blot * 0.4));
	float low_band = 1.0 - smoothstep(0.9, 1.5, h);
	float speck = smoothstep(0.83, 0.93, texture(noise_tex, uvm / 0.13 + vec2(0.31, 0.77)).b) * smoothstep(0.35, 0.7, n_mid)
		* (0.35 + 0.65 * low_band);
	vec2 sq = vec2(uvm.x * 0.94 + uvm.y * 0.34, uvm.y * 0.94 - uvm.x * 0.34);          // tilted strokes
	float scratch = smoothstep(0.55, 0.9, texture(grunge_tex, vec2(sq.x / 0.42, sq.y / 0.07) + vec2(0.7, 0.2)).b)
		* smoothstep(0.62, 0.85, n_fine + blot * 0.3) * low_band;
	float streak = g_streak * smoothstep(0.5, 0.8, n_big2) * (0.25 + 0.75 * exp(-hc / 1.1));
	float dmp = (1.0 - smoothstep(0.0, damp_height * (0.65 + 0.7 * n_mid), h)) * damp_amount;
	float cav = clamp((1.0 - m.r) * 2.0 + (0.5 - m.g) * 1.5, 0.0, 1.0);

	// ---------------------------------------------------------------- albedo
	float lum_a = surf_lum(a);
	float ref_l = mix(tex_mean_lum, surf_lum(a_lo), highpass);
	float detail = pow(max(lum_a / max(ref_l, 0.002), 0.0), detail_contrast);
	vec3 col = mix(paint_color * detail, a, tex_color_mix);
	if (uv_albedo_mix > 0.0) {
		col = mix(col, col * texture(uv_albedo_tex, UV).rgb * 1.6, uv_albedo_mix);
	}
	col *= mix(vec3(1.0), COLOR.rgb, vertex_color_amount);
	col *= 1.0 + macro_amount * ((n_big - 0.5) * 1.6 + (n_mid - 0.5) * 0.9);
	col = mix(col, col * vec3(1.05, 1.0, 0.86), smoothstep(0.45, 0.9, n_big2) * macro_hue * 0.6);
	col *= 1.0 - cavity_dirt * cav * 0.6;

	col = mix(col, grime_color * (0.75 + 0.5 * n_fine), clamp(floor_grime * fb, 0.0, 0.85));
	col *= 1.0 - 0.3 * dust_line * floor_grime;
	col = mix(col, col * vec3(0.72, 0.70, 0.67), clamp(ceil_grime * cb, 0.0, 1.0));
	col = mix(col, col * vec3(0.55, 0.52, 0.47), clamp(corner_grime * cg, 0.0, 1.0));
	col = mix(col, col * streak_tint, clamp(streak_amount * streak, 0.0, 1.0));
	col = mix(col, col * vec3(0.80, 0.77, 0.72), clamp(smudge_amount * smudge, 0.0, 1.0));
	col = mix(col, col * vec3(0.32, 0.30, 0.29), clamp(scuff_amount * scuff, 0.0, 1.0));
	col *= 1.0 - 0.55 * clamp(speck_amount * speck, 0.0, 1.0);
	col *= 1.0 - 0.4 * clamp(scratch_amount * scratch, 0.0, 1.0);
	if (damp_amount > 0.0) {
		col *= 1.0 - 0.38 * dmp;
		float edge = dmp * (1.0 - dmp) * 4.0;   // tide line at the top of the damp zone
		col *= 1.0 - 0.18 * edge * damp_amount;
		float eff = smoothstep(0.45, 0.85, g_smudge + n_fine * 0.25) * clamp(edge * 1.4 + dmp * 0.35, 0.0, 1.0);
		col = mix(col, vec3(0.80, 0.79, 0.74), clamp(efflorescence * eff, 0.0, 0.85));
	}
	if (mould_amount > 0.0) {
		float mo = smoothstep(0.15, 0.6, blot) * clamp(fb * 1.6 + cg * 1.4 + cb * 0.8, 0.0, 1.0) * smoothstep(0.35, 0.65, n_fine);
		col = mix(col, vec3(0.045, 0.05, 0.035), clamp(mould_amount * mo, 0.0, 0.92));
	}

	// ---------------------------------------------------------------- roughness
	float r = rough_base + rough_detail * (m.b - rough_mid) + rough_var * (n_mid - 0.5) * 2.0;
	r = mix(r, rough_grime, clamp(floor_grime * fb + ceil_grime * cb + corner_grime * cg * 0.7, 0.0, 1.0));
	r = mix(r, rough_smudge, clamp(smudge_amount * smudge * 1.3, 0.0, 1.0));
	r = mix(r, 0.55, clamp(scuff_amount * scuff, 0.0, 1.0));
	r = mix(r, 0.45, clamp(dmp * 0.7, 0.0, 1.0));

	// ---------------------------------------------------------------- normal
	vec3 tn = surf_unpack_normal(nt, normal_strength);
	if (detail_level > 0.5) {
		// roller / board waviness (finite differences on the medium fbm)
		float ws = 1.6;
		vec2 q = uvm / ws;
		float e = 0.03 / ws;
		float h0 = texture(noise_tex, q).g;
		float hx = texture(noise_tex, q + vec2(e, 0.0)).g;
		float hy = texture(noise_tex, q + vec2(0.0, e)).g;
		tn.xy += vec2(-(hx - h0), (hy - h0)) / 0.03 * wave_amp;
		if (seam_amount > 0.0 && wall) {
			// horizontal sheets: a joint 1.22 m over the floor line and butt joints every 2.44 m
			float dy = h - 1.22;
			float ridge_y = exp(-(dy * dy) / 0.0049);
			float du = mod(uvm.x + 0.61, 2.44) - 1.22;
			float ridge_u = exp(-(du * du) / 0.0049);
			tn.y += -(-2.0 * dy / 0.0049) * ridge_y * seam_amount * 0.004;
			tn.x += (2.0 * du / 0.0049) * ridge_u * seam_amount * 0.004;
			r -= 0.05 * seam_amount * max(ridge_y, ridge_u);
			col *= 1.0 + 0.015 * seam_amount * max(ridge_y, ridge_u);
		}
		if (drip_amount > 0.0) {
			vec2 dq = vec2(uvm.x / 0.42, uvm.y / 0.3) + vec2(0.5, 0.21);
			float de = 0.0016;
			float sparse = smoothstep(0.62, 0.8, blot + 0.25 * n_fine);
			float d0 = smoothstep(0.55, 0.95, texture(grunge_tex, dq).g) * sparse;
			float dx = smoothstep(0.55, 0.95, texture(grunge_tex, dq + vec2(de, 0.0)).g) * sparse;
			float dy2 = smoothstep(0.55, 0.95, texture(grunge_tex, dq + vec2(0.0, de)).g) * sparse;
			tn.xy += vec2(-(dx - d0), (dy2 - d0)) * drip_amount * 0.35;
			r -= 0.12 * drip_amount * d0;
		}
	}
	vec3 nw = normalize(T * tn.x + B * tn.y + N * max(tn.z, 0.05));

	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(r, 0.04, 1.0);
	METALLIC = 0.0;
	SPECULAR = specular_level;
	AO = mix(1.0, m.r, ao_amount);
	AO_LIGHT_AFFECT = 0.2;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
