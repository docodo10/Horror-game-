// Garderie: ball-pit balls (MultiMesh, per-instance colour; physics balls of garderie_physics.gd use the instance
// uniform ball_tint instead). Glossy plastic with dust. Legacy vertex push: balls within push_r of push_pos are shoved
// aside (unused while the physics bubble runs: push_pos stays far away).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 push_pos = vec3(0.0, -100.0, 0.0);
uniform float push_r = 0.5;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float rough = 0.26;
instance uniform vec4 ball_tint = vec4(0.0);   // a > 0: colour of a physics ball (sRGB)

varying vec3 inst_o;

// vertex / instance colours are authored in sRGB
vec3 srgb_to_lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	inst_o = o;
	vec3 d = o - push_pos;
	float dy = d.y;
	d.y = 0.0;
	float dist = length(d);
	float k = (1.0 - smoothstep(push_r * 0.35, push_r, dist)) * (1.0 - smoothstep(0.2, 0.9, abs(dy)));
	vec3 off = (dist > 0.001 ? d / dist : vec3(1.0, 0.0, 0.0)) * k * 0.22 + vec3(0.0, k * 0.05, 0.0);
	VERTEX += transpose(mat3(MODEL_MATRIX)) * off;
}

void fragment() {
	vec4 nz = texture(noise_tex, inst_o.xz * 3.1 + vec2(inst_o.y * 7.0));
	vec3 c = srgb_to_lin(ball_tint.a > 0.0 ? ball_tint.rgb : COLOR.rgb) * (0.85 + nz.g * 0.25);
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float dust = clamp(wn.y, 0.0, 1.0) * nz.b * 0.5;
	ALBEDO = mix(c, vec3(0.7, 0.68, 0.64), dust * 0.4);
	ROUGHNESS = clamp(rough + dust * 0.4 + nz.r * 0.1, 0.05, 1.0);
	SPECULAR = 0.55;
	CLEARCOAT = 0.35;
	CLEARCOAT_ROUGHNESS = 0.15;
}
