// Stylised flowing water for the Douro river. Animates vertex height with
// summed sines and scrolls a ripple pattern across the UVs using TIME.
shader_type spatial;
render_mode cull_disabled;

uniform vec4 shallow_color : source_color = vec4(0.20, 0.55, 0.86, 1.0);
uniform vec4 deep_color : source_color = vec4(0.06, 0.26, 0.52, 1.0);
uniform float wave_speed = 0.5;
uniform float wave_height = 0.35;
uniform float wave_scale = 0.18;
uniform float flow = 0.02;

void vertex() {
	float w = sin((VERTEX.x + TIME * wave_speed) * wave_scale)
		+ cos((VERTEX.z + TIME * wave_speed * 0.8) * wave_scale * 1.3);
	VERTEX.y += w * wave_height;
}

void fragment() {
	vec2 uv = UV + vec2(TIME * flow, TIME * flow * 0.7);
	float ripple = 0.5 + 0.5 * sin(uv.x * 38.0) * sin(uv.y * 38.0);
	ALBEDO = mix(deep_color.rgb, shallow_color.rgb, ripple);
	ROUGHNESS = 0.25;
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
