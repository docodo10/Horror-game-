// Surfaces module — painted wood: baseboards, casings, stair risers / skirt boards, balusters, doors, closet louvres.
// Blended triplanar hi-res painted-wood set (grain + cracks through the semi-gloss paint), chipped paint on worn
// spots and sharp edges (screen-space curvature), dust on the top faces, dirt and rubber scuffs near the floor,
// yellowed / greyed old paint variation, roughness breakup (semi-gloss paint, matte dust and chips).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/surface_common.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mask_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;   // R ao, G height, B rough
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D grunge_tex : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float detail_level = 1.0;
uniform float tile_size = 1.0;
uniform vec3 paint_color : source_color = vec3(0.90, 0.875, 0.815);
uniform float tex_mean_lum = 0.42;
uniform float detail_contrast = 0.55;
uniform float vertex_color_amount = 0.8;
uniform float normal_strength = 0.55;
uniform float ao_amount = 0.6;
uniform float macro_amount = 0.05;
uniform float specular_level = 0.5;

uniform vec3 chip_color : source_color = vec3(0.52, 0.45, 0.36);
uniform float chip_amount = 0.5;
uniform float edge_chips = 0.6;
uniform float dust_amount = 0.45;
uniform vec3 dust_color : source_color = vec3(0.55, 0.52, 0.48);
uniform float floor_dirt = 0.5;
uniform float scuff_amount = 0.6;
uniform float yellowing = 0.4;

uniform float rough_base = 0.38;
uniform float rough_detail = 0.5;
uniform float rough_mid = 0.58;

varying vec3 v_wpos;
varying vec3 v_wnrm;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void tri_sample(vec3 p, vec3 axis_n, float w, inout vec3 alb, inout vec4 msk, inout vec3 nrm, inout float lum_lo) {
	if (w < 0.01) {
		return;
	}
	vec2 uvm;
	vec3 T;
	vec3 B;
	surf_project(p, axis_n, uvm, T, B);
	vec2 uv = uvm / tile_size;
	vec3 a = texture(albedo_tex, uv).rgb;
	alb += a * w;
	lum_lo += surf_lum(textureLod(albedo_tex, uv, 6.0).rgb) * w;
	msk += texture(mask_tex, uv) * w;
	vec3 tn = surf_unpack_normal(texture(normal_tex, uv), normal_strength);
	nrm += (T * tn.x + B * tn.y + axis_n * tn.z) * w;
}

void fragment() {
	vec3 p = v_wpos;
	vec3 N = normalize(v_wnrm);
	vec3 w = pow(abs(N), vec3(6.0));
	w /= (w.x + w.y + w.z + 1e-5);
	vec3 alb = vec3(0.0);
	vec4 m = vec4(0.0);
	vec3 nrm = vec3(0.0);
	float lum_lo = 0.0;
	tri_sample(p, vec3(sign(N.x) + (N.x == 0.0 ? 1.0 : 0.0), 0.0, 0.0), w.x, alb, m, nrm, lum_lo);
	tri_sample(p, vec3(0.0, sign(N.y) + (N.y == 0.0 ? 1.0 : 0.0), 0.0), w.y, alb, m, nrm, lum_lo);
	tri_sample(p, vec3(0.0, 0.0, sign(N.z) + (N.z == 0.0 ? 1.0 : 0.0)), w.z, alb, m, nrm, lum_lo);
	// keep the geometric normal's contribution where the planar bases disagree with the curved profile
	vec3 nw = normalize(nrm + N * 0.35);

	vec3 pq = vec3(p.x + p.z, p.y, p.z - p.x);
	float n_mid = texture(noise_tex, pq.xy / 1.2 + pq.z * 0.37).g;
	float n_fine = texture(noise_tex, pq.xz / 0.4 + p.y * 0.21).b;
	float n_big = texture(noise_tex, vec2(p.x + p.y * 0.3, p.z) / 3.5).r;
	float g_scuff = texture(grunge_tex, vec2(pq.x / 1.1, p.y / 0.5)).b;

	float lum = surf_lum(alb);
	float detail = lum / max(mix(tex_mean_lum, lum_lo, 0.8), 0.002);
	// screen-space curvature: sharp edges and bullnoses chip first
	float curv = clamp(length(fwidth(N)) / max(length(fwidth(p)), 1e-4) * 0.012, 0.0, 1.0);
	float worn = smoothstep(0.78, 0.5, detail);
	float chip = clamp(worn * chip_amount * (0.5 + 0.5 * n_mid) + curv * edge_chips * smoothstep(0.45, 0.75, n_fine), 0.0, 1.0);

	float h = max(p.y - surf_floor_y(p), 0.0);
	float top = smoothstep(0.65, 0.95, N.y);
	float low = 1.0 - smoothstep(0.0, 0.16, h);
	float scuff = smoothstep(0.3, 0.8, g_scuff) * (1.0 - smoothstep(0.08, 0.2, h)) * (1.0 - top) * smoothstep(0.35, 0.65, n_mid);

	vec3 col = paint_color * mix(1.0, detail, detail_contrast);
	col *= mix(vec3(1.0), COLOR.rgb, vertex_color_amount);
	col *= 1.0 + macro_amount * (n_big - 0.5) * 2.0;
	col = mix(col, col * vec3(1.02, 0.98, 0.86), yellowing * smoothstep(0.4, 0.85, n_big));
	col = mix(col, chip_color * (0.7 + 0.6 * n_fine), chip);
	col = mix(col, dust_color, clamp(dust_amount * top * (0.45 + 0.55 * n_mid), 0.0, 1.0));
	col *= 1.0 - floor_dirt * low * (0.35 + 0.25 * n_fine);
	col = mix(col, col * vec3(0.3, 0.28, 0.27), clamp(scuff_amount * scuff, 0.0, 1.0));

	float r = rough_base + rough_detail * (m.b - rough_mid);
	r = mix(r, 0.75, chip);
	r = mix(r, 0.9, clamp(dust_amount * top, 0.0, 1.0));
	r = mix(r, 0.6, clamp(floor_dirt * low, 0.0, 1.0));

	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(r, 0.08, 1.0);
	METALLIC = 0.0;
	SPECULAR = specular_level;
	AO = mix(1.0, m.r, ao_amount);
	AO_LIGHT_AFFECT = 0.2;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
