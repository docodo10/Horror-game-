// La Gardienne — look module: the warm line of hall light under the upstairs door (level node doorStrip).
// Unshaded HDR glow (blooms), with soft "feet" shadows when someone stands behind the door (lighting.door_strip_occluded).
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 tint = vec3(1.0, 0.681, 0.308);   // linear 2700 K white-balanced at 3700 K
uniform float energy = 4.95;
uniform float occ = 0.0;
uniform float time_s = 0.0;
uniform float x0 = -3.425;
uniform float x1 = -2.625;
uniform float center_x = -3.025;
varying float wx;

void vertex() {
	wx = (MODEL_MATRIX * vec4(VERTEX, 1.0)).x;
}

void fragment() {
	float cx = center_x + sin(time_s * 0.7) * 0.03;
	float fa = wx - (cx - 0.1);
	float fb = wx - (cx + 0.11);
	float f = exp(-fa * fa / 0.0018) + exp(-fb * fb / 0.0018);
	float v = 1.0 - occ * min(1.0, f * 1.1);
	float ends = smoothstep(x0 - 0.01, x0 + 0.03, wx) * (1.0 - smoothstep(x1 - 0.03, x1 + 0.01, wx));
	ALBEDO = tint * energy * v * mix(0.55, 1.0, ends);
}
