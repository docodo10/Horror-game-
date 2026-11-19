// Dehors (chapter 3): the ground of the yard. One mesh, three tiling layers (lawn, gravel, dead leaves) laid out by a
// mask built from the level's layout (scripts/dehors/dehors_build.gd): R = gravel, G = leaves, B = bare earth,
// A = standing water. World-planar UVs; the mask lookup is warped by noise so that no edge is a straight line.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D mask_tex : filter_linear, repeat_disable, hint_default_black;
uniform vec4 mask_rect = vec4(100.0, -20.0, 0.02, 0.025);     // x0, z0, 1 / width, 1 / depth
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D leaves_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D leaves_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable, hint_default_white;
uniform float wet = 0.6;                                      // 0 = dry night, 1 = just rained

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	vec4 nz = texture(noise_tex, p * 0.043);
	vec4 nz2 = texture(noise_tex, p * 0.31 + vec2(0.37, 0.11));
	vec2 warp = (vec2(nz.r, nz.g) - 0.5) * 0.5 + (vec2(nz2.b, nz2.a) - 0.5) * 0.14;
	vec4 m = texture(mask_tex, (p + warp - mask_rect.xy) * mask_rect.zw);
	// sharpen the layer edges with the fine noise (stones spill onto the grass, leaves thin out)
	float k_gravel = smoothstep(0.38, 0.62, m.r + (nz2.r - 0.5) * 0.35);
	float k_leaves = smoothstep(0.3, 0.7, m.g + (nz2.g - 0.5) * 0.7) * (1.0 - k_gravel * 0.85);
	float k_dirt = smoothstep(0.3, 0.75, m.b + (nz2.b - 0.5) * 0.5) * (1.0 - k_gravel);
	float k_water = smoothstep(0.45, 0.6, m.a + (nz.b - 0.5) * 0.3);

	// lawn: two scales mixed by noise hide the repeat; darker, yellower patches
	vec3 g1 = texture(grass_tex, p * 0.45).rgb;
	vec3 g2 = texture(grass_tex, p * 0.19 + vec2(0.3, 0.7)).rgb;
	vec3 grass = mix(g1, g2, 0.45) * mix(vec3(0.72, 0.78, 0.7), vec3(1.12, 1.05, 0.8), nz.a);
	vec3 gn = texture(grass_n, p * 0.45).xyz;
	vec3 gravel = texture(gravel_tex, p * 0.62).rgb * mix(0.8, 1.1, nz.b);
	vec3 gvn = texture(gravel_n, p * 0.62).xyz;
	vec3 leaves = texture(leaves_tex, p * 0.55).rgb;
	vec3 ln = texture(leaves_n, p * 0.55).xyz;
	vec3 dirt = gravel * vec3(0.5, 0.4, 0.3) * 0.55 + grass * 0.18;

	vec3 col = mix(grass, dirt, k_dirt);
	vec3 nrm = mix(gn, vec3(0.5, 0.5, 1.0), k_dirt * 0.5);
	float rough = mix(0.82, 0.62, k_dirt);
	col = mix(col, leaves, k_leaves);
	nrm = mix(nrm, ln, k_leaves);
	rough = mix(rough, mix(0.75, 0.42, wet), k_leaves);
	col = mix(col, gravel, k_gravel);
	nrm = mix(nrm, gvn, k_gravel);
	rough = mix(rough, mix(0.8, 0.27, wet), k_gravel);
	// standing water in the ruts: dark, flat, a mirror for the moon and the lantern
	col = mix(col, col * 0.22, k_water);
	nrm = mix(nrm, vec3(0.5, 0.5, 1.0), k_water);
	rough = mix(rough, 0.03, k_water);

	ALBEDO = col;
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = 1.1;
	ROUGHNESS = rough;
	SPECULAR = mix(0.5, 0.75, max(k_water, k_gravel * wet));
	METALLIC = 0.0;
}
