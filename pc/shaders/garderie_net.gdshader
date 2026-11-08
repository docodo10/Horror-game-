// Garderie: knotted safety netting (alpha scissor). Up close the rope is cut out crisply; as the mesh gets denser on
// screen the scissor threshold becomes a per-pixel interleaved-gradient dither of the averaged coverage, so far nets
// read as a translucent dark veil (smoothed by TAA) instead of vanishing or turning into a solid wall.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D net_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float uv_scale = 2.5;

float ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec4 t = texture(net_tex, uv);
	vec2 dd = fwidth(uv) * 512.0;
	float px = max(dd.x, dd.y);
	float far_k = clamp((px - 1.5) / 5.0, 0.0, 1.0);
	ALBEDO = t.rgb * tint.rgb;
	ROUGHNESS = 0.82;
	SPECULAR = 0.3;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = mix(0.5, clamp(ign(FRAGCOORD.xy), 0.02, 0.98), far_k);
}
