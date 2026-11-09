// La Gardienne — look module: dust motes drifting in the moon beam (MultiMesh of camera-facing specks; per-instance
// custom data x = seed). Additive, never smaller than ~1.3 px (they twinkle as they cross the light).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float time_s = 0.0;
uniform float intensity = 1.0;
uniform vec3 tint = vec3(0.55, 0.62, 0.8);
varying float v_a;
varying vec2 v_uv;

void vertex() {
	float seed = INSTANCE_CUSTOM.x;
	float s = seed * 6.2831;
	vec3 p = MODEL_MATRIX[3].xyz;
	p += vec3(sin(time_s * 0.21 + s) * 0.05, sin(time_s * 0.13 + s * 1.7) * 0.06 - mod(time_s * 0.004 + seed, 0.08), cos(time_s * 0.17 + s * 2.3) * 0.05);
	vec4 vp = VIEW_MATRIX * vec4(p, 1.0);
	float dist = max(-vp.z, 0.05);
	float px = 2.0 * dist / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);   // world size of one pixel at that depth
	float world_size = 0.0022 * (0.5 + seed);
	float size = max(world_size, 1.3 * px);
	vp.xy += VERTEX.xy * size;
	POSITION = PROJECTION_MATRIX * vp;
	// energy conservation when clamped to the pixel size + slow twinkle
	v_a = (0.5 + 0.5 * sin(time_s * (0.7 + seed) + s * 3.0)) * min(1.0, (world_size * world_size) / (size * size) * 3.0);
	v_uv = UV;
}

void fragment() {
	float d = 1.0 - smoothstep(0.15, 0.5, length(v_uv - 0.5));
	ALBEDO = tint * d * v_a * intensity;
}
