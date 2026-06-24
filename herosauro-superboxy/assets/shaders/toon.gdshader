// Cel / toon lighting for the GL Compatibility renderer.
// Diffuse light is quantised into a few flat bands and a soft rim is added
// toward the camera silhouette. Pair with toon_outline.gdshader via next_pass.
shader_type spatial;
render_mode cull_back, specular_disabled;

uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform int bands : hint_range(1, 5) = 3;
uniform float ambient_floor : hint_range(0.0, 1.0) = 0.3;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy : hint_range(0.0, 8.0) = 0.0;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.2;
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	ALBEDO = albedo_color.rgb;
	EMISSION = emission_color.rgb * emission_energy;
}

void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	float banded = floor(ndotl * float(bands)) / float(bands);
	banded = max(banded, ambient_floor);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * banded;

	float rim = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 2.0) * rim_amount;
	DIFFUSE_LIGHT += rim_color.rgb * rim * ATTENUATION;
}
