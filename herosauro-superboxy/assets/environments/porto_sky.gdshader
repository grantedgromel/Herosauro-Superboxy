// Analytic golden-hour sky over the Douro, in place of ProceduralSkyMaterial.
//
// A two-colour vertical ramp is the one thing a real evening sky never is: the
// half of the dome the sun sits in runs warm and hazy from the Mie scatter along
// those sightlines, while the opposite half stays cool and clean. That azimuth
// asymmetry is what sells "physically lit" here, so the gradient carries two
// sun-facing scatter lobes on top of it plus a proper limb-softened disk.
//
// The sun is read out of LIGHT0_*, which means the disk and both lobes track
// whatever DirectionalLight3D the arena scene owns without this file — or the
// Environment resource — having to know where it points.
shader_type sky;

// --- Dome gradient -----------------------------------------------------------

uniform vec4 zenith_color : source_color = vec4(0.196, 0.376, 0.596, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.929, 0.678, 0.435, 1.0);
// Exponent on (1 - EYEDIR.y). Higher pins the warm band to the horizon instead
// of letting it bleed halfway up the dome and turn the whole sky orange.
uniform float horizon_falloff : hint_range(1.0, 16.0) = 4.0;

// --- Lower hemisphere --------------------------------------------------------

// Deliberately not black: below the horizon is the only IBL the underside of the
// deck and the arch truss ever receive, and a black lower half reads as a hole.
uniform vec4 ground_color : source_color = vec4(0.161, 0.129, 0.11, 1.0);
uniform float ground_falloff : hint_range(1.0, 32.0) = 6.0;
uniform float horizon_blend : hint_range(0.001, 0.5) = 0.09;

// --- Sun scatter lobes -------------------------------------------------------

uniform vec4 halo_color : source_color = vec4(1.0, 0.722, 0.42, 1.0);
// Tight lobe: the few degrees of blinding haze hugging the disk.
uniform float halo_tight_falloff : hint_range(4.0, 512.0) = 110.0;
uniform float halo_tight_energy : hint_range(0.0, 8.0) = 1.6;
// Wide lobe: the warm cast across the whole sun-side of the sky.
uniform float halo_wide_falloff : hint_range(1.0, 64.0) = 5.0;
uniform float halo_wide_energy : hint_range(0.0, 4.0) = 0.45;

// --- Sun disk ----------------------------------------------------------------

// LIGHT0_SIZE is the light's angular_distance, which is 0 unless someone asks for
// soft shadows, so the disk carries its own radius and only grows to match.
uniform float sun_radius : hint_range(0.001, 0.2) = 0.028;
uniform float sun_energy : hint_range(0.0, 64.0) = 12.0;
// Fraction of the radius spent softening the limb.
uniform float sun_limb : hint_range(0.0, 0.98) = 0.4;
// A pinprick that bright filters down into the radiance cubemap as blocky
// fireflies, and the DirectionalLight3D already delivers its real energy to the
// scene, so the IBL copy of the disk is deliberately tamed.
uniform float sun_ibl_scale : hint_range(0.0, 1.0) = 0.15;

uniform float sky_energy : hint_range(0.0, 8.0) = 1.0;
// One huge smooth ramp is the worst case for an 8-bit buffer, which is exactly
// what the web build resolves into. Multiplicative so the break-up scales with
// local brightness instead of crushing the dark half.
uniform float dither_strength : hint_range(0.0, 0.1) = 0.012;


void sky() {
	float up = clamp(EYEDIR.y, -1.0, 1.0);

	vec3 col = mix(zenith_color.rgb, horizon_color.rgb,
			pow(clamp(1.0 - up, 0.0, 1.0), horizon_falloff));

	// Ground half: the horizon colour dropping away into the dark river bounce.
	vec3 ground = mix(horizon_color.rgb * 0.5, ground_color.rgb,
			pow(clamp(-up, 0.0, 1.0), ground_falloff));
	// Soft rather than a hard step, so the sun haze spills onto the water the way
	// it does over a real river.
	col = mix(col, ground, 1.0 - smoothstep(-horizon_blend, 0.0, up));

	if (LIGHT0_ENABLED) {
		vec3 sun_dir = normalize(LIGHT0_DIRECTION);
		float cos_sun = clamp(dot(sun_dir, EYEDIR), -1.0, 1.0);
		float toward = max(cos_sun, 0.0);

		// Scatter is strongest along sightlines that graze the horizon, because
		// they travel through the most air. Fade both lobes toward the zenith.
		float grazing = mix(0.35, 1.0, pow(clamp(1.0 - abs(up), 0.0, 1.0), 2.0));
		col += halo_color.rgb * halo_wide_energy * pow(toward, halo_wide_falloff) * grazing;
		col += halo_color.rgb * halo_tight_energy * pow(toward, halo_tight_falloff);

		float radius = max(LIGHT0_SIZE, sun_radius);
		float outer = cos(radius);
		float inner = cos(radius * (1.0 - sun_limb));
		vec3 disk = LIGHT0_COLOR * LIGHT0_ENERGY * sun_energy
				* smoothstep(outer, inner, cos_sun);
		col += AT_CUBEMAP_PASS ? disk * sun_ibl_scale : disk;
	}

	col *= sky_energy;

	if (!AT_CUBEMAP_PASS) {
		float n = fract(sin(dot(EYEDIR.xz + EYEDIR.y, vec2(12.9898, 78.233))) * 43758.5453);
		col *= 1.0 + (n - 0.5) * dither_strength;
	}

	COLOR = col;
}
