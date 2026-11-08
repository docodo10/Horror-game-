// Surfaces module (pc/scripts/surfaces/) — helpers shared by the surface_*.gdshader files.
// World-space projection, level geometry (floor / ceiling heights, corners), noise and bump helpers.
// Coordinates: metres, +Y up, -Z north (same as Layout / the web build).

// ---------------------------------------------------------------------------------------------------- level geometry
// Set by Surfaces.apply() from Layout (defaults = the current layout).
uniform vec4 lvl_stairs = vec4(-3.5, -2.55, -1.78, 1.6);       // minX, maxX, topZ, bottomZ
uniform vec3 lvl_step = vec3(0.196429, 0.26, 14.0);            // riser height, tread depth, risers
uniform vec4 lvl_hall = vec4(-3.6, -2.45, -4.4, -2.75);        // upper hall minX, maxX, minZ, maxZ
uniform vec4 lvl_heights = vec4(2.5, 2.75, 5.2, 1.15);          // room ceiling, upper floor, upper ceiling, stair-opening maxZ
uniform vec2 lvl_corners[24];                                  // inner vertical corners (x, z)
uniform int lvl_corner_count = 0;

// y of the stair nosing line at z (clamped to the landing)
float surf_stair_line(float z) {
	return min(lvl_step.x * (1.0 + (lvl_stairs.w - z) / lvl_step.y), lvl_heights.y);
}

// Height of the walkable floor under p (the dirt line of a wall follows it: room 0, stair nosing line, landing / hall).
float surf_floor_y(vec3 p) {
	bool in_hall_x = p.x > lvl_hall.x - 0.05 && p.x < lvl_hall.y + 0.05;
	if (in_hall_x && p.z < lvl_hall.w + 0.02 && p.y > lvl_heights.y - 0.35) {
		return lvl_heights.y;
	}
	if (p.x < lvl_stairs.y - 0.02 && p.x > lvl_stairs.x - 0.1 && p.z < lvl_stairs.w + 0.05 && p.z > lvl_hall.w - 0.05) {
		float sl = surf_stair_line(p.z);
		if (p.y > sl - 0.24) {          // finished stairwell walls start at sl - 0.18, the closet under the flight ends at sl - 0.3
			return sl - 0.06;
		}
	}
	return 0.0;
}

// Height of the ceiling over p.
float surf_ceil_y(vec3 p) {
	bool stairwell = p.x < lvl_stairs.y + 0.051 && p.x > lvl_stairs.x - 0.15 && p.z < lvl_heights.w;
	bool hall = p.x > lvl_hall.x - 0.05 && p.x < lvl_hall.y + 0.05 && p.z < lvl_hall.w;
	if ((stairwell && p.y > lvl_heights.x - 0.3) || (hall && p.y > lvl_heights.y - 0.3)) {
		return lvl_heights.z;
	}
	return lvl_heights.x;
}

// Distance along a wall to the nearest inner corner that lies on this wall's plane (n = horizontal wall normal).
float surf_corner_dist(vec3 p, vec3 n) {
	float d = 99.0;
	vec2 nn = normalize(n.xz + vec2(1e-5));
	for (int i = 0; i < lvl_corner_count; i++) {
		vec2 c = lvl_corners[i] - p.xz;
		if (abs(dot(c, nn)) < 0.08) {
			d = min(d, length(c));
		}
	}
	return d;
}

// ---------------------------------------------------------------------------------------------------- projection
// Dominant-axis planar projection. uv in metres (u to the right as seen from the front, v down), T = d(world)/du,
// B = image "up" (OpenGL normal maps: n = T * x + B * y + N * z, T x B = N).
void surf_project(vec3 p, vec3 n, out vec2 uv, out vec3 T, out vec3 B) {
	vec3 a = abs(n);
	if (a.y >= a.x && a.y >= a.z) {
		float s = n.y >= 0.0 ? 1.0 : -1.0;
		uv = vec2(p.x * s, p.z);
		T = vec3(s, 0.0, 0.0);
		B = vec3(0.0, 0.0, -1.0);
	} else if (a.x >= a.z) {
		float s = n.x >= 0.0 ? 1.0 : -1.0;
		uv = vec2(-p.z * s, -p.y);
		T = vec3(0.0, 0.0, -s);
		B = vec3(0.0, 1.0, 0.0);
	} else {
		float s = n.z >= 0.0 ? 1.0 : -1.0;
		uv = vec2(p.x * s, -p.y);
		T = vec3(s, 0.0, 0.0);
		B = vec3(0.0, 1.0, 0.0);
	}
}

// Unpack an OpenGL normal map texel (RG or RGB) to a tangent-space vector with xy scaled by k.
vec3 surf_unpack_normal(vec4 t, float k) {
	vec2 xy = t.xy * 2.0 - 1.0;
	float z = sqrt(max(0.0, 1.0 - dot(xy, xy)));
	return vec3(xy * k, z);
}

float surf_lum(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float surf_smooth(float e0, float e1, float x) {
	return smoothstep(e0, e1, x);
}
