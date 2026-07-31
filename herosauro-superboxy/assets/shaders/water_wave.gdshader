// Stylised-realistic Douro water for the daylight Porto arena.
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
//
// ============================================================================
// THE DEFAULTS BELOW ARE ALL OVERRIDDEN BY Mat_river IN bridge_arena.tscn, AND
// THAT MATERIAL IS STILL AUTHORED FOR THE SUNSET.
//
// Every uniform in this file is set explicitly by that sub-resource, so changing a
// default here changes nothing at runtime. The defaults are corrected anyway,
// because they are what the next scene to use this shader will get and because a
// default that documents a sun which no longer exists is worse than no default. The
// arena scene belongs to the world stream; the four values it needs changed, with
// the reasoning, are:
//
//   shallow_color   (0.86, 0.685, 0.47)  -> (0.72, 0.80, 0.87)
//       This is the colour a grazing sightline returns, i.e. what the river is
//       mirroring. It was pinned under the sky shader's old warm horizon_color; that
//       is now (0.741, 0.831, 0.898) and a mirror cannot out-hue what it reflects.
//       Left warm, the far half of the Douro stays a sunset band under a blue sky —
//       and it is the largest single surface in shots 06 and 09.
//   glint_color     (1.0, 0.80, 0.55)    -> (1.0, 0.97, 0.90)
//       The glitter path is specular sunlight, so it is the sun's colour: 5100 K
//       warm white, not 3200 K amber.
//   glint_sharpness 165                  -> 240 -> 200
//       A low sun spreads its glitter into a long soft path down the water because
//       the reflected angle sweeps slowly; a high one concentrates it into a hard
//       patch. 240 was for the 51-degree key; the key is now 34 and the lobe widens
//       back part of the way.
//   sun_direction   (-0.859785, 0.19995, -0.469882) -> (0.337181, 0.559193, 0.757364)
//       SunLight's +Z basis column, which moves whenever the sun does. Left alone the
//       glitter sits on the wrong side of the river from every other highlight in
//       the frame, which is the kind of tell a critic finds immediately — and that is
//       exactly what Mat_river in bridge_arena.tscn is still doing. See the uniform.
// ============================================================================
shader_type spatial;
render_mode cull_disabled;

// --- Set from bridge_arena.tscn: these names must not change ----------------

// The grazing / mirror colour: pale estuary sky, matching the sky shader's
// horizon_color. Warm here was the single most sunset-coloured number in the file.
uniform vec4 shallow_color : source_color = vec4(0.720, 0.800, 0.870, 1.0);
// Douro silt-green rather than open-ocean blue. Under a high sun the near water is
// mostly this, because very little of it is at a grazing angle.
uniform vec4 deep_color : source_color = vec4(0.110, 0.195, 0.230, 1.0);
uniform float wave_speed = 0.5;
uniform float wave_height = 0.35;      // metres, peak of the summed swell
uniform float wave_scale = 0.18;       // base angular frequency (1 / metres)
uniform float flow = 0.02;             // downstream drift of the whole wave field
// Specular sunlight, so it is the sun's own colour at 5100 K.
uniform vec4 glint_color : source_color = vec4(1.0, 0.97, 0.90, 1.0);
uniform float glint_strength = 0.45;

// --- Tuning -----------------------------------------------------------------

// World-space direction *towards* the sun, i.e. SunLight's +Z basis column in
// bridge_arena.tscn: 34 degrees up, 66 degrees east of +x. If that light moves,
// move this with it — and move Mat_river's copy of it, which is the one that counts.
//
// STILL BROKEN AND STILL NOT MINE TO FIX. Mat_river in bridge_arena.tscn overrides
// this uniform with vec3(-0.859785, 0.19995, -0.469882), which is the ORIGINAL sunset
// sun from two rounds ago: it points into the -x/-z quadrant, 11.5 degrees up. Since
// the world stream owns that scene's sub-resources, the only thing this file can do is
// keep its own default honest and say so loudly. _atmosphere_probe.gd asserts this
// default against the scene's real SunLight, so the two cannot drift; nothing checks
// Mat_river, and the glitter path on the Douro is consequently ~120 degrees of azimuth
// away from where the sun is. It is in this pass's report.
uniform vec3 sun_direction = vec3(0.337181, 0.559193, 0.757364);
// 240 -> 200. A 34-degree sun lays a longer, softer glitter path than a 51-degree one
// — the reflected angle sweeps more slowly across the swell as it approaches the
// horizon — so the lobe widens back out, though nowhere near the 165 a true low sun
// over water wanted.
uniform float glint_sharpness : hint_range(16.0, 512.0) = 200.0;
uniform float chop_strength : hint_range(0.0, 3.0) = 1.0;
uniform float water_roughness : hint_range(0.0, 0.4) = 0.07;
// How fast the surface flips from deep to sky-mirror as the view angle flattens.
// Higher = a narrower band pinned to the far bank. 3.0 counted almost the whole
// surface as grazing and rendered the Douro as a flat pale sheet — a sandbank, not a
// river; 5.2 keeps the mirror term where it belongs and lets deep_color own the near
// and middle field. (This is the value Mat_river already uses; the default was the
// known-bad one.)
uniform float horizon_falloff : hint_range(1.0, 8.0) = 5.2;

// How much of the grazing-angle mirror is carried by ALBEDO, with the rest left to
// the BRDF's own specular. This uniform is NEW in the daylight pass and is
// deliberately not one Mat_river sets, because it is the fix for a structural bug
// rather than a retune of an authored value.
//
// The bug: at a grazing angle this shader mixed the whole way to shallow_color in
// ALBEDO, and then the renderer applied Schlick Fresnel on top of a ROUGHNESS 0.07
// surface and reflected the sky as well. The mirror was being paid for twice — once
// as a diffuse colour and once as an actual reflection — so the far half of the river
// came out as a flat sheet of shallow_color with the sky's reflection stacked on it.
// Under a warm sunset shallow_color that is a glare band, which is what it was tuned
// as; under a daylight rig with an untouched sunset uniform it is a pink sheet
// covering the middle third of shot 07, which is what a render measured.
//
// 0.30 keeps shallow_color's hue as a hint of what the water is mirroring — silt and
// suspended sediment do genuinely tint the surface return — and hands the other 70%
// to the specular path, which reflects the actual sky, actually occluded, through SSR
// on Forward+ and through the radiance cubemap on Compatibility. That is both the
// physically correct split and the one that stops a stale colour dominating a third
// of the frame.
//
// This does not make Mat_river's shallow_color correct, it makes it survivable. The
// value it should hold is in the header.
uniform float mirror_albedo : hint_range(0.0, 1.0) = 0.30;

uniform vec4 foam_color : source_color = vec4(0.93, 0.95, 0.96, 1.0);
// 0.30 -> 0.18. Whitecaps key off smoothstep(0.45, 0.95, h) on the unit-amplitude
// swell, so they fire on every crest however calm the water is set to be. The Douro
// at Porto is a tidal pool between two banks; foam belongs on the near water as a hint.
uniform float foam_strength : hint_range(0.0, 1.0) = 0.18;

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

	// Looking straight down you see into the water (deep); at a grazing angle the
	// surface turns into a mirror for the sky (shallow_color is the pale one).
	// Shaped like real Fresnel rather than a linear ramp, which is what pins the
	// bright band to the far bank instead of washing the whole river.
	// Troughs bias a shade deeper than crests.
	float facing = clamp(dot(n_world, to_cam), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, horizon_falloff);
	// Written as "how far toward the mirror", not "how deep", so mirror_albedo can
	// scale the one term without also scaling the depth cue. See its declaration:
	// the other 70% of the mirror is the renderer's specular, which reflects the real
	// sky instead of a colour standing in for one.
	float mirror = clamp(fresnel + h * 0.18, 0.0, 1.0) * mirror_albedo;
	vec3 base = mix(deep_color.rgb, shallow_color.rgb, mirror);

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
	// Near-mirror everywhere but the foam, so the sky radiance map — and SSR, which
	// is what puts the arch and the Ribeira in the water — actually shows up as a
	// reflection instead of a flat wash. This term matters far more under a blue sky
	// with an iron lattice across it than it did under an amber one.
	ROUGHNESS = mix(water_roughness, 0.55, foam);
	METALLIC = 0.0;
	// Left at the 4% dielectric default: the BRDF's own Schlick term already
	// brightens the grazing edge, and doubling up on it blows out the horizon.
	SPECULAR = 0.5;
}
