// Dehors (chapter 3): the night sky over the yard. A dark gradient, a moon veiled by slow cloud, a few stars in the
// gaps. Cheap: two noise lookups. The fog colour of the environment is close to `horizon`, so the tree line fades
// into it.
shader_type sky;

uniform vec3 zenith : source_color = vec3(0.004, 0.006, 0.012);
uniform vec3 horizon : source_color = vec3(0.03, 0.04, 0.06);
uniform vec3 moon_dir = vec3(0.45, 0.55, -0.7);
uniform vec3 moon_color : source_color = vec3(0.8, 0.86, 1.0);
uniform float moon_size = 0.035;
uniform float cloud_speed = 0.004;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable, hint_default_white;

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(horizon, zenith, pow(up, 0.45));
	vec2 uv = d.xz / (0.35 + up) * 0.35;
	float c1 = texture(noise_tex, uv + vec2(TIME * cloud_speed, 0.0)).r;
	float c2 = texture(noise_tex, uv * 2.7 - vec2(0.0, TIME * cloud_speed * 1.7)).g;
	float cloud = smoothstep(0.38, 0.8, c1 * 0.65 + c2 * 0.35);
	vec3 md = normalize(moon_dir);
	float a = acos(clamp(dot(d, md), -1.0, 1.0));
	float disc = 1.0 - smoothstep(moon_size * 0.9, moon_size, a);
	float halo = exp(-a * 7.0) * 0.5 + exp(-a * 2.2) * 0.12;
	// clouds: lit from behind near the moon, dark elsewhere
	col = mix(col, horizon * 0.75 + moon_color * halo * 0.35, cloud * 0.8);
	col += moon_color * (disc * (1.0 - cloud * 0.92) * 1.6 + halo * (0.25 + 0.5 * (1.0 - cloud)));
	float st = texture(noise_tex, d.xz / (0.2 + up) * 2.3).a;
	col += vec3(0.7, 0.8, 1.0) * smoothstep(0.93, 0.99, st) * (1.0 - cloud) * up * 0.5;
	if (d.y < 0.0) {
		col = mix(horizon, horizon * 0.4, clamp(-d.y * 3.0, 0.0, 1.0));
	}
	COLOR = col;
}
