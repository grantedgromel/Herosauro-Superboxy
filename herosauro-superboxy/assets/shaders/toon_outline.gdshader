// Inverted-hull outline. Render back faces grown along their normals as a flat
// dark colour to draw a silhouette around toon-shaded meshes. Use as next_pass.
shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled;

uniform vec4 outline_color : source_color = vec4(0.05, 0.05, 0.08, 1.0);
uniform float outline_width : hint_range(0.0, 0.25) = 0.03;

void vertex() {
	VERTEX += normalize(NORMAL) * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
