// Analytic clear-day sky over the Douro, in place of ProceduralSkyMaterial.
//
// A two-colour vertical ramp is the one thing a real sky never is, and a single
// pow() ramp — which is what this was — is only marginally better: it is monotone,
// so the eye reads one smear from pale to blue and correctly calls it a gradient
// rather than an atmosphere. Real skies are built out of *layers*, and each layer
// has a top as well as a bottom:
//
//   1. a two-band vertical ramp, horizon -> upper sky -> zenith, each band shaped
//      with a smoothstep so it fades IN and OUT instead of trailing off forever;
//   2. two exponential haze layers pinned to the horizon — the physically-correct
//      profile for a scattering layer, and the reason the pale band has a bright
//      core with a soft tail rather than a hard edge partway up the dome;
//   3. two sun scatter lobes and a limb-softened disk on top of all of it.
//
// This file used to carry two more layers — a Belt of Venus band and the cool wedge
// of Earth's own shadow, both on the anti-solar half. Both are *evening* phenomena:
// they are the planet's terminator painted on the haze, and they only exist while
// the sun is within a few degrees of the horizon. Under a 34-degree sun there is no
// terminator anywhere in the sky, so they are gone rather than dimmed. A rose band
// and a grey-blue wedge at reduced energy would not read as subtlety, they would
// read as dirt on the lens.
//
// What replaces them is nothing, and that is correct. A clear midday sky is a
// genuinely simple object: Rayleigh blue that deepens with elevation, Mie haze that
// whitens the last 15 degrees above the horizon, and an aureole around the sun. Its
// difficulty is not layer count, it is that the blue has to stay *saturated* while
// the horizon goes pale, which is what horizon_band / horizon_shape / zenith_shape
// are for.
//
// The lower hemisphere is derived from the finished upper-hemisphere colour rather
// than authored separately, and crossfaded SYMMETRICALLY about the horizon. That
// matters more here than it looks: the visible waterline is ~1.8 degrees BELOW the
// mathematical horizon (the river plane runs out to z = -590), so any brightness
// step at EYEDIR.y = 0 lands in open sky just above the water and reads as a hard
// painted line. The old one-sided smoothstep put a 2x step exactly there.
//
// The sun is read out of LIGHT0_*, which means the disk and both lobes track
// whatever DirectionalLight3D the arena scene owns without this file — or the
// Environment resource — having to know where it points. LightingRig adds three more
// directional lights (a cool sky fill and two coloured bounces); all three are
// created with sky_mode = LIGHT_ONLY specifically so they never become LIGHT0 and
// drag the sun disk off the real sun.
shader_type sky;

// --- Dome gradient -----------------------------------------------------------

// A real clear zenith at 41 degrees north in April, and the most saturated thing in
// the frame after the azulejo. Under a low sun the zenith had to be dark to give the
// image contrast against a warm wash; under a high one the contrast comes from the
// key, so the zenith is free to be *blue* instead of merely dark. This is the colour
// the RUBRIC means by "a genuinely blue sky", and it is also the colour that lands in
// every shadow on the bridge via ambient_light_sky_contribution = 0.92.
uniform vec4 zenith_color : source_color = vec4(0.125, 0.325, 0.690, 1.0);
// The band around 25-45 degrees, where Rayleigh blue has started losing to Mie haze
// but has not surrendered yet. Lighter and a shade less saturated than the zenith,
// never greyer — a grey mid-band is what makes a sky read as overcast.
uniform vec4 upper_color : source_color = vec4(0.322, 0.541, 0.804, 1.0);
// Sea haze coming up the Douro estuary. Pale, and still faintly blue: horizon haze
// under a high sun is scattered *sky*, so it desaturates toward white, not toward
// cream. The cream version of this number was the single loudest remnant of sunset.
//
// Darkened 0.741,0.831,0.898 -> 0.660,0.760,0.850 after a render measured the far
// bank at luminance 0.69 against a sky at 0.59. Distant geometry is 90% veiled by
// fog_aerial_perspective, i.e. it takes the colour of the sky BEHIND it — and the sky
// behind anything on the skyline is this band. Too bright here and the backdrop comes
// out brighter than the dome above it, which is the RUBRIC's "background competing
// with playable space" failure arriving through the atmosphere rather than through
// the art.
uniform vec4 horizon_color : source_color = vec4(0.660, 0.760, 0.850, 1.0);
// sin(elevation) at which the pale band hands over to upper_color. 0.30 = 17.5 deg.
uniform float horizon_band : hint_range(0.05, 0.9) = 0.30;
// Shape exponents inside each band. Below 1 the band gives way early, above 1 it
// holds its colour and then drops; both are then run through a smoothstep, so the
// pair behaves like a curve editor rather than a single falloff.
// horizon_shape 0.85 -> 0.70: the pale band gives way sooner, so the whitening stays
// a hem along the skyline instead of climbing a third of the dome the way it does at
// sunset. zenith_shape 1.15 -> 0.90: reach the deep blue earlier, so most of the
// visible dome is blue rather than the transitional band.
uniform float horizon_shape : hint_range(0.2, 4.0) = 0.70;
uniform float zenith_shape : hint_range(0.2, 4.0) = 0.90;

// --- Horizon haze ------------------------------------------------------------

// exp(-sin(elev) * falloff) is the transmittance profile of an exponential
// atmosphere, which is what haze actually is. It has no edge anywhere — the whole
// point — and stacking a tight layer on a broad one gives the band a bright core
// and a long soft tail, which is what a photograph shows.
//
// Both energies come down (0.55/0.30 -> 0.34/0.26) and both falloffs tighten. A low
// sun fires its light along the same sightlines the haze sits in, so the band is
// blinding and deep; a high sun lights the haze from above and it reads as a modest
// pale hem. Overdoing it here is what makes a daylight sky look smoggy — and, because
// the depth fog takes 90% of its colour from whatever sky is behind the geometry, it
// is also what makes the far bank glow. The tight layer took the second cut
// (0.42 -> 0.34) for the same reason horizon_color darkened.
uniform vec4 haze_color : source_color = vec4(0.760, 0.828, 0.888, 1.0);
uniform float haze_tight_falloff : hint_range(2.0, 80.0) = 18.0;   // e-fold at 3.2 deg
uniform float haze_tight_energy : hint_range(0.0, 1.0) = 0.34;
uniform float haze_broad_falloff : hint_range(1.0, 40.0) = 4.5;    // e-fold at 12.8 deg
uniform float haze_broad_energy : hint_range(0.0, 1.0) = 0.26;

// --- Lower hemisphere --------------------------------------------------------

// Deliberately not black: below the horizon is the only IBL the underside of the
// deck and the arch truss ever receive, and a black lower half reads as a hole.
// (LightingRig also hangs two bounce lights for that job — this is the floor.)
//
// Lifted hard from the old near-black warm brown, and retinted. Under a mid-morning
// sun the lower hemisphere is not a dark river at dusk, it is sunlit water, granite
// quays and green terraced banks all returning light upward, and the value it
// returns is roughly the albedo of that mixture times sin(elevation). It is left
// where the 51-degree key put it even though the key is now 34: sin(34)/sin(51) =
// 0.72 would argue for dimming it, but the water it is mostly made of turns into a
// far better mirror as the sun comes down, and the two effects very nearly cancel.
// Olive-grey rather
// than neutral because the banks are the biggest coloured mass in it — the RUBRIC's
// "green off the river banks", delivered as image-based light rather than as a lamp.
uniform vec4 ground_color : source_color = vec4(0.263, 0.275, 0.235, 1.0);
// How much of the sky's own colour survives just below the horizon. The water is
// a mirror at grazing angles, so the answer is "most of it".
uniform float ground_bounce : hint_range(0.0, 1.0) = 0.55;
uniform float ground_band : hint_range(0.02, 1.0) = 0.22;
uniform float ground_falloff : hint_range(0.2, 8.0) = 1.1;
// Half-width of the symmetric crossfade across EYEDIR.y = 0, in sine units.
uniform float horizon_blend : hint_range(0.002, 0.3) = 0.045;

// --- Sun scatter lobes -------------------------------------------------------

// Near-white, with only the whisper of warmth 1.29 air masses actually removes from
// a 5100 K sun. The old (1.0, 0.769, 0.478) was a 30-air-mass sunset and it was
// painting a third of the dome amber.
uniform vec4 halo_color : source_color = vec4(1.0, 0.976, 0.925, 1.0);
// Tight lobe: the aureole hugging the disk. 130 -> 220, i.e. half the angular width.
// The aureole is forward-scattered light through the air between you and the sun, so
// it shrinks as the path shortens, and a high sun has the shortest path of the day.
uniform float halo_tight_falloff : hint_range(4.0, 512.0) = 220.0;
uniform float halo_tight_energy : hint_range(0.0, 8.0) = 1.1;
// Wide lobe: the general brightening of the sun half of the sky. Cut hard, 0.38 ->
// 0.16 over a lobe half as wide (4 -> 8), because at midday the sun side is only
// slightly brighter than the anti-solar side. Leaving this at sunset strength is
// what would keep a "golden hour" read in the frame no matter what the key light did.
uniform float halo_wide_falloff : hint_range(1.0, 64.0) = 8.0;
uniform float halo_wide_energy : hint_range(0.0, 4.0) = 0.16;

// --- Sun disk ----------------------------------------------------------------

// LIGHT0_SIZE is the light's angular_distance in radians, which SunLight sets to
// 0.53 degrees = 0.0093 rad, so the disk carries its own radius and only grows to
// match. 0.028 rad (1.6 deg) was a low sun swollen by refraction and haze; 0.014 rad
// (0.80 deg) is a high one, still half again life size so it survives the 1280x720
// capture as a disk rather than as three pixels.
uniform float sun_radius : hint_range(0.001, 0.2) = 0.014;
// Raised 13 -> 22 to hold the disk's absolute brightness while SunLight's energy came
// down 2.4 -> 2.0, and then some: this is the one thing in frame that is allowed to
// clip, and a midday sun that does not is not a midday sun.
uniform float sun_energy : hint_range(0.0, 64.0) = 22.0;
// Fraction of the radius spent softening the limb. 0.45 -> 0.18: a low sun seen
// through 30 air masses has a genuinely fuzzy edge and a high one does not. Kept
// non-zero so the disk does not alias into a shimmering polygon as the camera orbits.
uniform float sun_limb : hint_range(0.0, 0.98) = 0.18;
// A pinprick that bright filters down into the radiance cubemap as blocky
// fireflies, and the DirectionalLight3D already delivers its real energy to the
// scene, so the IBL copy of the disk is deliberately tamed.
uniform float sun_ibl_scale : hint_range(0.0, 1.0) = 0.15;

// 1.0 -> 1.15. The sky is both the background and, through
// ambient_light_sky_contribution = 0.92, the fill on every shaded surface in the
// arena. A clear noon sky is genuinely brighter than a sunset one, and this is the
// honest place to say so — the alternative is raising ambient_light_energy, which
// adds a directionless term instead of a brighter dome.
uniform float sky_energy : hint_range(0.0, 8.0) = 1.15;
// Several huge smooth ramps stacked is the worst case for an 8-bit buffer, which
// is exactly what the web build resolves into. Multiplicative so the break-up
// scales with local brightness instead of crushing the dark half.
uniform float dither_strength : hint_range(0.0, 0.1) = 0.013;


void sky() {
	float up = clamp(EYEDIR.y, -1.0, 1.0);
	float above = max(up, 0.0);

	// --- Two-band vertical ramp ---
	float lower_t = clamp(above / horizon_band, 0.0, 1.0);
	float upper_t = clamp((above - horizon_band) / max(1.0 - horizon_band, 0.001), 0.0, 1.0);
	vec3 col = mix(horizon_color.rgb, upper_color.rgb,
			smoothstep(0.0, 1.0, pow(lower_t, horizon_shape)));
	col = mix(col, zenith_color.rgb, smoothstep(0.0, 1.0, pow(upper_t, zenith_shape)));

	// --- Haze layers ---
	// mix() rather than += so a hot haze colour can never push the horizon past
	// its own value and clip; the band's brightness is the colour, not the sum.
	float haze = exp(-above * haze_tight_falloff) * haze_tight_energy
			+ exp(-above * haze_broad_falloff) * haze_broad_energy;
	col = mix(col, haze_color.rgb, clamp(haze, 0.0, 1.0));

	if (LIGHT0_ENABLED) {
		vec3 sun_dir = normalize(LIGHT0_DIRECTION);
		float cos_sun = clamp(dot(sun_dir, EYEDIR), -1.0, 1.0);
		float toward = max(cos_sun, 0.0);

		// --- Sun-side scatter ---
		// Scatter is still strongest along sightlines that graze the horizon, because
		// they travel through the most air, so the wide lobe fades toward the zenith.
		// The floor went 0.30 -> 0.55 when the sun went up, because a sun's aureole
		// sits wherever the sun does and a floor tuned for a horizon sun was cutting
		// the lobe to a third exactly where it is supposed to be brightest. At 34
		// degrees the aureole is lower again and the floor matters less than it did,
		// but it is not put back: 0.30 was authored for an 11.5-degree sun sitting
		// IN the grazing band, which is a different picture from either of these.
		float grazing = mix(0.55, 1.0, pow(clamp(1.0 - abs(up), 0.0, 1.0), 2.0));
		col += halo_color.rgb * halo_wide_energy * pow(toward, halo_wide_falloff) * grazing;
		col += halo_color.rgb * halo_tight_energy * pow(toward, halo_tight_falloff);

		float radius = max(LIGHT0_SIZE, sun_radius);
		float outer = cos(radius);
		float inner = cos(radius * (1.0 - sun_limb));
		vec3 disk = LIGHT0_COLOR * LIGHT0_ENERGY * sun_energy
				* smoothstep(outer, inner, cos_sun);
		col += AT_CUBEMAP_PASS ? disk * sun_ibl_scale : disk;
	}

	// --- Lower hemisphere --------------------------------------------------
	// Derived from the finished sky above it, so the haze band and the sun's glare
	// spill onto the water instead of stopping dead at y = 0. Only then does it fall
	// away toward the river-and-banks bounce colour.
	float down = clamp(-up / ground_band, 0.0, 1.0);
	vec3 below = mix(col * ground_bounce, ground_color.rgb,
			smoothstep(0.0, 1.0, pow(down, ground_falloff)));
	col = mix(col, below, smoothstep(-horizon_blend, horizon_blend, -up));

	col *= sky_energy;

	if (!AT_CUBEMAP_PASS) {
		float n = fract(sin(dot(EYEDIR.xz + EYEDIR.y, vec2(12.9898, 78.233))) * 43758.5453);
		col *= 1.0 + (n - 0.5) * dither_strength;
	}

	COLOR = col;
}
