// Dehors (chapter 3): the night sky over the yard. A dark gradient, a moon veiled by cloud, no stars. Cheap: two
// noise lookups. The fog colour of the environment is close to `horizon`, so the tree line fades
// into it.
shader_type sky;

uniform vec3 zenith : source_color = vec3(0.008, 0.011, 0.02);
uniform vec3 horizon : source_color = vec3(0.05, 0.065, 0.095);
uniform vec3 moon_dir = vec3(0.45, 0.55, -0.7);
uniform vec3 moon_color : source_color = vec3(0.8, 0.86, 1.0);
uniform float moon_size = 0.035;
uniform vec2 cloud_offset = vec2(0.13, 0.41);          // (no TIME here: a sky that changes is filtered again every frame)
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable, hint_default_white;

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = clamp(d.y, 0.0, 1.0);
	// (fog to well above the tree tops: what stands in the distance fades into the sky, never lighter than it)
	vec3 col = mix(horizon, zenith, smoothstep(0.22, 0.85, up));
	vec2 uv = d.xz / (0.35 + up) * 0.35;
	float c1 = texture(noise_tex, uv + cloud_offset).r;
	float c2 = texture(noise_tex, uv * 2.7 - cloud_offset.yx).g;
	float cloud = smoothstep(0.38, 0.8, c1 * 0.65 + c2 * 0.35);
	vec3 md = normalize(moon_dir);
	float a = acos(clamp(dot(d, md), -1.0, 1.0));
	float disc = 1.0 - smoothstep(moon_size * 0.9, moon_size, a);
	float halo = exp(-a * 7.0) * 0.5 + exp(-a * 2.2) * 0.12;
	// clouds: lit from behind near the moon, dark elsewhere
	col = mix(col, horizon * 0.75 + moon_color * halo * 0.35, cloud * 0.8);
	col += moon_color * (disc * (1.0 - cloud * 0.92) * 1.6 + halo * (0.25 + 0.5 * (1.0 - cloud)));
	if (d.y < 0.0) {
		col = mix(horizon, horizon * 0.4, clamp(-d.y * 3.0, 0.0, 1.0));
	}
	COLOR = col;
}
