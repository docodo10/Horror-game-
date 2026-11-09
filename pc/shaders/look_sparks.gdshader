// La Gardienne — look module: blowout sparks (CPU-simulated in lighting.gd; per-instance custom data r = life, 0 = dead).
// Additive white-hot to orange specks, HDR so they bloom.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

varying float v_life;
varying vec2 v_uv;

void vertex() {
	v_life = INSTANCE_CUSTOM.r;
	vec3 p = MODEL_MATRIX[3].xyz;
	vec4 vp = VIEW_MATRIX * vec4(p, 1.0);
	float dist = max(-vp.z, 0.05);
	float px = 2.0 * dist / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float size = v_life > 0.0 ? max(0.007 * (0.5 + v_life), 2.0 * px) : 0.0;
	vp.xy += VERTEX.xy * size;
	POSITION = PROJECTION_MATRIX * vp;
	v_uv = UV;
}

void fragment() {
	if (v_life <= 0.0) discard;
	float d = 1.0 - smoothstep(0.0, 0.5, length(v_uv - 0.5));
	vec3 col = mix(vec3(4.0, 1.2, 0.25), vec3(12.0, 9.0, 5.0), clamp(v_life, 0.0, 1.0));
	ALBEDO = col * d * v_life;
}
