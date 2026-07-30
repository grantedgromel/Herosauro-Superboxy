// Fair-weather cumulus, as a cluster of soft-edged puffs.
//
// It replaces a StandardMaterial3D on the same geometry, and Round 1 named all four
// of that material's failures in one finding: hard opaque silhouettes, visible
// mesh-intersection seams where the puffs cross, khaki-brown undersides, and hard
// white caps. Three of those four are not a shading problem at all — they are what
// you get when you draw a cloud as an OPAQUE LAMBERT SOLID, and no choice of albedo,
// normal or roughness fixes any of them:
//
//   * a solid writes depth, so two intersecting spheres cut a visible circle in each
//     other. A cloud has no interior surfaces to show.
//   * a solid has a hard silhouette, because coverage goes 1 -> 0 across one pixel at
//     the limb. A real cumulus thins to nothing over metres and its edge is where you
//     can see the most sky through it.
//   * a Lambert underside goes to whatever ambient happens to be there, and the
//     previous ambient carried enough warm bounce to land it in khaki. The underside
//     of a fair-weather cumulus is lit by the sky it is sitting in: cool blue-grey,
//     never brown, and never darker than about half its cap.
//
// So this is transparent, does not write depth, fades its own alpha out at the limb,
// and shades from a sky colour underneath to a sun colour on the cap. The
// intersections disappear because there is no depth to intersect, the silhouette
// softens because the alpha is a function of the limb angle, and the underside is
// blue-grey because the underside is explicitly lit by the sky rather than by
// whatever ambient the arena happens to have.
//
// UNSHADED on purpose. A cloud at 60-140 m is nowhere near the arena, and the three
// fill lights LightingRig spawns for the bridge would otherwise all reach it —
// including QuayBounce, which comes from 70 degrees BELOW horizontal and is green-grey
// off the river. That light has no business on a cumulus, and it would put the
// undersides right back where Round 1 found them. Fog is deliberately NOT disabled:
// the clouds are 60-140 m out and should take the same aerial perspective everything
// else at that distance takes.
//
// sun_direction is set at runtime by sky_background.gd from the scene's actual
// SunLight, never authored here — this file's default exists only so the shader has
// something to compile against, and _atmosphere_probe.gd asserts the two agree. A
// hand-copied sun vector is exactly how water_wave.gdshader's Mat_river override
// ended up 120 degrees of azimuth stale.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;

// World-space direction TOWARDS the sun. Overwritten at load; see the header.
uniform vec3 sun_direction = vec3(0.337181, 0.559193, 0.757364);
// The sunlit cap. Slightly under white: a cumulus reflects about 0.9 and this is the
// value that has to sit above the sky behind it without clipping through the grade.
uniform vec4 sun_color : source_color = vec4(0.97, 0.965, 0.95, 1.0);
// The underside, lit by the dome. Sampled from the sky shader's upper_color pulled
// toward its horizon hem, because that is the part of the dome a cloud base sees.
uniform vec4 sky_color : source_color = vec4(0.60, 0.68, 0.79, 1.0);
// The deepest self-shadow, in the shaded creases between puffs. Cooler and darker
// than the base but nowhere near dark: light scatters through a fair-weather cumulus
// for hundreds of metres, which is why they never have black anywhere in them.
uniform vec4 shade_color : source_color = vec4(0.46, 0.55, 0.68, 1.0);
// Peak coverage at the thickest part of a puff.
uniform float opacity : hint_range(0.0, 1.0) = 0.94;
// How much of each puff's limb is spent fading out, as |dot(normal, view)|. 0.70
// puts the fade over the outer third of the projected radius: enough that no edge is
// a step, little enough that the cloud still has a body.
uniform float edge_softness : hint_range(0.05, 1.0) = 0.70;
// Width of the terminator. Large, and that is the physics: light entering the
// sunward side of a cloud is still coming out well past the geometric terminator,
// which is why cumulus have soft rounded shading and not a hard light/dark line.
uniform float terminator : hint_range(0.05, 1.5) = 0.95;

void fragment() {
	// NORMAL and VIEW are view-space; the sun is world-space. Do the lighting in
	// world space so a moving camera cannot roll the cloud's own shading.
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);

	float ndl = dot(nw, normalize(sun_direction));
	float lit = smoothstep(-terminator, terminator * 0.6, ndl);

	// Vertical position on the puff, 0 underneath and 1 on the cap. The base is sky,
	// the shaded creases are the deeper blue-grey, and the sun paints over the top.
	float up = nw.y * 0.5 + 0.5;
	vec3 base = mix(shade_color.rgb, sky_color.rgb, smoothstep(0.02, 0.62, up));
	ALBEDO = mix(base, sun_color.rgb, lit);

	// Coverage falls to zero at the limb, which is both the soft silhouette and the
	// reason two overlapping puffs stop showing their intersection.
	ALPHA = opacity * smoothstep(0.0, edge_softness, abs(dot(nw, vw)));
}
