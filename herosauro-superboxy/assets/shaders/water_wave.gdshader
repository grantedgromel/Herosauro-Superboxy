// Stylised-realistic Douro water for the golden-hour Porto arena.
//
// The previous version displaced vertices with two sines and then coloured the
// surface with sin(u * 38) * sin(u * 38). That pattern had nothing to do with
// the wave shape and the surface normal stayed dead flat, so the river never
// caught the sun and read as a blotchy oil slick. Here the normal is derived
// analytically from the summed wave derivatives — same waves the vertex stage
// displaces, plus finer chop that only exists in the normal — and Forward+ does
// the rest.
//
// Deliberately OPAQUE. Depth-based shore shallowing and contact foam need
// DEPTH_TEXTURE, which only carries the scene behind you from the transparent
// pass; moving a 240 m plane into that pass costs a screenful of overdraw, and
// there is no riverbed geometry, so the deep water would show sky straight
// through it. The shallow/deep split rides view angle and wave height instead,
// which is what actually drives the read looking down from a bridge deck.
shader_type spatial;
render_mode cull_disabled;

// --- Set from bridge_arena.tscn: these names must not change ----------------

uniform vec4 shallow_color : source_color = vec4(0.945, 0.620, 0.400, 1.0);
uniform vec4 deep_color : source_color = vec4(0.180, 0.320, 0.500, 1.0);
uniform float wave_speed = 0.5;
uniform float wave_height = 0.35;      // metres, peak of the summed swell
uniform float wave_scale = 0.18;       // base angular frequency (1 / metres)
uniform float flow = 0.02;             // downstream drift of the whole wave field
uniform vec4 glint_color : source_color = vec4(1.0, 0.85, 0.55, 1.0);
uniform float glint_strength = 0.45;

// --- Tuning -----------------------------------------------------------------

// World-space direction *towards* the sun. Default matches the SunLight basis
// in bridge_arena.tscn; if that light moves, move this with it.
uniform vec3 sun_direction = vec3(0.354, 0.707, 0.612);
uniform float glint_sharpness : hint_range(16.0, 512.0) = 190.0;
uniform float chop_strength : hint_range(0.0, 3.0) = 1.0;
uniform float water_roughness : hint_range(0.0, 0.4) = 0.055;
// How fast the surface flips from deep to sun-glare as the view angle flattens.
// Higher = a narrower, hotter band pinned to the far bank.
uniform float horizon_falloff : hint_range(1.0, 8.0) = 3.0;
uniform vec4 foam_color : source_color = vec4(0.93, 0.95, 0.96, 1.0);
uniform float foam_strength : hint_range(0.0, 1.0) = 0.30;

varying vec3 world_pos;


// One directional sine. Returns its height contribution and accumulates the
// horizontal gradient d(height)/d(xz), so the surface normal costs three extra
// cosines rather than a second set of texture taps.
float wave(vec2 p, vec2 dir, float freq, float amp, float speed, float t, inout vec2 grad) {
	float phase = dot(p, dir) * freq + t * speed;
	grad += dir * (freq * amp * cos(phase));
	return amp * sin(phase);
}


// Where in the wave field a given patch of river currently is. The Douro runs
// west, so `flow` slides the whole field downstream rather than scrolling a
// texture across a static surface. BOTH stages must sample here: if the vertex
// displacement and the fragment normal disagree about the phase, the drift
// between them grows without bound and the highlights walk off the crests.
vec2 field_pos(vec2 world_xz, float t) {
	return world_xz - vec2(t * flow * 12.0, t * flow * 4.0);
}


// The swell: three crossing trains. Amplitudes sum to 1.0 so the caller's
// wave_height stays honest metres.
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


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 grad = vec2(0.0);
	float h = swell(field_pos(world_pos.xz, TIME), TIME, grad) * wave_height;
	// The river plane is axis-aligned and unrotated, so a local +Y push and a
	// world +Y push are the same thing — no need to round-trip the matrix.
	VERTEX.y += h;
	world_pos.y += h;
}


void fragment() {
	float t = TIME;
	// world_pos.xz survived the vertex displacement untouched (only y moved), so
	// this lands on exactly the phase the geometry was built from.
	vec2 p = field_pos(world_pos.xz, t);

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

	// Looking straight down you see into the water (deep); at a grazing angle
	// the surface turns into a mirror for the sunset (shallow_color is the warm
	// one). Shaped like real Fresnel rather than a linear ramp, which is what
	// pins the glare band to the far bank instead of washing the whole river.
	// Troughs bias a shade deeper than crests.
	float facing = clamp(dot(n_world, to_cam), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, horizon_falloff);
	float depth_mix = clamp(1.0 - fresnel - h * 0.18, 0.0, 1.0);
	vec3 base = mix(shallow_color.rgb, deep_color.rgb, depth_mix);

	// Whitecaps on the top sliver of the crests, broken up so the band isn't a
	// clean contour line. Keyed off normalised wave height, so it survives
	// whatever wave_height / wave_scale the scene dials in.
	float fleck = 0.5 + 0.5 * sin(dot(p, vec2(2.7, -1.9)) + t * 1.7);
	float foam = smoothstep(0.45, 0.95, h) * mix(0.35, 1.0, fleck) * foam_strength;

	// Sun glitter: a tight Blinn lobe against the perturbed normal. Written as
	// emission because the fragment stage has no light data, and because under
	// Forward+'s HDR buffer it blooms instead of clipping.
	vec3 half_vec = normalize(to_cam + normalize(sun_direction));
	float glint = pow(max(dot(n_world, half_vec), 0.0), glint_sharpness);

	ALBEDO = mix(base, foam_color.rgb, foam);
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	EMISSION = glint_color.rgb * glint * glint_strength;
	// Near-mirror everywhere but the foam, so the sky radiance map actually
	// shows up as a reflection instead of a flat wash.
	ROUGHNESS = mix(water_roughness, 0.55, foam);
	METALLIC = 0.0;
	// Left at the 4% dielectric default: the BRDF's own Schlick term already
	// brightens the grazing edge, and doubling up on it blows out the horizon.
	SPECULAR = 0.5;
}
