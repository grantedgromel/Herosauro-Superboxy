// The Dragão pitch: mown stripes, white markings and grass grain, analytic so
// the whole playing surface is one quad and one draw call. Coordinates are the
// mesh's local XZ, which is the level's (the pitch sits at the level origin).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 grass_a : source_color = vec3(0.30, 0.66, 0.22);
uniform vec3 grass_b : source_color = vec3(0.23, 0.56, 0.17);
uniform vec3 runoff : source_color = vec3(0.20, 0.48, 0.17);
uniform vec3 line_col : source_color = vec3(0.97, 0.98, 0.95);
uniform vec2 half_size = vec2(28.0, 18.0);
uniform float line_half = 0.085;
uniform float stripe = 4.6667;
uniform float centre_r = 5.2;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float sd_box(vec2 p, vec2 h) {
	vec2 q = abs(p) - h;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

void fragment() {
	vec2 p = lp.xz;
	vec2 ap = abs(p);
	float aa = max(fwidth(p.x), fwidth(p.y)) * 0.75 + 0.002;

	float sidx = floor((p.x + half_size.x) / stripe);
	float st = mod(sidx, 2.0);
	vec3 g = mix(grass_a, grass_b, st);
	float inside = step(ap.x, half_size.x + 0.2) * step(ap.y, half_size.y + 0.2);
	g = mix(runoff * (0.94 + 0.06 * st), g, inside);

	// Grain at three scales: clumps, blades, mowing wear.
	float n = vnoise(p * 1.6) * 0.45 + vnoise(p * 6.5) * 0.35 + vnoise(p * 0.3) * 0.2;
	g *= 0.84 + 0.3 * n;
	// The floodlit middle is a touch brighter than the corners.
	float pool = 1.0 - smoothstep(10.0, 40.0, length(p * vec2(0.8, 1.1)));
	g *= 0.92 + 0.14 * pool;

	float d = abs(sd_box(p, half_size));
	d = min(d, max(abs(p.x), ap.y - half_size.y));
	d = min(d, abs(length(p) - centre_r));
	d = min(d, max(length(p) - 0.22, 0.0));
	vec2 q = vec2(ap.x, p.y);
	// Penalty and goal areas, scaled to this pitch.
	d = min(d, abs(sd_box(q - vec2(half_size.x - 4.4, 0.0), vec2(4.4, 10.7))));
	d = min(d, abs(sd_box(q - vec2(half_size.x - 1.45, 0.0), vec2(1.45, 4.9))));
	// Penalty spots and arcs (the arc only outside the box).
	vec2 spot = vec2(half_size.x - 5.9, 0.0);
	d = min(d, max(length(q - spot) - 0.17, 0.0));
	float arc = abs(length(q - spot) - 4.9);
	arc = ap.x < half_size.x - 8.8 ? arc : 1e3;
	d = min(d, arc);
	// Corner arcs.
	float corner = abs(length(ap - half_size) - 0.9);
	corner = (ap.x < half_size.x && ap.y < half_size.y) ? corner : 1e3;
	d = min(d, corner);

	float line = 1.0 - smoothstep(line_half - aa, line_half + aa, d);
	line *= inside;
	vec3 col = mix(g, line_col * (0.94 + 0.06 * n), line);

	ALBEDO = col;
	ROUGHNESS = mix(0.9, 0.7, line);
	SPECULAR = 0.25;
}
