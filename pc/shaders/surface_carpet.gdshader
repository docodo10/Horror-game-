// Surfaces module — wall-to-wall basement carpet (room floor + carpeted stairs and landing).
// Hi-res cut-pile set in world space with two-sample anti-tiling, the web build's baked dust (vertex colours),
// traffic paths (darker, greyer, flattened pile) along the walked lanes, ground-in dirt and old spill stains, and on
// the stairs a worn centre on every tread and dirty, scuffed nosings. Fabric rim (sheen) at grazing angles.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/surface_common.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mask_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;   // R ao, G height, B rough
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D grunge_tex : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float detail_level = 1.0;
uniform float tile_size = 0.9;
uniform vec3 tint : source_color = vec3(0.95, 0.93, 0.90);
uniform float vertex_color_amount = 0.9;
uniform float normal_strength = 1.0;
uniform float ao_amount = 0.7;
uniform float macro_amount = 0.10;
uniform float antitile = 1.0;

uniform vec4 lanes[12];                    // traffic segments x0, z0, x1, z1
uniform int lane_count = 0;
uniform float lane_width = 0.34;
uniform float lane_wear = 0.55;
uniform vec3 wear_tint : source_color = vec3(0.68, 0.64, 0.60);
uniform float dirt_amount = 0.3;           // ground-in dirt (large blotches)
uniform float stain_amount = 0.22;          // old spills (sparse dark stains)
uniform vec3 stain_tint : source_color = vec3(0.62, 0.52, 0.42);

uniform float stair_center_x = -3.05;      // walking line on the treads
uniform float stair_wear = 0.6;
uniform float nosing_dirt = 0.55;

uniform float rough_base = 0.86;
uniform float rough_detail = 0.6;
uniform float rough_mid = 0.65;
uniform float rim_amount = 0.35;

varying vec3 v_wpos;
varying vec3 v_wnrm;

float seg_dist(vec2 p, vec4 s) {
	vec2 a = s.xy;
	vec2 b = s.zw;
	vec2 ab = b - a;
	float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-5), 0.0, 1.0);
	return length(p - a - ab * t);
}

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

	float n_big = texture(noise_tex, uvm / 3.3 + vec2(0.1, 0.6)).r;
	float n_mid = texture(noise_tex, uvm / 1.1 + vec2(0.45, 0.25)).g;
	float n_fine = texture(noise_tex, uvm / 0.37).b;
	float blot = texture(noise_tex, uvm / 3.1 + vec2(0.77, 0.35)).a;
	float g_smudge = texture(grunge_tex, uvm / 1.6 + vec2(0.3, 0.6)).r;

	// two decorrelated samples (second one rotated 90 deg + scaled), blended by low-frequency noise
	vec3 a1 = texture(albedo_tex, uv).rgb;
	vec4 m1 = texture(mask_tex, uv);
	vec3 n1 = surf_unpack_normal(texture(normal_tex, uv), 1.0);
	vec3 a = a1;
	vec4 m = m1;
	vec3 tn = n1;
	if (antitile > 0.0) {
		vec2 uv2 = vec2(uv.y, -uv.x) * 0.83 + vec2(0.37, 0.71);
		float t = smoothstep(0.38, 0.62, n_big) * antitile;
		vec3 a2 = texture(albedo_tex, uv2).rgb;
		vec4 m2 = texture(mask_tex, uv2);
		vec3 n2 = surf_unpack_normal(texture(normal_tex, uv2), 1.0);
		n2 = vec3(n2.y, -n2.x, n2.z);
		a = mix(a1, a2, t);
		m = mix(m1, m2, t);
		tn = normalize(mix(n1, n2, t));
	}

	// ---------------------------------------------------------------- wear masks
	float wear = 0.0;
	for (int i = 0; i < lane_count; i++) {
		float d = seg_dist(p.xz, lanes[i]);
		wear = max(wear, exp(-(d * d) / (lane_width * lane_width)));
	}
	wear *= smoothstep(0.15, 0.75, n_mid * 0.7 + n_fine * 0.5);
	bool on_stairs = p.x < lvl_stairs.y + 0.02 && p.x > lvl_stairs.x - 0.02 && p.z < lvl_stairs.w + 0.04 && p.y > 0.08;
	float nosing = 0.0;
	if (on_stairs) {
		float c = exp(-pow((p.x - stair_center_x) / 0.24, 2.0));
		wear = max(wear, c * stair_wear * (0.65 + 0.35 * n_mid));
		nosing = (1.0 - smoothstep(0.55, 0.9, N.y)) * smoothstep(-0.6, -0.1, N.y);   // the bullnose front
		// dirt collects at the back of each tread (against the riser) and along the sides
		float sides = exp(-min(p.x - lvl_stairs.x, lvl_stairs.y - 0.05 - p.x) / 0.05);
		nosing = max(nosing, sides * 0.6 * step(0.7, N.y));
	}
	float dirt = smoothstep(0.35, 0.85, n_big * 0.6 + g_smudge * 0.6) * dirt_amount;
	float stain = smoothstep(0.35, 0.8, blot) * (0.6 + 0.4 * n_fine) * stain_amount;

	// ---------------------------------------------------------------- albedo
	vec3 col = a * tint;
	col *= mix(vec3(1.0), COLOR.rgb, vertex_color_amount);
	col *= 1.0 + macro_amount * ((n_big - 0.5) * 1.4 + (n_mid - 0.5) * 0.8);
	col = mix(col, col * wear_tint, clamp(wear * lane_wear, 0.0, 1.0));
	col = mix(col, col * vec3(0.8, 0.76, 0.7), dirt);
	col = mix(col, col * stain_tint, clamp(stain, 0.0, 1.0));
	col = mix(col, col * vec3(0.55, 0.52, 0.5), clamp(nosing * nosing_dirt * (0.6 + 0.4 * n_fine), 0.0, 1.0));

	// ---------------------------------------------------------------- roughness / normal
	float r = rough_base + rough_detail * (m.b - rough_mid);
	r = mix(r, 0.97, clamp(wear * lane_wear + nosing * 0.5, 0.0, 1.0));
	tn.xy *= normal_strength * (1.0 - 0.55 * clamp(wear * lane_wear * 1.3, 0.0, 1.0));
	vec3 nw = normalize(T * tn.x + B * tn.y + N * max(tn.z, 0.05));

	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(r, 0.3, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.3;
	AO = mix(1.0, m.r, ao_amount);
	AO_LIGHT_AFFECT = 0.3;
	RIM = rim_amount * (1.0 - 0.6 * wear);
	RIM_TINT = 0.6;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
