// Garderie: knotted safety netting (net.png: 3 mm cord, knots at the crossings, 5 cm cells). Hashed alpha (object-space
// stable, resolved by TAA) instead of a scissor threshold: the thin cord neither shimmers nor vanishes at a distance,
// where the mip-averaged coverage turns it into a fine dark veil. Grey-black cord with a soft sheen. The panels are
// subdivided and sag between the posts (garderie_play.gd), so the net is not a perfect plane.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D net_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float uv_scale = 2.5;
uniform float hash_scale = 1.0;

void fragment() {
	vec2 uv = UV * uv_scale;
	vec4 t = texture(net_tex, uv);
	ALBEDO = t.rgb * tint.rgb;
	ROUGHNESS = 0.55;
	SPECULAR = 0.35;
	ALPHA = t.a;
	ALPHA_HASH_SCALE = hash_scale;
}
