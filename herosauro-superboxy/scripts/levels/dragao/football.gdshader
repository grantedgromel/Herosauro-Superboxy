// A classic black-and-white football, analytic in object space so it rolls
// with the ball: black pentagons around the 12 icosahedron vertices, white
// hexagons around its 20 face centres (the truncated icosahedron), with thin
// seams where cells meet. Both centre sets are symmetric under coordinate sign
// flips, so the search runs in the positive octant only.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

varying vec3 op;

void vertex() {
	op = VERTEX;
}

void fragment() {
	vec3 n = normalize(op);
	vec3 q = abs(n);
	vec3 s = sign(n);
	const float PHI = 1.6180339;
	const float IP = 0.6180339;
	vec3 pc[3] = vec3[](normalize(vec3(0.0, 1.0, PHI)), normalize(vec3(1.0, PHI, 0.0)), normalize(vec3(PHI, 0.0, 1.0)));
	vec3 hc[4] = vec3[](normalize(vec3(1.0)), normalize(vec3(0.0, PHI, IP)), normalize(vec3(IP, 0.0, PHI)), normalize(vec3(PHI, IP, 0.0)));
	float ap = 10.0;
	int ip = 0;
	for (int i = 0; i < 3; i++) {
		float a = acos(clamp(dot(q, pc[i]), -1.0, 1.0));
		if (a < ap) { ap = a; ip = i; }
	}
	float ah = 10.0;
	int ih = 0;
	for (int i = 0; i < 4; i++) {
		float a = acos(clamp(dot(q, hc[i]), -1.0, 1.0));
		if (a < ah) { ah = a; ih = i; }
	}
	// Pentagon inradius 16.5 deg, hexagon 20.9: scale so the shared edge is equal.
	float pk = ap * 1.269;
	bool pent = pk < ah;
	vec3 r = pent ? pc[ip] : hc[ih];
	float base_id = pent ? float(ip) : 100.0 + float(ih);
	// Fold the octant back in, so mirrored cells get different ids.
	float id = base_id + 10.0 * (step(0.01, r.x) * s.x + 2.0 * step(0.01, r.y) * s.y + 4.0 * step(0.01, r.z) * s.z);
	float edge = abs(pk - ah);
	float seam = 1.0 - smoothstep(0.0, 0.035, edge);
	seam = max(seam, step(0.001, fwidth(id)) * 0.8);
	vec3 col = pent ? vec3(0.05, 0.05, 0.06) : vec3(0.95, 0.95, 0.93);
	col = mix(col, vec3(0.35, 0.36, 0.4), seam * (pent ? 0.0 : 0.9));
	ALBEDO = col;
	ROUGHNESS = pent ? 0.45 : 0.32;
	SPECULAR = 0.6;
	RIM = 0.4;
	RIM_TINT = 0.2;
}
