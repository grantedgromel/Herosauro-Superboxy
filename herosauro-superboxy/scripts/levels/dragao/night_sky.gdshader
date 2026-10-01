// Full-moon night over Porto: deep blue zenith, a city-glow horizon, hashed
// stars, and a big friendly cartoon moon with a halo.
shader_type sky;

uniform vec3 zenith : source_color = vec3(0.03, 0.06, 0.2);
uniform vec3 horizon : source_color = vec3(0.2, 0.3, 0.6);
uniform vec3 moon_dir = vec3(0.32, 0.3, 0.9);
uniform vec3 moon_col : source_color = vec3(1.0, 0.96, 0.82);
uniform float moon_size = 0.085;

float h3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(horizon, zenith, pow(up, 0.5));
	if (d.y < 0.0) {
		col = horizon * 0.7;
	}
	vec3 sd = d * 150.0;
	vec3 cell = floor(sd);
	vec3 f = fract(sd) - 0.5;
	float r = h3(cell);
	float star = step(0.982, r) * (1.0 - smoothstep(0.0, 0.33, length(f)));
	star *= smoothstep(0.02, 0.2, d.y);
	// A fixed per-star brightness, no TIME: a sky shader that reads TIME has
	// its radiance re-rendered every frame, which the web build cannot afford.
	star *= 0.55 + 0.45 * fract(r * 913.0);
	col += vec3(0.95, 0.97, 1.0) * star * 1.4;

	vec3 md = normalize(moon_dir);
	float a = acos(clamp(dot(d, md), -1.0, 1.0));
	float disc = 1.0 - smoothstep(moon_size * 0.95, moon_size, a);
	// Soft craters: a few fixed dimples on the disc.
	vec3 t1 = normalize(cross(md, vec3(0.0, 1.0, 0.0)));
	vec3 t2 = cross(t1, md);
	vec2 m = vec2(dot(d - md, t1), dot(d - md, t2)) / moon_size;
	float cr = 0.0;
	cr += 1.0 - smoothstep(0.12, 0.22, length(m - vec2(-0.3, 0.25)));
	cr += 1.0 - smoothstep(0.08, 0.16, length(m - vec2(0.35, -0.1)));
	cr += 1.0 - smoothstep(0.1, 0.18, length(m - vec2(0.05, -0.45)));
	cr += 1.0 - smoothstep(0.05, 0.1, length(m - vec2(0.45, 0.4)));
	vec3 mc = moon_col * (1.15 - 0.16 * clamp(cr, 0.0, 1.0)) * (1.0 - 0.18 * length(m));
	float glow = exp(-a * 10.0) * 0.55 + exp(-a * 3.2) * 0.14;
	col = mix(col + moon_col * glow, mc * 1.25, disc);
	COLOR = col;
}
