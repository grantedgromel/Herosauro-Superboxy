// The Douro: a river that reflects, running between two quays it can reach.
//
// The normal is derived analytically from the summed wave derivatives — the same
// waves the vertex stage displaces, plus finer chop that only exists in the normal
// — and the renderer does the lighting. That part has been right since Wave 1.
//
// Deliberately OPAQUE, and now for a second reason as well as the original one.
// The original: depth-based shore shallowing needs DEPTH_TEXTURE, which only
// carries the scene *behind* you from the transparent pass, so a 240 m plane moved
// into that pass costs a screenful of overdraw and — with no riverbed geometry —
// would show sky straight through the deep water. The second, learned this round:
// screen-space reflections are computed against the OPAQUE buffer, so a transparent
// river cannot receive SSR at all, and SSR is the only thing that can put the iron
// arch in the water. The shore band is solved analytically below instead.
//
// --- What Round 3 measured, and what changed here -------------------------------
//
// Two adversarial critics independently reported that the Douro does not read as
// water, and one made it their blind-test tell. Three measurements, three causes:
//
//  1. NO REFLECTION. A three-band sample across shot 07 varied under 8% between
//     water under bright coloured terraces, open mid-span, and water under a dark
//     cliff — and the trend ran backwards, the water being *brightest* under the
//     *darkest* bank. In shot 06 a large iron arch stands over calm water and
//     returns nothing.
//
//     Two causes, one in this file and one in the Environment. In the Environment:
//     ssr_fade_out was 6.0 under a comment claiming it was a distance, when it is
//     the exponent in pow(1 - ray_progress, n) — so every reflection found past the
//     first ~15% of the ray march was multiplied by under 0.02 and deleted. See
//     assets/environments/porto_daylight.tres. In this file: deep_color was an
//     0.19-luminance blue-grey, which is the albedo of wet concrete rather than of
//     river water, and it swamped a reflection worth 4-15% Fresnel. A river is dark
//     and reflective; what makes it read is that the reflection is nearly all of it.
//
//  2. VISIBLE TILING. Autocorrelation along x found periodic peaks at lag 17 px
//     (r = 0.41) in the far band and lag 27 px (r = 0.50) in the mid band — about
//     fifteen repeats of the same streak across the river. That is exactly what a
//     sum of three pure sines has to produce: the swell repeats every 34.9 m and
//     the foam mask, which was smoothstep() of the raw sum, repeats with it. The
//     field is now domain-warped by a low-frequency value noise and the foam is
//     gated by a second, so the crests keep the shape they were tuned for and stop
//     being a comb. See warp() and foam_mask().
//
//  3. NO SHORELINE. A column scan cut granite L 134.6 to water L 51.7 in TWO
//     pixels: no foam, no lapping, no disturbance where a tidal river meets a
//     vertical quay wall. shore_mask() adds it, and it is analytic because the
//     shader has no way to ask the terrain where the bank is — see the uniform
//     block for how that number is kept from drifting.
//
// --- On the sun vector ----------------------------------------------------------
//
// This file's default and Mat_river's override in scenes/world/bridge_arena.tscn
// now agree, and _atmosphere_probe.gd asserts BOTH against the scene's real
// SunLight rather than only the default — which is how the override sat 121 degrees
// of azimuth stale for three rounds while the probe passed. Nothing in this header
// is a to-do any more; if that changes, say so here.
shader_type spatial;
render_mode cull_disabled;

// --- Set from bridge_arena.tscn: these names must not change ----------------

// The grazing / mirror colour: pale estuary sky, matching the sky shader's
// horizon_color. It is a HINT of what the water is mirroring — silt and suspended
// sediment genuinely tint the surface return — not the mirror itself. The mirror
// itself is the renderer's specular; see mirror_albedo.
uniform vec4 shallow_color : source_color = vec4(0.720, 0.800, 0.870, 1.0);
// The body of the water: what comes back up out of it rather than off it.
//
// 0.110/0.195/0.230 -> 0.042/0.081/0.086. The old value is 0.185 luminance, which is
// the diffuse albedo of damp concrete; the Douro is a silty estuary channel and its
// body reflectance is nearer 6%. That is not a stylistic darkening, it is the whole
// of finding 1 above: a surface whose own albedo returns 19% of the key cannot show
// a reflection worth 4-15%, so the river was a painted blue sheet with a reflection
// invisibly on top of it. Dark and reflective is what makes water read as water, and
// it is also what makes the water go DARK under a dark bank and BRIGHT under a lit
// one, which is the measurement the critics took.
uniform vec4 deep_color : source_color = vec4(0.042, 0.081, 0.086, 1.0);
uniform float wave_speed = 0.5;
uniform float wave_height = 0.35;      // metres, peak of the summed swell
uniform float wave_scale = 0.18;       // base angular frequency (1 / metres)
uniform float flow = 0.02;             // downstream drift of the whole wave field
// Specular sunlight, so it is the sun's own colour at 5100 K.
uniform vec4 glint_color : source_color = vec4(1.0, 0.97, 0.90, 1.0);
uniform float glint_strength = 0.45;

// --- Tuning -----------------------------------------------------------------

// World-space direction *towards* the sun, i.e. SunLight's +Z basis column in
// bridge_arena.tscn: 34 degrees up, 66 degrees east of +x. If that light moves, move
// this with it — and move Mat_river's copy, which is the one that counts. Both are
// gated in _atmosphere_probe.gd against the scene's own SunLight node.
uniform vec3 sun_direction = vec3(0.337181, 0.559193, 0.757364);
// A 34-degree sun lays a longer, softer glitter path than a 51-degree one — the
// reflected angle sweeps more slowly across the swell as it approaches the horizon.
uniform float glint_sharpness : hint_range(16.0, 512.0) = 200.0;
uniform float chop_strength : hint_range(0.0, 3.0) = 1.0;
uniform float water_roughness : hint_range(0.0, 0.4) = 0.06;
// How fast the surface flips from body to sky-mirror as the view angle flattens.
// Higher = a narrower band pinned to the far bank. 3.0 counted almost the whole
// surface as grazing and rendered the Douro as a flat pale sheet — a sandbank, not a
// river; 5.2 keeps the mirror term where it belongs and lets deep_color own the near
// and middle field.
uniform float horizon_falloff : hint_range(1.0, 8.0) = 5.2;

// How much of the grazing-angle mirror is carried by ALBEDO, with the rest left to
// the BRDF's own specular — i.e. to SSR on Forward+ and to the radiance cubemap on
// Compatibility, both of which reflect the ACTUAL sky, arch and banks rather than a
// constant standing in for them.
//
// 0.30 -> 0.14, and it comes down for the same reason deep_color does. Every unit of
// mirror carried in ALBEDO is a unit of flat colour laid over the reflection, and
// with ssr_fade_out fixed there is now a real reflection underneath to be laid over.
// Kept non-zero because silt does tint the surface return and because it is the only
// grazing brightening the mobile tier (no SSR, no reflection probes) ever gets.
uniform float mirror_albedo : hint_range(0.0, 1.0) = 0.14;

uniform vec4 foam_color : source_color = vec4(0.93, 0.95, 0.96, 1.0);
// Whitecaps on the open river. Low on purpose: the Douro at Porto is a tidal pool
// between two banks, and foam belongs on it as a hint. What this no longer does is
// fire on EVERY crest — see foam_mask().
uniform float foam_strength : hint_range(0.0, 1.0) = 0.30;

// --- The shoreline ----------------------------------------------------------
//
// The shader cannot ask the terrain where the bank is, so the bank is described
// here. That is the pattern this project has already been burned by once (Mat_river
// held a hand-copied sun vector three rounds after the sun moved), so it is handled
// the same way that was: _atmosphere_probe.gd calls TerrainBuilder.front_x() at
// several z and fails if these four numbers stop describing the wall it returns.
// They cannot drift silently and nobody has to remember them.
//
// The quay line is |x| = shore_half_width + shore_taper * z, over the reach the bank
// is modelled at all; outside that reach there is no wall to lap against.
uniform float shore_half_width = 52.0;
uniform float shore_taper = 0.028;
uniform float shore_z_min = -128.0;
uniform float shore_z_max = 46.0;
// Metres of water that carry the disturbance. A tidal river against a vertical
// granite wall throws a band of broken water a couple of metres wide; at 60 m — the
// distance the quay sits at in shot 07 — that is 4-6 px, which is the difference
// between a two-pixel cut from stone to water and a shoreline.
uniform float shore_band : hint_range(0.0, 12.0) = 2.6;
uniform float shore_foam : hint_range(0.0, 2.0) = 0.85;

varying vec3 world_pos;


// --- Value noise ------------------------------------------------------------
//
// Deterministic, driver-independent and free of sin(): a sin-based hash bands
// visibly on some GL Compatibility drivers, and the web tier has to match the
// desktop one. Nothing here is random in the ARCHITECTURE.md sense — it is a pure
// function of world position, so every frame of every run produces the same field
// and the capture gate is unaffected.
float hash21(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}


float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}


// One directional sine. Returns its height contribution and accumulates the
// horizontal gradient d(height)/d(xz), so the surface normal costs three extra
// cosines rather than a second set of texture taps.
float wave(vec2 p, vec2 dir, float freq, float amp, float speed, float t, inout vec2 grad) {
	float phase = dot(p, dir) * freq + t * speed;
	grad += dir * (freq * amp * cos(phase));
	return amp * sin(phase);
}


// Where in the wave field a given patch of river currently is. BOTH stages must
// sample here: if the vertex displacement and the fragment normal disagree about
// the phase, the drift between them grows without bound and the highlights walk off
// the crests.
//
// The drift now runs DOWNSTREAM. It used to be (12, 4) in xz — i.e. mostly +x —
// which is straight across this arena, because the Douro here runs along Z and the
// bridge crosses it along X. The whole field was therefore sliding sideways from
// bank to bank, and a critic reported the surface streaks as "unrelated to current".
// -z is downstream toward the Atlantic; the small +x component is the set toward the
// outside of the bend the Ribeira sits on.
vec2 field_pos(vec2 world_xz, float t) {
	return world_xz - vec2(t * flow * 2.5, -t * flow * 12.0);
}


// Domain warp. This is the whole of finding 2.
//
// A sum of sines is a comb: three trains at 34.9 m, 20.5 m and 11.3 m repeat their
// joint pattern often enough that autocorrelation along one image row found the same
// streak fifteen times across the river. Displacing the SAMPLING POSITION by a
// low-frequency noise before evaluating them leaves every train its own wavelength
// and shape — which is what was tuned against a render and is worth keeping — while
// making the phase relationship between them vary from place to place, so no two
// stretches of river carry the same crest pattern.
//
// 7 m of displacement over a ~70 m correlation length: 1.3 radians of phase jitter on
// the dominant train, which is enough to break the repeat and far too little to bend
// a wavefront into a visible swirl.
//
// The cost is that grad is now the gradient in WARPED space rather than in world
// space; strictly it wants multiplying by the warp's Jacobian. That Jacobian is
// (1 + O(0.1)) here, so the error is a few per cent of the surface slope, i.e. a
// fraction of a degree of normal — well under the chop it sits on top of, and much
// cheaper than the four extra noise taps the exact form costs.
vec2 warp(vec2 p) {
	float a = vnoise(p * 0.0142);
	float b = vnoise(p * 0.0142 + vec2(37.2, 11.7));
	return p + (vec2(a, b) - 0.5) * 14.0;
}


// The swell: three crossing trains. Amplitudes sum to 1.0 so the caller's
// wave_height stays honest metres. Directions are unchanged — their crests run
// broadly along the channel, which is what puts the surface streaks downstream where
// a river's are.
float swell(vec2 p, float t, inout vec2 grad) {
	float h = 0.0;
	h += wave(p, normalize(vec2(1.0, 0.18)), wave_scale, 0.52, wave_speed, t, grad);
	h += wave(p, normalize(vec2(-0.25, 1.0)), wave_scale * 1.7, 0.31, wave_speed * 0.82, t, grad);
	h += wave(p, normalize(vec2(0.80, -0.60)), wave_scale * 3.1, 0.17, wave_speed * 1.35, t, grad);
	return h;
}


// Ripples an order of magnitude below the river mesh's ~5 m vertex spacing.
// Gradient only: displacing these would alias into a strobing mess.
void chop(vec2 p, float t, inout vec2 grad) {
	wave(p, normalize(vec2(0.90, 0.45)), wave_scale * 7.0, 0.030 * chop_strength, wave_speed * 2.1, t, grad);
	wave(p, normalize(vec2(-0.55, 0.85)), wave_scale * 12.0, 0.016 * chop_strength, wave_speed * 2.9, t, grad);
	wave(p, normalize(vec2(0.35, -0.95)), wave_scale * 21.0, 0.008 * chop_strength, wave_speed * 3.7, t, grad);
}


// Metres of open water between here and the quay wall, as a 0-1 nearness.
//
// The wall the terrain builder lays is |x| = 52 + 0.028 z over z in [-128, 46]; past
// the downstream end the bank sinks into the water as a rock headland and there is
// nothing to lap against, so the whole term fades out over the last twelve metres
// rather than stopping at a line. The upstream end runs into the photogrammetry
// backdrop and gets the same treatment.
float shore_mask(vec2 xz) {
	float reach = smoothstep(shore_z_min - 12.0, shore_z_min + 4.0, xz.y)
			* (1.0 - smoothstep(shore_z_max - 12.0, shore_z_max, xz.y));
	float wall = shore_half_width + shore_taper * clamp(xz.y, shore_z_min, shore_z_max);
	float d = abs(xz.x) - (wall - shore_band);
	return reach * smoothstep(0.0, shore_band, d);
}


// Where whitecaps are ALLOWED to be, before the crest test.
//
// The old mask was smoothstep(0.45, 0.95, h) alone, so every crest in the field
// broke, everywhere, identically — which is both physically wrong (whitecaps happen
// where the wind has fetch and the water is steep, in patches) and the second half of
// the tiling finding: a foam band drawn on a periodic height field is itself
// periodic. Two independent noise fields fix it: one decides which stretches of river
// are breaking at all, and one jitters the height at which they break.
float foam_mask(vec2 p, float h, float slope) {
	float patch = smoothstep(0.42, 0.86, vnoise(p * 0.021));
	float trip = 0.40 + 0.34 * vnoise(p * 0.115 + vec2(13.0, -7.0));
	float crest = smoothstep(trip, trip + 0.42, h);
	// Steep water breaks; a long low swell does not, however high its crest.
	float steep = smoothstep(0.05, 0.22, slope);
	return crest * patch * steep;
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 grad = vec2(0.0);
	float h = swell(warp(field_pos(world_pos.xz, TIME)), TIME, grad) * wave_height;
	// The river plane is axis-aligned and unrotated, so a local +Y push and a
	// world +Y push are the same thing — no need to round-trip the matrix.
	VERTEX.y += h;
	world_pos.y += h;
}


void fragment() {
	float t = TIME;
	// world_pos.xz survived the vertex displacement untouched (only y moved), so
	// this lands on exactly the phase the geometry was built from — including the
	// warp, which both stages apply identically.
	vec2 p = warp(field_pos(world_pos.xz, t));

	vec2 grad = vec2(0.0);
	float h = swell(p, t, grad);
	grad *= wave_height;    // swell() is unit-amplitude; put the gradient in metres
	chop(p, t, grad);       // chop amplitudes are already metres

	// Horizontal plane, so the tangent frame is trivially world XYZ and the
	// normal falls straight out of the height gradient.
	vec3 n_world = normalize(vec3(-grad.x, 1.0, -grad.y));
	if (!FRONT_FACING) {
		n_world = -n_world;
	}
	vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - world_pos);

	// Looking straight down you see into the water (the body); at a grazing angle
	// the surface turns into a mirror. Shaped like real Fresnel rather than a linear
	// ramp, which is what pins the bright band to the far bank instead of washing the
	// whole river. Troughs bias a shade deeper than crests.
	float facing = clamp(dot(n_world, to_cam), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, horizon_falloff);
	// Written as "how far toward the mirror", not "how deep", so mirror_albedo can
	// scale the one term without also scaling the depth cue.
	float mirror = clamp(fresnel + h * 0.18, 0.0, 1.0) * mirror_albedo;
	vec3 base = mix(deep_color.rgb, shallow_color.rgb, mirror);

	// The shore. Three things happen in the last couple of metres against a quay:
	// the water shallows over the wall's own footing and picks up silt, it is broken
	// by the reflected wave off a vertical face, and it foams. The first is a colour
	// lift toward shallow_color; the second and third are foam, surging with the
	// swell rather than sitting as a painted stripe.
	float shore = shore_mask(world_pos.xz);
	base = mix(base, shallow_color.rgb, shore * 0.30);
	float surge = 0.45 + 0.55 * smoothstep(-0.25, 0.55, h);
	float lap = shore * shore * surge * shore_foam;

	float slope = length(grad);
	float open_foam = foam_mask(p, h, slope) * foam_strength;
	float foam = clamp(open_foam + lap, 0.0, 1.0);

	// Sun glitter: a tight Blinn lobe against the perturbed normal. Written as
	// emission because the fragment stage has no light data, and because under
	// Forward+'s HDR buffer it blooms instead of clipping.
	vec3 half_vec = normalize(to_cam + normalize(sun_direction));
	float glint = pow(max(dot(n_world, half_vec), 0.0), glint_sharpness);

	ALBEDO = mix(base, foam_color.rgb, foam);
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	EMISSION = glint_color.rgb * glint * glint_strength;
	// Near-mirror everywhere but the foam and the shore, so SSR — which is what puts
	// the arch and the Ribeira in the water — actually shows up as a reflection
	// instead of a flat wash. Broken water against the wall is not a mirror, and
	// neither is a whitecap.
	ROUGHNESS = mix(water_roughness, 0.62, max(foam, shore * 0.55));
	METALLIC = 0.0;
	// Water's true F0 is 0.02 (IOR 1.33), which Godot writes as SPECULAR 0.25. It is
	// left at the 0.04 dielectric default instead, and that is a deliberate half-stop
	// of licence rather than an oversight: the near field is the half of the river a
	// grazing Fresnel cannot reach, and at 0.25 it loses the sheen that says the
	// surface is wet at all. The grazing band — which is most of the frame — is
	// dominated by the Schlick term and is unaffected either way.
	SPECULAR = 0.5;
}
