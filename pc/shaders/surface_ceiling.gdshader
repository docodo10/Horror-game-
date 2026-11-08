// Surfaces module — knockdown / stucco ceilings (main room, stairwell, upper hall).
// Hi-res knockdown relief (normal + AO + height) in world space, off-white paint x the scan's luminance detail,
// dust settled in the knockdown valleys, greying along the walls and in the corners, a heat / smoke stain above the
// bulb, faint yellowed blotches, roughness breakup.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/surface_common.gdshaderinc"

uniform sampler2D albedo_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable; // L variation (linear)
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mask_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;   // R ao, G height, B rough
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D grunge_tex : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float detail_level = 1.0;
uniform float tile_size = 1.25;
uniform vec3 paint_color : source_color = vec3(0.86, 0.83, 0.76);
uniform float detail_contrast = 0.25;      // knockdown albedo variation (luminance map centred on 0.5)
uniform float vertex_color_amount = 0.8;
uniform float normal_strength = 0.55;
uniform float ao_amount = 0.5;
uniform float cavity_dirt = 0.2;
uniform float macro_amount = 0.06;
uniform float specular_level = 0.35;

uniform vec4 room_box = vec4(-3.5, 3.5, -2.75, 2.75);  // minX, maxX, minZ, maxZ of the ceiling's room (edge dust)
uniform float edge_grime = 0.35;
uniform float edge_width = 0.3;
uniform vec3 heat_center = vec3(0.25, 2.5, 0.35);       // ceiling mount of a light (yellow-brown heat / smoke stain)
uniform float heat_amount = 0.0;
uniform float heat_radius = 0.75;
uniform float stain_amount = 0.25;
uniform vec3 stain_tint : source_color = vec3(0.86, 0.76, 0.58);

uniform float rough_base = 0.88;
uniform float rough_detail = 0.6;
uniform float rough_mid = 0.76;

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

	float var = texture(albedo_tex, uv).r;
	vec4 m = texture(mask_tex, uv);
	vec4 nt = texture(normal_tex, uv);
	float n_big = texture(noise_tex, uvm / 3.9 + vec2(0.2, 0.7)).r;
	float n_mid = texture(noise_tex, uvm / 1.4 + vec2(0.55, 0.15)).g;
	float n_fine = texture(noise_tex, uvm / 0.5).b;
	float blot = texture(noise_tex, uvm / 2.9 + vec2(0.33, 0.81)).a;
	float g_smudge = texture(grunge_tex, uvm / 2.1 + vec2(0.4, 0.2)).r;

	// distance to the walls of this ceiling's room + corners (two walls close)
	vec4 dd = vec4(p.x - room_box.x, room_box.y - p.x, p.z - room_box.z, room_box.w - p.z);
	dd = max(dd, vec4(0.0));
	float dx = min(dd.x, dd.y);
	float dz = min(dd.z, dd.w);
	float de = min(dx, dz);
	float edge = exp(-de / edge_width) * (0.55 + 0.45 * n_mid);
	float corner = exp(-max(dx, dz) / (edge_width * 1.3));
	float cav = clamp((1.0 - m.r) * 1.8 + (0.5 - m.g) * 1.2, 0.0, 1.0);

	vec3 col = paint_color * (1.0 + (var - 0.5) * detail_contrast);
	col *= mix(vec3(1.0), COLOR.rgb, vertex_color_amount);
	col *= 1.0 + macro_amount * ((n_big - 0.5) * 1.6 + (n_mid - 0.5));
	col *= 1.0 - cavity_dirt * cav * (0.5 + 0.5 * n_mid);
	col = mix(col, col * vec3(0.66, 0.64, 0.6), clamp(edge_grime * (edge + corner * 0.8), 0.0, 1.0));
	float st = smoothstep(0.2, 0.75, blot) * smoothstep(0.4, 0.8, g_smudge + n_big * 0.3);
	col = mix(col, col * stain_tint, clamp(stain_amount * st, 0.0, 1.0));
	if (heat_amount > 0.0) {
		float r = length(p.xz - heat_center.xz);
		float ring = exp(-pow(max(r - 0.12, 0.0) / heat_radius, 2.0)) * (0.65 + 0.35 * n_mid);
		col = mix(col, col * vec3(0.78, 0.68, 0.52), clamp(heat_amount * ring, 0.0, 1.0));
	}

	float rgh = rough_base + rough_detail * (m.b - rough_mid) + 0.05 * (n_mid - 0.5);
	rgh = mix(rgh, 0.97, clamp(edge_grime * edge + cav * 0.3, 0.0, 1.0));

	vec3 tn = surf_unpack_normal(nt, normal_strength);
	if (detail_level > 0.5) {
		float ws = 2.2;
		vec2 q = uvm / ws;
		float e = 0.03 / ws;
		float h0 = texture(noise_tex, q).g;
		float hx = texture(noise_tex, q + vec2(e, 0.0)).g;
		float hy = texture(noise_tex, q + vec2(0.0, e)).g;
		tn.xy += vec2(-(hx - h0), (hy - h0)) / 0.03 * 0.008;
	}
	vec3 nw = normalize(T * tn.x + B * tn.y + N * max(tn.z, 0.05));

	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(rgh, 0.05, 1.0);
	METALLIC = 0.0;
	SPECULAR = specular_level;
	AO = mix(1.0, m.r, ao_amount);
	AO_LIGHT_AFFECT = 0.35;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
