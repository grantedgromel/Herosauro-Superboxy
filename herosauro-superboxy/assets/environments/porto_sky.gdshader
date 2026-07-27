// Analytic golden-hour sky over the Douro, in place of ProceduralSkyMaterial.
//
// A two-colour vertical ramp is the one thing a real evening sky never is, and a
// single pow() ramp — which is what this was — is only marginally better: it is
// monotone, so the eye reads one smear from orange to blue and correctly calls it
// a gradient rather than an atmosphere. Real evening skies are built out of
// *layers*, and each layer has a top as well as a bottom:
//
//   1. a two-band vertical ramp, horizon -> upper sky -> zenith, each band shaped
//      with a smoothstep so it fades IN and OUT instead of trailing off forever;
//   2. two exponential haze layers pinned to the horizon — the physically-correct
//      profile for a scattering layer, and the reason the warm band has a bright
//      core with a soft tail rather than a hard edge partway up the dome;
//   3. azimuth asymmetry: the sun half runs warm and hazy from Mie scatter along
//      those sightlines, and the ANTI-solar half carries Earth's own shadow (the
//      cool grey-blue wedge on the horizon) under the Belt of Venus (the rose band
//      just above it). Those two are what make a sky read as "evening" rather than
//      as "orange"; they cost four lines and they are free real estate;
//   4. two sun scatter lobes and a limb-softened disk on top of all of it.
//
// The lower hemisphere is derived from the finished upper-hemisphere colour rather
// than authored separately, and crossfaded SYMMETRICALLY about the horizon. That
// matters more here than it looks: the visible waterline is ~1.8 degrees BELOW the
// mathematical horizon (the river plane runs out to z = -590), so any brightness
// step at EYEDIR.y = 0 lands in open sky just above the water and reads as a hard
// painted line. The old one-sided smoothstep put a 2x step exactly there.
//
// The sun is read out of LIGHT0_*, which means the disk and every lobe track
// whatever DirectionalLight3D the arena scene owns without this file — or the
// Environment resource — having to know where it points. LightingRig adds two more
// directional lights (a cool sky fill and a warm water bounce); both are created
// with sky_mode = LIGHT_ONLY specifically so they never become LIGHT0 and drag the
// sun disk off the real sun.
shader_type sky;

// --- Dome gradient -----------------------------------------------------------

// Deeper and more indigo than a daytime zenith. With the sun at 11.5 degrees the
// top of the dome is genuinely dark, and that darkness is where the image gets its
// contrast: against a pale zenith the whole frame reads as one warm wash.
uniform vec4 zenith_color : source_color = vec4(0.129, 0.243, 0.451, 1.0);
// The dusty desaturated band around 30-50 degrees, where Rayleigh blue has already
// started losing to the haze but the warmth has not arrived yet.
uniform vec4 upper_color : source_color = vec4(0.372, 0.451, 0.588, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.878, 0.639, 0.404, 1.0);
// sin(elevation) at which the warm band hands over to upper_color. 0.30 = 17.5 deg.
uniform float horizon_band : hint_range(0.05, 0.9) = 0.30;
// Shape exponents inside each band. Below 1 the band gives way early, above 1 it
// holds its colour and then drops; both are then run through a smoothstep, so the
// pair behaves like a curve editor rather than a single falloff.
uniform float horizon_shape : hint_range(0.2, 4.0) = 0.85;
uniform float zenith_shape : hint_range(0.2, 4.0) = 1.15;

// --- Horizon haze ------------------------------------------------------------

// exp(-sin(elev) * falloff) is the transmittance profile of an exponential
// atmosphere, which is what haze actually is. It has no edge anywhere — the whole
// point — and stacking a tight layer on a broad one gives the band a bright core
// and a long soft tail, which is what a photograph shows.
uniform vec4 haze_color : source_color = vec4(0.988, 0.784, 0.510, 1.0);
uniform float haze_tight_falloff : hint_range(2.0, 80.0) = 22.0;   // e-fold at 2.6 deg
uniform float haze_tight_energy : hint_range(0.0, 1.0) = 0.55;
uniform float haze_broad_falloff : hint_range(1.0, 40.0) = 5.5;    // e-fold at 10.5 deg
uniform float haze_broad_energy : hint_range(0.0, 1.0) = 0.30;

// --- Anti-solar half ---------------------------------------------------------

// The Belt of Venus: backscattered sunlight off the upper atmosphere, sitting
// roughly 6-15 degrees above the horizon opposite the sun.
uniform vec4 belt_color : source_color = vec4(0.749, 0.541, 0.588, 1.0);
uniform float belt_height : hint_range(0.0, 0.6) = 0.15;           // sin(8.6 deg)
uniform float belt_tightness : hint_range(1.0, 40.0) = 9.0;
uniform float belt_energy : hint_range(0.0, 1.0) = 0.36;
// Earth's shadow underneath it: the planet's own terminator projected onto the
// haze. Cool, desaturated, and hugging the horizon much more tightly than the belt.
uniform vec4 earth_shadow_color : source_color = vec4(0.318, 0.353, 0.478, 1.0);
uniform float earth_shadow_falloff : hint_range(2.0, 80.0) = 26.0;
uniform float earth_shadow_energy : hint_range(0.0, 1.0) = 0.32;
// How far round the dome the counter-glow reaches. 1.3 keeps it inside the
// anti-solar hemisphere with a soft edge instead of a visible seam at 90 degrees.
uniform float counter_spread : hint_range(0.25, 8.0) = 1.3;

// --- Lower hemisphere --------------------------------------------------------

// Deliberately not black: below the horizon is the only IBL the underside of the
// deck and the arch truss ever receive, and a black lower half reads as a hole.
// (LightingRig also hangs a warm bounce light for that job — this is the floor.)
uniform vec4 ground_color : source_color = vec4(0.129, 0.110, 0.098, 1.0);
// How much of the sky's own colour survives just below the horizon. The water is
// a mirror at grazing angles, so the answer is "most of it".
uniform float ground_bounce : hint_range(0.0, 1.0) = 0.62;
uniform float ground_band : hint_range(0.02, 1.0) = 0.22;
uniform float ground_falloff : hint_range(0.2, 8.0) = 1.1;
// Half-width of the symmetric crossfade across EYEDIR.y = 0, in sine units.
uniform float horizon_blend : hint_range(0.002, 0.3) = 0.045;

// --- Sun scatter lobes -------------------------------------------------------

uniform vec4 halo_color : source_color = vec4(1.0, 0.769, 0.478, 1.0);
// Tight lobe: the few degrees of blinding haze hugging the disk.
uniform float halo_tight_falloff : hint_range(4.0, 512.0) = 130.0;
uniform float halo_tight_energy : hint_range(0.0, 8.0) = 1.5;
// Wide lobe: the warm cast across the whole sun-side of the sky.
uniform float halo_wide_falloff : hint_range(1.0, 64.0) = 4.0;
uniform float halo_wide_energy : hint_range(0.0, 4.0) = 0.38;

// --- Sun disk ----------------------------------------------------------------

// LIGHT0_SIZE is the light's angular_distance, which is 0 unless someone asks for
// soft shadows, so the disk carries its own radius and only grows to match.
uniform float sun_radius : hint_range(0.001, 0.2) = 0.028;
uniform float sun_energy : hint_range(0.0, 64.0) = 13.0;
// Fraction of the radius spent softening the limb. Higher than it was: a low sun
// seen through 30 air masses has a genuinely fuzzy edge, and the softer limb also
// stops the disk aliasing into a shimmering polygon as the camera orbits.
uniform float sun_limb : hint_range(0.0, 0.98) = 0.45;
// A pinprick that bright filters down into the radiance cubemap as blocky
// fireflies, and the DirectionalLight3D already delivers its real energy to the
// scene, so the IBL copy of the disk is deliberately tamed.
uniform float sun_ibl_scale : hint_range(0.0, 1.0) = 0.15;

uniform float sky_energy : hint_range(0.0, 8.0) = 1.0;
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
		float away = pow(max(-cos_sun, 0.0), counter_spread);

		// --- Anti-solar: belt first, then Earth's shadow under it ---
		float belt = exp(-abs(above - belt_height) * belt_tightness) * away;
		col = mix(col, belt_color.rgb, clamp(belt * belt_energy, 0.0, 1.0));
		float shade = exp(-above * earth_shadow_falloff) * away;
		col = mix(col, earth_shadow_color.rgb, clamp(shade * earth_shadow_energy, 0.0, 1.0));

		// --- Sun-side scatter ---
		// Scatter is strongest along sightlines that graze the horizon, because
		// they travel through the most air. Fade both lobes toward the zenith.
		float grazing = mix(0.30, 1.0, pow(clamp(1.0 - abs(up), 0.0, 1.0), 2.0));
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
	// Derived from the finished sky above it, so the haze band, the counter-glow
	// and the sun's glare all spill onto the water instead of stopping dead at
	// y = 0. Only then does it fall away toward the dark river bounce.
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
